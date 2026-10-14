# 30s 启动期限与冷应用缓存：高并发实测

## 结论与人测包建议

- 在用户指定的近 30 路并行条件下，不暂停其它任务，同一冻结源码、两个新的独占应用缓存根都到达 `data_assembly` 和真实主管确认的 READY。
- `cache_population` 外部日志观测耗时 **17.049–25.484s**；创建请求开始到主管确认 READY 的同进程单调计时为 **35.189–45.567s**。
- worker 第一个启动阶段到 READY 日志的外部观测为 **26.980–36.864s**。第一轮仅此段已超过 30s，故本机这个冷应用缓存场景下 **默认 30s 偏紧**，不是只有缓存循环要考虑预算。
- 建议人测包的本机部署 `server.cfg` 在 `[server]` 段显式声明 **`startup_seconds = 600.0`**。这是有限的 **保守安全上限（10 分钟）**，不是典型启动耗时：相对本轮完整可用时间最大值 45.567s，保留 554.433s 余量，约 13.17 倍观察上限；两轮也确实均使用这一声明并成功到 READY。
- 600s 的具体余量属于部署安全选择，不是把未测耗时伪装成实测。两个样本不能证明任意负载、无限调度饥饿、磁盘故障或永久阻塞时都能启动；本建议满足当前高负载下不贴边裁掉健康冷启动的保守目标。没有声称“worker READY 不稳定已修”。生产默认、源码模板、DLL、引擎均未由本代理修改，正式包配置也尚未由本代理写入。

建议仅更新人测部署文件对应键，不复制诊断最小 CFG 替换完整人测配置：

```ini
[server]
startup_seconds = 600.0
```

正式入口传入该文件：`--server-gateway --config E:/<人测包目录>/server.cfg`。没有确认 `--startup-seconds` 这样的独立 CLI 数值参数，不能凭空写一个。

## 真实来源：确实是可由本机部署入口显式声明的参数

以下为当前源码原文，关键文件与本轮冻结 SHA 已核对一致：

1. `assets/config/server.cfg:5,25`
   ```ini
   [server]
   startup_seconds = 30.0
   ```
   正式 CFG 模板已经显式声明 30.0；`server_cli.gd:256-258` 的首次生成入口从 `res://assets/config/server.cfg` 复制模板。
2. `scripts/net/server/server_room_manager.gd:9`
   ```gdscript
   var startup_seconds: float = 30.0
   ```
   上一轮以及本场景原夹具直接 `Gateway.new()`，未经过 CLI 配置注入，所以取 manager 默认 30s。
3. `scripts/net/server/server_cli.gd:19-20,30-31`
   ```gdscript
   if arguments.size() != 2 or arguments[0] != "--config":
       _fail("启动方式：--server-gateway --config 本机配置.json 或 server.cfg")
   _configuration_path = arguments[1]
   var configuration = read_configuration(_configuration_path)
   ```
4. `scripts/net/server/server_cli.gd:59-60`
   ```gdscript
   if configuration.has("startup_seconds") and (typeof(configuration.startup_seconds) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(configuration.startup_seconds)) or configuration.startup_seconds <= 0 or configuration.startup_seconds >= float((9223372036854775807-Time.get_ticks_msec())/1000)):
       _fail("房间启动时限无效")
   ```
5. **注入点** `scripts/net/server/server_cli.gd:101`
   ```gdscript
   gateway.manager.startup_seconds = float(configuration.get("startup_seconds", 30.0))
   ```
6. `scripts/net/server/server_bootstrap.gd:34` 的 `CONFIGURATION_FIELDS` 白名单原文包含 `"startup_seconds"`；`:61-64,73-76` 使用 `ConfigFile` 读取 `.cfg` 并把 `[server]` 的键展平到本机配置字典；`server_cli.gd:274-275` 复用此读取入口。
7. **截止时间消费者** `scripts/net/server/server_room_manager.gd:502-503`
   ```gdscript
   var startup_deadline:int = _startup_now_msec() + int(startup_seconds * 1000.0)
   var spawned:Dictionary = _process_owner.call("spawn", OS.get_executable_path(), arguments)
   ```
   `:564-570` 到期报 `startup_deadline` 并调用 `_terminate_process(room)`；`:583` 在读取报告后仍验证未超过该截止时间。恢复创建也在 `:803` 使用当前 `startup_seconds`。

**判定**：它是本机部署配置可显式提供、正式入口实际消费的主管启动预算，不是公开房间 settings 规则，也不是 worker 的 supervisor 心跳期限。当前实现不是“缺声明就拒绝”的强制必填契约：缺键仍回退 30.0，因此不能声称所有现有部署均已显式声明。人测包应主动写出此键，而非暗改 manager 默认。

## 同一场景、声明方式与隔离边界

- 唯一源码新增：`newtests/gateway_cold_start_budget_runner.py`。冻结生产 `scripts/assets/data/addons` 与原夹具依赖，原文件逐一 hash 校验。
- 原夹具 `tests/gateway_relisten_acceptance_test.gd` SHA256：`3681be694b39f0184d9f582beb899b96377c20803640ac8c3eef674fa5c99027`，与上一轮一致，源及冻结副本均未修改。
- 隔离新诊断场景继承原夹具，复用原 `run()`，只生成 `check_real_worker_close()` 的诊断覆盖：保留原创建 settings、独立 cache 模式、公开 Gateway/Manager 入口、原 READY/保存关闭/重监听断言。额外加入 CFG 声明检查、参数注入及计时；不修改生产 worker 或 manager。
- 隔离 `generated/server.cfg` 明文仅两行：`[server]` 和 `startup_seconds=600.0`。诊断覆盖用生产 `server_bootstrap.read_configuration(args[1])` 读取，再按正式 CLI 同一字段注入 `gateway.manager.startup_seconds`。它不是完整正式 CLI/发行包验收；不能把诊断覆盖称为生产 CLI 整链已验收。
- 本轮公开的三个不同预算：**主管启动 600s**（显式 CFG）、**夹具观察 610s**（从该 CFG 推导，并替换原夹具的 40s 观察窗）、**执行器看门狗 1200s**（只管本轮拥有 Job 的失控回收）。正常关闭的原 30s 观察预算未改。没有暗增心跳、ENet 超时或其它生产时限。
- worker 使用原 manager 的真实原生 spawn/verify/state/terminate/release，没有伪造所有权；日志观察只读固定 stage/result 行及 READY banner 布尔值，不读 config、票据、ready 内容或恢复载荷。日志句柄使用 Win32 `FILE_SHARE_READ|WRITE|DELETE`，自测证明观察句柄存在时仍可原子 rename；这不证明所有潜在观察开销为零。
- 根进程命令为 `--headless --fixed-fps 60`；真实 worker 参数保持生产创建路径原样。探针主/子进程验证 user:// 物理落在本轮 E 盘独占目录。未触碰 PID 17120/28100；未暂停其它任务；未做名字批杀。

## 实测记录及计时解释

隔离 owner：`E:/scratch/isolated-553062541c5042f1929619170d508e19`。

| 项目 | run | run2 |
|---|---:|---:|
| 空应用缓存 cache_population 日志间隔 | 25.484s | 17.049s |
| 仅采样误差对应的日志可见性区间 | 25.419–25.544s | 16.982–17.114s |
| data_assembly 日志间隔 | 4.055s | 3.890s |
| worker 首个阶段到 READY 日志 | 36.864s | 26.980s |
| 上一项日志可见性区间 | 36.802–36.926s | 26.917–27.036s |
| 创建请求开始到主管确认 READY | 45.567s | 35.189s |
| 到达 data_assembly / READY | 是 / 是 | 是 / 是 |
| RESULT | checks=40, failures=[] | checks=40, failures=[] |
| root/runner exit | 0 / 0 | 0 / 0 |
| 缓存落盘文件数 / bytes（退出后 metadata） | 203 / 95675402 | 203 / 95675402 |
| 日志观察阶段与退出后原件逐项核对 | 52 条完全一致 | 52 条完全一致 |
| Job 活跃自有进程数 | 0 | 0 |
| SCRIPT ERROR / ERROR / observer error | 无 / 无 / 无 | 无 / 无 / 无 |

计时边界必须区分：
- “冷”只指每轮新的 room-local 应用 CAS、固定 data 与 user 输出根；**未清 OS 文件页缓存**。第二轮也不是共享 CAS 命中，但 OS 缓存可更暖，不能把两轮差异全归因机器负载。
- 创建到 READY 使用夹具同 PID 的 `Time.get_ticks_msec()`；包含 `create_room()` 里的前置校验、配置写入以及 worker/主管就绪检查。
- 生产启动截止从 spawn 前才建立，不从 `create_room()` 入口算。不能机械拿 35.189s 推断第二轮在 30s manager 预算下必然失败；第一轮 **worker 第一个启动阶段之后都用了约 36.864s**，已足以证明 30s 偏紧。
- cache_population 与其它 worker 阶段是外部 `perf_counter()` 对既有阶段日志的真实观测，不是假造 worker 内部时钟。采样周期目标 50ms，阶段事件最大实际扫描间隔两轮分别 84.679ms、75.909ms。表中区间仅界定日志可见性的采样误差，不额外保证日志 flush 和调度迟延都在区间内；这些未单独测量，不能把 microsecond 级同批打印间隔当真实函数耗时。
- 两轮全场景总执行墙钟 54.609s、43.824s，含原场景其它检查及真实关闭，不当作 worker 启动或缓存耗时。

## 当时机器负载

用户决定保持近 30 路并行，本轮不尝试识别每条代理对应 PID，不由进程数猜代理数。

- 12 个逻辑 CPU；通过 Windows `GetSystemTimes` 采样计算系统忙碌率，**两轮样本均为 100%**（53 个和 43 个样本）。额外原始 1s 验证：idle/kernel/user delta 为 `[0, 43125000, 77812500]`（100ns 单位），再次算得 100%。第二轮逐样本还存原始 delta。
- 内存负载第一轮 45–48%，第二轮 44–49%；总物理内存 50587303936 bytes，没有把内存压力猜成缓存卡死。
- 系统进程数第一轮 392–436，第二轮 405–438。开始/结束可见 python.exe 为 18→19、18→21，另有多份 Godot、Hermes、Node 等进程；只采 image/count，未采可能含凭据的命令行。
- 这些证明本次不是暂停任务后的干净基线。CPU 已饱和，但未测磁盘队列、每次安全路径检查、锁等待或 flush 子调用，不声称证明具体缓存慢点。完整负载序列见 `machine-load.jsonl`。

## 阶段序列与首分歧

两轮均为下列序列，每阶段都有 `result=1 → 0`，无新增首次失败阶段：

`signal_protection → launch_arguments → configuration → settings → selection_mode → catalog_scan → data_plan → cache_policy → cache_population → data_assembly → data_validation → fixed_source_registration → process_content（内含 content_environment → rules_reload）→ roster → host → recovery_binding → selection_configuration → blob_publication → room_asset_installation → startup_pin_release → identity_bridge → data_approval → transaction_audit → ready_publication → SERVER_ROOM_READY`

生产 worker 原件各为 `worker-0.engine.log:4-56`；`cache_population:20-21`、`data_assembly:22-23`、`ready_publication:54-55`、READY banner `:56`。主管检查前公开观测证明同一真实原生实例 `ever_ready=true, ready=true, identity_verified=true, native_state=1, heartbeat_status=healthy`，不是仅凭日志 banner 判 READY。

后续原场景真实保存回执与安全重监听检查亦通过；仅记录该诊断预算下的场景结果，不将它升级为默认预算修复或发行包总验收。

## 命令与证据

仓库工作目录 `E:/Projects/Godot/FateDominationGame-master`：

```text
python -B newtests/gateway_cold_start_budget_runner.py selftest
python -B newtests/gateway_cold_start_budget_runner.py prepare 600
python -B newtests/gateway_cold_start_budget_runner.py probe E:/scratch/isolated-553062541c5042f1929619170d508e19
python -B newtests/gateway_cold_start_budget_runner.py import E:/scratch/isolated-553062541c5042f1929619170d508e19
python -B newtests/gateway_cold_start_budget_runner.py run E:/scratch/isolated-553062541c5042f1929619170d508e19
python -B newtests/gateway_cold_start_budget_runner.py run2 E:/scratch/isolated-553062541c5042f1929619170d508e19
```

完成执行均 exit 0；第二轮是事先公开的有限独立冷应用缓存样本，不覆盖第一轮材料、不继续重跑到绿。

原件目录：
- `manifest.json`：源 SHA、声明文件 SHA、argv、PID、退出码、Job0 与 root 计时。
- `evidence/run.stdout.log`、`evidence/run.stderr.log`、`evidence/worker-0.engine.log`、`evidence/stage-observation.jsonl`、`evidence/machine-load.jsonl`。
- 第二轮同类证据在 `evidence/run2/`，运行输出文件名为 `run2.stdout.log` / `run2.stderr.log`。
- 汇总数据：`docs/gateway-cold-start-budget-measurements.json`。

关键冻结 hash：
- manager `ea4f181aacb86400ec4c46143298cf7edab3ceed952a1ba12ba78ef81f9123e4`。
- worker `a1d935675ce6d6a3f804ac9000104b15d95c2c279c8cf13c459acdd3920107eb`。
- cache `eb7b3d1dfec6cf017e64ea15eecdfa60d7d9ea44087bd4e527453c2853f5b9de`。
- engine `ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424`（未修改）。

## 改动、问题与未覆盖

本代理仅新增 runner、此报告及汇总 JSON；隔离内新增诊断子类/场景和显式 CFG 声明。原生产/夹具 hash 保持不变。

- 初始 observer 自测因 Windows CRLF 导致尾行字节断言失败，已在自有 runner 改为 splitlines 后通过；发生在业务运行之前，不算产品 RED。
- 汇总 JSON 完整写回受到工具分页保护拒绝，文件未受损；改用定位补丁补入两轮 worker 阶段计时，JSON lint 通过。
- 其它代理在运行期间改过 `v2_view_presenter.gd` / `lobby_session.gd` / `effect_manager.gd`，本轮仍执行同一不可变隔离冻结。关键 manager/worker/cache/assembler/CLI/bootstrap/模板/原夹具 hash 与当前仍一致，但 **不认证漂移后的全仓整链**。
- 缓存内部具体耗时归因、OS 真冷缓存、低负载基线、正式导出包完整入口、任意更严重负载下的最坏上界均未验证。没有修改/发布人测包，没有把默认 30s 判成已修。
