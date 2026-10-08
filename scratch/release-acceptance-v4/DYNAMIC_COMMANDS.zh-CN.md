# 必须串行的动态验收命令 — 当前全部 NOT_RUN

本轮禁止运行 Godot，以下是交给主代理的执行清单，**不是已执行日志**。必须逐阶段人工核对后继续；不得并发导出/跑游戏/修改源码。任一失败停止本批，保留原日志和文件，不删除用户数据、不按名字全局杀进程。

## 0. 前置门槛（NOT_RUN）
所有生产写入者退出→主代理审核交接→冻结版本与干净独立副本→记录源码 SHA/版本→独立测试 namespace。若坚持全产物都在 scratch，现有夹具会写 user://；先审阅每套实际输出路径并隔离。`--user-data-dir` 不在本轮确认的引擎接口中，不能臆造参数。

先核对两平台模板、原生库、导出插件已启用；纯信令重新暂存，确认共享 bootstrap SHA 已与当前源码同步，显式 load/preload 闭包无规则。Windows 信号适配 DLL/SO ABI 和系统依赖需要在实际平台验证，文件存在不算加载。

下面 `$PROJECT` **必须指获批冻结副本**；路径由主代理实际创建后填入，不能拿共享树直接边改边跑。

```bash
GODOT='D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe'
AUDIT='E:/Projects/Godot/FateDominationGame-master/scratch/release-acceptance-v4'
PROJECT='<获批冻结副本绝对路径>'
BUILD="$AUDIT/<本次唯一批次>/dist"
# BUILD 须不存在；创建新目录，不复用旧 server-dist。
mkdir -p "$BUILD/windows" "$BUILD/linux"
```

## 1. 两平台实际 release 导出（NOT_RUN）

```bash
"$GODOT" --headless --path "$PROJECT" --export-release 'FateServer Windows' "$BUILD/windows/FateServer.exe" > "$BUILD/windows/export.log" 2>&1
code=$?; printf 'windows export exit=%s\n' "$code"
# 检查退出码+完整日志+Windows实物与manifest后才执行下一条。
"$GODOT" --headless --path "$PROJECT" --export-release 'FateServer Linux' "$BUILD/linux/FateServer.x86_64" > "$BUILD/linux/export.log" 2>&1
code=$?; printf 'linux export exit=%s\n' "$code"
```

每平台检查 executable、PCK、data、实际平台 WebRTC 库、信号 gdextension + DLL/SO（库可能被 Godot 导出到顶层，按包内 gdextension 映射核对，不能机械要求源码目录形状）、Windows `.console.exe`。记录 SHA256；PCK 内 CFG 与冻结模板一致；data 全量文件哈希相同且无额外规则，不只数条目；无旧 tmp/~文件。导出插件 push_error 不一定使退出码失败，完整日志是准入条件。

## 2. 首次 CFG、路径与真实启动（NOT_RUN）
从其他 cwd 启动，配置使用本批绝对路径，首次目标须不存在：

```bash
cd C:/Windows
"$BUILD/windows/FateServer.console.exe" --headless --audio-driver Dummy --log-file "$BUILD/windows/first.log" -- --server-gateway --config "$BUILD/windows/server.cfg"
```

应只 `SERVER_CONFIG_CREATED`、退出0、未监听。随后**只编辑本批测试 CFG**：`data_root="data"`；storage_root/identity_registry/console_dir/status_file 全部显式指向本批隔离绝对路径；身份库新建、无真实凭据。显式设置空闲公开 UDP/TCP 端口与内部范围、四策略、data预算。未知字段/段、策略非法值、roles冲突应整体失败，不发布 ready；合法启动命令同上。核对本次 PID、角色、端口和实际可执行文件，ready 原子回读。

Linux 先只读查询发行版，不改默认发行版：
```bash
wsl.exe --list --verbose
```
若确认为 FateLinux，用受控安装将本批 Linux 包复制到**新建的** `/home/fate/<本次唯一批次>/`；房间/身份/control/日志用 Linux 原生目录，不能借旧 WSL 包。从 `/` 启动：
```bash
wsl.exe -d FateLinux --exec bash -lc 'cd /; /home/fate/<本次唯一批次>/FateServer.x86_64 --headless --log-file /home/fate/<本次唯一批次>/engine.log -- --server-gateway --config /home/fate/<本次唯一批次>/server.cfg'
```
网关常驻应由受控协调器持有 PID/句柄并管理本批生命周期，不用一条无超时前台命令当完整自动验收。当前上述目标目录尚未创建，故 NOT_RUN。

## 3. Windows 发行专项（NOT_RUN）
只有两套当前有新包目标钩子，可显式运行：
```bash
FATE_TEST_SERVER_EXECUTABLE="$BUILD/windows/FateServer.exe" "$GODOT" --headless --fixed-fps 60 --path "$PROJECT" --scene res://tests/net_server_export_test.tscn > "$BUILD/windows/runtime.log" 2>&1
# 核对本套，再执行下一套。
FATE_TEST_SERVER_EXECUTABLE="$BUILD/windows/FateServer.exe" "$GODOT" --headless --fixed-fps 60 --path "$PROJECT" --scene res://tests/net_server_export_identity_test.tscn > "$BUILD/windows/identity.log" 2>&1
```
- `net_server_export_reload_test`/`net_server_export_create_test`：**NOT_RUN / BLOCKED_NEW_TARGET**。reload硬编码旧exe，create继承reload；设 FATE_TEST_SERVER_EXECUTABLE 不能改变目标，需获批夹具适配后再列命令，不能改生产或覆盖旧包取巧。
- `net_server_roles_test`：**NOT_RUN / BLOCKED_CURRENT_ROLE_CONTRACT**。虽然读 FATE_TEST_SERVER_BINARY，但当前仍以根游戏项目 `roles=[relay]` 期望成功；新源码明确拒绝。它不是独立纯信令项目验收，不能把新安全拒绝改成旧期望求绿。

源级生命周期补充，独立逐套运行，不能代替 release：
```bash
"$GODOT" --headless --fixed-fps 60 --path "$PROJECT" --scene res://tests/authority_worker_lifecycle_contract_test.tscn > "$BUILD/lifecycle-source.log" 2>&1
"$GODOT" --headless --fixed-fps 60 --path "$PROJECT" --scene res://tests/identity_inheritance_test.tscn > "$BUILD/inheritance-source.log" 2>&1
```

## 4. 真实 stdin/管理、安全 stop（NOT_RUN）
先网关独立运行且本批 control.json 已回读，输入端独立启动：
```bash
printf 'status\nhelp\nnot-a-command\nexit\n' | "$BUILD/windows/FateServer.console.exe" --headless --audio-driver Dummy -- --server-console "$WIN_CONTROL"
wsl.exe -d FateLinux --exec bash -lc "printf 'status\\nhelp\\nnot-a-command\\nexit\\n' | '$LINUX_EXE' --headless -- --server-console '$LINUX_CONTROL'"
```
WIN_CONTROL、LINUX_EXE、LINUX_CONTROL 均为协调器本批真实路径，未给出前不运行。必须另测 stdin 开着不输入期间 UDP 真实入房仍响应，EOF/exit 后网关活着；再独立输入 `stop`，核对保存回执完成、SERVER_STOP_COMPLETE、所有 worker 实际退出、ready清理和存档/审计可读回。只获得 pending 不能认定保存成功。

## 5. Linux 远端预检/窗口完整局/恢复（NOT_RUN）
先协调器独立启动本批 Linux 服务，报告取得真实地址/端口（不固定旧IP/不假定localhost UDP）：
```bash
wsl.exe -d FateLinux --exec hostname -I
FATE_TEST_SERVER_ADDRESS="$LINUX_ADDRESS" FATE_TEST_SERVER_PORT="$LINUX_PORT" "$GODOT" --headless --fixed-fps 60 --path "$PROJECT" --scene res://tests/net_server_linux_preflight_test.tscn > "$BUILD/linux/preflight.log" 2>&1
FATE_TEST_SERVER_ADDRESS="$LINUX_ADDRESS" FATE_TEST_SERVER_PORT="$LINUX_PORT" "$GODOT" --fixed-fps 60 --path "$PROJECT" --scene res://tests/net_server_linux_match_test.tscn -- window > "$BUILD/linux/match-window.log" 2>&1
FATE_TEST_SERVER_ADDRESS="$LINUX_ADDRESS" FATE_TEST_SERVER_PORT="$LINUX_PORT" FATE_TEST_LINUX_ROOM_ROOT="$LINUX_ROOM_UNC" FATE_TEST_LINUX_CONSOLE_ROOT="$LINUX_CONSOLE_UNC" "$GODOT" --fixed-fps 60 --path "$PROJECT" --scene res://tests/net_server_linux_save_recovery_test.tscn -- window > "$BUILD/linux/save-recovery-window.log" 2>&1
```
逐条协调器清理并重新独立起服务，不共享前一测试房间状态。Linux room/control UNC只用于读证据/本机管理回执；客机同步文件在Windows本地。既有恢复夹具部分硬编码 FateLinux；若改发行版，先审阅并适配，不仅替换外层 --distro。`net_server_linux_gateway_restart_test` 还需 FATE_TEST_RESTART_REQUEST/RESULT 外部协调器，单独tscn不能完成整网关重启，当前 **NOT_RUN / BLOCKED_COORDINATOR**。

默认身份认证开启的组合恢复需另验：save→crash→新instance/独立日志→原钥+原票据重连→全部原真人与data屏障→恢复真实中局并继续；错钥持有效票据、缺绑定旧档、房主明确member_id继承、过期revision/sequence拒绝分别记录。旧身份关闭的夹具不证明这些链条。根事务回滚与进程崩溃恢复分开，重启不叫回滚。

## 6. 原生系统信号（NOT_RUN）
当前 `tests/run_server_signal_acceptance.py` 的 Windows release binary仍硬编码旧dist，root写旧test目录，且 identity_registry=""；**Windows新包信号验收 BLOCKED_NEW_TARGET**，需要获批测试协调器增加实际 --windows-exe/--output-root/认证模式后才运行。不得执行不存在的参数。

Linux已支持下列真实参数，但输出仍落旧test根，如本轮要求只写scratch，也先适配协调器；以下只在输出范围获批后适用：
```bash
python "$PROJECT/tests/run_server_signal_acceptance.py" --platform linux --release --distro FateLinux --linux-exe "$LINUX_EXE" --linux-storage-base "$LINUX_SIGNAL_STORAGE" --signal term
# 完成并清理本批后另起：--signal int；分别追加 --reject 验拒绝保持活着。
```
独立Windows Ctrl+C/Ctrl+Break、Linux SIGINT/SIGTERM成功/拒绝分支；真实store/flush/rename失败与超时也需独立故障夹具。只发给协调器持有的本批OS进程身份，不能仅kill(pid)并以PID存在当身份。未录制拒绝不算认证恢复。CTRL_CLOSE/LOGOFF/SHUTDOWN 未支持，单列 NOT_RUN/UNSUPPORTED，不以系统关机做破坏测试。

## 7. 独立纯信令发布（NOT_RUN / BLOCKED_NOT_RELEASED）
正式发行目标尚无，无可执行发布命令。先由主代理获批生成独立project和两平台export_presets，再用实际预设名串行导出（不发明当前不存在的预设）。当前候选仅源级入口：
```bash
"$GODOT" --headless --path "$SIGNALING_PROJECT" -- --server-signaling --config "$SIGNALING_CFG"
```
只能用于重暂存后候选，不等于release；必须有 --server-signaling，候选不提供缺省game场景。CFG仅允许server地址/端口/预算/roles=[relay]及relay段；拒绝data/storage/管理字段。真实WebSocket→建房/限流/打洞、同端口UDP可绑定、无规则autoload/worker/save/游戏字节；停信令后已建立WebRTC双向对局继续。两机异地NAT/无TURN游戏流量与物理Linux、长期负载分别 NOT_RUN。

## 最终记账
每项独立记录命令、实际二进制与源码SHA、完整日志、退出码、RESULT checks/失败/错误、window段实际开启、room/PID/instance与OS句柄身份、状态/保存/审计回读。本清单所有动态项 status=NOT_RUN，exit/checks/error_count=null，不能填0或沿用旧绿。
