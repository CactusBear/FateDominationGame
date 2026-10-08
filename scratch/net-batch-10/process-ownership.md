# 真实 OS 进程所有权生产接线审计

## 结论与边界

仅静态只读审计，未运行 Godot、未加载 DLL/SO、未创建/终止任何进程、未修改生产文件。唯一交付文件为本报告。路径均相对项目根 `E:/Projects/Godot/FateDominationGame-master`。

源码已实现真正的进程句柄所有权，Windows 用 CreateProcessW 返回的 hProcess，Linux 用 clone3(CLONE_PIDFD) 原子取得 pidfd；verify/state/terminate/release 均查内存 token + PID，再操作原始句柄，没有 OpenProcess(PID)、OS.kill 或裸 kill(PID) 回退。**但生产恢复入口与新版退出状态不兼容，Linux 发布二进制缺少新增类，失败清理和关闭回执也有缺口。不能据此宣称整条生产生命周期已验收。**

## 问题与建议

### P1 — 已运行房间崩溃后，公开重新加入路径不会触发恢复（静态确认）

- 证据：`scripts/net/server/server_room_manager.gd:210-216` 发现 EXITED 后只设置 ready=false/error，仍保留原正 PID 和 process_token；`server_gateway.gd:194-198` 仍假定 poll 会把 pid 改为 -1，只有 `binding.pid <= 0` 才调用 recover_room。
- 结果：原成员持有效恢复凭据重新 server_join 时，正 PID 使重启分支被跳过；随后加入 _pending，下一轮 `server_gateway.gd:63-66` 因 room.error 非空拒绝。主管仍在运行期间的真实子进程崩溃恢复被阻断。主管重启后 discover_rooms 注册 pid=-1 的路径不受此处影响。
- 建议：不要为迎合旧网关直接清除 PID/token，否则丢失释放原句柄的必要绑定。将退出状态作为主管显式 API/生命周期状态供网关判断；对已验证 EXITED 的登记调用 recover_room（带旧 PID/instance），由管理器释放旧所有权并发布新绑定。RUNNING 启动中可等待，UNKNOWN 必须拒绝。
- 补验收：真实建房→原生句柄确认退出→公开 server_join 携恢复凭据→新 PID/instance/token→旧令牌失效→新 ready→原成员身份恢复。现有 `tests/net_server_rooms_test.gd:58-66` 直接调用 manager.recover_room，覆盖不到该公开入口缺陷；本次未执行测试。

### P1 — Linux 生产 SO 尚未包含 FateProcessOwner（发布接线阻断；二进制静态证据）

- `addons/fate_server_signals/fate_server_signals.gdextension:7-8` 指向正式 Windows DLL/Linux SO；源码 `src/server_signals.cpp:95-98` 已注册新增类，SConstruct:14 用 Glob 收入新增 cpp。
- 实际正式 SO 的字节扫描没有 `FateProcessOwner`，也没有 `spawn`；Windows DLL 有这两个字面量。新增绑定的 GDCLASS/GDREGISTER_CLASS 与 D_METHOD 应携带这些类名/方法名字面量，所以现有 SO 不具备新增绑定；未调用动态加载器验证。
- 实际产物：
  - Linux SO：469560 bytes，SHA256 `9edf007f0e2327226e8a31f601bf8ad68a4f13b5beeb9f963a936d8154ad78fe`。
  - Windows DLL：370176 bytes，SHA256 `a0b6456f9b88cccb43ae3477e8d4ca909aa6cce3d6652cca42ebfb0caf219a73`。
- 结果：Linux ClassDB.class_exists("FateProcessOwner") 应返回 false，管理器安全阻断 create/recover，不能把源码跨平台支持当成已发布功能。
- 建议：在真实 Linux 构建环境重新构建正式 SO并核验依赖/导出/类方法注册；Windows 字符串存在只证明包含绑定，不能代替实际 Godot 加载与调用验收。禁止 Godot 的本批不补此运行结论。

### P2 — recover 的发布/清理失败可能留下磁盘登记分叉或不可管理新进程（失败分支静态确认）

- 证据：`server_room_manager.gd:329-336` 先发布新 config.instance_id；旧 ready 删除失败、spawn 失败、旧 token release 失败时，`:340-341/:349-350/:356-357` 回写旧 instance，但忽略 write_configuration 的返回值。
- 更严重分支：`:353-359` 在新子进程已启动后才释放旧 token；若旧释放失败，对新 token 的 terminate/release 均忽略结果，且未把新 token/PID 登记到 rooms 或待清理集合。
- 结果：回写失败时，内存旧 instance 与磁盘新 instance 不同，后续 recover 被配置一致性校验拒绝；终止失败时新进程虽仍在 native owner map 中，但主管业务层不再持有其绑定，不能按房间重试清理。不能将该分支称为“恢复失败关闭已完成”。
- 建议：旧 EXITED 所有权应在新 spawn 前确认可释放；失败恢复过程要保留显式启动中/待清理记录，任何新 token 都保持可寻址，直到确认 EXITED + release。配置回写错误单独报告并保留可重试修复状态。ready 清理放在新配置最终发布前，或采用显式可恢复发布状态；不是靠外层字段回滚伪造磁盘事务。
- 补验收：注入旧 release 失败、新 terminate 超时、配置回写失败，确认无失联 token、无成功回执、后续管理操作能继续诊断/清理。

### P2 — close / 析构吞掉终止失败，不能证明所有自有进程已退出（静态确认）

- 证据：`server_room_manager.gd:395-397` 的单房 stop 正确在 terminate/release 失败时保留登记；但 `close():401-403` 不汇总 stop_room 返回值。`server_gateway.gd:433-447` 已清掉连接/认证状态后调用这个 void close，无法向调用者表明仍有房间运行。
- `server_room_manager.gd:405-408` PREDELETE 忽略 terminate 结果；`process_owner_core.cpp:259-262` 析构对每个 entry 调用 stop 后无条件 dispose，即使 stop 返回 false 也关闭句柄并丢失后续控制能力。
- 影响：显式关闭失败无机器可判定回执；析构终止超时/失败时可能让仍运行的 worker 失去原生所有权。worker `server_room_worker.gd:203-216` 的心跳失联退出是 ready 之后的协作兜底，不能证明卡在启动/阻塞执行中的进程也会退出。进程句柄本身也不具备主管被硬杀后自动杀子进程的语义。
- 建议：close 返回逐房间结果并保持管理器存活及待清理队列直到真实退出；析构作为 best-effort，不能替代已确认关闭。若需求包括主管异常死亡的强退出保证，另行考虑 Windows Job Object(KILL_ON_JOB_CLOSE)、Linux 受约束生命周期机制，明确其继承/竞态边界；不能仅以心跳或句柄存在宣称强保证。

### P2 — dedicated 监听入口未在能力缺失时提前阻断（静态确认）

- 证据：`server_gateway.gd:37-43` listen 只验证目录并立即 transport.listen；`server_cli.gd:123` 的 game 角色直接调用此入口。脚本全量调用点搜索中，只有 LAN/P2P `authority_host_client.gd:26` 有额外主管能力门禁。
- 结果：缺新增扩展或 Linux 当前旧 SO 时，dedicated 仍可监听，却不能创建/恢复任何真实工作进程。create/recover 自身已在写入/spawn 前阻断，不会因此退回裸 PID，但服务启动成功会掩盖不可用部署。
- 建议：在 game 服务监听前调用 process_ownership_available，缺失返回 ERR_UNAVAILABLE 与现有中文说明；不影响纯信令角色。保留 poll 撤销 ready 的现有防线。

## 已静态确认的正确接线

- `process_owner_binding.cpp:16-38` 暴露 available/spawn/state/verify/terminate/release，verify 明确只接受 RUNNING；注册在 SCENE 初始化级别，.gdextension entry_symbol 与导出初始化入口对应，Windows bcrypt 链接项存在。
- `process_owner_core.cpp:125-148` Windows spawn 持有 CreateProcess 返回句柄，不重新按 PID 认领；命令参数采用引号/反斜杠转义，拒绝 NUL/非法 UTF-8；不允许继承句柄。
- `process_owner_core.cpp:155-196` Linux clone3 原子 pidfd，执行门在登记句柄后才放行，并通过 CLOEXEC 管道确认 exec；缺能力失败关闭，没有不安全 fork+PID fallback。
- token 是 CSPRNG 128-bit 能力，仅位于 native map 与 room 内存；discover_rooms:283 不从文件认领 token/PID。state/terminate/release 都要求同一 owner map 的 token/PID 成对匹配，release 只允许 EXITED。
- create_room:127 在目录写入/spawn 前门禁；recover_room:294 同样先门禁，正 PID 必须确认 EXITED，不会靠 OS.is_process_running 或 ready 自证所有权。
- recover_room:337-343 在 spawn 前清旧 ready；每次重启产生独立 instance_id 和 engine.<instance>.log。ready 校验匹配 room/PID/instance/mode；is_ready 额外校验原生句柄 RUNNING。
- poll 检测异常退出保留房间和原目录，stop_room 的正常成功路径先 terminate（内部等真实退出）再 release，再擦登记。停止不删除存档目录。
- 本轮源码搜索未发现主管通过 OS.kill/OS.create_process 持有或终止生产 worker；现有真实崩溃测试中的 OS.kill 是测试注入，不能作为生产所有权实现。

## 验证与尚未验收

实际执行：生产源码/构建文件/发布映射/调用方/既有测试静态读取，git status/diff 只读命令，Python 读取正式 DLL/SO 的大小、SHA256 与绑定字面量。git 显示本范围 addons 与 manager/gateway 为未跟踪文件，故 git diff 为空不能当成“无实现”或可靠基线；审计以当前磁盘源码为准。

未执行：Godot、GDExtension 实际加载、原生编译、子进程 spawn/exit/terminate、跨平台 PID 复用与外来 token 测试、网关公开恢复测试。没有把字符串扫描或源码检查当成真实 OS 生命周期通过。建议主代理修 P1 接线后再串行做运行验收，尤其补公开恢复入口与失败注入，而非仅重复 manager 单组件成功路径测试。
