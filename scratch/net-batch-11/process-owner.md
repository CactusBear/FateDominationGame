# Windows ProcessOwner / supervisor 静态审计

## 结论与边界

- **未发现 PowerShell `File.Replace` 参数顺序错误，也未发现正常 `state/terminate/release` 路径的 HANDLE 双关或 PID 重用误杀。**
- 主要缺口：心跳发布错误不传入房间状态；同步 PowerShell 无超时且串行阻塞所有房间；原生析构忽略停止失败并丢失最后所有权；心跳路径缺少与启动配置等价的安全校验。
- 仅审计当前生产源码，未修改生产文件，**未运行 Godot、未启动/终止房间工作进程、未执行实际文件替换**。PowerShell 只执行了只读 .NET 方法反射；不能把此结果称为心跳原子性或原生扩展运行验收。
- 仓库：`E:/Projects/Godot/FateDominationGame-master`。现有工作树包含大量其他未提交变更；本报告不评判或覆盖它们。

## 已确认正确的生命周期与关闭竞态

| 环节 | 源码依据 | 静态结论 |
|---|---|---|
| 创建与绑定 | `addons/fate_server_signals/src/process_owner_core.cpp:125–149` | 创建前生成随机 token 并预留 map 槽；`CreateProcessW` 失败删槽。成功后关闭 `hThread`，将 `hProcess` 与原始 PID 存入私有表。`bInheritHandles=FALSE`，不会通过此创建调用把主管持有的句柄传给子进程。 |
| 查询 | 同文件 `203–206,220–224`；hpp `12` | `WAIT_OBJECT_0→EXITED(0)`，`WAIT_TIMEOUT→RUNNING(1)`，其余→UNKNOWN(-1)。token 未知或 PID 不匹配也是 UNKNOWN，不把查询失败伪装成退出。 |
| 终止 | 同文件 `225–242` | 对同一个已持有的 HANDLE 操作，不按 PID 重开。查询后进程自行退出时，`TerminateProcess` 失败会重新检查 EXITED；成功/竞争退出后仍等待 HANDLE 信号，最多 5 秒。超时返回 false，正常调用不销毁 entry。 |
| 释放 | 同文件 `253–258` | 只有 token/PID 相符且确认 EXITED 才 CloseHandle 并删 entry。二次 release 因找不到 token 返回 false，不再关句柄。terminate 不隐式 release。 |
| 并发 | 同文件 `126,221,240,254` | spawn/state/terminate/release 共享 mutex，正常公共调用不会在 Wait/Terminate 时被另一 release 关掉同一 HANDLE。5 秒终止等待也持锁，因此会阻塞该 owner 的其他房间操作。 |
| manager | `scripts/net/server/server_room_manager.gd:65–75,304–308,396–410` | 状态 UNKNOWN 不准恢复；stop_room 先 terminate 再 release，任一步失败保留房间登记和目录。正常路径没有 PID-only fallback。 |
| 析构脚本守卫 | manager `416–419` | PREDELETE 前检查 `is_instance_valid(_process_owner)`，不是仅用非 null 检查；此前清理阶段“空基类调用”问题在这个入口已有守卫。 |

注意：原生析构 `259–263` 没有 mutex，但在正确 RefCounted 生命周期下，最后引用销毁时不应仍有公共方法在执行；**仅凭没有锁不能认定已存在可达的析构并发竞态**。若未来从其他原生线程保存裸指针调用，必须另行证明对象存活与线程退出顺序。

## PowerShell 原子替换参数与错误处理

依据：manager `370–394`。

1. 在同一目录写 `supervisor.json.<主管PID>.tmp`，flush、读取文件错误、close，然后尝试 rename。
2. 仅当 rename 失败、平台为 Windows、目标存在时，执行：
   ```powershell
   $ErrorActionPreference='Stop'; try {
       [System.IO.File]::Replace('<temporary>','<path>','<backup>'); exit 0
   } catch { exit 1 }
   ```
3. 当前 Windows PowerShell 的只读反射真实返回：
   ```text
   Void Replace(System.String, System.String, System.String)
   sourceFileName
   destinationFileName
   destinationBackupFileName
   Void Replace(System.String, System.String, System.String, Boolean)
   sourceFileName
   destinationFileName
   destinationBackupFileName
   ignoreMetadataErrors
   ```
   因此 **temporary=新内容源、path=被替换目标、backup=旧目标备份，顺序正确**。使用的是合法三参重载，不是缺少第四参的错误调用。
4. 三路径均 globalize，并把 `'` 变成 `''` 后置于 PowerShell 单引号字符串；没有据此发现路径文本导致的 PowerShell 注入。临时文件/目标/备份位于同目录，设计上避免跨卷替换。目标不存在时不调用 Replace，符合 Replace 要求已有目标的语义。
5. 异常统一 exit 1，`OS.execute` 返回 0 才记为成功；启动失败/负退出值也不会被当成功。没有“先删除目标再 rename”的应用层窗口。
6. 尚未证明实际 `DirAccess.rename_absolute` 在本项目 Godot/Windows 下是否会覆盖已有文件、fallback 的触发频率、文件共享模式、杀毒软件/ACL/文件系统下的原子行为；**不能断言每秒必定启动 PowerShell，也不能断言正常场景永远无需 fallback**。

## 发现：已静态确认，未修复

### F1 / P2：心跳发布失败只写 manager.error，房间仍可能对外 ready

- 位置：manager `375–377,382–385,392–394` 对照 `198–235`；worker `205–216`。
- `_write_supervisor` 是 void，失败只赋全局 `error`，不写 `room.error`、不清 `room.ready`。poll 的停止分支看的是 `room.error`，ready 分支在 `221–222` 直接 continue；`is_ready` 的真实进程验证也不会检查 manager.error。
- 故磁盘写满、权限问题、Replace 失败时，已 ready 房间在工作进程尚未退出期间仍可被报告 ready，随后工作进程按旧心跳超时自行退出。一次房间的心跳失败还会留在全局 error 中，后续成功心跳并不清除它，难以定位当前哪个实例有问题。
- 建议：发布函数返回明确结果，将错误按 room/PID/instance 记录；声明一致的容错策略（可配置重试/宽限或立即取消 ready），不要继续用“全局报错但房间健康”混合语义。停止失败仍须保留 token/目录。

### F2 / P1（条件触发）：PowerShell 替换无超时，串行阻塞共享主管和其他房间心跳

- 位置：manager `205–211,387–390`；`max_rooms=16`；worker `211–216`。
- `OS.execute` 同步等待，没有实现级超时；fallback 按 rooms 顺序执行。PowerShell 启动/文件 I/O 卡顿或多个房间累计耗时超过各自 supervisor_timeout 时，主管无法继续发后续心跳及轮询；工作进程会将主管卡顿当主管丢失而退出。默认超时为 5 秒。
- 严重性来自共享主管故障放大，不是已经测得本机 PowerShell 慢。触发前提是 rename 失败进入 fallback，再发生足够长的执行延迟；本次没有时序复现。
- 原生 `terminate` 在 mutex 内等 5 秒也会串行阻塞该 owner；poll 清理多个出错房间时同样会推迟下一轮其他健康房间心跳（manager `217–220,234–235`）。
- 建议：把安全的 Windows replace 收敛为有明确错误码的原生短调用，或实现受控异步发布、硬期限与旧实例结果隔离；终止等待与共享心跳调度解耦。不要用无限阻塞 helper 做主管活性证明。

### F3 / P2：原生析构忽略 stop 失败，仍关闭最后 HANDLE

- 位置：core `225–232,259–263`；manager `412–419`。
- 普通 terminate 失败会保留 entry，可重试；析构却无条件 `stop(entry); dispose(entry);`。若状态 UNKNOWN、TerminateProcess 失败且未确认退出，或 5 秒等待超时，仍会关最后 HANDLE，然后随对象销毁丢失 token 表。
- CloseHandle 本身不会终止进程。于是析构后存在“未证明退出且不能再用原所有权重试”的缺口；这不是正常公共路径 HANDLE 泄漏，也不意味着所有 stop 超时都会留下运行子进程（TerminateProcess 可能已成功，只是退出尚未完成）。
- PREDELETE 先逐房间 terminate，失败时又落到原生析构再试；返回值都被忽略。`close()` 也忽略各 stop_room 返回值，不能把调用 close 当所有房间已关闭的证据。
- worker 心跳超时是缓解，不是硬保证：超时检查位于 `_process`，主线程挂住时不能保证执行。当前 CreateProcess 没有建立 kill-on-close Job Object。
- 建议：用显式可报告的 shutdown 在对象最后释放前处理失败并保留存活 owner；若产品要求主管退出必杀子进程，评估 Job Object 与创建/加入任务的无逃逸时序。不要简单“给析构加锁”就宣称解决孤儿进程。

### F4 / P2（本机目录可被篡改时）：心跳 tmp/path/backup 未沿用恢复路径安全约束

- 位置：manager `108–119` 对照 `370–394`。
- write_configuration 对 target/tmp 有 RecoveryPaths.checked，而 `_write_supervisor` 直接 open/rename/Replace/remove。启动时房间目录的校验不能证明后来每次写入仍无链接/重解析点；固定 PID 命名临时/备份文件也可能被预先布置。
- 若其他本机主体有修改房间存储目录的权限，替换链接路径或布置 tmp 链接可能让写入越过房间目录，备份清理也缺少边界校验。具体 Windows 链接种类与 FileAccess/Replace 行为未运行验证；这不是已证明远程客户端任意文件写，也没有发现公开网络入口能设置 room.directory。
- 建议：对心跳各路径统一使用已批准根、规范路径和无链接检查；仍须承认 check/use 竞态，并用私有目录 ACL 或原生目录/句柄约束封闭本机篡改面。

### F5 / P3：丢失底层错误码与备份清理结果，难以区分停止/替换失败原因

- 位置：core `144–147,203–206,231–232,244–246`；binding `25–38`；manager `388–394`。
- CreateProcess/Wait/Terminate/CloseHandle 的 GetLastError 未返回；CloseHandle 返回值被忽略。PowerShell catch 吞掉异常内容，output 不读取，backup/tmp remove 结果不检查。
- 当前失败分支总体 fail-closed，但日志不能区分 ACL、共享冲突、无效 HANDLE、helper 启动失败或 5 秒等待超时；备份清理失败也会被一次成功 Replace 掩盖。
- 建议：增加结构化错误码/阶段字段，包含房间实例和操作、不记录秘密 token；备份删除失败按独立清理告警处理，不将其误报为新心跳没有发布。

## 不升级为已确认缺陷的边界

- `_process_state/_terminate_process/_release_process`（manager `65–75`）只检查非 null，未各自检查 is_instance_valid；但当前 poll/stop/recover 外层会调用 process_ownership_available 清理失效引用，PREDELETE 又有明确守卫。未找到绕开这些守卫的当前公开调用链，因此不把此项重复登记为已可达崩溃。
- `_process_state` 读取 `room.pid` 未校验，但 create/discover/recover 建立的房间结构都有 PID；对公开可变 rooms 被外部代码任意破坏的健壮性，不等于目前已发现网络输入直接污染 PID。
- state 返回 RUNNING 与随后终止之间进程可能自行退出；持有 HANDLE 使此竞态不会变成杀掉 PID 重用的新进程。
- Windows `available()` 每次尝试随机数生成（core `100–102`），因此 RNG 短暂故障会令 poll/stop 整体失败关闭，即使旧 HANDLE 尚可用。可把“新建能力”和“现有所有权操作能力”拆开；未复现 RNG 故障，不列为主阻断。
- 正常退出后 poll 保留 entry/HANDLE（不自动 release）；后续 recover/stop 才释放，这是保留恢复身份的现有生命周期，不应仅凭退出后句柄仍存在误判为无界泄漏。

## 静态验证与后续验收缺口

已执行：读取以上生产文件与调用方、git status（只读）、.NET File.Replace 重载参数反射（退出码 0）、源码 SHA-256 快照。

未执行：Godot 加载/解析/场景测试；Windows DLL 重新构建或加载验证；HANDLE 计数/真实 terminate/release；磁盘满、共享冲突、ACL/链接注入；PowerShell 阻塞与多房间超时；主管异常退出/工作线程挂住时的孤儿进程验收。

建议后续专项按条件覆盖：
1. 单房间首次创建与已有目标 Replace；带空格、中文和单引号路径；对比 helper 退出码和工作进程实际读到的 version。
2. 写失败、Replace 失败、备份删除失败，验证各房间 ready/error 状态与目录保留。
3. 子进程自退与 terminate 同时发生、重复 release、错误 token/错误 PID、并发 state/release（对象始终保留强引用）。
4. 延迟 helper 或延迟终止等待，验证多房间心跳隔离，不用单房间成功代替共享调度验收。
5. shutdown 失败/超时与主管退出，明确残留子进程处理；不能仅看退出码或调用了 close。

### 被审计源码快照

| 文件 | SHA-256 |
|---|---|
| `addons/fate_server_signals/src/process_owner_core.cpp` | `885d81fb9f261ce8424412609cdfd2e2ecf4a58cded8357ee59d3b257b463d65` |
| `addons/fate_server_signals/src/process_owner_core.hpp` | `c5faebb36cf912e8f9d9681513f8ab99b88f08caf191c601209fd471eb509f4c` |
| `addons/fate_server_signals/src/process_owner_binding.cpp` | `280deaae9d958f4214833ccfc1e8b17c187d1aa28092b9d417f1e3e84005d538` |
| `scripts/net/server/server_room_manager.gd` | `963ee13079abe0f3459f39dad671504a8572c6431ba7104aceb413b1f3e13de8` |
| `scripts/net/server/server_room_worker.gd` | `a09ae74b4d12413faa6bd49952ed9a4fcdf8d38d475f955f91e345c761b5c4be` |

本报告为静态确认与条件风险清单，不是生产修复或 Windows 运行通过证明。
