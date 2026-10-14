# 重构恢复：业务实测基线与统一复验入口

> 本轮仅归档/静态核对，**没有启动 Godot，没有新增 runner，没有改生产、原测试、旧报告、政策或 DLL**。JSON 是纯数据，`auto_start=false`；所有后续用例 `not_run`，当前复验通过数为 0。

## 1. 基线身份与证据边界

- 历史证据根：`E:/scratch/current-business-live-test`。由 `final-results.json`、两份原 manifest、全部原日志重新聚合，未以摘要手填数字。
- 历史 source 指纹：`be1a1043afaa31538c429e96ac5ed7385fa47620fe7e0fb1143e9ece75bd0da3`；原始文件项 **1553**，文件路径/长度/SHA 完整保存在计划的 `historical_baseline.source_files`。
- 源路径集读回时间（UTC）：`2026-10-12T05:07:00.516812+00:00`。本轮按同一有序路径集逐文件重算：`be1a1043afaa31538c429e96ac5ed7385fa47620fe7e0fb1143e9ece75bd0da3`，与历史不同项 **0**。这只是历史路径集的只读时点观察，不是全仓最终冻结，也不认证后续写入。新增 preview 夹具不在该历史指纹内。
- 指纹公式与原 `finalize.py:12` 相同：SHA-256(UTF-8 JSON 文件清单，`sort_keys=True`、`separators=(",", ":")`、`ensure_ascii=False`)；保留列表原序，条目含 `path/sha256/bytes`。
- 历史引擎 SHA-256：`ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424`；历史转换后 `project.godot` SHA-256：`55123245c0946188cbee4f77a6a86fa579f49afa2dd8352d9e86d054ac4351ea`。
- 类缓存历史读回：`AreaActionRules → res://scripts/system/area_action_rules.gd`；`MatchLobbySession → res://scripts/net/session/lobby_session.gd`；不允许 docs/reports 归档类注册污染新冻结。
- 当前原日志清单 **194** 项、截图 **13** 项逐项重算 SHA 均与原记录相等；45 次运行的 stdout/stderr 均读回。原解析器 `parse/analyze` 与执行器 `unique_fields` 仅提取原 AST 纯函数重解析，**45 次与历史 analysis 完全一致**；这不是业务重跑。
- 计划保全每次原 argv、exit、RESULT 原文、完整失败数组、错误、失败 CHECK、日志 SHA，以及进程回执与全部文件指纹。完整 CHECK 原始字节仍在原 evidence 目录；本任务没有权限新增日志档案文件，不能声称原始日志正文已入库。
- 两个新文件位于可版本管理的 docs/newtools；本轮不 git add、不提交。外部 scratch 不应当作永久归档，父代理可另获授权后归档原日志。

## 2. 代码计算的历史统计

|口径|数量|
|---|---:|
|实际运行次数|45|
|不同场景|36|
|历史严格通过运行|14|
|历史非通过运行|31|
|headless 运行|42|
|真实窗口运行|3|
|历史窗口通过|0|
|按场景＋业务参数＋模式去重后的最新用例|43|
|最新用例历史通过|14|
|最新用例历史非通过|29|
|有效唯一 RESULT 运行|41|
|无 RESULT 运行|3|
|有 RESULT 但协议非法|1|
|合法 RESULT 声明检查数|1870|
|历史通过运行声明检查数|1263|
|全部原日志实际 CHECK 事件|1886|
|SCRIPT ERROR 行|9|
|真实进程回执|48|

- 进程回执均记录自然退出、自有 Job active=0、日志句柄释放；这些是**历史回执**，不是当前系统进程扫描。历史用户编辑器 PID 6420 不能当作后续启动的永久许可。
- 首批外层工具被中断；原 manifest 保留 20 次套件，补批 25 次，进程回执分别 22/26。只认可原内核回执，不从 PID 消失反推 exit。
- 非通过不是“31 个生产缺陷”：其中有前置未达、脚本错误、非法/缺 RESULT、未注入诊断。未到部署不算验过出牌，未生成待选不算验过选择后果。
- 有效 RESULT 检查数、通过运行检查数、原 CHECK 事件数分别计账，不相互代替。身份恢复与自然终局预算重试仍属同一用例，不增加业务覆盖。

## 3. 十四项历史绿色控制（新冻结必须全跑，不能继承绿）

|场景|历史 checks|
|---|---:|
|`res://tests/magic_payment_contract_test.tscn`|271|
|`res://tests/engagement_test.tscn`|21|
|`res://tests/battle_event_discard_test.tscn`|40|
|`res://tests/post_battle_choice_test.tscn`|191|
|`res://tests/round_change_test.tscn`|13|
|`res://tests/turn_order_test.tscn`|5|
|`res://tests/turn_transition_test.tscn`|50|
|`res://tests/card_effect_runtime_test.tscn`|228|
|`res://tests/card_revealed_test.tscn`|30|
|`res://newtests/game_start_session_origin_test.tscn`|69|
|`res://newtests/b06_initial_card_registration_probe.tscn`|57|
|`res://newtests/a1_refill_draw_origin_test.tscn`|106|
|`res://newtests/b31_round_tail_change_order_probe.tscn`|168|
|`res://tests/net_data_sync_test.tscn`|14|

## 4. 全部历史运行索引（保留红与不可判定）

|记录|场景 / 业务参数|模式|exit|历史判定|checks|首个失败或协议原因|
|---|---|---|---:|---|---:|---|
|H01|`res://tests/magic_payment_contract_test.tscn` |headless|0|PASS|271||
|H02|`res://tests/section5_engine_test.tscn` |headless|0|ASSERTION_RED_AND_INVALID_RESULT|—|invalid_result: Invalid \escape: line 1 column 90 (char 89); false_check|
|H03|`res://tests/command_spell_test.tscn` |headless|1|ASSERTION_OR_PRECONDITION_RED|91|command move reaches chosen arbitrary location|
|H04|`res://tests/servant_skill_eight_magic_test.tscn` |headless|1|ASSERTION_OR_PRECONDITION_RED|26|real servant skill passes the eight-magic gate|
|H05|`res://tests/deploy_rules_test.tscn` |headless|1|ASSERTION_OR_PRECONDITION_RED|21|next seat in order|
|H06|`res://tests/deploy_rules_layer_test.tscn` |headless|1|ASSERTION_OR_PRECONDITION_RED|22|deploy_to_area lands on the best seat|
|H07|`res://tests/engagement_test.tscn` |headless|0|PASS|21||
|H08|`res://tests/battle_event_discard_test.tscn` |headless|0|PASS|40||
|H09|`res://tests/post_battle_choice_test.tscn` |headless|0|PASS|191||
|H10|`res://tests/round_change_test.tscn` |headless|0|PASS|13||
|H11|`res://tests/turn_order_test.tscn` |headless|0|PASS|5||
|H12|`res://tests/turn_transition_test.tscn` |headless|0|PASS|50||
|H13|`res://tests/climax_elimination_test.tscn` |headless|1|ASSERTION_OR_PRECONDITION_RED|16|player deployed before the cut|
|H14|`res://tests/climax_gated_ability_test.tscn` |headless|1|ASSERTION_OR_PRECONDITION_RED|5|the priciest noble phantasm is loaded from the servant template|
|H15|`res://tests/card_effect_runtime_test.tscn` |headless|0|PASS|228||
|H16|`res://tests/card_keyword_test.tscn` |headless|1|ASSERTION_OR_PRECONDITION_RED|28|clone keeps the keyword|
|H17|`res://tests/card_revealed_test.tscn` |headless|0|PASS|30||
|H18|`res://tests/net_cards_test.tscn` |headless|0|SCRIPT_ERROR|—|expected_one_stdout_result; engine_or_assertion_error|
|H19|`res://tests/net_move_test.tscn` |headless|1|ASSERTION_OR_PRECONDITION_RED|3|fixture has legal regular movement target|
|H20|`res://tests/checkpoint_identity_test.tscn` |headless|1|ASSERTION_OR_PRECONDITION_RED|15|Array 1500个不同身份同内容集合在原预算内采集|
|H21|`res://newtests/game_start_session_origin_test.tscn` |headless|0|PASS|69||
|H22|`res://newtests/game_start_session_origin_test.tscn` `-- allocation_failure`|headless|1|DIAGNOSTIC_ALLOCATION_FAULT_NOT_INJECTED|3|allocation failure closes and never resurrects old token|
|H23|`res://newtests/b06_initial_card_registration_probe.tscn` |headless|0|PASS|57||
|H24|`res://newtests/a1_refill_draw_origin_test.tscn` |headless|0|PASS|106||
|H25|`res://newtests/b31_round_tail_change_order_probe.tscn` |headless|0|PASS|168||
|H26|`res://newtests/round_tail_discard_played_cards_probe.tscn` |headless|1|ASSERTION_OR_PRECONDITION_RED|28|尾部普通攻击原对象离开出牌区且确实进入原玩家弃牌堆|
|H27|`res://newtests/four_kind_real_execution_test.tscn` `-- set_concealed`|headless|1|ASSERTION_OR_PRECONDITION_RED|10|real deploy command|
|H28|`res://newtests/four_kind_real_execution_test.tscn` `-- play_group`|headless|1|ASSERTION_OR_PRECONDITION_RED|10|real deploy command|
|H29|`res://newtests/four_kind_real_execution_test.tscn` `-- end_action`|headless|1|ASSERTION_OR_PRECONDITION_RED|11|real deployment satisfies obligation|
|H30|`res://newtests/four_kind_real_execution_test.tscn` `-- activate`|headless|1|ASSERTION_OR_PRECONDITION_RED|10|real deploy command|
|H31|`res://newtests/choice_submit_real_execution_test.tscn` `-- player_choice`|headless|1|ASSERTION_OR_PRECONDITION_RED|43|真实时点产生待选项: choice_submit_player|
|H32|`res://newtests/choice_submit_real_execution_test.tscn` `-- option_choice`|headless|1|ASSERTION_OR_PRECONDITION_RED|38|真实时点产生待选项: choice_submit_option|
|H33|`res://newtests/choice_submit_real_execution_test.tscn` `-- cancel_choice`|headless|1|ASSERTION_OR_PRECONDITION_RED|56|真实时点产生待选项: choice_submit_mandatory|
|H34|`res://newtests/choice_submit_real_execution_test.tscn` `-- confirm_broadcast`|headless|1|ASSERTION_OR_PRECONDITION_RED|8|真实规则行动与战斗产生播报等待|
|H35|`res://tests/net_selection_test.tscn` |headless|1|ASSERTION_OR_PRECONDITION_RED|11|explicit human and AI seats initialized|
|H36|`res://tests/net_resume_identity_test.tscn` |headless|0|PRELIMINARY_FRAME_CAPPED_NO_RESULT|—|expected_one_stdout_result; false_check|
|H37|`res://tests/net_data_sync_test.tscn` |headless|0|PASS|14||
|H38|`res://tests/broadcast_authority_enet_test.tscn` |headless|1|SCRIPT_ERROR|27|real deployment|
|H39|`res://tests/native_choices_window_test.tscn` `-- window`|window|1|ASSERTION_OR_PRECONDITION_RED|59|nonzero_exit; result_failures; engine_or_assertion_error|
|H40|`res://tests/net_v2_ui_input_parity_window_test.tscn` `-- window`|window|1|ASSERTION_OR_PRECONDITION_RED|6|formal network v2 renders native owned hand|
|H41|`res://newtests/round75_order_resources_window_test.tscn` `-- window`|window|1|ASSERTION_OR_PRECONDITION_RED|34|A 行动顺位表真实展开折叠入口存在|
|H42|`res://tests/natural_game_over_test.tscn` |headless|0|PRELIMINARY_FRAME_CAPPED_NO_RESULT|—|expected_one_stdout_result; false_check|
|H43|`res://tests/net_resume_identity_test.tscn` |headless|1|ASSERTION_OR_PRECONDITION_RED|10|真实效果进入原真人的玩家选择待答|
|H44|`res://tests/replay_restore_batch_test.tscn` |headless|1|ASSERTION_OR_PRECONDITION_RED|4|real engine reaches broadcast barrier|
|H45|`res://tests/natural_game_over_test.tscn` |headless|1|ASSERTION_OR_PRECONDITION_RED|12|local natural end within guard|

## 5. 本轮统一复验选择

计划共 **37 个用例 / 29 个场景**：headless 34，窗口 3；包含全部 14 项历史绿色控制和 3 个无历史业务运行记录的 preview 分支。**实际新启动 0，当前绿 0**。这是聚焦整合，不是全量回归/发行门。

|组|用例数|复验目的|
|---|---:|---|
|control_14|14|控制原本已过的费用、卡效、开局、抽补、回合等行为|
|deployment|2|旧部署两专项先定位失败发生在哪个入口/前置|
|deployment_downstream_commands|4|set_concealed/play_group/end_action/activate 分开，不能以部署红代替后果覆盖|
|seq|2|net_cards 与 broadcast_authority_enet，保留 Dictionary 缺 seq 回溯|
|discard|1|原对象入弃牌/技能回区/残留/候选与推进差值|
|choice|4|四种提交种类及真实待选/播报和规则后果|
|preview|3|preview/startup/formal-submit；保存原来源，不放宽裸报价默认拒绝|
|checkpoint|1|原 Array/Dictionary 1500 身份、别名/循环/碰撞与比较预算|
|recovery_terminal|3|通过前置后再跑身份恢复/回放屏障/自然终局完整入口|
|window|3|native choices/v2 输入/资源，窗口必须串行，争议断言先分类|

**执行顺序**：单写者全部结束 → 一次独立字节新冻结 → 零错误冷 import/类缓存核对 → 部署与四命令 → seq/弃牌/choice/preview/checkpoint → 同冻结十四控制 → 前置确实到达后恢复/自然终局 → 单执行者串行窗口。所有路径、场景参数、预算与历史对应记录在 JSON 的 `cases`；阶段排序按 `execution_order`，不要把数组中的控制项顺序误读成先执行的要求。

### 需要裁定的测试口径，不默认改产品

- **独立可折叠顺位表、顶栏玩家名已被用户拒绝**：`docs/user-decisions-2026-10-11.md:75-83,135-143` 是已签前端范围；`newtests/round75_order_resources_window_test.gd:120-131` 是旧窗口探针，其断言仍要求这些控件/名称。保留历史红，主代理先分类测试范围；不得把拒绝的需求重新列成必修或待用户重复批准。
- 该探针 `:159-167` 验缺字段是否残留垃圾，须与“新增缺失数值占位”区别；政策不授予改生产/删断言的默认权限。资源实时刷新与 GUI 命中仍独立保留。
- `allocation_failure` 没有注入实际分配故障，历史 2 条红保留；正常业务控制只选无参开局，故障分支另有完整注入授权与证据后才判定。
- `group-preview-origin_contract.gd:71-73` 的 `literal-hard` 要求裸报价放行，不是本轮成功目标；`:83-98` 的 `submit` 分支预期正式适配器拒绝，只选 `formal-submit` 作为正式入口成功探针。**后者只验回执成功，不独立证明扣款/移牌/终态全后果**；不得将其与其他冻结的绿拼接成整链。
- `group_preview_prefix_validity_test.gd:20-44` 直接清库/构造对象，没有可信来源准备，不纳入本轮强制绿；交合法夹具 owner 核对，不放宽生产门。

## 6. 给主代理的实际运行入口（不再设计或新增工具）

**首选直接复用现有函数，不运行旧 scratch runner 的 main，也不新增 runner。**

- 执行器：`tools/run_isolated_godot_test.py:582`：`execute(command, env, generated, evidence, label, budgets, records, *, no_kill=False)`。必须显式 `no_kill=True`，进入 `execute_observation`；返回 `(stdout, stderr, actual_exit_code)`。
- 判定器：`tools/tests/test_round29_integrated_evidence.py:154`：`analyze(out, err, code)`。本轮静态重解析已逐次对上原证据。不要改用 legacy `runner.analyze` 而静默改变结果协议。
- 参数完整映射：`command=绑定路径后的 cases[].godot_argv_template`；`env=仅子进程批准环境`；`generated=Path(新 owner/generated)`；`evidence=Path(新 owner/evidence)`；`label=case.id`；`budgets=case.budgets`；`records=新 manifest.processes`；`no_kill=True`。调用前/异常 finally 都持久化 manifest；空 records 不证明没启动。JSON 已逐项提供全部参数与原生 argv，主代理只绑定新冻结与日志根，不需增加执行器。
- 环境五目录必须落物理 E 的新 generated 子树；批准根/fixture/screenshot 参数见 JSON `executor.child_environment_templates`。必须先建实际祖先与截图目录，不能拿字符串声明充当落盘证明。
- 如确需双阶段主/worker 路径探针，调用既有 `run_two_phase_probe(executable, probe, env, generated, evidence, token, budgets, records)`（`:833`）；它真实派生 worker，必须先核并发名额。用户编辑器＋主探针＋worker 会超过历史总引擎上限 2，**不能擅自关闭编辑器或转同进程替身**。单槽路径证据不得冒称完整 worker 证据。
- 新冻结：独立文件复制，不用硬链接；历史 `source_files` 加上所选新 fixture 及真实递归依赖。记录 source 与转换后 frozen 两套 hash；开发 VCS 最小转换已有 `transform_isolated_editor_vcs(text)`，任何 MCP/插件转换需显式批准并保留原 autoload/通知契约；主源绝不修改。import 用真实 `--headless --editor --import --path <新冻结> --quit-after 1200`，仍经 execute(no_kill=True) 监督且零错误。
- 启动许可不由本计划授予。先停止所有共享写者，重新读实际引擎进程/父子关系、E 盘空间、源/冻结哈希。后续编辑即作废本轮待验指纹，不得继承历史 14 绿。

### 全部精确 argv（仅两个路径绑定项未决，不能拿占位符直接运行）

`{engine}` = 主代理批准的**物理 E 非 console 引擎独立副本**；`{frozen_project}` = 本轮新冻结项目。二者绝不是已清理的历史 generated 路径。所有命令通过上述 execute 函数，不直接裸 subprocess，不使用默认强杀。每项墙钟/字节/自由空间预算已在 JSON 明列。

|用例|组|墙钟秒|Godot argv（原生路径）|
|---|---|---:|---|
|V01|control_14|180|`'{engine}' --headless --fixed-fps 60 --path '{frozen_project}' --scene res://tests/magic_payment_contract_test.tscn --quit-after 3600`|
|V02|control_14|180|`'{engine}' --headless --fixed-fps 60 --path '{frozen_project}' --scene res://tests/engagement_test.tscn --quit-after 3600`|
|V03|control_14|180|`'{engine}' --headless --fixed-fps 60 --path '{frozen_project}' --scene res://tests/battle_event_discard_test.tscn --quit-after 3600`|
|V04|control_14|180|`'{engine}' --headless --fixed-fps 60 --path '{frozen_project}' --scene res://tests/post_battle_choice_test.tscn --quit-after 3600`|
|V05|control_14|180|`'{engine}' --headless --fixed-fps 60 --path '{frozen_project}' --scene res://tests/round_change_test.tscn --quit-after 3600`|
|V06|control_14|180|`'{engine}' --headless --fixed-fps 60 --path '{frozen_project}' --scene res://tests/turn_order_test.tscn --quit-after 3600`|
|V07|control_14|180|`'{engine}' --headless --fixed-fps 60 --path '{frozen_project}' --scene res://tests/turn_transition_test.tscn --quit-after 3600`|
|V08|control_14|180|`'{engine}' --headless --fixed-fps 60 --path '{frozen_project}' --scene res://tests/card_effect_runtime_test.tscn --quit-after 3600`|
|V09|control_14|180|`'{engine}' --headless --fixed-fps 60 --path '{frozen_project}' --scene res://tests/card_revealed_test.tscn --quit-after 3600`|
|V10|control_14|150|`'{engine}' --headless --fixed-fps 60 --path '{frozen_project}' --scene res://newtests/game_start_session_origin_test.tscn --quit-after 1800`|
|V11|control_14|150|`'{engine}' --headless --fixed-fps 60 --path '{frozen_project}' --scene res://newtests/b06_initial_card_registration_probe.tscn --quit-after 1800`|
|V12|control_14|150|`'{engine}' --headless --fixed-fps 60 --path '{frozen_project}' --scene res://newtests/a1_refill_draw_origin_test.tscn --quit-after 1800`|
|V13|control_14|150|`'{engine}' --headless --fixed-fps 60 --path '{frozen_project}' --scene res://newtests/b31_round_tail_change_order_probe.tscn --quit-after 1800`|
|V14|control_14|150|`'{engine}' --headless --fixed-fps 60 --path '{frozen_project}' --scene res://tests/net_data_sync_test.tscn --quit-after 1800`|
|V15|deployment|180|`'{engine}' --headless --fixed-fps 60 --path '{frozen_project}' --scene res://tests/deploy_rules_test.tscn --quit-after 3600`|
|V16|deployment|180|`'{engine}' --headless --fixed-fps 60 --path '{frozen_project}' --scene res://tests/deploy_rules_layer_test.tscn --quit-after 3600`|
|V17|deployment_downstream_commands|150|`'{engine}' --headless --fixed-fps 60 --path '{frozen_project}' --scene res://newtests/four_kind_real_execution_test.tscn --quit-after 1800 -- set_concealed`|
|V18|deployment_downstream_commands|150|`'{engine}' --headless --fixed-fps 60 --path '{frozen_project}' --scene res://newtests/four_kind_real_execution_test.tscn --quit-after 1800 -- play_group`|
|V19|deployment_downstream_commands|150|`'{engine}' --headless --fixed-fps 60 --path '{frozen_project}' --scene res://newtests/four_kind_real_execution_test.tscn --quit-after 1800 -- end_action`|
|V20|deployment_downstream_commands|150|`'{engine}' --headless --fixed-fps 60 --path '{frozen_project}' --scene res://newtests/four_kind_real_execution_test.tscn --quit-after 1800 -- activate`|
|V21|seq|180|`'{engine}' --headless --fixed-fps 60 --path '{frozen_project}' --scene res://tests/net_cards_test.tscn --quit-after 3600`|
|V22|seq|150|`'{engine}' --headless --fixed-fps 60 --path '{frozen_project}' --scene res://tests/broadcast_authority_enet_test.tscn --quit-after 1800`|
|V23|discard|150|`'{engine}' --headless --fixed-fps 60 --path '{frozen_project}' --scene res://newtests/round_tail_discard_played_cards_probe.tscn --quit-after 1800`|
|V24|choice|150|`'{engine}' --headless --fixed-fps 60 --path '{frozen_project}' --scene res://newtests/choice_submit_real_execution_test.tscn --quit-after 1800 -- player_choice`|
|V25|choice|150|`'{engine}' --headless --fixed-fps 60 --path '{frozen_project}' --scene res://newtests/choice_submit_real_execution_test.tscn --quit-after 1800 -- option_choice`|
|V26|choice|150|`'{engine}' --headless --fixed-fps 60 --path '{frozen_project}' --scene res://newtests/choice_submit_real_execution_test.tscn --quit-after 1800 -- cancel_choice`|
|V27|choice|150|`'{engine}' --headless --fixed-fps 60 --path '{frozen_project}' --scene res://newtests/choice_submit_real_execution_test.tscn --quit-after 1800 -- confirm_broadcast`|
|V28|preview|180|`'{engine}' --headless --fixed-fps 60 --path '{frozen_project}' --scene res://newtests/group-preview-origin_contract.tscn --quit-after 3600 -- preview`|
|V29|preview|180|`'{engine}' --headless --fixed-fps 60 --path '{frozen_project}' --scene res://newtests/group-preview-origin_contract.tscn --quit-after 3600 -- startup`|
|V30|preview|180|`'{engine}' --headless --fixed-fps 60 --path '{frozen_project}' --scene res://newtests/group-preview-origin_contract.tscn --quit-after 3600 -- formal-submit`|
|V31|checkpoint|180|`'{engine}' --headless --fixed-fps 60 --path '{frozen_project}' --scene res://tests/checkpoint_identity_test.tscn --quit-after 3600`|
|V32|recovery_terminal|150|`'{engine}' --headless --fixed-fps 60 --path '{frozen_project}' --scene res://tests/net_resume_identity_test.tscn`|
|V33|recovery_terminal|150|`'{engine}' --headless --fixed-fps 60 --path '{frozen_project}' --scene res://tests/replay_restore_batch_test.tscn --quit-after 1800`|
|V34|recovery_terminal|330|`'{engine}' --headless --fixed-fps 60 --path '{frozen_project}' --scene res://tests/natural_game_over_test.tscn`|
|V35|window|150|`'{engine}' --fixed-fps 60 --path '{frozen_project}' --scene res://tests/native_choices_window_test.tscn --quit-after 1800 -- window`|
|V36|window|150|`'{engine}' --fixed-fps 60 --path '{frozen_project}' --scene res://tests/net_v2_ui_input_parity_window_test.tscn --quit-after 1800 -- window`|
|V37|window|150|`'{engine}' --fixed-fps 60 --path '{frozen_project}' --scene res://newtests/round75_order_resources_window_test.tscn --quit-after 1800 -- window`|

- 身份与自然终局完整入口保留场景自 quit + 有限墙钟监督，不加首次截断的帧限；原有帧限无 RESULT 记录永久保留为不可判定。历史墙钟预算是执行观察门，非新性能要求；超限保留 exit=null/自有现场并停止后续派发，绝不强杀或伪造 exit。
- 窗口三项同一执行者串行，去掉 `--headless` 并保留 `-- window`；通知说明不需前台但不要最小化/遮住截图。必须读回开始/结束通知、实际 GUI 事件和原生画面；本任务没有查看新画面，历史五张已查看仅是原报告记录。

## 7. 已失效或不合本轮策略的入口

|入口|实际问题|处理|
|---|---|---|
|`E:/scratch/current-business-live-test/isolated-7493628bbbb2e5925a76e6dc3894075f/generated`|原 generated 已清理，项目与 CurrentGodot.exe 均不存在|旧 argv 只保留为证据，新建独立冻结再绑定|
|`E:/scratch/current-business-live-test/run_current.py`|固定旧 ROOT/PID6420，main 覆盖原 summary/report|只读参考，不重新执行 main|
|`supplement.py`|顶层读取旧 pointer/已删除 generated，并追加旧 supplement manifest|禁止导入当纯 helper，不用 prepare 伪造续跑|
|`finalize.py`|依赖已回收 freeze，会改旧证据并清理|不重跑；仅只读复用公式|
|`newtools/run_choice_submit_real_execution.py`|--root/--godot/--kind 是真实参数，但用旧 PROBE_SCRIPT、execute 未传 no_kill|不执行其 main；直接用统一 execute API 传四 kind|
|`tools/run_isolated_godot_test.py` CLI|没有 --window/--user-args；固定 headless；双阶段探针可能超引擎名额；冻结导入不会复用历史 VCS/MCP 转换|不得编造 flag、丢 kind 或静默跳窗口；使用同文件 execute 函数|
|`tools/run_refactor_headless_baseline.py`|固定旧报告输出/D 引擎，异常 taskkill/proc.kill|不用于本轮|

## 8. 验收与未覆盖

- 每项必须：唯一合法 stdout RESULT、stderr 无 RESULT 协议行、正整数 checks、显式空失败声明、实际 CHECK 一致且无 false、零 SCRIPT ERROR/ERROR、真实 exit0；同时 source/freeze 零漂移、整 Job0、日志释放。历史检查数只是比较值，变更须给源码/分支依据，不通过降阈值刷绿。
- 原首红、前置阶段、后果断言分别记录；无 RESULT/启动前阻断/漂移未复验/未到目标不是 PASS。十四控制也只能以新冻结实跑回执计绿。
- 业务红但自有 Job 已退出/日志释放，可按已批准 collect-failures 继续独立项；共享漂移、路径/空间门或 retained/未知退出立即停。窗口不得与其他窗口并行。
- 原始日志/manifest/失败目标与截图先保全再精确 owner 清理；原现场/用户编辑器/正式存档不是清理对象。
- 本选集不覆盖完整发布/三角色导出、正式独立 worker、LAN 加入/保存恢复/主管重启、多机跨网、OS 硬件输入、身份管理员/密码窗口。恢复/自然终局虽列完整入口，历史没有到目标，后续未实际成功不得改写为覆盖。

## 9. 原证据定位与 SHA

|原文件|SHA-256|
|---|---|
|`final-results.json`|`846c37e194b772fdf1214cd981dbb439ce8076a6467356efd58ef74604271cb2`|
|`summary.json`|`6fafaf84a4a7a812e20329004e45d0d4f5a5b4f0df698fa4a4c9915069af9354`|
|`report.md`|`b5737a10bf57387554a16fef807c793981b74ac74c4f44846b6f8a55d8f5f07e`|
|`source-fingerprint.json`|`2be12b2c5e72b95b36c0141c90cc5835a99872791422a87b09eb04928e4982af`|
|`base-manifest.original.json`|`30654536d9e148cc2f29dc5bd2102ce82a03e222f0a8830c9fc817c7212d8dff`|
|`supplement-manifest.json`|`bd594b6a1c68b49c7a58ab100fbf7861289002ab91fb25180b49977c8420ec24`|
|`run_current.py`|`119bbbe6791c0c44549013dcac3dc883503352a3bfcbb3cf8fcda98427290346`|
|`supplement.py`|`b97608530baa0bd84be117b9376d2a97971c356c4df7e813e2df2906c77a4e02`|
|`finalize.py`|`bc6beab8689699c091d0f406c7bae4e54e314477c42d19818c26067794a72025`|

原 runner/当前执行器/解析器的本轮读回 SHA 仅作静态检视身份，不倒填成历史执行时绑定。机器计划另存全部日志/截图 hash、历史 source 文件与 45 次运行的完整失败列表，供主代理逐项复核。

文档/计划整理时间（UTC）：`2026-10-12T05:11:41.143540+00:00`。本轮仅完成保全与执行入口整理；未启动引擎、未修业务、未新增任何当前绿色。
