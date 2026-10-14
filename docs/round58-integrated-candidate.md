# Round58：当前完整 headless 实际执行

**最终 selected=98 / executed=98 / unique=98 / pass=87 / strict-pass=86 / red=11 / blocked=0 / not-run=0。顶层 passed=false，sourcePASS=false，releasePASS=false。不再运行任何套件。**

## 原件与同冻结绑定

根：`E:/scratch/isolated-1105873e41cd4f6a94a999e65ac6af50/`。以下相对路径均在该根下：

- `manifest.json`：最终逐套命令、fixture/env、RESULT、父进程退出码、Job释放、源文件hash与归档索引。SHA256：`d439e06fd4a92592211d306dfa292ba2af90c04c699bdd3fb52ee19b5bcc85b4`。
- `pre-continuation-manifest.json`：原93套及原9红未改原件，SHA256 `7c727b7461a11ca9e80ef1e7be2aa52427cb390d967a021a67285fca06904cd1`。
- `execution-readback.json`：程序化 selected/executed/pass/red/not-run/unique 对账、逐红原始日志hash、首错及进程记录。
- `evidence/complete-<suite>.stdout.log`、对应 `.stderr.log`：逐套未过滤原始输出。下文11个suite均有这两份原件。
- `evidence/frozen-inputs/index.json`：825份冻结 GDScript/场景/工程/扩展声明字节归档，逐份SHA读回通过。不是只保留测试名字。
- `worker/`：实际父/子日志及允许归档的report/manifest；不包含身份秘密、控制配置、存档和records。

父source指纹与最后实际重算指纹完全相同：

`1b2e5277f8769e1c65ed42695bb8b796580b9003288443ff85ba1508784dd0c4`

2025份明确冻结依赖逐文件终末重算，`final_drift=[]`。工程副本只有既有授权的editor/VCS转换，threading保留20；正式default simulation=15，不缩种子、动作、恢复次数或规则预算。原引擎及正式DLL未替换。

|实际source文件|before/end SHA256（相同）|
|---|---|
|`scripts/net/server/server_shutdown.gd`|`7526d0b8fd7d427a04a67085f462425f845e883a3210ee8017a0a30963b60227`|
|`scripts/net/server/server_room_manager.gd`|`fadbeb892cfce741d62b95ff1c452d86b883d9a39c811851318d4a97f3799d53`|
|`scripts/net/server/server_console_channel.gd`|`9eea95ad15fc0f4e04c3d9edfe0071a523e1f44a23558b324ceab818de16da02`|
|正式template_release DLL|`92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd`|
|`addons/fate_server_signals/src/process_owner_core.cpp`|`0e7dc7f94845dc23bd7c6d853d90e5995ae1581539a785f60511f197f7a29d8a`|

parent的native iterator一行修复已进入本指纹，但没有由此替换正式DLL，不能宣称新native能力已部署。原完整执行期间唯一记录的excluded测试变化是 `tests/net_v2_ui_input_parity_window_test.gd`：`fa75228c7a827107cd3f40b93d42a5190f8e4ddec2dac317530afa826187f6ac` → `c9f3e708b6c8bd7f1db8049f43a21803810205739e10761431abb5ccfca46c27`。它不在本次freeze依赖或执行集内，不把GUI写入解释成本次业务首错；也不宣称全tests树没有变化。

## 选择、入口与实际执行

原入口实际Python `--preflight-only` exit0：95 headless、97 formal，formal确实包含2个GUI。status contract/approval两套已经在选集；缺少的283 shutdown闭包实际是下面三套，新增后98 headless、100 formal：

- `server_shutdown_close_handoff_test`：mandatory86。
- `server_shutdown_close_handoff_pending_test`：mandatory36。
- `net_server_shutdown_failure_test`：mandatory161。

真实命令（仓库根）：

```text
python -B tools/tests/test_round29_integrated_evidence.py --round50 --preflight-only --approved-root E:/scratch
python -B tools/tests/test_round29_integrated_evidence.py --round50 --complete-candidate --collect-failures --approved-root E:/scratch
python -B tools/tests/test_round29_integrated_evidence.py --round50 --complete-candidate --collect-failures --approved-root E:/scratch --resume-current-manifest E:/scratch/isolated-1105873e41cd4f6a94a999e65ac6af50/manifest.json
```

首次实际启动在formal=0时发现执行器误冻结3个 `~*.dll` 热重载克隆；冷导入会删除它们，正式DLL与源码未变。只排除该生成类型，正式声明DLL继续严格hash；原阻断与诊断记录保留在 `isolated-9e96fb4e6a8e40ae9d43da725f801e51`、`isolated-92fab6d553454131a7e5af0884cefb6f`，不混入本次PASS。

当前98选集执行到93套时，relay CFG父进程触发 `byte_budget`，不是调度漏项或解析器漏掉5个结果。执行器真实扫描 `generated.parent`，累计已运行fixture与归档超过8 GiB阈值；不是证明磁盘实际耗尽或OS硬配额。父exit125、20条CHECK true、无RESULT，属于**已执行broken / 环境预算中止**，不能算业务断言红，也不能算未执行。

原93套结束：84 pass / strict83 / 9 red / 5未启动。末5名称没有进程label、没有原始stdout/stderr、没有suite row；不是executedbroken。全部自有Job释放及归档清理后，按parent授权仅补这5套：两个performance和三个shutdown。**不换token、不重跑原93套、不覆盖原9红、不增8 GiB阈值。**

续执行实际重新验证父2025份sourcehash完全一致，重建同一token下原freeze，转换后的每份字节与原 `frozen_hashes` 相等；相同引擎hash、原场景序号 `complete-93` 至 `complete-97`、相同fixture路径、APPDATA/LOCALAPPDATA/输出根和预算。原生helper仅重绑新执行器所有权。新冷导入exit0/errors=[]。最终 `original_red_rows_unchanged=true`，5套全部真正启动，追加3 PASS、2 RED；程序检查98名称和mode唯一、98=87+11、missing=[]。

严格parser与candidate单元最后14项通过（`E:/scratch/round58-continuation-unit.stderr.log`）；负向覆盖漂移、残留Job、缺row但已启动的executedbroken、禁止旧红重跑及正式DLL保留。

|mode|selected|executed|pass|red|本轮边界|
|---|---:|---:|---:|---:|---|
|short headless|92|92|83|9|普通上限180秒|
|native integration|1|1|1|0|assembly mandatory66|
|long correctness|2|2|1|1|restart仅一次，外层600秒；另一套headless按原预算|
|performance|2|2|1|1|真实原场景，外层600秒；原业务门未放宽|
|scoped bind negative|1|1|1|0|不等同严格零ERROR|
|GUI required|2|0|0|0|`local_spell_restore_test`、`server_validation_countdown_test`，本轮not-run|

独立required extracted harness `round50_finished_lobby_tight_test`：本指纹独立step一次，exit0、6个实际CHECK、唯一RESULT checks6、archive/same-freeze验证通过；不计入98或100。worker45前置也不额外计formal场景（该名字的complete行仍只计一次）。

native standalone2 (`test_temporary_cleanup_core.py` / `test_process_tree_owner_core.py`) 本轮not-run；supplementary `round47_host_lifecycle_board_test -- window` 本轮not-run。没有等待GUI、冒计headless、使用release EXE --script或借用其它freeze的GUI/native成功。

## CHECK总数差87的实际程序对账

**5542是合法唯一RESULT的declared checks合计，不是已观察5542个断言；实际原始CHECK行5455，含失败和无RESULT中断前事件。**

五套不打印CHECK行，仅在RESULT声明：

|suite|declared|CHECK打印|
|---|---:|---:|
|client_identity_inbox_contract_test|58|0|
|gateway_instance_binding_test|20|0|
|content_environment_test|30|0|
|worker_content_environment_test|45|0|
|deployment_approved_root_test|47|0|

这五套声明合计200。反向五套无合法RESULT却有打印：round28 49、end_command 21、activation_command 21、play_groups 2、relay_cfg 20，合计113。程序核验 `5542-5455 = 200-113 = 87`。其余有RESULT且打印CHECK的套件逐套数量一致。没有把quiet套件的声明冒充逐事件观测，也没有把中断前113条CHECK作为这些套件通过。

## 全部11个RED：最早原始失败与最小已证实原因

每行日志均为 `evidence/complete-<suite>.stdout.log/.stderr.log`，hash及完整命令/fixture/父exit/Job见 `execution-readback.json`；对应原输入源字节在 `evidence/frozen-inputs/tests/`。表中exit125是执行器终止，不是自然成功。

|suite|父exit|最早原始失败 / 源码位置|定位与剩余未知|
|---|---:|---|---|
|round28-command-migration_test|125|SCRIPT ERROR：给Control写不存在的 `_network_session_transferred`；`verify_enet_held` :173；另有继承end :170|旧夹具未迁宿主生命周期字段，协程中断无RESULT后timeout；不是“CHECK都绿”|
|battle_board_end_command_test|125|同字段赋值错误，`run` :170|旧夹具契约断裂；无RESULT/timeout保留|
|battle_board_activation_command_test|125|同字段赋值错误，`run` :150|旧夹具契约断裂；无RESULT/timeout保留|
|active_choice_source_command_test|0|同字段赋值错误，`network_cases` :330|RESULT checks65/failed0仍拒绝SCRIPT ERROR，不放行|
|location_choice_source_command_test|0|同字段赋值错误，`network_cases` :178|RESULT checks37/failed0仍拒绝SCRIPT ERROR|
|player_choice_source_command_test|0|同字段赋值错误，`network_cases` :281|RESULT checks65/failed0仍拒绝SCRIPT ERROR|
|battle_play_groups_test|125|stdout首先 `single player who played cards receives one group false`；:47 `get_child(0)`越界；:48 `has_meta` nil|首个真实分组缺失尚未定位；后两错是无保护继续访问的级联，不假定是某个展示模块根因|
|net_server_gateway_restart_test|1|`中局续局出现客户端错误立即停止 false`，RESULT checks52|真实client-error导致续局短路；不是600秒timeout。末镜像seq422/426、round10/outpost、game_over=false；错误具体字符串未被夹具输出，完整根因未知|
|net_server_relay_cfg_test|125|执行器 `execution_error=byte_budget`；20 CHECK true、没有RESULT|环境累计8 GiB预算中止，已执行broken；不把未到达的断言虚构成业务失败，也没有重跑抹去它|
|validation_pipeline_performance_test|1|204/204组装后 `ROOM_DATA_ASSEMBLY_REJECT`：phase=write、rename_attempted=true、rename_error=1、staging_exists=true；随后 `complete production preparation includes real isolated loading false`|真实正式准备发布失败；destination_length181/staging_length199，`PIPELINE_PREPARATION_ERROR 无法发布完整会话目录`。未到真实isolated loading。未捕获原Win32底层原因，不声称已根治；原性能/完整链门继续RED|
|server_shutdown_close_handoff_test|1|新recover实例自发close：`SERVER_STOP_FAILED {room:"房间状态写入失败，未关闭"}`，随后两条false|明确卡在保存写入拒绝而非已完成release；具体新request/磁盘receipt因归档缺口未能复核，不能推断是旧receipt、句柄锁或竞态|

restart真实父进程耗时278.931秒，外层上限600秒，runs=1；60秒性能gate在60008 ms为false。没有自然终局，没有执行正式终局save/readback/journal终末hash，不能报正确性通过。`evidence/restart-continuation/continuation-0.json` 与 `continuation-1.json` 已原字节归档、读回，reason=client_error，不使用decisions计数替代权威推进证据。

### shutdown：历史283绿不冲抵本次红

本轮三套全部执行，实际CHECK分别86/36/161，合计283，pending36及原regression161 PASS；main86有2条false：

1. `shutdown 自发 close 原保存→退出→release 链完成新代际`（源:114）。
2. `新关闭 proof 精确属于新 instance/request`（源:116）。

原始stdout仍证明前段公开console单房close后的空大厅保存判据、EXITED/release、一次stop、摘要/绑定拒绝与recover新实例成立；自有目录冲突撤销/原recovery恢复检查也true，随后新实例真实close请求已发出检查true。**但紧接着原件明确打印“房间状态写入失败，未关闭”，不得以之前的close/save成功宣布整个shutdown通过。**

归档缺口：执行器只保留log/report/manifest，未保留该fixture的 `evidence.json` 和 `control/*.response.json`；generated清理后不能提供这次失败的完整原receipt字节、request_id或stop.status。这里只能报告原始stdout、准确两条断言及冻结源码，不能用历史283的receipt、源码预期或后来的成功补造本次response。没有再次运行或修改测试/生产来填这个缺口。历史283 PASS与本次main RED均保留。

## strict差一与未授权worker ERROR

原93 pass84/strict83、最终pass87/strict86之差均来自唯一 `gateway_bind_failure_test`：实际7 checks、exit0、精确六行stderr调用栈、冻结源hash和line13绑定通过，`strict_passed=false`。其logger副本 `worker/complete-65/appdata/FateDomination/logs/godot.log` 只有精确 `ERROR: Couldn't create an ENet host.`，同stdout/stderr/hash/Job绑定，scope verified=true；未对其它ERROR扩许可。

此外8份worker日志未获scope豁免，顶层继续false：

- complete-1 round28、complete-2 end、complete-3 activation、complete-4 active_choice、complete-6 location_choice、complete-21 player_choice：上述已移除字段SCRIPT ERROR的原logger副本。
- complete-17 `battle_play_groups_test`：get_child越界与nil has_meta原logger副本。
- **complete-45 `room_data_preparation_dependencies_test`**：`preparation-33196-2328362/work-5/room_validation/33196-2363261/engine.log` 真实打印无法读取 `validation-data/masters` 与 `validation-data/servants` 两条ERROR。该parent行CHECK/RESULT通过不等于worker零ERROR；本次严格scope未验证，不能按“它是负向测试”或trace文字擅自忽略。它不是第12个suite row红，但独立阻断source总门。

parent原始error行总数10与上述worker logger副本是不同统计，不把副本重复加成新suite。最终拒绝原因为 `current_suite_failure`、`unscoped_worker_engine_error`。

## assembly66与隔离收尾

assembly本次exit0、RESULT66、实际CHECK66、零stderr错误，mandatory无skip。真实覆盖小清单成功/摘要读回、目标文件/目录冲突、取消、父目录移走、cache改变、自有FileAccess锁、真实FindFirstFile枚举、独立external-file占锁、正式204文件完整清单发布/逐文件读回、204自有锁拒绝和真实RoomDataPreparation加载。外部锁PID39184，共享读写但不共享删除，原回执匹配并检查真实退出码0；自有文件DELETE error32与外部锁/无自有句柄区分，完整204路径均受helper scope/owner/token授权。

这只是该受控样本通过；**同source的pipeline正式发布实际RED仍存在，不能由assembly66成功推断历史或当前偶发发布失败已根治。**

真实main/worker物理E user://、随机token、child exit0和实际worker_pool20预检通过。最终103条根执行记录全部 `exited=true / active_owned_processes=0 / log_handles_released=true`，原93与补5所有权均保留；不是宣称103个唯一PID或所有child自然exit0。各RED子进程若无独立退出码记录，明确保持未知，Job0只证明不再活动。

最终所有manifest日志/worker索引及825源字节归档SHA读回通过，`cleanup=generated_removed`，生成树不存在。旧PID28100、正式项目、正式存档、候选包、正式DLL均未清理或改动。未升级Godot、未导出release、未改生产/GDScript游戏测试、未重跑9个已执行红项。

项目唯一改动：两个owned执行器文件 `tools/tests/test_round29_integrated_evidence.py`、`tools/tests/test_round50_candidate_selection.py`，以及本文。其它产物仅在批准E scratch。执行器新增三套选择/检查/E根注入、热重载克隆排除、漂移原件记录、同token仅缺套续执行与负向单元；没有删mandatory、吞ERROR或放宽业务时限。
