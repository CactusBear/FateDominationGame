# Round55：extracted_harness 的独立 required 边界

## 结论与执行命令

当前只读预检真实返回 `selection_ready`、`blockers=[]`，没有启动 Godot、cold import 或正式业务场景；这不是 sourcePASS。

源稳定、GUI/source case owners 完成交接后，在项目根执行已有完整 caller：

```bash
python -B tools/tests/test_round29_integrated_evidence.py --round50 --complete-candidate --collect-failures --approved-root E:/scratch
```

该命令现在包含当前同一 parent source fingerprint 内的 **生成→归档→执行 tight harness** required step，不再依赖正式项目存在 `res://tight_session.gd`。本轮没有执行完整 95、GUI、mandatory66 或 native standalone，也没有宣布整合/发行通过；完整命令的真实整批行为仍待源稳定后的执行。

当前可复核计数：正式 selectedscene=97，headless=95；short_headless=89、native_integration=1、GUI=2、long_correctness=2、performance=2、known_engine_negative=1。独立 required harness=1，不充抵 selectedscene/headless/checks totals；worker45 prerequisite 另列。native standalone=2、额外 board window invocation=1 仍各自独立，不在本轮冒充已执行。

## 亲读实际入口，不复制第二套实现

`tests/round50_finished_lobby_receipt_runner.py` 的提取不是公共函数/API，而是 `main()` 中 `args.suite == 'tight'` 的内嵌分支；它没有 source-root 参数。该分支从 `scripts/net/session/lobby_session.gd` 抽取原有 7 个方法和原常量，并附带它自己既有的诊断 fixture 声明。亲读的真实方法为 request、_request_sequence、_accept_match_command_result、_consume_match_result、_deliver_match_result、_reject_request、_fail。

没有修改 runner，也没有调用其 `main()` 去重新读取 live source 来冒充 parent freeze。自有 caller 的 `round50_extraction_callable` 用 AST 精确定位并编译这一个真实分支，注入独占 `freeze`/`run` 路径；不复制提取算法或 Session 规则代码。API shape、外部名字、7 方法定义、runner SHA 和提取分支 SHA 均检查；不支持的 runner 演进必须重新由 owner 交接，不自行猜测兼容。

文件操作白名单限定为：读 frozen Session；写诊断 project.godot、tight_session.gd 和 extraction archive。路径逃逸变异必须拒绝。完整 Session 的原字节仅是冻结提取输入和可审计来源，未构造第二个生产 Session 实例。

## 耦合分拆及 required 判定

原来将一个 generated diagnostic helper 当成正式静态 res 依赖，会让完整预检永远 exit1；直接删掉 harness 又会遗漏 required 行为。现在正式场景选择与独立 required harness 分开建模；其原有 .gd/.tscn、runner 和生产 Session 进入同一 source hash map，但 helper 仅写到 `generated/diagnostics/round50_finished_lobby_tight_test/`，不写 formal frozen project。

`run_round50_full` 在同一次 freeze、main/worker probe 后、formal import/场景前调用真实 adapter；使用相同物理 E 引擎副本和通用 Windows Job executor、180 秒预算。诊断 project 仅采用原 runner 的 tight project 配置，不替换正式 project.godot/threading。未放宽 native 冷 import、mandatory66、默认15秒、20线程或任何未知 ERROR。

归档包括：原 Session、原 runner、原 tight 场景脚本/场景、生成 helper、scope.json。scope 绑定整个 parent hash map/fingerprint、输入 hash、helper hash、engine hash、源/诊断/归档根、owner PID/creation、真实提取 API。生成后读回 SHA 一致才执行；执行后及完整收尾前再次校验 archive。全日志严格要求 exit0、唯一合法 RESULT、6 CHECK、6 checks、空 failures、零 ERROR、物理 E 独占 user path、自有进程全退出/日志句柄释放、冻结输入/生成 helper/engine 不漂移。

required step 不进入正式 suites 表。`summarize_round50_current` 在原正式汇总之上再合并 required gate：formal 全绿但 harness失败/未执行、坏 archive、不同 fingerprint 或 source drift 都整体 FALSE。未执行明确列 `required_harness.not_run`；实际已 launch 后失败仍保留 executed、原日志与 exit，不写成未运行。只有静态 API readiness 的预检仍为 `sourcePASS=false`/`releasePASS=false`。

## 本轮真实证据（不同执行不合并计绿）

### 原独立 runner：本轮指定命令只执行一次

```bash
python -B tests/round50_finished_lobby_receipt_runner.py --suite tight
```

exit0，6 CHECK，唯一 `RESULT {"checks":6,"failures":[]}`，零 ERROR；依赖 live drift=[]，generated 已回收。

原证据目录：`E:/HermesScratch/round50-finish-74cc8159a8c5440489b0c57682a9af7a/`，保留 manifest.json、dependencies.json、tight_session_extracted.gd 和原日志。该独立成功不充抵未来新 freeze required step。

### 最终 caller adapter 真实场景执行

manifest：`E:/scratch/isolated-c246ffabfd6e4325b2226a5f3349ba73/manifest.json`。

逐字节重读：同目录 `readback.json`。

archive：`evidence/harness/round50_finished_lobby_tight_test/`。

原 stdout/stderr：`evidence/required-round50_finished_lobby_tight_test.stdout.log` / `.stderr.log`。

- exit0、RESULT checks=6/failures=[]、观察6 CHECK、零 ERROR。
- archive_verified=true、same_freeze_verified=true、source_drift=[]、独占 user path 和 Job退出读回通过。
- parent fingerprint：`1fb21b9784f440f8d8bf9196baf025b5b4e31026372cc6831bffca13db02ac27`。
- Session SHA256：`11b0f98a6cf68a8b441680ba2d24741be39c9a7c470aa6569e9fbe711a0dbf56`。
- extracted helper SHA256：`db0f4dbb972f4f7fe047d6e761d67e34d3890f672f2ee2c61160d4c8238a3264`。
- runner SHA256：`3114c4334353f02859ae33bad7cee1dc420dacc31f2d44dd0e92b995b56b5bae`。
- stdout SHA256：`24e3300744c28eb06e7741a93a6e11427effe9177c299ab3fc599bcfa5c7e56f`。
- 执行 aggregator SHA256：`7d94c1e88ab3df178ebec61eccc16ddbc9a4a350505cbb4ae0d93f8f60dd2035`，readback 与当前代码一致。
- 与独立 runner 的 Session hash/helper 原字节相同，但不宣称整批正式 freeze 已跑。
- generated 不存在、源引擎 hash 未变；role 明确为 adapter_only_no_formal_candidate_credit，formal_scenes_executed=0。

中间诊断曾暴露 `contained()` 对不存在目标的 strict resolve、以及手写诊断 owner 不符合 generic cleanup 的 UUID/原生路径回执。这些异常原样保留；目标先按真实物理 E 建立并再 contained 校验，自有诊断树通过独占转移回执 `E:/scratch/isolated-39b2c0f31ffa40c8aaa04b22257dd937/manifest.json` 回收。完整 caller 的 generated 回执改为真实 `str(Path)`，没有修改/忽略 generic cleanup 的拒绝规则。最终上述新 UUID run 无需转移即可完成正常清理。

## RED/GREEN 与未通过项

`python -B tools/tests/test_round50_candidate_selection.py`：11 tests，exit0。已真实观察新增 required汇总/adapter缺失 RED、最终正式绿但 required失败的汇总缺失 RED、提取路径逃逸 RED；对应修复后 GREEN。覆盖正式通过但 required失败整体FALSE、not_run、坏 archive、fingerprint错、source hash错阻断launch、API形状拒绝、preflight不launch Godot。

`python -B tools/tests/test_round33_integrated_selection.py`：4 tests，exit0。

`python -B tools/tests/test_round29_integrated_evidence.py --parser-only`：strict parser PASS，exit0。

额外只读执行 `test_round40_selection.py`：20 tests 中 2 FAIL/1 ERROR，exit1。原因分别为历史 GUI source hash 不同、round43 旧 freeze 相对当前源漂移、旧70静态闭包不含现 round50_guard_observer；原拒绝没有放宽，也未越权修改旧测试或拼成新通过记录。

## 唯一仓库写入范围

- tools/tests/test_round29_integrated_evidence.py
- tools/tests/test_round50_candidate_selection.py
- 本文档

production、游戏 tests、native、gate、正式 DLL、原独立 runner 全部只读。没有 GUI 权限，没有导出或完整95执行；源继续变化时，未来完整命令仍须重新预检、冻结、实际跑完，不能把 selection_ready 或本轮诊断6当 sourcePASS。
