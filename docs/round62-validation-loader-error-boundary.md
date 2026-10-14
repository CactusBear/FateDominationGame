# Round62：loader 扫描错误能力边界

## 结论与范围

已完成严格单职责错误能力注入。仅修改两个生产脚本：

- `scripts/system/global/load_game.gd`：四个入口接收可选 `Callable`，仅原两个 roster 扫描失败出口分流。
- `scripts/net/validation/room_data_validation_worker.gd`：仅替换 `_inspect_loaded_content` 中的一行 reload 调用，将当前扫描诊断追加现有 `report.errors`。

新增 `tests/loader_error_boundary_test.gd/.tscn`、独立 `tests/round62_loader_error_boundary_runner.py` 和本文。其它生产脚本、既有测试、门禁、完整 runner 均未修改。未提交 Git。

最终命令：

```text
python tests/round62_loader_error_boundary_runner.py green
```

真实退出码 **0**；最终 manifest `passed=true`；归档与哈希读回通过；全部自有 Job 的 `active_owned_processes=0` 后才清理，`generated_removed`，生成目录实际不存在。

## 接口与耦合审查

亲读 loader、worker、`roster_catalog`、任务 report reader 和准备依赖专项。现有可复用能力是单次扫描的 `roster_catalog.error` 与 worker `report.errors`；没有既有 error sink。扫描器本身没有 `push_error`，错误是在 loader 原两个失败出口输出，因此不修改扫描器、不让 worker 猜测 masters/servants 路径，也不添加预扫描。

四个入口：

```gdscript
load_game(error_sink:Callable = Callable())
reload_game(error_sink:Callable = Callable())
load_masters_from_jsons(load_path:String, error_sink:Callable = Callable())
load_servants_from_jsons(load_path:String, error_sink:Callable = Callable())
```

- sink 是调用作用域内的单字符串通知能力，不存入 autoload 字段、不持有 worker/session/report 管理器对象，不引入新的状态或错误类型。
- `reload_game` 仍按原顺序清理标志、标签和快照；只将参数传给 `load_game`。
- `load_game` 仍按原顺序加载攻击、事件、地利、令咒、两种 roster、标签及快照，最后 seed；仅向两种 roster 函数传递参数。
- 扫描失败时 valid sink 接收原 `roster_catalog.error` 一次；否则原 `push_error` 一次；原 `return` 不变。没有捕获或吞掉回调异常，也没有处理解析/读取/其它 engine ERROR。
- 扫描、解析、正常加载、目录推导、空名单拒绝和 seed 路径不变。既有 seed 自身扫描逻辑未修改；本轮没有增加扫描，也没有将 seed 内部诊断再次写进 report。
- worker 用闭包仅捕获本次 `report`，无跨请求保存。报告仍含 `errors/masters/servants/ok`，没有测试字段。
- 游戏重开与服务器 room worker 的无参 reload 保留原语义；`_ready` 无参 load 也保持原行为。
- report writer、随机模拟配置与门槛、`environment.restore(token)` 两处现有出口完全未修改。

## RED 先行

实现前运行：

```text
python tests/round62_loader_error_boundary_runner.py red
```

退出 **1**，`RESULT checks=10`，唯一断言失败是“每次原扫描错误恰好进入 report 一次”。实际 stderr 两个 ERROR 精确来自原 `load_masters_from_jsons:185` 与 `load_servants_from_jsons:197`，经 `reload_game → _inspect_loaded_content` 到达。其它九个断言通过，包含：缺 roster `ok=false/masters=0/servants=0`、不模拟、恢复精确 outer 环境及测试恢复原环境。

证据：

`E:/scratch/isolated-4730eebfa2b248c9818417b63853ddab/manifest.json`

原 stderr、stdout、parent logger、缺 roster report、修改前两个生产源文件均已归档。该运行不是 parser/入口失败。

## 最终同冻结验收

最终 manifest：

`E:/scratch/isolated-da02984e532f43a08e445aca142ddebb/manifest.json`

冻结映射总摘要：

`42a81409d57f71d208e999cdb9c7b00fa34ff61d79002c52edd929dd415c02a6`

| 场景/模式 | 真实 exit | checks | failures | 验收 |
|---|---:|---:|---|---|
| loader_error_boundary | 0 | 62 | [] | 缺双 roster、缺一种、文件非目录扫描拒绝、sink 精确诊断一次、空目录扫描不输出错误、load/reload 传递、正常完整 roster、实际单卡/204 子进程、15 秒观测合同 |
| expectednegative | 0 | 9 | [] | 无 sink 的 load/reload/两种直接 roster 调用产生准确六个原 ERROR |
| expectednegative_extra | 0 | 9 | [] | 同样六个原 ERROR 加额外真实 ERROR，原负向判定器确实拒绝 |
| worker_content_environment | 0 | 45 | [] | 全部原检查：静态成功、真实 await 模拟、模拟拒绝、真实 report rename 失败提前返回、空名单、服务器进程环境不恢复 |
| content_environment | 0 | 30 | [] | 原环境 token 全部合同 |
| room_data_preparation_dependencies | 0 | 34 | [] | 原专项全部检查，实际单卡 receiver/assembler/worker 拒绝；额外读回 worker report/logger 排除“子进程入口缺失也算拒绝” |
| validation_countdown_contract | 0 | 21 | [] | 原倒计时专项全部检查 |

合计 **210** 检查，包括两个独立 expected-negative 场景，不代表完整性能/GUI/98 套通过。两个旧环境专项原输出 `failures=0`，专属 runner 只对其精确 RESULT 名称适配为数组供只读通用解析器检查；没有改测试输出或移除任何 ERROR。

### 真实 child 与报告

- 单卡专项 child **PID 39556，exit=1**。父任务实际保留报告、拒绝批准，而非因 logger 出错提前丢弃报告。
- 完整 204 child **PID 14656，exit=0**，实际生产 catalog/plan 产生 **204 文件**，不是“204 JSON”。保留源路径批准校验、真实组装和 loader；最终 **7 masters/8 servants/ok=true/errors=[]**。
- dependencies 的另一个真实 child **PID 33884**，其 1 文件报告同样读回拒绝。该原专项没有输出其 child exit，因此不单独声称其退出码；整场 Job0证明它已结束。
- 三个实际 validation user probe 均落在本次物理 E 盘自有 `generated/appdata/FateDomination`，均 pool=20。
- 两个 1 文件报告均严格为：两条原扫描错误（masters 与 servants，各一次）加“所选数据缺少可加载的御主或从者”，`masters=0/servants=0/ok=false/random_simulation.configured=false`。
- 新专项、dependencies 的 parent stdout/stderr/logger 及三个 child logger 全部无非预期 `ERROR/SCRIPT ERROR/SHADER ERROR`。

### expected-negative 不属于完整门禁白名单

专属模式只接受当前自有根、精确 operation/kind/path/message、准确六个 ERROR、loader 源调用栈、正常 RESULT 与 exit。所有其它错误、数量变化、路径变化、脚本错误仍为红。额外模式真实执行 `push_error("ROUND62_UNEXPECTED_EXTRA_ERROR")`，其底层分析明确 `passed=false`；外层只记录“检测器正确拒绝这个刻意制造的额外错误”。没有加入 full whitelist，未过滤 stderr，也未修改正式任务的 logger ERROR 门禁。

### 15 秒与性能定义

原 server template 的 `enabled=true/budget=15.0` 与 pool20保持；新专项显式对15秒进度接收、单调倒计时、重复拒绝、耗尽不批准与取消清空做真实 Godot API 合同检查。完整204专项仅为本轮 loader 边界明确 `enabled=false/seconds=0`，报告保留这一事实。未改变原模板或旧 full 模拟/性能定义，**不声称运行了完整15秒正式性能链**。

## 隔离、归档与只读冻结

- 原 Godot4.7.2 executable 复制到物理 E 独占目录，使用原旧 DLL，没有重编译/新 DLL。
- 每个过程/场景180秒看门狗；任务夹具170秒；原 pool20不变。所有 root 先 suspended 创建、分配自有 Windows Job、再恢复；没有按进程名终止，也没有触碰用户目录/28100。
- 隔离副本仅禁用 VCS/MCP autoload/plugin 并替换其默认 main scene；application/user 配置和 threading 原样保留，实际主/子 user probe 证明物理E落点。
- 最终10条 owned root 过程记录均 exit0、Job0；3个实际 validation child 由所属 Job 一并核对结束。
- 64个证据文件逐项摘要读回通过，含真实 stdout/stderr、parent/child logger、worker manifest/options/report、瞬态作用域 report、user probes、源文件与 runner。manifest 写出后读回一致，再依据 ownership/全部Job0执行精确生成根清理。
- `source_drift=[]/frozen_drift=[]`；收尾重新计算当前全部冻结源摘要，仍与最终记录一致。Git diff/check执行，但工作树已有大量前轮未提交改动；本轮改动另与 RED冻结源比对，确认仅上述四入口/两失败出口/worker一行，不将旧累计 diff 当作本轮成果。

关键只读摘要：

- server.cfg：`351798e5909021fa472f2206bdc63c1a9271322c5800cbfdffb96e2b491301d5`
- 旧 DLL：`92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd`
- 原 Godot executable：`ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424`

## 中途失败与未证实因果

全部失败均保留独立证据，不拼接成最终通过：

1. `isolated-04ddb16f353040e9a14f6bc3af8bd0d1`：专项 runner 冻结漏掉 worker scene，实际 child ERROR；另外新夹具错把“204文件”当“204 JSON”，以及旧 RESULT 的 CRLF/整数 failures 适配不足。仅修新增 runner/测试，未动生产逻辑。dependencies 原测试仅断言拒绝可能错把入口失败视为正确；最终以精确 child报告及全部logger补强。
2. `isolated-02efccc627e54e199ec489c95a5fd66e`：修正后的旧版专项整组通过；但本轮最终验收不引用它拼接结果，最终全部重新同冻结运行。
3. `isolated-eaec18432e9e4e6cb0ec49d82f0d8ffc`：加入独立单卡 child exit验收后，完整204在assembler发布阶段真实拒绝，`rename_error=1/files=204/index=204`。原 report已存档，没有 whitelist或产品重试修改。当时活体归档器递归读取 data/staging，存在不共享删除的文件句柄，可能干扰 Windows原子发布。
4. 将专属归档器改为跳过 data/cache/staging，只读诊断，且用 `FILE_SHARE_READ|WRITE|DELETE` 的句柄；同一最终生产源与测试冻结全部重跑得到最终绿。**这仅排除当前归档器的该类持锁风险，尚未证明历史那次 rename失败唯一由归档器导致，也不证明旧assembler永无瞬态拒绝。** 生产发布路径一行未改。

## 未覆盖边界

按本轮明确范围，不跑98套、不跑GUI、不用新DLL；生产可见策略与服务器加载语义均未变，因此只交付 headless loader专项证据。没有新的导出/正式安装包验证、跨机链或完整full性能认证；没有将关闭模拟的204校验冒充原15秒full性能基线。现有 worker-content 专项实际模拟2秒仍完整执行。

## 本轮 V4A（相对本轮 RED 冻结源）

```diff
*** Begin Patch
*** Update File: scripts/system/global/load_game.gd
@@
-func load_game():
+func load_game(error_sink:Callable = Callable()):
@@
-	load_masters_from_jsons(masters_path)
-	load_servants_from_jsons(servants_path)
+	load_masters_from_jsons(masters_path, error_sink)
+	load_servants_from_jsons(servants_path, error_sink)
@@
-func reload_game():
+func reload_game(error_sink:Callable = Callable()):
 	load_masters_finished = false
 	load_servants_finished = false
 	tag_list.clear()
 	temp_stored_jsons_arr.clear()
-	load_game()
+	load_game(error_sink)
@@
-func load_masters_from_jsons(load_path:String):
+func load_masters_from_jsons(load_path:String, error_sink:Callable = Callable()):
 	var files: Dictionary = {}
 	roster_catalog.error = ""
 	roster_catalog._scan(load_path, files)
 	if not roster_catalog.error.is_empty():
-		push_error(roster_catalog.error)
+		if error_sink.is_valid():
+			error_sink.call(roster_catalog.error)
+		else:
+			push_error(roster_catalog.error)
 		return
@@
-func load_servants_from_jsons(load_path:String):
+func load_servants_from_jsons(load_path:String, error_sink:Callable = Callable()):
 	var files: Dictionary = {}
 	roster_catalog.error = ""
 	roster_catalog._scan(load_path, files)
 	if not roster_catalog.error.is_empty():
-		push_error(roster_catalog.error)
+		if error_sink.is_valid():
+			error_sink.call(roster_catalog.error)
+		else:
+			push_error(roster_catalog.error)
 		return
*** Update File: scripts/net/validation/room_data_validation_worker.gd
@@
-	LoadGame.reload_game()
+	LoadGame.reload_game(func(message:String): report.errors.append(message))
*** End Patch
```

上述 V4A 使用实际 tab 缩进。新增专项源码与专属runner详见同名文件及最终证据 `evidence/runner.py`，均未替换既有门禁。
