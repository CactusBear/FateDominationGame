# Round36 三网关部署／发现夹具

## 结论

**局部完成，整体 RED；不能宣布三套全 GREEN。**

- `net_server_gateway_test`：真实 Godot exit 0，唯一 `RESULT checks=19 failures=[]`。
- `net_server_discovery_validation_test`：真实 Godot exit 0，唯一 `RESULT checks=33 failures=[]`。
- `net_server_gateway_restart_test`：真实 Godot exit 1，唯一 `RESULT checks=55 failures=["中局崩溃恢复后真人继续提交操作直至终局"]`。原生独立 worker 的磁盘发现、新实例恢复、双客户端完整镜像等价及恢复后双方新操作均通过；完整终局门仍红，没有删掉这个断言来制造 GREEN。
- 故意坏根三例、错钥两例：均 exit 1、唯一合法失败 RESULT、无脚本／引擎错误；执行器逐例 `expected_failfast_observed=true`。最终整套驱动器 exit **1**，不按 Python 编排成功冒充 Godot 成功。
- 最终同一候选源码漂移 `[]`；不拼接前后运行通过数。无窗口验收。

## 权限与修改范围（中文 V4A）

仅三份分配的 `.gd` 和独占新增夹具有写入。production、aggregator、既有父测试和旧证据只读。

1. `tests/net_server_gateway_test.gd`：先验证显式物理 E 输出参数，配置正式部署批准数据根、策略及登记库；客户端通过正式 `configure_identity` 生成合法 RSA，真实网络挑战完成登记；验证 manager 原生句柄、ready 报告和实际存活状态；冷缓存放独占根；失败立即返回 RESULT；收尾走真实保存关闭。
2. `tests/net_server_gateway_restart_test.gd`：仍继承完整真人中局 baseline，不用单元测试命令代替 Godot。复用执行器环境及首输出根参数，显式身份和部署；旧网关先公开保存关闭、确认原生 EXITED/release，再 listen/discover，休眠登记不认领旧 PID。真实 reconnect 发起新 worker，保持双客户端共享双射、实际资产 SHA-256、旧实例拒绝和完整终局门。
3. `tests/net_server_discovery_validation_test.gd`：删除副本外硬编码输出。通过公开 manager 创建原生 worker，安全关闭后读取其真实 `config.json`／`recovery.json` 作为当前 schema 来源，不手工伪造合法恢复档。使用合法随机 32 位十六进制房间目录，仅逐项改变坏端口、越界端口、目录越界、数据根越界、未知恢复 phase、未知 schema、旧配置缺 instance；七例全部拒绝、无部分登记／启动。有效发现不自动启动、poll 不改存档、重复发现不覆盖、close 保留存档。
4. 新增 `tests/round36_gateway_fixture.gd`：独占根／公开部署／合法身份／原生 ready／保存关闭公共测试编排。不给生产猜测批准根，不改身份或资源默认。
5. 新增 `tests/round36_gateway_equivalence.gd`：继承旧严格比较器，只补正式 `MatchViewBuilder` 的 `zone_hand_entries/*/card`、`residue_cards/*`、`special_command_spells/*` 显式引用和资产路径。跨客户端双射、类型、数组顺序、完整字段、内容哈希均保留。真实镜像坏引用与缺资产反例均拒绝。
6. 新增 `tests/round36_gateway_run.py`：显式依赖冻结、物理 E 独占引擎／APPDATA／TMP／输出、真实子进程 probe、真实 Godot import／scene、Windows Job 180 秒看门狗，仅本次已拥有进程树、先归档后回收。冻结 project 仅关闭 `[editor]` 的两项 VCS 设置，保留 threading=20。最终返回码由真实正向和故意失败结果决定。

耦合说明：复用生产公开 API 和已有严格等价原语；不复制规则、数据加载或生产恢复实现。未授权父测试没有诊断根注入点，因此仅在拥有的 restart 测试覆盖恢复编排，把错误比较 JSON／可选窗口 PNG 也放本次根。恢复与续局各 60 秒阶段上限用于先形成 RESULT 并给安全收尾留预算；不是产品性能指标，不能据此判定生产死锁。续局只消费权威 `can_end`／部署候选／必要 pending，不穷举可选效果；仍要求真实完整终局，没有缩短正式回合或放宽录制、批准、身份、资源门。

## RED → 局部 GREEN 原始证据

命令（仓库根 `E:/Projects/Godot/FateDominationGame-master`）：

```text
python -B tests/round36_gateway_run.py red
python -B tests/round36_gateway_run.py diagnostic-restart
python -B tests/round36_gateway_run.py green
```

所有具体引擎 argv／PID／退出码／耗时在各 manifest 的 `processes`。scene 命令为真实 `Godot.exe --headless --fixed-fps 60 --path <本次冻结项目> --scene res://tests/<suite>.tscn -- <已存在物理E首输出根>`，不是 Python 单元测试替身。aggregator 的 restart 参数补丁未修改。

### 初始 RED

`reports/refactoring/round36-gateway-red-bcf4045099a64e4ea30fa8a434145a0e/manifest.json`

|套件|Godot exit|checks|原始失败|
|---|---:|---:|---|
|gateway|1|4|未明确 worker ready、未收到所有权|
|restart|1|39|直接 close 活 worker 后不能清空／重新监听／磁盘发现及恢复，关闭缺原生退出证明|
|discovery|1|5|非法目录 ID、未批准数据根、旧恢复 schema 导致合法／非法预期均失配|

RED discovery 旧源码的副本外路径不能获准执行，冻结副本仅替换输出根到本次独占目录；原始源码保存为 `red-discovery-original.gd`，转换前后 hash 在 manifest。非法 ID、schema、批准根均未改，因此 RED 不掩盖问题；未写任何旧硬编码目录。

### 最终同一候选

`reports/refactoring/round36-gateway-green-6eb48df795ea4e45a43d3b7916e4213f/manifest.json`

|实际 scene / 反例|Godot exit|checks|判定|秒|
|---|---:|---:|---|---:|
|gateway|0|19|GREEN|15.191|
|restart|1|55|RED：完整终局未到|152.809|
|discovery|0|33|GREEN|23.160|
|gateway bad-root|1|1|预期 fail-fast|4.386|
|gateway wrong-key|1|6|预期 fail-fast|4.433|
|restart bad-root|1|1|预期 fail-fast|4.526|
|restart wrong-key|1|5|预期 fail-fast|4.506|
|discovery bad-root|1|1|预期 fail-fast|4.421|

主 stdout/stderr、worker engine 日志、config/ready/recovery/控制回执和各文件 SHA-256 均保存在同目录。最终主日志及全部实际 worker engine 日志无 `SCRIPT ERROR`／`ERROR:`；最终不是无失败。

## restart 真实恢复证据与剩余问题

最终主管 PID 21708；原 worker PID **25904**，磁盘重新发现后恢复 worker PID **14048**，相同房间目录但新 instance，真实 manager 原生 ownership/ready 存活通过。目录：

```text
E:/scratch/isolated-6eb48df795ea4e45a43d3b7916e4213f/generated/fixtures/net_server_gateway_restart_test/server-match-21708-3735872/workers/2409e4f423cb7ac008b1f6c6ef48959a
```

已通过：原两真人 RSA、真实 approved 数据 barrier、原生退出／release、磁盘休眠发现不启动、无凭据不能触发恢复、原凭据公开 reconnect、镜像清空后必须等新发布、新 instance 配置／ready／句柄一致、旧 PID/instance 不影响新实例、两客户端共享引用映射且资产实际哈希一致、双方恢复后继续提交真实规则命令。

最终续局进度（不是卡死）：约 15／30／45 秒时分别 round 3／4／5；双方 decisions 从 20/21 → 27/34 → 39/42，seq 从 71/72 → 131/132 → 191/192。60 秒续局阶段不能到完整终局，仍保留红项。精确交接：`net_server_gateway_restart_test.gd::_continue_restored_match` 的完整终局预算与正式录制每命令处理耗时不匹配；目前证据不足以归因于某个 production 性能函数，不擅改生产或扩大本次 180 秒预算。

### 生产恢复不稳定性：仅交接，不修改／不宣称修复

另一次真实运行：

`reports/refactoring/round36-gateway-diagnostic-restart-69f386ea25024c2fb6e052850fc767a2/manifest.json`

恢复 worker engine 日志明确：

```text
ERROR: 存档恢复失败关闭：恢复失败并关闭会话（未回滚原对局）；请丢弃此会话并重启权威：恢复期间房间已变化，原子恢复不可用
[0] _fail (res://scripts/net/server/server_room_worker.gd:550)
[1] _try_restore_match (res://scripts/net/server/server_room_worker.gd:364)
[2] _process (res://scripts/net/server/server_room_worker.gd:322)
```

公开客户端随之 `房间连接已断开`；不强行恢复或绕过 fail-closed。生产入口精确交接：`lobby_session.gd::restore_local_match` 第 1848 行 await `candidate.restore_archive` 后，1850–1851 行 maintenance 返回 false；`_restore_checkpoint` 1930–1933 行检查原 room snapshot 并维护 native transport。需要生产 owner 区分 snapshot 变化和原生断线锁存取消；目前没有实证识别究竟是哪一项先改变，不能编造根因。

另一份 `...diagnostic-restart-45ab0aca37ee40e2b03e10e90b27631b` 保存了 `等待全部原真人重连后恢复` 的实际 worker ERROR 及随后同步失败。它们不是本次最终同一候选通过记录，全部保留，不通过多次尝试挑一条成功来证明稳定。

## 安全／根／回收

- 最终物理根为 `E:/scratch/isolated-6eb48df795ea4e45a43d3b7916e4213f/generated`；批准首输出根及所有客户端缓存、恢复比较、控制台和 worker 输出在其下。
- APPDATA、LOCALAPPDATA、TEMP、TMP、TMPDIR 仅本次子环境修改，全部正斜杠物理 E，未改全局环境。
- 同一 E 引擎真实 main/child probe PID 33752／6816：`user://` 实际回执均为独占 `generated/appdata/FateDomination`，20 worker threads；回执读回、内容／文件哈希、子进程退出码 0 均验证。真实房间 worker 根另由 native binding + config/ready 证明；probe 是独立实际进程，不冒称 production 增加了 user-root 回执。
- 本次 9 份独占 manifest 全部 `generated_removed`，生成树实际不存在；每个记录进程树 `exited=true`、`active_owned_processes=0`、日志句柄已释放。先归档原始日志／worker 小证据再删独占生成树；无名称扫杀、无裸 PID 杀其他任务、无旧前缀目录删除。
- 最终生产批准根／身份／资源关键八文件与初始 RED SHA-256 相同：server_room_manager、server_gateway、server_room_worker、recovery_path_safety、player_identity、player_registry、member_identity_bindings、lobby_session；各 hash 在 manifests。其他并行 owner 的修改不归本任务所有。
- 中间一次 candidate 有 `master_manager.gd` 并行漂移，明确不复用其通过证据；最终候选漂移空。
- 仓库 `.gitignore:47 /tests/` 忽略这三份目标及新增夹具，`git diff` 不能代表这些未跟踪文件；未强制 add／commit。三份目标改前／最终 SHA-256 保存在 RED／最终 manifest，最终文件字节与候选一致。

未完成：三套全 GREEN、完整終局预算内完成、恢复不稳定生产根因、GUI／跨机／跨网验收。未放宽任一生产批准根、身份或资源门。
