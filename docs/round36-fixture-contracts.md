# Round36 fixture contracts

## 结论与边界

Round33 三红项已在真实 Godot 专项中 RED → GREEN；三个目标各完成两次 GREEN，另有五套直接相关回归通过。四个 false/早退负向均真实 exit1、唯一合法 RESULT、failures=1，严格分析器明确拒绝，没有吞掉失败。

只修改以下三个测试脚本，三个 `.tscn` 原字节保持不变：

- `tests/gateway_deferred_test.gd`
- `tests/gateway_disconnect_safe_close_test.gd`
- `tests/client_match_inbox_contract_test.gd`

未修改 production、generic runner、aggregator、gate 或 allowlist；未 git add/commit。未将本轮专项结果改写为 Round33 全量通过，也未验收窗口输入。

## 根因与局部修复

1. `gateway_deferred` 的 RefCounted 手拼桩缺具体 transport 的恢复探针、三个应用信号及 manager.rooms。改用现有 `enet_transport.gd`、`server_room_manager.gd` 具体基类，继承完整契约，只保留调度回调、trace、安全关闭时机与 binding 判据替身。link close 调用现有 `super.close()`；没有向生产添加 setter，也没有新访问 `_recovery_probe`。原16项调用条件/标签的词法 token 完全一致，调度→即时响应→延迟错误→detach/close、重复通知/关闭去重、替换路由及静默关闭断言全部保留。scope 用 `JSON.stringify` 输出。
2. 安全关闭专项旧 `RESULT ... PASS errors=0` 没有合法 checks/failures。`check()` 增加真实计数与 CHECK 事件，原7项断言不变，终点输出 `checks=7 failures=0`。
3. F06 原34项完成后输出第一条 RESULT，重连11项后又输出 RESULT，并含裸 `status=GREEN/RED`。中间改 PROGRESS，正常终点和原早退分支删除冗余 status，分别只有一条合法 RESULT；保留原34+11项实际执行和全部条件/标签。静态41个调用点因五次循环实际执行45项，未按重复文案去重。

三个 check 函数都输出逐次 CHECK，合法 RESULT 的计数与真实事件数严格一致。

**调度替身仅证明控制流，不证明 OS PID、句柄、进程身份或安全保存关闭。** 原生证据来自另跑的 `gateway_relisten_acceptance_test` 正式独立 worker：真实创建、句柄/ready、保存回执、EXITED/release、显式重监听38项全部通过；与路由替身分开报告。

## 真实执行

执行入口（归档内保留相同 harness/verify 源码）：

```text
python -B E:/scratch/round36-fixture-harness-daee9f61a91d42729761edb7398d402d.py prepare
python -B E:/scratch/round36-fixture-harness-daee9f61a91d42729761edb7398d402d.py green
python -B E:/scratch/round36-fixture-harness-daee9f61a91d42729761edb7398d402d.py finish
python -B E:/scratch/round36-fixture-verify-daee9f61a91d42729761edb7398d402d.py
python -B tools/check_layer_deps.py --json
```

前三命令及 verify 实际 exit0。每套真实命令为：

```text
E:/scratch/isolated-daee9f61a91d42729761edb7398d402d/generated/Godot.exe --headless --fixed-fps 60 --path E:/scratch/isolated-daee9f61a91d42729761edb7398d402d/generated/project --scene res://tests/<suite>.tscn
```

每进程180秒，无窗口；3 GiB生成树监控预算、1 GiB剩余空间下限。所有进程挂起后加入自有 Windows Job 再恢复，仅管理本次自有PID；20条根进程记录均已退出、ActiveProcesses=0、日志句柄释放，无超时/预算终止。字节预算是监控阈值，不是系统磁盘配额。

冻结只复制明确项目依赖和所选测试及其显式引用，不复制整个 tests、旧证据或缓存。复用只读 runner 的 execute/verify_probe/delete_owned 与只读严格 aggregator 的 analyze；隔离副本 project.godot 只按既有授权转换两项 `[editor]` VCS 设置，原工程不改，threading=20保留。导入 exit0、errors=[]。

### RED（修改前本轮真实重现）

|目标|exit|原始输出/拒绝|
|---|---:|---|
|gateway_deferred_test|1|checks=16 failures=7，缺探针/信号/rooms 的 SCRIPT ERROR，裸scope不合法|
|gateway_disconnect_safe_close_test|0|`RESULT gateway_disconnect_safe_close PASS errors=0`；invalid_result|
|client_match_inbox_contract_test|0|两条 RESULT（34/45），最终裸status；expected_one_stdout_result|

原始 RED 日志及对应失败源码原字节独立保留，未以 GREEN 覆盖。

### GREEN（同一隔离副本，仅三个独占测试更新到修复字节）

|suite|exit|checks|failures|RESULT|
|---|---:|---:|---:|---|
|gateway_deferred_test|0|16|0|唯一合法，scope="scheduling_unit_only"|
|gateway_disconnect_safe_close_test|0|7|0|唯一合法|
|client_match_inbox_contract_test|0|45|0|唯一合法；中间PROGRESS checks=34 failures=0|
|gateway_instance_binding_test|0|20|0|唯一合法|
|gateway_relisten_acceptance_test|0|38|0|唯一合法，正式独立worker|
|client_identity_inbox_contract_test|0|58|0|唯一合法|
|host_room_inbox_contract_test|0|34|0|唯一合法|
|match_command_result_protocol_test|0|39|0|唯一合法|

八个唯一专项合法 checks 合计257；三个目标负向恢复后各再次GREEN，因此正向运行11次。所有正向 stdout/stderr 均无 SCRIPT ERROR、ERROR、FAIL或 false CHECK；每次严格分析 passed=true。

### false/早退负向（仅自有冻结测试文件变异）

|负向|exit|checks|failures|严格分析|
|---|---:|---:|---:|---|
|gateway_deferred 响应→延迟错误→关闭断言替换 false|1|16|1|false_check/result_failures/nonzero_exit，拒绝|
|安全关闭第一项断言替换 false|1|7|1|false_check/result_failures/nonzero_exit，拒绝|
|F06 第一项断言替换 false，仍走完34+11|1|45|1|false_check/result_failures/nonzero_exit，拒绝|
|F06 合法view夹具观察者7改8，真实拒绝触发原早退|1|6|1|false_check/result_failures/nonzero_exit，拒绝|

四次均 stdout 单 RESULT、检查事件数等于 checks，无脚本解析错误。变异未触碰共享源码；每次 finally 恢复冻结文件原字节，摘要读回一致，三个目标恢复后实际重跑通过。负向失败不计入正向通过数。

## 隔离与归档回收

主进程探针 PID8808，OS.create_process 真实 child PID22772；随机token相同且PID独立。两者 `OS.get_user_data_dir()` 以及物理读回均为：

```text
E:/scratch/isolated-daee9f61a91d42729761edb7398d402d/generated/appdata/FateDomination
```

主/child token文件和JSON回执摘要校验一致，child实际退出码0；主/child实际 worker_pool_max_threads均20。正式独立worker的保存关闭在相关回归单列验证，未用最小child代替其业务证明。

归档：

`reports/refactoring/round36-fixture-contracts-daee9f61a91d42729761edb7398d402d/`

- `manifest.json`：真实命令、PID、退出码、严格判定、源码指纹、探针及清理回执。
- `evidence/*.stdout.log` / `*.stderr.log`：3次RED、11次GREEN、4次负向及probe/import原始日志。
- `evidence/red-source/`、`green-source/`、`negative-source/`：有界夹具源码证据。
- `fixture-changes.patch`：相对本轮RED原字节的实际diff。
- `verification.json`、`gate-before.json`、`gate-after.json`、`harness.py`、`verify.py`：断言保留、计数/负向、门与归档摘要验证。

归档日志逐项SHA256读回一致；源Godot摘要不变；除三个授权夹具外冻结所覆盖源文件期间漂移=[]。归档后整树无链接/边界及进程退出复核，generated（独占E引擎、项目/import缓存、APPDATA、fixtures）已回收；精确路径存在=False，只保留最小证据。

A04/A05改前、改后均PASS/exit0：findings=80、allowlist=80、NEW=[]、stale=[]，未增加私有访问或扩allowlist。

## 已知限制

- 三个目标测试被 `.gitignore:47:/tests/` 忽略，普通 git diff 不展示修改；所以保存RED/GREEN字节、SHA256与显式 `fixture-changes.patch`，没有用空diff冒充未改。
- 脏工作树全局 `git diff --check` 实际exit2，仅打印已有其他文件CRLF转换警告；未修改这些非本次文件。目标修改以有界归档diff、Godot执行、词法断言比较和门校验为准。
- 本轮只完成三夹具契约与直接相关回归，不是全66套新的整合freeze，也不是GUI/多机/公网验收。
