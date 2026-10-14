# Round47：worker launch route 收敛与关闭证明交接

## 已完成

- 唯一生产修改：`scripts/net/server/server_bootstrap.gd`、`scripts/net/server/server_room_manager.gd`。
- 新公开静态入口：`role_scene_arguments(role:String, engine_arguments:PackedStringArray, role_arguments:PackedStringArray) -> PackedStringArray`。
- 只从现有 `PROCESS_ROUTES` 选择四个场景角色：console、room worker、validation worker、gateway；纯 signaling 非场景角色及未知角色返回空 argv。engine 参数已有 `--` 或 `--scene` 也拒绝，避免第二场景来源/分界。
- builder 只复制并组装 argv，依次追加 `--scene <现声明scene> -- <role> <payload>`，最后复用现 `process_arguments`。未复制 spawn，未改 executable、Windows 引用规则、原生 owner、console 模式或 PCK 入口。editor 非 fate_server 保留 path/scene；其他入口仍由原 process_arguments 剥除分界前 path/scene；`--main-pack`、log/audio 和分界后字节保留。
- manager 的 create/recover 两处都真实调用 builder，原生 spawn 直接消费返回 argv；两处 worker `.tscn` 硬引用已删除。批准根仍由本机 manager 显式设置，三个路径仍由原逻辑 globalize。CLI 没有认证 key；实例身份/认证 IPC 不变。
- 未写 server_cli、worker、validation_task、cleanup ledger、native 或 gate/allowlist。

## 同冻结真实短套

运行命令（仓库根）：

```text
python tests/round47_worker_launch_route_runner.py final
```

证据根：
`E:/Projects/Godot/FateDomination/test/round47-worker-launch-route/final-71f14e4be3664c8292e3a3018de854af/`

- `manifest.json`：passed=true；contract exit0/22 checks；`--custom-features fate_server` contract exit0/22 checks；lifecycle exit0/39 checks，32.463秒；均 failures=[]。
- 真正使用当前官方4.7.2 engine 的 E 盘独占副本，源/副本 SHA256 一致；未升级/覆盖引擎。APPDATA、LOCALAPPDATA、TEMP、TMP、TMPDIR 均显式设 E 独占路径。
- 主/真实 child user-path probe exit0（不是 authority worker 的替身验收）；正式 worker 则另用真实 native spawn/READY、Windows Win32_Process 的 CommandLine/ExecutablePath/ParentProcessId 精确核对。正式父进程 PID1720，fresh PID33608，restart PID25640；两次 child binary 真实为 E 根，三个批准路径及实际日志/房间文件也在 E 根。
- `evidence/retained/runtime/launch-evidence.json` 保存 fresh/closed/restart 绑定、READY、精确 builder argv 与实际 WMI 命令行、父 user 路径和实际关闭回执。
- 房间 `498bccfc1932ceca45e438bf4b033e34`：fresh instance `2d1b7b55a5f1f61693ec8b4e75f3bc32`；restart instance `c1cad30f5ecb26c2a44a77cebead04a9`。
- 成功关闭请求 `4642f2577d73fe9ae0c83ab2f030affc`：真实 result 为 closing=true、room_state_saved=true、saved=false（保存大厅状态，不冒称对局录制存档）；随后真实 EXITED/release 才产生 closed binding。
- 负向：未知 role、不允许第二 scene/分界；fresh/restart 缺 approved root；存活实例不可 release；真实 recovery 目标目录冲突使 worker 保存拒绝、仍存活且无 closed；pending close 不准 recover/不准伪造历史；失败 request 不能借成功历史；restart 后旧 closed 不授权新实例/旧 binding 不得 release 新实例。
- parent/stdout/stderr 与两份 worker engine 日志均无 SCRIPT ERROR/SHADER ERROR/ERROR；自有外层 Job 各次 ActiveProcesses=0。restart 测试最终仅 native owner 清理，不冒称第二次保存退出。
- 四个拥有的 .gd 与最终冻结哈希逐一一致。generated 工程/engine/user/runtime 仅在自有 Job 为0后回收；保留 manifest、命令、日志、绑定回执、最小源码及 artifact SHA256。
- 没跑235秒整局，不宣称自然终局、窗口、多机、实际发行PCK启动或完整CLI部署验收。fate_server contract 是当前 engine 的参数剥离分支验证，不是新导出包。

TDD：有效业务 RED 在 `red-a14b8038e9464157ad396aface48540a`，exit1、1 check 精确缺公开API；不是 parser error。初次 `red-ff038b0d02d645d08a95b5b956ce14f8` 的 fixture 对 preload class 直接 has_method/call 导致解析失败并触发180秒看门狗，仅算夹具问题，不算业务 RED；改为未入树 Node 实例动态调用后重新观察有效 RED。旧尝试 generated 也仅按自有 Job 为0证据归档后回收。

## 给主代理：精确退休 Gate2 两项（由主唯一删除）

实跑 `python tools/check_layer_deps.py` 返回 exit1，findings=62、allowlist=80、new=0、stale=18。这里只贡献两项 layer STALE，其余16项为并行测试迁移；不修改闸门、不以扩大许可掩盖。

`tools/check_layer_deps.py` 当前读到的170、171行，分别保留 provenance 347、564。只删下面两条，bootstrap 四个 route 例外保留：

```python
ExceptionSite("layer", 'scripts/net/server/server_room_manager.gd', 'res://assets/scenes/main_menu/server_room_worker.tscn', 'var arguments := PackedStringArray(["--headless", "--audio-driver", "Dummy", "--path", ProjectSettings.globalize_path("res://"), "--log-file", ProjectSettings.globalize_path(log_file), "--scene", "res://assets/scenes/main_menu/server_room_worker.tscn", "--", "--server-room-worker", ProjectSettings.globalize_path(directory.path_join("config.json")), ProjectSettings.globalize_path(_approved_root()), ProjectSettings.globalize_path(storage_root)])', 347),
ExceptionSite("layer", 'scripts/net/server/server_room_manager.gd', 'res://assets/scenes/main_menu/server_room_worker.tscn', 'var arguments:=PackedStringArray(["--headless", "--audio-driver", "Dummy", "--path", ProjectSettings.globalize_path("res://"), "--log-file", ProjectSettings.globalize_path(log_file), "--scene", "res://assets/scenes/main_menu/server_room_worker.tscn", "--", "--server-room-worker", ProjectSettings.globalize_path(config_path), ProjectSettings.globalize_path(_approved_root()), ProjectSettings.globalize_path(storage_root)])', 564),
```

`git diff --check -- scripts/net/server/server_bootstrap.gd scripts/net/server/server_room_manager.gd` exit0。新增 tests 被原仓库 ignore；无普通 git diff 不表示未创建，最终 manifest 有源码哈希。

## 给 validation_task 串行消费者（只交接口）

在原 start 的 engine 参数里保留 `--headless --audio-driver Dummy --fixed-fps 60 --path ... --log-file ...`；移除自写 scene/分界/role，把原 data_directory、manifest、report（及可选 simulation_path）作为 payload。调用：

```gdscript
var arguments:PackedStringArray = Bootstrap.role_scene_arguments("--room-data-validation-worker", engine_arguments, role_arguments)
if arguments.is_empty():
    # 原任务错误返回，不调用 create_process。
    return false
process_id = OS.create_process(OS.get_executable_path(), arguments)
```

builder 已应用 process_arguments，无需再次处理；payload 的选项文件仍在 `--` 后。部署授权与生命周期不迁入 builder。该文件保持只读，主代理后续串行接线/实跑。

## 给 cleanup 能力 owner：真实现有证明定义

下列都是已读的现有接口，未新增 bool 或公开可变原生 owner：

1. `ServerRoomManager.instance_binding(id)` 返回 `{room,pid,instance_id,authority_host_mode}`。`binding_matches` 只核当前登记身份；`process_state_for_binding(binding)` 是原 token+PID 句柄状态 RUNNING=1、EXITED=0、UNKNOWN=-1，不得退回裸 PID。
2. `hold_process_supervision(id,request_id)` 要求合法请求及 RUNNING，持有同请求关闭监督。`release_process_for_binding(binding,request_id)` 只在同绑定 EXITED、同 supervision/request 且 native release 成功后记录 `closed_process_binding`，将 pid=-1/token空/ready=false。
3. `closed_binding_for_request(id,request_id)` 仅返回当前登记 instance/mode 对应、pid=-1/token空、request/room 完全匹配的闭合绑定副本。返回形状严格是原 binding merged `{request_id}`。restart 更新 instance 后旧历史返回空。本测试真实覆盖这些语义。
4. **closed 本身只证明 EXITED+release，不单独证明保存。** 保存还需 `ServerConsoleChannel.saved_close_receipt(response)` 的真布尔 ok、closing 和 saved 或 room_state_saved，并核对 room/pid/instance/mode/request 完整同绑定。console 的公开 `poll()` 只有实际回执和真实退出才正常释放；公开 `execute("room <id> result <request>")` 提供绑定结果及 consumption_sha256。
5. `retired_binding_for_request` / `retire_unconfirmed_close` 也基于实际 EXITED+release，但保存未确认，只允许迟到回执读取，不授权清理/恢复/停止新实例，不能当 saved closed。
6. 已有公开消费口 `ServerConsoleChannel.acknowledge_close_result(args, expected_sha256, consumed_at)`，或可信本机 `room <id> consumed <request> <sha256>`。它校验保存回执与摘要，再将真实 closed 交给 `TemporaryCleanupLedger.consume_close`。ledger 核注册 producer、完整绑定/请求、磁盘回执一致和哈希；读取 result 或 poll 不等于显式消费。
7. **manager/native 没有 Job-release 或“所有派生进程已退出”公开证明。** `addons/fate_server_signals/src/process_owner_core.cpp` 的 Windows spawn 持有 CreateProcessW 返回 hProcess；inspect 用 WaitForSingleObject，release(253–258) 只确认该 token/PID EXITED，再 CloseHandle/erase。没有 JobObject。测试工具 `tools/run_isolated_godot_test.py::OwnedJob.active()` 是本次外层 Job accounting ActiveProcesses=0，属于验收独占容器，不能当生产 manager 的跨进程能力。
8. 现 `ServerConsoleChannel.poll_cleanup_schedule` 明确 blocked=true、removed_files=0，missing_capabilities 为 complete_instance_registry、cross_process_file_exclusion。manager.rooms 观测集合不是全系统完整性/文件互斥证明。ledger.cleanup 的 snapshot 对 current_instances_complete、exclusive_files 的需求不能靠新增 bool=true 满足；本轮未提供这两项缺失能力，也未触碰 cleanup owner 文件。

新增产物：`tests/round47_worker_launch_route_test.gd/.tscn`、`tests/round47_worker_launch_lifecycle_test.gd/.tscn`、`tests/round47_worker_launch_route_runner.py`、本文。
