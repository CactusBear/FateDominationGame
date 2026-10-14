# Round50：CLI 只读部署配置闭包

## 修改及依赖边界

- 唯一生产写入：`server_cli.gd`、新 `server_deployment_validation.gd`。新组件为无实例状态的 `RefCounted`，只有部署声明闭包和其 heartbeat/cleanup 参数 helper；CLI 三个旧静态入口保留为委托，真实 `_ready` 调用该委托。
- `Bootstrap.configuration_error` 保留共享 unknown/roles 门；`Paths.absolute/checked` 保留规范路径、全部祖先无链接和根存在门；`CleanupPolicy.configuration_error` 保留 cleanup 配置政策。没有复制 `Bootstrap.read_configuration`、全局 service 查找、spawn、写文件或历史配置升级。
- **不是把整个 `_ready` 搬走。** 原闭包不校验 data/端口/身份配额/游戏 data_root，坏根或坏预算的闭包返回值仍可能为空，之后原 CLI 门拒绝。数据仍调用 `RoomState.valid_simulation_settings`；数据根仍调用 `RecoveryPathSafety`；资源配额仍采用 CLI 原有限数值/整数/真实 bool 判断及 transport 单消息预算；权威策略仍调用 `ServerPolicyConfig.validate`。这些后续门、应用配置、命令启动、角色和 reload 编排原样保留，未复制进组件或改顺序。
- cleanup 参数检查中的 `current_instances=[]` 只用于原 policy 的形状检查，不能证明完整实例集合、互斥或授权实际清理；运行时台账/执行器仍由 console 自有生命周期处理。空配置仍表示未启用；启用但缺字段、关闭却夹带批准根均拒绝。
- 对提取前的本机 CLI 快照逐函数比对：除三个委托入口，其余函数内容全部不变。保留完整中文错误与 JSON 精确整数转换；不把 NaN/Inf、bool、小数或越界数当预算。
- 没有新增生产15秒常量；默认仍来自 `assets/config/server.cfg`。已有显式配置不覆盖，data reload 仍拒绝，不授予历史 config 新权限。
- bootstrap、console、manager、worker、data approval、模板、native SDK/DLL 等均只读。其他写入者的 console 漂移只记版本证据，不触发全仓重审。

## 同冻结真实执行结果

命令：`python -B E:/scratch/round50-deployment-boundary/run.py`，本次退出码 **0**。

|专项|实际结果|墙钟|
|---|---|---|
|`server_deployment_validation`|63 CHECK；唯一 RESULT；failures=[]；exit0|5.4784844秒|
|`server_deployment_default_budget`|13 CHECK；唯一 RESULT；failures=[]；exit0；真实 CLI child 六项且 exit0|7.5601489秒|

两套 headless，固定60fps，均在每进程180秒、生成量2GB、剩余空间1GB监控门内；没有 GUI/全发行验收。资源初导入及正式 autoload 导入 exit0、无 SCRIPT ERROR/ERROR；同冻结 source_drift=[]、frozen_drift=[]。

### 旧/新配置表

提取前 CLI 字节快照 SHA256：`d2b54b9f18d4f8c864061397cde3aca2a91386c35a4c9a922fb3e6529a6e4418`。

22种配置分别比较闭包 String、输入不变和真实旧/新 CLI `_ready` result：

- 旧显式61.25预算合法、身份明确关闭、缺省 cleanup 未启用。
- 非规范坏根、真实 Windows junction；端口 bool/房间预算小数/内部端口越界；身份速率 bool/消息配额越界。
- data 非真实 bool、负预算、缺配对字段；cleanup 缺配置、非真实 bool、关闭夹带授权。
- unknown→roles→路径、data→路径、部署 bool→unknown、heartbeat→cleanup、cleanup→unknown、roles/p2p 冲突的多错误首门。

表内每项运行原 `_ready`，不在测试中重写校验器。观察 adapter 仅将预期 `_fail` 的完整中文字符串收进 result 并关闭本实例，不调用 push_error，避免预期配置拒绝污染无引擎错误门。合法配置真正完成 gateway 监听及配置快照；原/新依次释放自身监听。

另对 NaN、Inf、-Inf、bool、小数、负数、超过精确整数上限逐项比对 heartbeat/cleanup 拒绝；合法1.0仍转为整数1。只读 cleanup shape 检查前后未产生台账文件、原输入未变。

### 默认配置＋真实 child

正式 `create_configuration/read_configuration` 逐字节读取当前模板，data enabled=true/budget15；已有61.25配置再次创建返回 `ERR_ALREADY_EXISTS`，SHA256不变。真实 CLI child PID16232、主PID26828；child实际 `_ready` 读到 manager data15/pool20。在自有 cfg 将 data改43后调用原 reload，收到原中文“包含需重启的配置变更，本次未应用”，运行 manager data仍15。

child回执、CLI原日志和 cfg 已归档。此专项不启动房间 worker，不证明权威房间预算传输或完整随机模拟，严格属于用户允许的“CLI config13＋真实 child”部署契约。

## 证据、版本与收尾

- 当前 manifest：`E:/scratch/isolated-d2eb7adb52014df5b9be2272deba86e7/manifest.json`；SHA256=`aea8ebe96ccb03a163b26df8bf9dd73d03aa1ea76e2f3815e0b15d02852023f5`。
- 同根 `evidence/comparison.json`、`deployment_contract.json`、两套 stdout/stderr、`actual-user-output`、`legacy_server_cli.gd`、`runner.py`；额外读回在 `evidence/delivery-verification.json`。
- CLI SHA256=`8ecc943bd496ef2c85e16e66c3495a6b37b63818d56e94e2e398c0a94ddfaf6a`；新组件=`7396c12aebfec92c1e1ae56c507ad052ed4b9c1619f11c7b102af1831c4f7af3`。
- 模板=`351798e5909021fa472f2206bdc63c1a9271322c5800cbfdffb96e2b491301d5`；原 addon DLL=`92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd`。仍用4.7.2同字节引擎副本，没有升级 native SDK或替换生产 DLL。
- 所有自有 Job 已退出；主/探针 child 实际 user 根证据在 manifest；CLI child回执也是同一独占 E 根。仅移除本次已核对目标的自有 junction 和 generated树，generated已不存在；没有按进程名清扫或操作用户 server、身份、存档、部署。
- `git diff --check -- scripts/net/server/server_cli.gd` exit0。新测试被既有 `/tests/` ignore 隐藏，未擅改 ignore/暂存；提交者需显式纳入。

## 保留的失败与范围限制

1. 首次 runner 将故障输入 junction 放在 owner 内，严格预算遍历正确拒绝 `link/reparse point`；同时 cmd中文输出的UTF-8解码报错。原 manifest `E:/scratch/isolated-95b1c748cb0240448d8efbc7103e49fc/manifest.json` 保留。随后仅将自有故障输入放到监控 owner 的独占同级路径，保留 manifest所有权/目标核对并单独回收；cmd使用GBK解码。不放宽生产路径安全或预算遍历。
2. 既有 `server_simulation_default_budget` 实跑失败：`E:/scratch/isolated-9dd9c21b4c35475d9d75b4bffbeb971a/manifest.json`，exit1、44.647秒。真实 CLI 已启动且 manager15、已有显式不覆盖、reload拒绝可观察；首个真实房间 worker 未在原测试窗口回传 settings，rows=[]，现场保留 `data.building-*`。根因本轮未定位，不归因此次纯委托，也不冒称 native 发布故障已证实/已修。该冻结期间 console由另一写入者变更，原版本漂移已归档。
3. 上述失败没有改 worker、assembly、native SDK、生产时限或旧专项断言来冒绿；按允许的另一路径新跑独立配置13项＋真实 CLI child。**当前部署专项 PASS 不升级成原房间整链、完整204数据、GUI或整个 release PASS；不把 samplebin/CLI READY当发行证据。**

新测试：`server_deployment_probe.gd`、`server_deployment_validation_test.gd/.tscn`、`server_deployment_default_budget_test.gd/.tscn`。旧 CLI 对照源码/adapter只由 runner在冻结副本提供，不进入生产。