# Round50：Windows Job 子树退出证明原语（未接生产）

## 结论与唯一写入范围

新增 `addons/fate_server_signals/src/process_tree_owner_core.hpp/.cpp`、
`tools/tests/test_process_tree_owner_core.py`、`tools/tests/process_tree_owner_core_probe.cpp` 和本文。
只交付 `fate::WindowsJobLease` 能力；没有复制 spawn API，没有启动 Godot/editor、冷 import，
没有改现 ProcessOwner/binding/DLL/SConstruct、manager、console、ledger、cleanup 或 gate。
没有 `saved`、`complete_registry`、当前实例集合或删除许可字段，更没有默认开启删除。

实测命令：`python tools/tests/test_process_tree_owner_core.py`。
最终 5 tests 全通过，0 failure/error/skip，退出码 0，8.496 秒。
最终证据根：`E:/FateProcessTreeProof-dffc8c85e5ff45cab03ea2d2b1a09eb6/`。
`evidence.json` 包含源码 SHA-256、编译退出码、5 个模式的实际输出（34 行 JSON）；
各模式 stdout/stderr、`build.cmd`、`build.raw.log` 均保留。
已独立读回所有源码摘要匹配、编译/5 个模式退出码均为 0；本驱动 exe/obj 已回收且读回无剩余。
所有生成物及子进程 TMP/TEMP/TMPDIR 在已检查无 reparse 祖先的自建物理 E 根。

## 已读真实缺口

- 现 `process_owner_core.cpp:125-200` 在 Windows 直接 `CreateProcessW(..., flags=0)`，
  关闭 hThread 后才交付 token/PID，没有 assign-before-resume 边界。
- `inspect:203-218` 仅 `WaitForSingleObject(root HANDLE,0)`；
  `release:253-258` 在根 signaled 后关闭该 HANDLE 并擦除 entry。
  `terminate:225-243` 和析构 `259-263` 也仅处理根；不能证明所有子代已退出。
- `process_owner_binding.cpp` 现公开 `available/spawn/state/verify/terminate/release`；
  没有 Job 子树观察、创建身份或结构化 tree receipt。
- `server_room_manager.gd:364-376` 以 root state=0 + `_release_process(room)` 创建
  `closed_process_binding`，清 pid/token/close supervision；它当前不是 Job active=0 证明。
- `tools/run_isolated_godot_test.py:256-344` 的 OwnedJob 会先把 suspended root assign 再 resume，
  用 Job accounting 读 active，但启用 KILL_ON_JOB_CLOSE 并提供 stop。这是测试强制回收策略，
  不能直接拿来管理已经 ready、尚未保存的生产 worker。

## 解耦与精确 API

`WindowsJobLease` 不创建、resume、发送策略 stop 或 terminate 进程；它只托管一个 caller supplied process
对应的私有 Windows Job，验证 binding 和真实 accounting，最后在零活跃时释放自身句柄。
copy/move 都禁止，内部 mutex 串行 assign/observe/release；调用方仍必须协调对象生命周期与析构，
不能并发销毁正在调用的对象。

```cpp
fate::WindowsJobLease lease;
fate::WindowsJobLease::Binding b{owner_token, pi.dwProcessId, creation_filetime};
fate::WindowsJobLease::SuppliedProcess p{
    reinterpret_cast<intptr_t>(pi.hProcess), b, true
};
auto assigned = lease.assign(p);
// 只有 assigned.ok 且 stage=assigned_before_resume 才进入 caller ResumeThread(pi.hThread)。
// 失败保留未知监督状态，绝不能 root-only fallback 或把进程继续启动。
auto observed = lease.observe(b);
auto final = lease.release(b);
// 仅 final.ok && final.release_complete && final.handles_released 才有该 lease 的释放证明。
```

调用方前置合同：

1. 必须是本机可信 native creator 的真实 `CreateProcessW(CREATE_SUSPENDED)` hProcess，
   尚未 resume、未让任何线程工作/创建子代。caller 明确拥有创建身份与原始 hProcess/hThread。
   参数 bool 默认为 false；它是可信 caller 的所有权/暂停声明，**不是内核暂停检测**。
   单凭 hProcess 没有公开 Win32 原语独立证明所有线程从未运行，不能对任意已运行进程设置 true 认领。
2. supplied hProcess 是借用，不是所有权转移，不按 PID `OpenProcess`；caller 原始句柄仍由 caller 负责。
   lease 只复制出一个非继承句柄并核对 `GetProcessId`、`GetProcessTimes` 的完整创建 FILETIME。
   token 必须沿现 ProcessOwner 的真实随机内存 capability，同原 root/PID/创建时间保持绑定；
   测试常量 token 仅自建夹具使用，禁止作为生产认证替身。
3. lease 创建 unnamed、non-inheritable Job，不向外导出 assign/Job HANDLE，
   显式配置本 Job LimitFlags=0（不允许本 Job breakaway，不启用 kill-on-close）。
   不排除 caller 已有 outer Job；真实 nested assign 不兼容时返回 `assign_job_failed/native_error`，
   不 retry 为裸根监督。任何失败后该对象单次 assign 已消耗，observe/release 都不能生成成功证明。
4. assign 后重新读 root identity/membership、Job limits/accounting，必须 running、active=1、total=1；
   才返回 assigned_before_resume。检查失败意味着已产生但未证明的 Job，不代表未 assign，
   caller 必须保留/诊断现场或按显式本机紧急策略处置，不能 resume 或自动说已保存。
5. `observe(b)` 重验本机 owner、完整 token/root PID/creation、root HANDLE、Job limit flags，
   用 `QueryInformationJobObject(JobObjectBasicAccountingInformation)` 读 **exact Job** ActiveProcesses。
   不枚举系统/PID 名/控制台，不把读失败默认 0；必须先检查 ok 和 active_known。
   Job 子树约束只覆盖从该根正常继承 Job 的子代，不能覆盖 worker 通过别的服务/RPC 创建的外部进程。
6. `release(b)` 不消费旧 snapshot；当次重新 query，必须 root signaled **且** active_known=true、active=0。
   根 exit 不等于 child exit；active>0 返回 tree_still_active 并保留两句柄。
   只有 CloseHandle(root duplicate) 与 CloseHandle(private Job) 都成功，才返回
   tree_zero_handles_released / release_complete=true / handles_released=true。
   部分关闭失败返回 unknown stage、poison lease，绝不生成 complete；析构仍只关闭残余句柄。
   release 后 observe/release 都 unknown，不能凭已关闭对象重新签发回执。
7. root_exit_code 单独保留；崩溃退出可最终证明树确实归零，但**不是 saved**、不是正常关闭认可。
   保存成功、消费确认、停止策略、房间/instance/mode/request 绑定、完整 registry 和审计持久化由上层提供。
8. 析构只 CloseHandle，不调用任何 terminate，也不自动返回 receipt。
   未释放的 live/unknown lease 被销毁会失去证明；同模块内保留 PID+creation tombstone 阻止再 claim。
   这只是本机同模块反复 claim 防护，不跨进程、不持久、不完整登记；不要把它称 complete_registry。
   显式 release 成功才撤销 claim；进程/dll 重启不能从磁盘 token/PID 恢复 Job 所有权。

## 原生实测

两个实际子代是 root→child→grandchild，controller 只持有自己 CreateProcess 的根句柄和
由对应 creator 通过 DuplicateHandle 交回的精确 child/grandchild HANDLE，带 inherited event/map
握手；不从 PID 反查进程。事件准许自然退出，Job lease 永远不负责 stop/kill。
正常 case 的真实读回：

| 阶段 | root | exact Job active / total | release_complete |
|---|---|---:|---|
| suspended 根 assign 后、resume 前 | running，ready event 未触发 | 1 / 1 | false |
| ROOTEXIT + child/grandchild 仍活 | exited，exit code 0 | 2 / 3 | false |
| 两个子代自然退出后 observe | exited | 0 / 3 | false |
| release 当次再次 query 并关闭两句柄 | exited | 0 / 3 | true |
| release 后再次 observe | unknown | active_known=false | false |

正常 case controller 实际 HANDLE 数从 70 降至 68，独立确认 lease 关闭了两只句柄。
UNKNOWN receipt 的默认 active=0 **不可当零证明**，因为 ok/active_known 为 false。
根 signaled 与 Job accounting 更新不是原子；根崩溃时实见 active 曾短暂仍为 3。
probe 只在测试看门狗内等待 accounting 变为 2，core 始终保守拒绝，不添加生产政策超时。

其余实际覆盖：

- stale token、错误 PID、错误 creation 时间不改变有效 lease；随后真实 binding 仍可观察/最终释放。
- 两 lease、不同 token 争同一 root identity：duplicate_root_claim；同对象再次 assign：lease_already_attempted。
- 缺明确 suspended ownership、错误 creation、无效 HANDLE 都拒绝且不 resume。
- root 自身以 `TerminateProcess(GetCurrentProcess(),73)` 崩溃，两个真实子代继续运行：release 仍拒绝。
  两子代之后自然退出，active=0 才返回 release proof，exit code 73 被保留，不输出 saved。
- root 已退出但两个子代活着时析构 lease，两精确 descendant HANDLE 仍 WAIT_TIMEOUT；
  后续事件触发，两进程 HANDLE 自然 signaled。另测 suspended 根的 lease 析构后 duplicate claim tombstone。
- 真实外层 Job 带 JOB_OBJECT_UILIMIT_HANDLES，本机 Windows 仍允许追加私有嵌套 Job；
  正验真实 resume/spawn/drain 后 private Job active=0、release 成功。
  **未发现可自然构造的不兼容嵌套形态，不把这个正验冒充拒绝验收。**
- 另建测试专用 hooked object：通过 `/FI` 强制包含 probe 的声明段，只重定向 core 编译单元的
  AssignProcessToJobObject/QueryInformationJobObject；生产 core 没有 test 宏或注入 API。
  hook 为 **同一真实 Job** 复制只有 JOB_OBJECT_QUERY 的 HANDLE，再调用真实 AssignProcessToJobObject，
  原生返回 ERROR_ACCESS_DENIED=5；验证 assign_job_failed、unknown release、根仍 suspended。
  Query 负验复制只有 JOB_OBJECT_ASSIGN_PROCESS 的 HANDLE，真实 Query 返回 error 5；
  即使此前已成功读到 active=0，release 也必须拒绝；恢复正常权限后仍持有原 lease，可以重新 query/release。
  这是句柄权限故障注入的真实内核拒绝，不是自然嵌套不兼容的实测，也不是合成 native 响应。

正常 tree/crash/abandon 链接无 hook 的当前 core；bindings/invalid 采用单独 hooked object。
两套都 MSVC `/std:c++17 /EHsc /W4 /WX /MT`，不用 Godot DLL 替身。
测试中的 never-resumed/失败根，只由 fixture 明确对自己 constructor 创建的精确根 HANDLE 做紧急退休；
子代通过 fixture 事件自然结束。生产 lease 内完全没有 terminate 函数。
未对 CloseHandle 部分失败、所有版本 Windows nested 不兼容、控制器进程被外部强杀做真实故障注入，
不声称这些生产整链验收完成。

## 给 main 唯一 native 集成人选的接线合同（不是本轮已实施）

- 仍复用现 ProcessOwner::spawn 的参数校验、命令行编码与随机 token，不复制另一 spawn 实现。
  将现 Windows CreateProcess flags 改为 CREATE_SUSPENDED，保留 hThread，读取 root creation FILETIME，
  Entry 新增原 root creation 与 `unique_ptr<WindowsJobLease>`。同一个随机 token 同时绑定 root 和 lease。
- Entry 完整登记后调用 assign；只有 assign 成功，再由原 spawn caller 调用 ResumeThread 并核对返回值为 1。
  assign/resume 失败不交付 Spawn 成功、不解除 root-only gating；未就绪 suspended 根的显式紧急退休
  与已 ready 未保存 worker 的 stop policy 必须分开，不能沿用旧析构的隐式 stop。
- `state(token,pid)` 可继续保持根状态语义；新增结构化 `tree_observe(token,pid)`，
  binding 内部补 creation，不接收外部调用方随意提供“证明 bool”。
  `release(token,pid)` 的 true 必须升级为该 Entry 对同一 lease 当次 release_complete，
  并确认 ProcessOwner 原 root HANDLE 自身也成功关闭后才 erase Entry。
  更合适新增 `release_tree` 回结构化 receipt，binding 保留旧 bool wrapper 但不得降级为 root-only release。
- manager 只有 tree release_complete（加原 owner HANDLE 释放完成）、完整请求/实例/mode 绑定及原保存确认，
  才能记录 closed；root=EXITED、旧 closed 字典或 STOP_COMPLETE 文本都不能单独授权 cleanup。
  崩溃树归零 receipt 只能用于退出事实/异常回执消费，不变成保存成功或删除许可。
- 保存拒绝/UNKNOWN/超时必须保持监督与产物；析构不能默默强杀 ready 未保存 worker。
  若 operator 明确紧急停止，在独立策略 API 中绑定本机 token/完整实例并保留 unsaved/recovery_required，
  不能由 WindowsJobLease 析构暗中提供 saved 或 cleanup_permission。
- 完整当前实例 registry、跨进程部署排他、ledger 事务/未解决意图、原生文件 identity producer、
  temporary cleanup native binding 和安全文件删除能力，仍是互相独立的 blocked prerequisites。
- main 唯一 native 集成人选后续必须构建/加载实际 DLL，并用真实 worker 正负验：
  suspended-assign-resume、自然关闭、有活孙进程、保存拒绝/未确认、根 crash、unknown、stale、duplicate、
  shutdown 生命周期和根/树双句柄释放。未做这些之前不得把本独立 probe 通过提升为生产 manager/cleanup 完成。
  本轮遵守冷 import 的唯一 owner `sa-0-7f403a02`，未启动引擎、未换引擎、未抢生产接线写权。
