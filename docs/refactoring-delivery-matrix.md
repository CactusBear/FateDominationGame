# 重构交付矩阵：当前核对结果与历史证据

> 核对时间：`2026-10-10T23:16:00.522089+08:00`；源仓库 `E:/Projects/Godot/FateDominationGame-master`，HEAD `8c0f946faf6cc0cd3f04f12f66f5a99a413088ca` 的可变工作树。**不是冻结源码，不是最终发行/全量通过。**

## 1. 阅读口径与现在还差什么

- 状态严格使用：**已完成并验证 / 已接线未全链验 / 模块未接 / 未开始 / 阻断**。完成仅限能力名写明的范围；历史基线任务、静态删壳任务与最终功能交付分开。模块接口存在或模块专项绿不等于生产 caller 已采用；生产已采用又不等于端到端、窗口、正式 EXE 已验。
- 专项 PASS 只授其原冻结/入口/模式；本轮仅阅读旧运行原件、静态源码及运行 Python gate/单元，**没有启动 Godot/GUI/worker/导出 EXE、没有重跑任何游戏专项、没有测速、没有操作 PID17120/28100**。
- 原 A01–G05 的126个唯一ID全部保留；新表四列逐项给出能力、状态、证据和完成缺口。后文原矩阵全文原样保留在“历史附录”；原行号、数量、PASS和指纹仅为历史时点，不能与新表混用。
- 最新全量候选仅执行 **70/101**（69 PASS、68 strict、1 RED；31未执行）；sourcePASS/releasePASS=false。用户流程为实现→真人包→用户测试并通知后才全量，不自行续跑。缺恢复/保存关停整链、当前最终导出包与真人/多机验证，不给完成百分比。**补充（2026-10-10 晚）：那次唯一的 RED（`gateway_relisten_acceptance`）已单独复验为绿——`40/40 CHECK、exit0、ERROR0、Job0`，处置方式是"部署声明 `assets/config/server.cfg:25 startup_seconds=600.0` + 夹具改为读该声明"（详见 `docs/startup-declaration.md`）。这不等同 70/101 那次全量已重跑，全量仍待用户通知后执行。**
- gate 实际观测漂移：本轮首次 `findings=5/allowlist=5/NEW=0/STALE=0` exit0；之后曾读回 `findings=4/allowlist=5/NEW=0/STALE=1，exit1`。**现已 PASS：`findings=4 allowlist=4 new=0 stale=0 rules={'layer': 4}`，exit0**——`tests/pending_board_power_test.gd:99` 已迁为公开只读快照 `EffectManager.pending_announcements_snapshot()`（文件内 `_pending_announcements` 已彻底消失），主代理按退休 policy 精确删除 `tools/check_layer_deps.py` 中对应许可条目，并直接实跑该套件 **171 checks / failures=[] / exit=0** 作为退休安全证据。剩余 4 条为组合根层依赖（`server_bootstrap.gd:76–79`，均带原文与行号）。
- 本轮真实 `python -B -m unittest tools.tests.test_check_layer_deps -v`：**Ran 20、OK、exit0**（TMPDIR/TEMP/TMP 均指 E 盘）。此前曾为 Ran20、FAILED(failures=4)、exit1——失败是两条基线检验及 outpost 两个 subtest 遭遇同一 pending_board_power STALE，现随许可退休全部解除。另修正该套件一处过时假设：`test_real_baseline_copy_cli_pass_new_and_stale` 原先要求白名单里必须存在一条 private 锚点；private 全部退休后改为对该规则断言"无 findings、无 stale"（未放宽既有断言，layer 分支原样保留）。
- 核对途中内容管理 `receive_management` 已出现生产调用，match模块也新增方法；与委派背景不同，按本轮磁盘读取更新，不照抄“待接线”。最终源读取仍可能被其他写者继续修改；§5列读取指纹和漂移，后续接线后请重新核对，不静默继承本表。

## 2. 本轮直接核对的关键运行原件

下列结果为旧冻结的原件读回，不是本轮重新执行；截图本轮未加载，所以不声称本轮亲验画面。路径末尾 evidence/*.stdout.log、*.stderr.log 的全文读/解析清单在§5。

| 证据简称 | 原件路径 | 直接读回结果 / 不能推出的结论 |
|---|---|---|
| R73 | `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/round73-user-stop-readback.json`；`docs/round73-current-integrated.md` | selected101/executed70/unique70/pass69/strict68/red1/unexecuted31；70套原 stdout/stderr逐份读/解析，观察CHECK4513。声明4666独立保留。gateway_relisten exit1、30 checks/2 failures；bind负向ERROR精确分账。不是全量绿。 |
| 恢复正确性 | R73同根 `evidence/complete-net_server_gateway_restart_test.stdout.log` | exit0、61 checks；原60秒性能门passed=false。只读既有结果，不把正确性改称性能通过，不重跑测速。 |
| R71发布/保存 | `E:/scratch/isolated-b3cc1bfe631149fa94f6a7c789f25491/manifest.json`；`E:/scratch/isolated-ed9fd487c32d490087e239301371f838/manifest.json`；`docs/round71-publish-save-reliability.md` | 原shutdown86执行只有7 checks，在生产worker READY失败；pending36/failure161是各自结果，不代86/实际对局尾保存整链。manifest与报告已读，原40份父子日志本轮未重读。 |
| R71诊断三角色 | `E:/FateCandidates/round71-build-only-4f7fb4194e19acdf-91306a82/manifest.json`；`docs/round71-three-role-build-candidate.md` | 已真实产出三角色，不再写“只有两角色”；仅build-only旧诊断产物，不是当前最终真人包。EXE/PCK/DLL本轮未重新读包字节。 |
| R71信令单阶段 | `E:/FateCandidates/round71-signal-runtime-fdffbf9b47dbf9ff-91306a82/formal-runtime.json` | signaling-ready局部；不替client/server/status/negative及正式双client。 |
| R74旧client启动 | `E:/Caches/Hermes/cache/scratch/g05-client-startup-round74-adjacent-once-sa53/runtime.json`；`docs/round74-old-client-adjacent-startup.md` | EXE正常exit0，但原runner/API判据FAIL(exit1)、old_artifact/nonfinal；不替当前准入。 |

## 3. A01–G05 当前逐项矩阵

“当前源码”证据仅指本轮完整字节读取及符号/引用静态核对；没有隐含 Godot 解析或行为通过。R73按§2原冻结归属，旧E58/E60等仍保留历史附录原路径/摘要。

### A 批

| 能力名 | 状态 | 证据路径或命令 | 缺什么才算完成 |
|---|---|---|---|
| A01 初始脚本漂移基线 | 已完成并验证 | `reports/refactoring/baseline.txt`（原始基线已读）；`tools/check_inventory_drift.py`；仅本行的历史产物或静态要求完成，不能推出整链/全量PASS；历史细节见历史附录同ID | 本行限定产物/静态任务无新增缺口；无基线补造；以后迁移按本矩阵hash定位，不更新旧inventory抹漂移。 |
| A02 初始 headless 红绿基线 | 已完成并验证 | `reports/refactoring/baseline-headless.json`（初始24套基线原件已读，不是当前选集）；仅本行的历史产物或静态要求完成，不能推出整链/全量PASS；历史细节见历史附录同ID | 本行限定产物/静态任务无新增缺口；原基线任务已做；最终候选改用当前选集，不再重做初始基线。 |
| A03 初始六窗口基线 | 已完成并验证 | `reports/refactoring/window-logs/first-run/baseline-window.json`（初始六套原件已读，不是当前GUI绿）；仅本行的历史产物或静态要求完成，不能推出整链/全量PASS；历史细节见历史附录同ID | 本行限定产物/静态任务无新增缺口；保留初始基线；当前窗口按D15/D20b/C10d验收，不借无源码hash历史GUI。 |
| A04 跨层依赖棘轮 | 已完成并验证 | `python -B tools/check_layer_deps.py` → **PASS `findings=4 allowlist=4 new=0 stale=0 rules={'layer': 4}`，exit0**；`python -B -m unittest tools.tests.test_check_layer_deps -v` → **Ran 20、OK、exit0**（TMPDIR/TEMP/TMP 均指 E 盘）；历史细节见历史附录同ID | 无待办。组合根 `server_bootstrap.gd:76–79` 四条场景路径引用**经用户裁定（A4"保留"）作为正当声明保留**，为接受稳态，不再作为待清项；不得为提高数字强删合法路由。 |
| A05 内核私有访问棘轮 | 已完成并验证 | 最后一条私有读取许可已按 policy **精确退休**（`tools/check_layer_deps.py` 原 184 行 `tests/pending_board_power_test.gd:99 → EffectManager._pending_announcements` 删除）；退休前提已满足：公开等价能力 `EffectManager.pending_announcements_snapshot()`（`effect_manager.gd:108–109`，深拷贝、不 flush、不消费）已接线且被该套件本身验证；`python -B … --scene res://tests/pending_board_power_test.tscn` → **171 checks / failures=[] / exit=0**；gate 与自身单元均绿（见 A04 行）；T11 | 无待办。生产私有读取为 0；其余测试/诊断许可**按用户口径不强删**（不为凑数字）。 |
| A06 卡面/BUFF/费用/日志文字 golden | 已接线未全链验 | `tests/refactor_text_golden_test.gd` / `run`（定义已定位）；历史细节见历史附录同ID | 同冻结compare原text golden，保存原stdout/RESULT；不重新capture吞差异。；本轮未跑compare，R73未选，不借历史摘要记当前通过。 |
| A07 位置规则自然终局 golden | 已接线未全链验 | `tests/refactor_area_golden_test.gd` / `run`（定义已定位）；历史细节见历史附录同ID | 同冻结compare到自然终局；隔离预期突变须红→恢复绿，不改共享生产。；本轮未跑compare，R73未选，不借历史摘要记当前通过。 |
| A08 展示模型构建成本历史探针 | 已完成并验证 | `reports/refactoring/build-cost.json`；`tests/refactor_build_cost_probe.gd`（历史采样任务，不是新测速）；仅本行的历史产物或静态要求完成，不能推出整链/全量PASS；历史细节见历史附录同ID | 本行限定产物/静态任务无新增缺口；不重复无收益微优化；C09验证同刷新build一次/显式invalidate及视角隔离。 |

### B 批

| 能力名 | 状态 | 证据路径或命令 | 缺什么才算完成 |
|---|---|---|---|
| B01 独立位置规则模块 | 已接线未全链验 | `scripts/system/area_action_rules.gd` / `block_reason`（定义已定位）；历史细节见历史附录同ID | 解析AREA并compare A07，保持MoveLocation原operation不改。 |
| B02 旧 UI 位置查询转发 | 已接线未全链验 | `scripts/game_scene/tactical_board_ui.gd` / `area_action_block_reason_for`（定义已定位）；`scripts/game_scene/tactical_board_ui.gd` / `_estimate_move_cost`（定义已定位）；历史细节见历史附录同ID | A07 + area_lock_window + misc_rules_fix；确认旧签名调用不变。 |
| B03 MatchDriver 位置查询接线 | 已接线未全链验 | `scripts/match/match_driver.gd:1`；历史细节见历史附录同ID | match_driver_headless + A07，绑定driver/AREA/source hash。 |
| B04 权威端位置规则接线 | 已接线未全链验 | `scripts/net/authority/match_authority.gd` / `pending_for`（定义已定位）；`scripts/net/authority/match_authority.gd` / `_submit`（定义已定位）；历史细节见历史附录同ID | 当前同冻结重跑这三专项，确认位置入口仍经dispatcher。 |
| B05 正式 board 位置拒绝接线 | 已接线未全链验 | `scripts/game_scene/battle_board_v2.gd:1`；历史细节见历史附录同ID | 真实area_lock_window -- window，读可见拒绝文案。 |
| B06 正式 board 移动估费/落点 | 已接线未全链验 | `scripts/system/area_action_rules.gd` / `first_effect_location_target`（定义已定位）；历史细节见历史附录同ID | board + bellerophon_edges，同冻结验证常规/效果移动。 |
| B07 调试移动魔力预检 | 已接线未全链验 | `scripts/debug/debug_adapters/debug_map_adapter.gd:1`；历史细节见历史附录同ID | debug_console零魔力移动明确拒绝，并检查扣费前拒绝；需要原RED→GREEN原件而非只说新增测试。 |
| B08 卡面文字模块 | 已接线未全链验 | `scripts/ui/text/card_desc_text.gd:1`；历史细节见历史附录同ID | 解析 + A06 compare；测试本人/公开卡授权先于格式化。 |
| B09 费用文字模块 | 已接线未全链验 | `scripts/ui/text/cost_text.gd:1`；历史细节见历史附录同ID | 解析 + A06费用空串/前导换行compare。 |
| B10 日志文字模块 | 已接线未全链验 | `scripts/ui/text/game_log_text.gd` / `line`（定义已定位）；历史细节见历史附录同ID | A06 compare全部日志及胜者文案差异审阅，不重新capture。 |
| B11 选择确认文字模块 | 已接线未全链验 | `scripts/ui/text/choice_text.gd:1`; `scripts/game_scene/native_choice_renderer.gd:1`；历史细节见历史附录同ID | native_choices_window -- window，真实card-confirm文本/点击。 |
| B12 旧 UI 文字转发 | 已接线未全链验 | `scripts/game_scene/tactical_board_ui.gd` / `_build_card_desc`（定义已定位）；`scripts/game_scene/tactical_board_ui.gd` / `_resolve_effect_cost_items`（定义已定位）；`scripts/game_scene/tactical_board_ui.gd` / `_format_game_log_line`（定义已定位）；历史细节见历史附录同ID | A06 + reported_ui + number_display，保留小数/整数显示合同。 |
| B13 ViewBuilder 授权后文字投影 | 已接线未全链验 | `scripts/match/view_builder.gd` / `card_view`（定义已定位）；`scripts/match/view_builder.gd` / `public_log`（定义已定位）；历史细节见历史附录同ID | 当前match_view/privacy及A06，确保隐私授权不下放文本模块。 |
| B14 权威卡牌确认文字 | 已接线未全链验 | `scripts/match/match_seat_query.gd` / `_card_choice_confirm_text`（定义已定位）；历史细节见历史附录同ID | net_pending，核对真实秘密选择确认文本。 |
| B15 待答费用文字 | 已接线未全链验 | `scripts/match/match_seat_query.gd` / `pending`（定义已定位）；历史细节见历史附录同ID | net_pending + native_choices_window -- window。 |
| B16 正式 board 独立文字消费 | 已接线未全链验 | `scripts/game_scene/battle_board_v2.gd:1`；历史细节见历史附录同ID | board + native_choices_window -- window；核对显示不重算隐私数据。 |
| B17 正式 board 删除旧 UI 常量依赖 | 已完成并验证 | `scripts/game_scene/battle_board_v2.gd:1`；仅本行的历史产物或静态要求完成，不能推出整链/全量PASS；历史细节见历史附录同ID | 本行限定产物/静态任务无新增缺口；最终解析board，不借本项宣称统一UI已完成。 |
| B18 只读玩家查找接口 | 已接线未全链验 | `scripts/system/global/game_data_manager.gd` / `find_player_data`（定义已定位）；历史细节见历史附录同ID | player_query_purity，对不存在玩家keys前后相等。 |
| B19 玩家查询纯度反例测试 | 已接线未全链验 | `tests/player_query_purity_test.gd:1`；历史细节见历史附录同ID | 当前公开find/build/name/block_reason四入口纯度专项。 |
| B20 位置规则缺玩家不创建 | 已接线未全链验 | `scripts/system/area_action_rules.gd` / `block_reason`（定义已定位）；历史细节见历史附录同ID | player_query_purity + A07，保留原有效玩家语义。 |
| B21 board 玩家查询不创建 | 已接线未全链验 | `scripts/game_scene/battle_board_v2.gd:1`；历史细节见历史附录同ID | board未知玩家/观战座位纯度。 |
| B22 统一玩家名只读查询 | 已接线未全链验 | `scripts/system/global/effect_manager.gd` / `player_shown_name`（定义已定位）；历史细节见历史附录同ID | player_name + player_query_purity，存在/缺失两方向。 |
| B23 权威/座位/分派玩家查询 | 已接线未全链验 | `scripts/net/authority/match_authority.gd` / `_submit`（定义已定位）；`scripts/match/match_seat_query.gd` / `actions`（定义已定位）；`scripts/match/match_command_dispatcher.gd` / `_dispatch`（定义已定位）；历史细节见历史附录同ID | net_move/net_cards/net_authority_ui_preview_feedback当前同冻结复验。 |
| B24 玩家查询调用点语义分类 | 已接线未全链验 | `tools/classify_player_data_calls.py` / `build_report`（定义已定位）；历史细节见历史附录同ID | 当前调用点逐个语义审阅并产出绑定当前 SHA 的完整分类；unknown 不自动变成只读。旧统计只在历史附录。 |
| B25 原玩家名 golden 与批准差异 | 已完成并验证 | `docs/refactoring-golden/player_names.json`；`tests/player_shown_name_golden_test.gd`（保留旧预期）；仅本行的历史产物或静态要求完成，不能推出整链/全量PASS；历史细节见历史附录同ID | 本行限定产物/静态任务无新增缺口；保留旧golden；B26验证统一口径，不再询问D5。 |
| B26 统一姓名与日志姓名 | 已接线未全链验 | `scripts/system/global/effect_manager.gd` / `player_shown_name`（定义已定位）；`scripts/ui/text/game_log_text.gd` / `line`（定义已定位）；历史细节见历史附录同ID | player_shown_name_golden + A06 + player_name，所有批准差异逐条记录。 |
| B27 终局通知姓名消费 | 已接线未全链验 | `scripts/system/global/game_progress.gd` / `end_game`（定义已定位）；历史细节见历史附录同ID | turn_order/player_name，胜者通知未知ID不创建玩家。 |
| B28 淘汰解析姓名消费 | 已接线未全链验 | `scripts/system/global/climax_resolver.gd:1`；历史细节见历史附录同ID | climax_elimination + purity。 |
| B29 旧 UI 静态姓名转发 | 已接线未全链验 | `scripts/game_scene/tactical_board_ui.gd` / `_player_shown_name_by_id`（定义已定位）；历史细节见历史附录同ID | A06 + player_shown_name_golden。 |
| B30 旧 UI 实例姓名转发 | 已接线未全链验 | `scripts/game_scene/tactical_board_ui.gd` / `_player_shown_name`（定义已定位）；历史细节见历史附录同ID | reported_ui，明确无空格旧文案差异，不用静态grep替代可见文本。 |
| B31 正式 board 投影姓名 | 已接线未全链验 | `scripts/game_scene/battle_board_v2.gd` / `_player_name`（定义已定位）；历史细节见历史附录同ID | board + 顶栏/横幅/战果榜实际窗口名字检查。 |
| B32 删除两个私有姓名兼容壳 | 已完成并验证 | `scripts/system/global/game_progress.gd:1`; `scripts/system/global/climax_resolver.gd:1`；仅本行的历史产物或静态要求完成，不能推出整链/全量PASS；历史细节见历史附录同ID | 本行限定产物/静态任务无新增缺口；B27/B28行为证据另验，不复造兼容壳。 |

### C 批

| 能力名 | 状态 | 证据路径或命令 | 缺什么才算完成 |
|---|---|---|---|
| C01 显式失效/同刷新复用策略 | 已接线未全链验 | `scripts/game_scene/battle_io/local_battle_source.gd` / `invalidate`（定义已定位）；`scripts/game_scene/battle_board_v2.gd` / `refresh_all_ui`（定义已定位）；历史细节见历史附录同ID | 同刷新一次 build、显式 invalidate、视角隔离专项；既有策略采用不等于当前性能通过，不启动测速。 |
| C02 presenter 私有访问四类盘点 | 已接线未全链验 | `tools/list_presenter_private_access.py` / `build`（定义已定位）；历史细节见历史附录同ID | 更新四类分类与当前 board/presenter 指纹，逐调用退休；本轮只核对工具/源码存在，不追认旧数量。 |
| C03 公开选择合法性接口 | 已接线未全链验 | `scripts/system/global/effect_manager.gd` / `is_card_selection_valid`（定义已定位）；`scripts/system/global/effect_manager.gd` / `location_option_origin_allowed`（定义已定位）；历史细节见历史附录同ID | net_pending 当前同冻结复验，保留peer/seq/审计边界。 |
| C04 座位待答查询抽取 | 已接线未全链验 | `scripts/match/match_seat_query.gd` / `pending`（定义已定位）；`scripts/net/authority/match_authority.gd` / `pending_for`（定义已定位）；历史细节见历史附录同ID | net_pending + net_locations 当前同冻结复验，保留peer/seq/审计边界。 |
| C05 座位 actions 查询抽取 | 已接线未全链验 | `scripts/match/match_seat_query.gd` / `actions`（定义已定位）；`scripts/net/authority/match_authority.gd` / `actions_for`（定义已定位）；历史细节见历史附录同ID | net_cards + net_move 当前同冻结复验，保留peer/seq/审计边界。 |
| C06 座位组合 preview 查询抽取 | 已接线未全链验 | `scripts/match/match_seat_query.gd` / `preview`（定义已定位）；`scripts/net/authority/match_authority.gd` / `preview_group`（定义已定位）；历史细节见历史附录同ID | net_authority_ui_preview_feedback 当前同冻结复验，保留peer/seq/审计边界。 |
| C07 本地只读 source | 已接线未全链验 | `scripts/game_scene/battle_io/local_battle_source.gd:1`；历史细节见历史附录同ID | battle_source_adapter + player_query_purity；同刷新build一次、观察者隔离。 |
| C08 网络只读 source | 已接线未全链验 | `scripts/game_scene/battle_io/network_battle_source.gd:1`；历史细节见历史附录同ID | battle_source_adapter，close/reconnect后断旧信号并清视图。 |
| C09 正式 board source 接线 | 已接线未全链验 | `scripts/game_scene/battle_board_v2.gd` / `_ready`（定义已定位）；`scripts/game_scene/battle_board_v2.gd` / `refresh_all_ui`（定义已定位）；历史细节见历史附录同ID | board + net_v2_browsing -- window + build计数/视角专项。 |
| C10 BUFF 统一投影迁移 | 已接线未全链验 | `scripts/game_scene/battle_board_v2.gd` / `_fill_buff_rows`（定义已定位）；`scripts/match/view_builder.gd` / `buff_views`（定义已定位）；历史细节见历史附录同ID | C10a–d合并同冻结验收，特别说明文本与本方/对手隐私。 |
| C10a BUFF 隐私字段投影 | 已接线未全链验 | `scripts/match/view_builder.gd` / `buff_views`（定义已定位）；历史细节见历史附录同ID | match_view_privacy，非本人隐藏与本人内容齐全。 |
| C10b board/presenter 字典 BUFF 消费 | 已接线未全链验 | `scripts/game_scene/battle_board_v2.gd` / `_bind_ops`（定义已定位）；`scripts/game_scene/battle_board_v2.gd` / `_fill_buff_rows`（定义已定位）；`scripts/net/ui/v2_view_presenter.gd` / `refresh`（定义已定位）；历史细节见历史附录同ID | board + shared-presentation，记录两调用输入真实类型。 |
| C10c 删除 BaseBuff 双渲染分支 | 已完成并验证 | `scripts/game_scene/battle_board_v2.gd` / `_fill_buff_rows`（定义已定位）；仅本行的历史产物或静态要求完成，不能推出整链/全量PASS；历史细节见历史附录同ID | 本行限定产物/静态任务无新增缺口；C10d保留真实窗口，不把删分支算整体显示验收。 |
| C10d BUFF 双方窗口/文字验收 | 已接线未全链验 | `tests/battle_board_v2_test.gd:1`; `tests/refactor_text_golden_test.gd:1`；历史细节见历史附录同ID | board+A06；本方与对手BUFF悬浮逐字检查，非headless。 |
| C11 事件弃牌来源共享浏览 | 已接线未全链验 | `scripts/game_scene/battle_board_v2.gd` / `_bind_situation_and_piles`（定义已定位）；历史细节见历史附录同ID | board+net_v2_browsing窗口：分类/标题/开合、隐私/顺序及旧调用消失；只认迁移后hash证据。 |
| C12 令咒/资源统一投影 | 已接线未全链验 | `scripts/game_scene/battle_board_v2.gd` / `_bind_sigils`（定义已定位）；`scripts/game_scene/battle_board_v2.gd` / `_bind_self`（定义已定位）；历史细节见历史附录同ID | board+shared_spell_view+mirror负向，并看资源/自定义令咒图；最终同冻结gate。 |
| C13 顺位节点复用 | 已接线未全链验 | `scripts/game_scene/battle_board_v2.gd` / `_bind_rivals`（定义已定位）；`scripts/game_scene/battle_board_v2.gd` / `_bind_rival_order`（定义已定位）；历史细节见历史附录同ID | 重复刷新instance_id相等且不重播动画；browsing窗口；最终同冻结gate。 |
| C14 阶段/残留共享展示 | 已接线未全链验 | `scripts/game_scene/battle_board_v2.gd` / `_bind_shared_phase_view`（定义已定位）；`scripts/game_scene/battle_board_v2.gd` / `_bind_residue_entries`（定义已定位）；历史细节见历史附录同ID | shared-presentation+net_v2_residue_phase窗口，阶段清理/残留复用；最终同冻结gate。 |
| C15 战区/出牌组共享展示 | 已接线未全链验 | `scripts/game_scene/battle_board_v2.gd` / `_bind_strips`（定义已定位）；`scripts/game_scene/battle_board_v2.gd` / `_bind_groups`（定义已定位）；历史细节见历史附录同ID | net_v2_area窗口，正常process飞牌、扇形展开/收拢中间帧及四组完整可见；最终同冻结gate。 |

### D 批

| 能力名 | 状态 | 证据路径或命令 | 缺什么才算完成 |
|---|---|---|---|
| D01 set_concealed 共用分派 | 已接线未全链验 | `scripts/match/match_command_dispatcher.gd` / `_dispatch`（定义已定位）；`scripts/net/authority/match_authority.gd` / `_submit`（定义已定位）；历史细节见历史附录同ID | 当前dispatcher+net_cards专项；set_concealed参数/座位/拒绝无副作用正反例。 |
| D02 cancel_choice 共用分派 | 已接线未全链验 | `scripts/match/match_command_dispatcher.gd` / `_dispatch`（定义已定位）；`scripts/net/authority/match_authority.gd` / `_submit`（定义已定位）；历史细节见历史附录同ID | 当前dispatcher+net_pending专项；cancel_choice参数/座位/拒绝无副作用正反例。 |
| D03 location_choice 共用分派 | 已接线未全链验 | `scripts/match/match_command_dispatcher.gd` / `_dispatch`（定义已定位）；`scripts/net/authority/match_authority.gd` / `_submit`（定义已定位）；历史细节见历史附录同ID | 当前dispatcher+net_locations专项；location_choice参数/座位/拒绝无副作用正反例。 |
| D04 activate 共用分派 | 已接线未全链验 | `scripts/match/match_command_dispatcher.gd` / `_dispatch`（定义已定位）；`scripts/net/authority/match_authority.gd` / `_submit`（定义已定位）；历史细节见历史附录同ID | 当前dispatcher+net_pending专项；activate参数/座位/拒绝无副作用正反例。 |
| D05 player_choice 共用分派 | 已接线未全链验 | `scripts/match/match_command_dispatcher.gd` / `_dispatch`（定义已定位）；`scripts/net/authority/match_authority.gd` / `_submit`（定义已定位）；历史细节见历史附录同ID | 当前dispatcher+net_pending专项；player_choice参数/座位/拒绝无副作用正反例。 |
| D06 card_choice 共用分派 | 已接线未全链验 | `scripts/match/match_command_dispatcher.gd` / `_dispatch`（定义已定位）；`scripts/net/authority/match_authority.gd` / `_submit`（定义已定位）；历史细节见历史附录同ID | 当前dispatcher+net_pending专项；card_choice参数/座位/拒绝无副作用正反例。 |
| D07 option_choice 共用分派 | 已接线未全链验 | `scripts/match/match_command_dispatcher.gd` / `_dispatch`（定义已定位）；`scripts/net/authority/match_authority.gd` / `_submit`（定义已定位）；历史细节见历史附录同ID | 当前dispatcher+net_pending专项；option_choice参数/座位/拒绝无副作用正反例。 |
| D08 active_choice 共用分派 | 已接线未全链验 | `scripts/match/match_command_dispatcher.gd` / `_dispatch`（定义已定位）；`scripts/net/authority/match_authority.gd` / `_submit`（定义已定位）；历史细节见历史附录同ID | 当前dispatcher+net_pending专项；active_choice参数/座位/拒绝无副作用正反例。 |
| D09 move 共用分派 | 已接线未全链验 | `scripts/match/match_command_dispatcher.gd` / `_dispatch`（定义已定位）；`scripts/net/authority/match_authority.gd` / `_submit`（定义已定位）；历史细节见历史附录同ID | 当前dispatcher+net_move专项；move参数/座位/拒绝无副作用正反例。 |
| D10 play_group 共用分派 | 已接线未全链验 | `scripts/match/match_command_dispatcher.gd` / `_dispatch`（定义已定位）；`scripts/net/authority/match_authority.gd` / `_submit`（定义已定位）；历史细节见历史附录同ID | 当前dispatcher+net_cards专项；play_group参数/座位/拒绝无副作用正反例。 |
| D11 end_action 共用分派 | 已接线未全链验 | `scripts/match/match_command_dispatcher.gd` / `_dispatch`（定义已定位）；`scripts/net/authority/match_authority.gd` / `_submit`（定义已定位）；历史细节见历史附录同ID | 当前dispatcher+net_pending专项；end_action参数/座位/拒绝无副作用正反例。 |
| D12 deploy 共用分派 | 已接线未全链验 | `scripts/match/match_command_dispatcher.gd` / `_dispatch`（定义已定位）；`scripts/net/authority/match_authority.gd` / `_submit`（定义已定位）；历史细节见历史附录同ID | 当前dispatcher+net_locations专项；deploy参数/座位/拒绝无副作用正反例。 |
| D13 本地请求完成适配器 | 已接线未全链验 | `scripts/game_scene/battle_io/local_battle_commands.gd` / `submit`（定义已定位）；`scripts/game_scene/battle_board_v2.gd` / `_run_battle_command`（定义已定位）；历史细节见历史附录同ID | adapter专项；submit前关联、同步回执早于返回、拒绝不扣费。 |
| D14 网络请求完成适配器 | 已接线未全链验 | `scripts/game_scene/battle_io/network_battle_commands.gd` / `submit`（定义已定位）；历史细节见历史附录同ID | protocol+adapter：close/reconnect代际、unknown、不自动重发、同号旧回执不结算新请求。 |
| D15 全交互共同 command 端口 | 已接线未全链验 | `scripts/game_scene/battle_board_v2.gd` / `_submit_battle_command`（定义已定位）；`scripts/game_scene/battle_board_v2.gd` / `_run_battle_command`（定义已定位）；`scripts/net/ui/v2_view_presenter.gd` / `card_input`（定义已定位）；`scripts/net/ui/v2_view_presenter.gd` / `confirm_area`（定义已定位）；历史细节见历史附录同ID | 剩余 presenter/panel 直发 Session 入口统一 command；两模式真实连续输入、拒绝恢复、版本/回执关联和无重复扣费。 |
| D16 当前组合手牌合法提示 | 已接线未全链验 | `scripts/game_scene/battle_board_v2.gd` / `_held_card_playable`（定义已定位）；`scripts/game_scene/battle_board_v2.gd` / `_held_playable_signature`（定义已定位）；`scripts/game_scene/battle_board_v2.gd` / `_manual_effects_of`（定义已定位）；历史细节见历史附录同ID | refactor_held_actions + 当前组候选变化/无合法mode/组上限/旧异步preview失效。 |
| D17 组合费用共享预览 | 已接线未全链验 | `scripts/game_scene/battle_board_v2.gd` / `_bind_mana_cost_preview`（定义已定位）；`scripts/game_scene/battle_board_v2.gd` / `_render_group_cost_preview`（定义已定位）；历史细节见历史附录同ID | refactor_group_projection + source-adapter，选牌/hidden变化/旧预览拒绝；两模式实际费用浮窗。 |
| D18 四类待答共同 renderer/命令 | 已接线未全链验 | `scripts/game_scene/battle_board_v2.gd` / `_show_effect_modal`（定义已定位）；`scripts/game_scene/battle_board_v2.gd` / `_show_player_select_panel`（定义已定位）；历史细节见历史附录同ID | 网络 panel 共同命令接线与四类本地/ENet 正反路径；取消不是 min=0 空集；新版本确认不得洗白旧 seq。 |
| D19 单机自然终局 | 已接线未全链验 | `tests/natural_game_over_test.gd` / `run_local`（定义已定位）；`scripts/game_scene/battle_board_v2.gd` / `_check_game_over`（定义已定位）；历史细节见历史附录同ID | natural_game_over单机：game_end唯一、Board一次、say一次、日志不弹、场景保留。 |
| D19b 联机自然终局 | 已接线未全链验 | `tests/natural_game_over_test.gd` / `run_network`（定义已定位）；历史细节见历史附录同ID | natural_game_over联机真实推进；保留无额外LogBrowser与四条终局断言。 |
| D20 联机终局唯一展示入口 | 已接线未全链验 | `scripts/net/ui/v2_view_presenter.gd` / `show_game_over`（定义已定位）；`scripts/game_scene/battle_board_v2.gd` / `_check_game_over`（定义已定位）；历史细节见历史附录同ID | natural_game_over网络红→绿的当前原件，确认日志只由用户主动打开。 |
| D20b 正式返回大厅/主菜单所有权 | 已接线未全链验 | `scripts/game_scene/battle_board_v2.gd` / `_update_board_return_controls`（定义已定位）；历史细节见历史附录同ID | 正式两模式非headless真实点击：真实accepted+大厅match_reset+同Session移交；主菜单真实close。不得重设_network_session_transferred。 |
| D20c 统一终局姓名/战果排序 | 已接线未全链验 | `scripts/game_scene/battle_board_v2.gd` / `_check_game_over`（定义已定位）；`scripts/game_scene/battle_board_v2.gd` / `_player_name`（定义已定位）；`scripts/game_scene/battle_board_v2.gd` / `_score_sorted_ids`（定义已定位）；`scripts/net/ui/v2_view_presenter.gd` / `show_game_over`（定义已定位）；历史细节见历史附录同ID | natural_game_over双路径及一次展示，源码/测试/场景hash同冻结。 |
| D20d 房主返回大厅真实完成回执 | 已接线未全链验 | `scripts/net/session/lobby_session.gd` / `_receive`（定义已定位）；`scripts/net/authority/match_authority.gd` / `finish_match_to_lobby`（定义已定位）；历史细节见历史附录同ID | 同冻结GUI走房主返回，所有客户match_reset，非房主等待/拒绝，不用大厅快照冒accepted。 |
| D21 board 仅保留批准的模式分支 | 已接线未全链验 | `scripts/game_scene/battle_board_v2.gd:1`；历史细节见历史附录同ID | 逐函数完成展示/输入模式分支迁出，只保留原方案四类；未知 helper 不自动授层许可；最终同冻结窗口验证。 |
| D22 presenter 等待/身份/guard 薄壳 | 已接线未全链验 | `scripts/net/ui/v2_view_presenter.gd` / `refresh`（定义已定位）；`scripts/net/ui/v2_view_presenter.gd` / `_bind_hand`（定义已定位）；`scripts/net/ui/v2_view_presenter.gd` / `card_input`（定义已定位）；`scripts/net/ui/v2_view_presenter.gd` / `area_input`（定义已定位）；`scripts/net/ui/v2_view_presenter.gd` / `confirm_area`（定义已定位）；历史细节见历史附录同ID | 仍有整屏刷新/手牌/输入等非薄壳职责；共同 consumer 接线后逐符号退休，当前源码专项及窗口复验。 |

### E 批

| 能力名 | 状态 | 证据路径或命令 | 缺什么才算完成 |
|---|---|---|---|
| E01 单调通知序号 | 已接线未全链验 | `scripts/system/global/effect_manager.gd` / `push_message`（定义已定位）；`scripts/system/global/effect_manager.gd` / `push_effect_result`（定义已定位）；`scripts/system/global/effect_manager.gd` / `latest_allocated_message_serial`（定义已定位）；历史细节见历史附录同ID | notification_identity专项：pop/return/clear/reset/rollback不会旧ID复用；不篡规则hash。 |
| E02 epoch:serial 通知投影/镜像 | 已接线未全链验 | `scripts/match/view_builder.gd` / `notifications_for`（定义已定位）；`scripts/net/authority/match_authority.gd` / `bind_notification_boundary`（定义已定位）；历史细节见历史附录同ID | notification_projection+privacy，删除前项、同文不同ID、多观察者、跨局不碰撞。 |
| E03 通知按 ID 收件与裁剪 | 已接线未全链验 | `scripts/net/ui/notification_inbox.gd` / `ingest`（定义已定位）；历史细节见历史附录同ID | notification_panel_identity：同文两次、同snapshot不重入、裁剪后重现语义；不能据seen有界称权威队列有界。 |
| E04 重连固定已分配水位 | 已接线未全链验 | `scripts/net/authority/match_authority.gd` / `bind_notification_boundary`（定义已定位）；`scripts/system/global/effect_manager.gd` / `latest_allocated_message_serial`（定义已定位）；`scripts/match/view_builder.gd` / `notifications_for`（定义已定位）；历史细节见历史附录同ID | notification_reconnect_baseline：认证后首view前新发保留、旧消息不补；恢复/新局水位不碰撞。 |
| E05 显式播报确认部署策略 | 已接线未全链验 | `scripts/net/authority/match_authority.gd` / `declare_broadcast_confirmation`（定义已定位）；历史细节见历史附录同ID | broadcast_policy_boundary+真实lobby创建前显式true/false；读worker顶层配置及当前规则屏障。 |
| E05b 规则推进与 UI Node 解耦 | 已接线未全链验 | `scripts/system/global/game_progress.gd` / `_effects_block_progress`（定义已定位）；历史细节见历史附录同ID | battle_broadcast+full_game，headless/AI默认false不阻塞。 |
| E06 检查点/回放播报状态与输送批次 | 已接线未全链验 | **match_replay 专项现已通过**：`tests/match_replay_test.gd` 预算经实测修正后 **CHECK=10、failures=[]、exit=0、ERROR=0、Job0**（600 秒声明依据实测 369.558 秒、复跑 383.427 秒；夹具 SHA `01b339c7aea542d280637b91b7e15a2293262699daeb6d5de14bfe6bffaa65be`；报告 `docs/replay-fixture-budget-correction-20261011.md`）；`scripts/match/rule_state.gd` / `_roots`（定义已定位）；`scripts/match/effect_checkpoint.gd` / `restore`（定义已定位）；`scripts/match/match_replay.gd` / `restore`（定义已定位）；历史细节见历史附录同ID | broadcast_policy_boundary（已见 40/40）+ **真实恢复旧 batch 拒绝**仍缺；不以 E62 恢复失败充通过。170 秒性能门未过，与本行无关。 |
| E07 播报屏障公开投影 | 已接线未全链验 | `scripts/match/view_builder.gd` / `broadcast_view`（定义已定位）；历史细节见历史附录同ID | match_view/privacy及错误字段拒绝，确认私有数据未泄露。 |
| E07b 真人播报批次确认 | 已接线未全链验 | `scripts/match/match_command_dispatcher.gd` / `_dispatch`（定义已定位）；`scripts/system/global/game_progress.gd` / `confirm_battle_broadcast_batch`（定义已定位）；历史细节见历史附录同ID | broadcast网络两真人各自确认解除；旧batch/重放/非资格拒绝不扣费。 |
| E07c AI 按控制器逐个确认 | 已接线未全链验 | `scripts/net/authority/match_authority.gd` / `_step_broadcast_confirmation`（定义已定位）；`scripts/game_scene/battle_io/local_battle_commands.gd` / `tick_broadcast_confirmation`（定义已定位）；历史细节见历史附录同ID | 真实1真人6AI屏障：AI逐个后仍等真人，再真人确认续行。 |
| E07d 房主代断线确认授权/审计 | 已接线未全链验 | `scripts/net/session/lobby_session.gd` / `_confirm_absent_broadcast`（定义已定位）；`scripts/net/authority/match_authority.gd` / `confirm_absent_broadcast`（定义已定位）；历史细节见历史附录同ID | 真实断线仍等待；房主代确认审计事实，非房主/已复连/旧候选拒绝。 |
| E07e 正式 UI 播报确认整链 | 已接线未全链验 | `scripts/game_scene/battle_board_v2.gd` / `_broadcast_absent_declaration`（定义已定位）；`scripts/game_scene/battle_board_v2.gd` / `_update_battle_broadcast`（定义已定位）；`scripts/game_scene/battle_board_v2.gd` / `_submit_battle_command`（定义已定位）；历史细节见历史附录同ID | 正式lobby→独立worker显式true→实际真人/代断线点击→batch解除→规则续行；单机/联机各非headless。 |
| E08 内容环境安装/还原 | 已接线未全链验 | `scripts/system/global/content_environment.gd` / `install`（定义已定位）；`scripts/system/global/content_environment.gd` / `restore`（定义已定位）；历史细节见历史附录同ID | 最终同源ContentEnvironment正常/中途失败/嵌套token值和身份还原专项。 |
| E09 大厅内容准备环境消费 | 已接线未全链验 | `scripts/net/session/lobby_session.gd` / `_prepare_rule_data`（定义已定位）；历史细节见历史附录同ID | lobby_content_environment_restore；失败后还原（room worker进程级安装不要求restore），实际恢复终局另看F16阻断。 |
| E10 大厅规则采用环境消费 | 已接线未全链验 | `scripts/net/session/lobby_session.gd` / `_restore_room_rules`（定义已定位）；历史细节见历史附录同ID | lobby_content_environment_restore；失败后还原（room worker进程级安装不要求restore），实际恢复终局另看F16阻断。 |
| E11 本地恢复/失败关闭环境消费 | 已接线未全链验 | `scripts/net/session/lobby_session.gd` / `restore_local_match`（定义已定位）；`scripts/net/session/lobby_session.gd` / `_fail_closed_restore`（定义已定位）；历史细节见历史附录同ID | lobby_content_environment_restore + restart；失败后还原（room worker进程级安装不要求restore），实际恢复终局另看F16阻断。 |
| E12 权威存档恢复环境消费 | 已接线未全链验 | `scripts/net/authority/match_authority.gd` / `restore_archive`（定义已定位）；历史细节见历史附录同ID | net_server_gateway_restart；失败后还原（room worker进程级安装不要求restore），实际恢复终局另看F16阻断。 |
| E13 两个 worker 环境消费 | 已接线未全链验 | `scripts/net/server/server_room_worker.gd` / `_load_process_content`（定义已定位）；`scripts/net/validation/room_data_validation_worker.gd` / `_inspect_loaded_content`（定义已定位）；历史细节见历史附录同ID | worker_content_environment + loader_error_boundary；失败后还原（room worker进程级安装不要求restore），实际恢复终局另看F16阻断。 |
| E14 角色启动组合根统一路由 | 已接线未全链验 | `scripts/system/global/load_game.gd` / `_ready`（定义已定位）；历史细节见历史附录同ID | 当前同源client/server实际EXE各启动，worker/validation入口真实执行；不能借旧PKG52。 |
| E15 内容准备显式能力注入及消费者 | 已接线未全链验 | `scripts/net/validation/room_data_preparation.gd` / `_init`（定义已定位）；历史细节见历史附录同ID | preparation_consumer/dependencies同冻结，替换旧准备器断信号/取消任务/别名消费，正常204与缺roster报告。 |

### F 批

| 能力名 | 状态 | 证据路径或命令 | 缺什么才算完成 |
|---|---|---|---|
| F01 公开事务 capture/restore | 已接线未全链验 | `scripts/system/global/effect_manager.gd` / `capture_transaction_state`（定义已定位）；`scripts/system/global/effect_manager.gd` / `restore_transaction_state`（定义已定位）；历史细节见历史附录同ID | match_replay+guard rollback，恢复保留原对象/失败记录同冻结；故障不能被checkpoint回滚吞掉。 |
| F02 公开暂停执行快照 | 已接线未全链验 | `scripts/system/global/effect_manager.gd` / `paused_runs_snapshot`（定义已定位）；`scripts/match/rule_state.gd` / `_roots`（定义已定位）；历史细节见历史附录同ID | kernel_state_boundaries+规则hash/root等价同冻结；故障不能被checkpoint回滚吞掉。 |
| F03 公开审计失败标记 | 已接线未全链验 | `scripts/system/global/effect_manager.gd` / `mark_guard_audit_failed`（定义已定位）；`scripts/match/match_replay.gd` / `_confirm_audit`（定义已定位）；`scripts/net/authority/match_authority.gd` / `confirm_audit`（定义已定位）；历史细节见历史附录同ID | guard audit失败负向+match_replay同冻结；故障不能被checkpoint回滚吞掉。 |
| F04 公开效果 actor/name 与 guard 诊断 | 已接线未全链验 | `scripts/system/global/effect_manager.gd` / `effect_fact_actor_id`（定义已定位）；`scripts/system/global/effect_manager.gd` / `effect_source_name`（定义已定位）；`scripts/net/authority/match_authority.gd` / `guard_diagnostic`（定义已定位）；历史细节见历史附录同ID | net_runtime_guard及guard_diagnostic投影同冻结；故障不能被checkpoint回滚吞掉。 |
| F05 DummyBot 与私有测试消费者退役 | 已完成并验证 | DummyBot/事务消费者已迁；**其唯一待办（pending_board_power 旧私有许可）已按 policy 精确退休**：`python -B tools/check_layer_deps.py` → **PASS `findings=4 allowlist=4 new=0 stale=0`，exit0**（private findings **0**）；`python -B -m unittest tools.tests.test_check_layer_deps -v` → **Ran 20 OK**；`tests/pending_board_power_test` 实跑 **171 checks / failures=[] / exit 0**；历史细节见历史附录同ID | 无待退休项。三条**故障注入窄许可按设计保留**（不强删负向）；DummyBot 三公开方法已迁并保持明确窄许可。 |
| F06 客户端 match 收件器 | 已接线未全链验 | `scripts/net/session/client_match_inbox.gd` / `receive`（定义已定位）；`scripts/net/session/lobby_session.gd` / `_receive`（定义已定位）；历史细节见历史附录同ID | client_match_inbox + net_server_one_round + net_v2，close/reconnect/selection reset不丢事件。 |
| F07 客户端 blob 收件器 | 已接线未全链验 | `scripts/net/content/blob_receiver.gd` / `receive_client`（定义已定位）；`scripts/net/session/lobby_session.gd` / `_receive`（定义已定位）；历史细节见历史附录同ID | net_blob/authorization/send/concurrent；实际坏chunk、重复、取消不放宽预算。 |
| F08 客户端身份收件器 | 已接线未全链验 | `scripts/net/identity/client_identity_inbox.gd` / `receive`（定义已定位）；`scripts/net/session/lobby_session.gd` / `_receive_client_identity`（定义已定位）；历史细节见历史附录同ID | 真实认证/复连/继承负向全套；重连水位与request代际联验，E62失败保持阻断。 |
| F09 主机请求职责收件器迁移 | 已接线未全链验 | `scripts/net/session/lobby_session.gd` / `_receive`（定义已定位）；T01–T10逐请求现状；`docs/round71-host-match-inbox.md`；历史细节见历史附录同ID | 新请求模块与生产接线分别见 T01–T10；start 及 match 三类逐个消费并专项验证，身份/内容发布/恢复整链仍须同冻结。旧16-kind清单已过时。 |
| F10 服务端房间生命周期只读表 | 已完成并验证 | `reports/refactoring/server-room-lifecycle.md`（直接读表；只授文档任务）；仅本行的历史产物或静态要求完成，不能推出整链/全量PASS；历史细节见历史附录同ID | 本行限定产物/静态任务无新增缺口；后续使用当前MAN符号重新定位，不拿旧状态表行号作当前运行证明。 |
| F11 运行资源配额与批准根 | 已接线未全链验 | `scripts/net/server/server_room_manager.gd` / `runtime_admission_error`（定义已定位）；`scripts/net/server/server_room_manager.gd` / `_active_runtime_count`（定义已定位）；`scripts/net/server/server_room_manager.gd` / `recover_room`（定义已定位）；`scripts/net/server/server_room_manager.gd` / `_approved_root`（定义已定位）；历史细节见历史附录同ID | runtime_admission创建/休眠/恢复/UNKNOWN+配置变更负向；完整恢复仍F16红。 |
| F12 保存/退出/释放/关停闭包 | 阻断 | `scripts/net/server/server_room_manager.gd` / `release_process_for_binding`（定义已定位）；§2 R73/R71直接原件，旧阻断原件完整保留历史附录；历史细节见历史附录同ID | R73 shutdown86未跑；R71 shutdown只有7检查即在 worker READY失败，未到保存。先定位 READY，再同源真实保存→退出→释放→gateway正常stop；不强杀补绿。 |
| F13 worker startup 与运行监督 | 已接线未全链验 | `scripts/net/server/server_room_manager.gd` / `poll`（定义已定位）；`scripts/net/server/server_room_manager.gd` / `startup_status`（定义已定位）；历史细节见历史附录同ID | 能力丢失/恢复/实例替换/关闭监督组合真worker，bound instance复核；UNKNOWN不强杀。 |
| F14 心跳失败与安全 close | 已接线未全链验 | `scripts/net/server/server_room_manager.gd` / `_poll_heartbeat`（定义已定位）；历史细节见历史附录同ID | heartbeat_runtime_integration：写失败→成功、持续故障、保存未决；原engine不换、不自设新超时。 |
| F15 可选本机自动清理生产 proof | 阻断 | `scripts/net/server/temporary_cleanup_ledger.gd` / `_cleanup`（定义已定位）；`scripts/net/server/server_console_channel.gd` / `poll_cleanup_schedule`（定义已定位）；历史细节见历史附录同ID | 本机完整实例登记、跨进程排他、ledger意图/恢复事务、正式DLL及同HANDLE删除读回全部证明。新人测包可明确未启用，不自改用户完整重构范围。 |
| F16 恢复→自然终局→尾保存整链 | 阻断 | `scripts/net/server/server_room_manager.gd` / `create_room`（定义已定位）；`scripts/net/server/server_room_manager.gd` / `recover_room`（定义已定位）；§2 R73/R71直接原件，旧阻断原件完整保留历史附录；历史细节见历史附录同ID | R73 restart正确性61检查通过是该冻结的局部证据，不能覆盖恢复/终局/尾save及关停所有出口。补同源恢复→自然终局→尾保存/日志hash→安全关停；保留历史first-cancel未知因果。不跑新的性能测试。 |

### G 批

| 能力名 | 状态 | 证据路径或命令 | 缺什么才算完成 |
|---|---|---|---|
| G01 最终三角色 PCK/开发资源审计 | 已接线未全链验 | `tools/release/package_audit.py` / `pck_index`（定义已定位）；`tools/release/package_audit.py` / `audit`（定义已定位）；§2 R73/R71直接原件，旧阻断原件完整保留历史附录；历史细节见历史附录同ID | 已有 R71 build-only 三角色诊断产物；当前最终三角色重新制作并读实际PCK/project.binary/EXE/DLL，证明无开发helper。旧包静态绿不覆盖后续源。 |
| G02 发行冻结剔开发插件/autoload | 已接线未全链验 | `tools/release/freeze_prepare.py` / `transform_project`（定义已定位）；`tools/release/freeze_prepare.py` / `transform`（定义已定位）；历史细节见历史附录同ID | 最终角色冻结转换与实际包读取一致；不把开发工程 export_presets 未改说成正式输出已验。 |
| G03 显式输出/preset 外置数据复制 | 已接线未全链验 | `tools/copy_data_after_export.py` / `resolve_output_dir`（定义已定位）；历史细节见历史附录同ID | 隔离新E输出验证显式preset/输出成功、缺/双参数/未知preset拒绝与数据hash；无默认first preset。 |
| G04 同源三角色构建/运行编排 | 已接线未全链验 | `tools/release/release_prepare.py:1`; `tools/release/round56_three_role_freeze.py:1`；§2 R73/R71直接原件，旧阻断原件完整保留历史附录；历史细节见历史附录同ID | R71 build-only 已真构建，signal单阶段通过；当前 client/server/status/negative及正式客户端认证开局仍缺，禁止把编排单元/旧包startup当整链。 |
| G05 当前最终三角色真人测试包 | 阻断 | `tools/release/round56_three_role_freeze.py` / `main`（定义已定位）；`tools/release/runtime_audit.py` / `run_role`（定义已定位）；§2 R73/R71直接原件，旧阻断原件完整保留历史附录；历史细节见历史附录同ID | 当前源码冻结及获准制作，三角色实际导出；两正式client认证/内容/开局/对局保存关停与signal正负、用户真人/多机实测。R71旧诊断包不含之后接线。 |

## 4. 新接线与尾项（拆分模块/生产/验收层）

| 能力名 | 状态 | 证据路径或命令 | 缺什么才算完成 |
|---|---|---|---|
| T01 join两字段形状门生产接线 | 已接线未全链验 | `scripts/net/session/lobby_session.gd`→`host_identity_request_codec.validate`；`newtests/join_shape_session_wiring_evidence/join-green-verified.json`和原日志已读：42 checks、exit0；`newtests/join_shape_session_wiring_handoff.md` | 当条接线专项原冻结绿；当前变化后最终包真实身份/内容/发布整链；不把夹具传输当多机RSA。 |
| T02 choose_master生产接线 | 已接线未全链验 | 当前Session调用`host_room_inbox.receive_choice`已读；模块原件`E:/scratch/pw-8ba2bf92/evidence/final-verified.json`75 checks/exit0与日志已读；`newtests/host_room_choice_request_handoff.md`是早期模块报告 | 75项只证明模块，生产线已存在但不能借模块报告宣Session wire全链绿；直接Session request认证/seq/发布专项与最终窗口。 |
| T03 preview_group生产接线 | 已接线未全链验 | 当前Session→`host_match_request_inbox.receive_preview`；`newtests/round74_host_preview_handoff.md`已读 | 本轮未读到可绑定当前Session字节的完整新接线原日志；保留形状/权威拒绝/seq与结果投递，直接接线验收和正式UI。 |
| T04 密码事务生产接线 | 已接线未全链验 | 当前Session→`host_room_password_request.receive`；`E:/scratch/pw-9051221c/evidence/final-green-verified.json`及日志：48 checks/exit0；`newtests/f09_room_password_session_handoff.md` | 当条原冻结专项绿，不代表当前不同Session整体冻结通过；最终真实认证、保存失败还原及远端发布链。 |
| T05 identity_ack生产接线 | 已接线未全链验 | 当前Session→`resume_ack_transaction.acknowledge`；`E:/scratch/pw-5ed75bc6/evidence/identity-ack-green-verified.json`及日志：54 checks/exit0；`newtests/identity_ack_session_wiring_handoff.md` | 原冻结窄接线绿；ENet、多机、实际身份文件、恢复全链尚缺。本轮不读/输出真实凭据。 |
| T06 start请求模块/接线 | 已接线未全链验 | `scripts/net/session/host_room_inbox.gd:receive_start`与Session当前start分支已读；`E:/scratch/pw-e392b13a/evidence/green-verified.json`及日志24 checks/exit0；`newtests/host_room_start_request_handoff.md` | 模块专项24绿；已见生产调用但未读新wire原件。认证/seq/阶段/错误及发布行为接线专项，随后最终正式入口。 |
| T07 begin_match 请求闭包迁出 | 已接线未全链验 | **已接生产**：`scripts/net/session/lobby_session.gd:1038` 调用 `_host_match_request_inbox.receive_begin_match(args, begin)`；合约/接线专项 **16/16、exit0、ERROR0、Job0**；反向替换后与改前 bytes 完全相同（除该处外未动）；生产路径实证含正式选人后开局成功；Session SHA `e07db399d36ac77d8f2458644b1fb75901882a5d39f89d7d6f8770ad16d5c5f3` | 未验：自然终局后的收尾路径、独立 worker、跨机、GUI、全量回归。 |
| T08 match_finished_lobby 请求闭包迁出 | 已接线未全链验 | **已接生产**：`lobby_session.gd:1093` 调用 `_host_match_request_inbox.receive_match_finished_lobby(args, finish)`；合约 **15/15**、接线专项 **24/24**，均 exit0、ERROR0、Job0；反向替换 bytes 相同；生产实证：`finish` 原样回传真实权威"对局尚未结束"；Session SHA `e07db399…` | 未验：**自然终局后的 finish 成功收尾**、独立 worker、跨机、GUI、全量回归。 |
| T09 broadcast_confirm_absent 请求闭包迁出 | 已接线未全链验 | **已接生产**：`lobby_session.gd:1073` 的 `broadcast_confirm_absent` 分支走 `_confirm_absent_broadcast`(`:2212`)，内部 `.bind` 到 checked 版本(`:2214`)；合约 **38/38**、接线专项 **29/29**，均 exit0、ERROR0、Job0；生产实证：**真实 RSA/ENet 断线后房主确认离线真人并读回审计**；外层无效形状仍走原拒绝分支；Session SHA `e07db399…` | 未验：独立 worker、跨机、GUI、全量回归；三入口共用的写者已释放，后续接线可正常排。 |
| T10 server_data四类内容管理闭包 | 已接线未全链验 | 当前Session 已调用`host_content_inbox.receive_management`；模块接口与`docs/round74-small-integration-queue.md`已读 | 队列早期模块61只是二手摘要，本轮未读其原运行回执；新增wire尚缺已读直接专项。认证/dedicated/owner/phase/连接门及原消息/失败不变，真实批准/发布链。 |
| T11 pending_board_power完整公告快照/许可退休 | **完成** | 公开只读快照 `EffectManager.pending_announcements_snapshot()`（`effect_manager.gd:108–109`：`return _pending_announcements.duplicate(true)`，**深拷贝、不 flush、不消费、无副作用**，契约注释见 `:107`；内部 flush 消费者是另一处 `:2690–2694`）已在该测试接线，文件内 `_pending_announcements` 已消失（grep 空）→ **等价性由主代理直接读源码确认**；许可条目 `tools/check_layer_deps.py`（原 184 行）已按 policy 精确删除；gate 现 **PASS findings=4 allowlist=4 new=0 stale=0 exit0**；该套件直接实跑 **171 checks / failures=[] / exit=0**（`D:/Godot4/…console.exe --headless --fixed-fps 60 --path . --scene res://tests/pending_board_power_test.tscn`，APPDATA/LOCALAPPDATA/TMPDIR 均指 E 盘）。 | 若日后该测试再引入私有读，gate 会以 NEW 报出，需重新走"先接公开等价能力再申请许可"。 |
| T12 action_completion公开原因与生产消费 | 已接线未全链验 | `scripts/system/global/game_progress.gd:action_completion_block_reason`、can_end/end消费及`newtests/action_completion_public_contract_test.gd`已读；gate不再见旧私有锚点 | 本轮没有读该公开原因专项原report/stdout/stderr；缺实际执行回执、原长局/正式交互层验收，不借源码当运行PASS。 |
| T13 queue_time_point_batch公开入队/生产waiting消费 | 已接线未全链验 | `effect_manager.gd`公开方法/调用已读；`E:/Caches/Hermes/cache/scratch/f05-public-queue/proof.json`与其`root-v2-time-point-c0dca108037c447d860d16550e4c092f/report.json`已读；原正/变异/恢复115及waiting14独立保留 | 公共入口与生产消费存在；本轮未逐份重读该report全部stdout/stderr、不代新全量；最终同源事务/等待和发布行为。 |
| T14 横幅/浏览器层级 | 已接线未全链验 | board当前80/85声明已读；`E:/scratch/round75-banner-layer-green/isolated-3c728ddd530e4aed907f0e63e3d56515/manifest.json`及日志hash读回：headless7/window95、exit0；`newtests/round75_banner_browser_layer_handoff.md` | 原冻结窗口专项绿；本轮未亲看9张截图，之后board小数修复已改变整文件hash；最终整合窗口/导包不能继承旧freeze全绿。 |
| T15 本地最高威力保留小数 | 已接线未全链验 | board `BaseNumber.display_text`真实caller已读；`E:/scratch/local-battle-power-display-green/isolated-e99ec50251254d4cbbadf00ef6819751/manifest.json`及日志hash：45/exit0；`newtests/local_battle_power_display_handoff.md` | headless真实文本专项绿，不是像素/窗口；旧round74小数截断golden只留历史，不能回套；不顺带改变无赢家文案，最终窗口/包实验。 |
| T16 网络战斗结果文字共享函数/caller | 已接线未全链验 | `shared_view_sections.gd:public_battle_result_lines`→presenter.open_log；`E:/scratch/round74-public-battle-text-green-final/isolated-9b9d249cd6a04fb08802724c1cddde79/manifest.json`及日志hash：19/exit0、comparison.matched；handoff已读 | 仅网络formatter与授权snapshot消费等价；单机无赢家文案未统一；无新GUI/ENet/worker整链验，最终正式入口。 |
| T17 除外区共享浏览/生产按钮 | 已接线未全链验 | board共享BtnOutOfGame与presenter退休已读；`E:/scratch/round74-out-of-game-targeted/isolated-6abdb4949a1344738b8ad5600e69836b/manifest.json`及日志hash：headless93/window78、exit0；handoff已读 | 该冻结本地/回环输入专项绿，非多机/worker；本轮4张截图未加载；最终整合双方隐私/开关/牌背窗口和导包。 |
| T18 战果榜网络窗口输入门 | 阻断 | `docs/round74-small-integration-queue.md`与`newtests/round74_scoreboard_handoff.md`已读；`E:/scratch/round75-scoreboard-gui-corrected/isolated-71f5af2cc8f44a4bb8f7b7d4410f6123/round75_handoff.md`仅保留引用、本轮未读 | 原夹具只替board source，presenter网络Session空而disabled；需按生产生命周期建立前置，唯一GUI执行者重跑原输入序列并原生读画面。没有读网络门最终绿，不冒本地43通过为双模式通过。 |
| T19 全量回归交付 | 阻断 | R73原readback与70套日志；未执行31项精确清单见下 | 先遵用户顺序制作/真人测试；等用户明确通知后同源全量并对账selected/executed/unique/pass/strict/red/not_run；不得自动续跑或把专项拼全量。 |
| T20 最终包与真人/多机实测 | 阻断 | R71build-onlymanifest、信令formal-runtime及R74旧clientAPI均已读；§2/G05 | 当前冻结正式三角色重新导出并逐角色源/PCK/DLL绑定，两个正式client认证/内容/开局/对局/保存关停；真人用户/多机跨网结果。旧诊断包及headless正常退出不代真人实测。 |

### R73的31项未执行（本轮原readback核对，不是31项失败）

- `round47_host_lifecycle_test`
- `round47_host_lifecycle_board_test`
- `round47_presenter_power_test`
- `server_data_status_inbox_contract_test`
- `server_data_status_inbox_approval_test`
- `deployment_approved_root_test`
- `server_simulation_default_budget_test`
- `validation_countdown_contract_test`
- `round47_public_test_observer_test`
- `command_spell_test`
- `ask_player_option_test`
- `requirement_null_test`
- `session_restart_test`
- `debug_console_pause_test`
- `round47_worker_launch_route_test`
- `round47_worker_launch_lifecycle_test`
- `round50_validation_launch_route_test`
- `net_server_cli_test`
- `round50_finished_lobby_receipt_test`
- `net_server_cli_p2p_test`
- `net_server_identity_cli_test`
- `net_server_cfg_test`
- `net_server_relay_cfg_test`
- `validation_pipeline_performance_test`
- `validation_stage_timing_test`
- `server_shutdown_close_handoff_test`
- `server_shutdown_close_handoff_pending_test`
- `net_server_shutdown_failure_test`
- `loader_error_boundary_test`
- `round70_declared_card_backs_test`
- `view_builder_non_card_objects_test`

另2项GUI、2项native standalone、supplementary GUI及独立loader-negative未被70套headless代偿，参`docs/round73-current-integrated.md`。

## 5. 实际阅读清单与未读边界

- 本轮程序阅读全文字节/解析的诊断日志：**204份**。其中R73 formal70套对应140份stdout/stderr；该根其余被读取的顶层日志另列，prerequisite/harness不充入70。四个新UI/text专项已读取的28份顶层日志SHA与各manifest artifacts逐项相符，mismatch=0。没有重读全部worker日志，旧报告对子日志的检查只授其报告原范围。
- 表列“源码读取”＝完整字节读、SHA及符号/引用定位；重点新接线/完成缺口由正文人工审阅，**不是逐行人工行为审计**。表列“manifest/report”＝JSON/文字原件直接读，不自动表示其所声明的每个文件均已再读。
- 本轮**未读/未验**：所有截图实际像素；旧E58的1270份归档本体与E60全日志集合；N59完整native事件日志；PKG52/R71实际EXE/PCK/DLL包字节；R71保存40份父子日志/control回执原文；新match三类最终GREEN与新content接线最终原件；action_completion实际运行原件；T18 corrected GUI报告；所有真实用户配置/密钥/票据/存档/records内容（不在授权范围）。旧证据引用全部保留，不用本轮manifest阅读冒称读完这些。
- 模板文字`tests/<简称>_test.gd/.tscn`不是文件，不计missing实现；其余未读原件如确实不存在在下表标missing，不补造。
- 本轮起始源码记录到最终重点读回发现变动：`scripts/net/session/lobby_session.gd`。该表只描述两个读取时刻，不假装全仓冻结。

### 当前源码/报告/manifest逐文件读回（SHA绑定读取时刻）

| 实际读取路径 | 阅读类型 | SHA256 / 说明 |
|---|---|---|
| `E:/Caches/Hermes/cache/scratch/f05-public-queue/proof.json` | manifest | `bcdd9588d1189a489a0dbd0cbaf5ea1591263aab60079ad03c740c6f23e16920` |
| `E:/Caches/Hermes/cache/scratch/g05-client-startup-round74-adjacent-once-sa53/runtime.json` | manifest | `8250d8d75077af3fb9ab5e14a2126fe03175307584e5b0e8c538ed6d8a6e16c6` |
| `E:/Caches/Hermes/cache/scratch/root-v2-time-point-c0dca108037c447d860d16550e4c092f/report.json` | manifest | `454dfaf522e9146855d1cf8f2f7e834d3393bcd7a8a5dc12fe4100950b0dd255` |
| `E:/Caches/Hermes/cache/scratch/round54-packaged-protocol-first-worker-sa3/actualruntime.json` | manifest | `145bf48d45450c5269a1a01ec99beed0063d16cbc408a713f5dfb6d79f81646f` |
| `E:/FateCandidates/round52-current-roles-20261010-sa1/manifest.json` | manifest | `5a6f9013bbb09a29798a12b999ca1428222f0e3c061f1caf7fd005c0b72230f0` |
| `E:/FateCandidates/round71-build-only-4f7fb4194e19acdf-91306a82/manifest.json` | manifest | `0ed4780f6c7291ee44dd8af1183de83bebc9d4b7b0ac14708b25fc9d62b45bb9` |
| `E:/FateCandidates/round71-signal-runtime-fdffbf9b47dbf9ff-91306a82/formal-runtime.json` | manifest | `67671db7d2d4ec04dd78665caa290a9f777564e217a4dc41f08657268ee06fd7` |
| `E:/FateDiagnostics/round59-native-runtime-20261010-3/functional.json` | manifest | `0a81a3398903b33f1e81ec068c81e0463852b73415a0ce5c8c126a4daf6e7588` |
| `E:/FateDiagnostics/round59-native-runtime-20261010-3/metadata.json` | manifest | `ca2a0f0b59c1dc864fa07780a0dc0d1d2c51fbce07d9be579fcf88842410b9ae` |
| `E:/FateDiagnostics/round59-native-runtime-20261010-3/result.json` | manifest | `39cb2647ddf037e491b67354ce8bc869f4469a5429ea8c6fd3461e953c4ad814` |
| `E:/HermesScratch/round55-gui-first-divergence/final-ef684b20cc224fc3a049d90caac1209e/manifest.json` | manifest | `8a808a1097a1aab665a3632d2298e2a3216388a9e4d64f4b309c59ef1626b266` |
| `assets/scenes/game_scene/battle_board_v2.tscn` | historical-reference-current-bytes | `39a681e1f00578e2a2d7278b241262a72a78afe99937d99553c6ebf615c0fb6d` |
| `docs/refactoring-execution.md` | report | `14617f79896c636e2e028f32549698cbbc73cedbb1bb71a2c9f0578c4834822f` |
| `docs/refactoring-golden/player_names.json` | historical-baseline-original | `f575d17769baa996d6d9e60f75a58f144404325bbee17053ef26025dc79ca0ec` |
| `docs/refactoring-open-questions.md` | report | `9ec29b687a13a50a5c774aba01002c1be7ef1c184a7fe6877d23d90450314f5a` |
| `docs/refactoring-plan.md` | historical-reference-current-bytes | `aeb65eb24433893b70e0e58a81aef3fc28dc2655369a52d7771d7eb66dfe7c44` |
| `docs/round71-host-match-inbox.md` | report | `9024421eb86dc2075a727083e67a77b908a0ba3d4f0e42c1d9815290f967b318` |
| `docs/round71-publish-save-reliability.md` | report | `ab2d491ec6649d586f3273a8298f6917325c1c64e995ca1df458c1946a0e293c` |
| `docs/round71-three-role-build-candidate.md` | report | `7e5825f354ac5c34d6b0b6e2e0b81a2d78ae2b2b998a70a3641743703ac2b299` |
| `docs/round73-current-integrated.md` | report | `068c2f323492e26102d35edbb4bb362d92a1f77f2ce6760b9edd79c53c9afc7b` |
| `docs/round73-discard-handoff-verification.md` | report | `1425847ce3e9492ffb13a5a9c7a3a7eeba948adae1cd9b03ae460c001298838d` |
| `docs/round73-discard-window.md` | report | `02f77fb346190250d41a986d66e7865cf38a8a82afb8ae206b9803c9d394a368` |
| `docs/round74-layer-allowance-retirement.json` | report | `28872b370bbfe8c9ac2ec04501084382d28267e1bc2242d866a4c927527d4df7` |
| `docs/round74-old-client-adjacent-startup.md` | report | `a20ab409ab040b6b134f96a85ebe39622cac0b8789fbb307f8e2938c945fecfc` |
| `docs/round74-small-integration-queue.md` | report | `aff1ccdab78c501074b0e5711771503de98c630364f9c258cf738d6e4a351a08` |
| `newdocs/round60-save-restore-first-failure.md` | report | `d66dfef16d9efbf7d59c1ba59a810e97a7bd4b338bd657dfe9e261901d795fc0` |
| `newtests/action_completion_public_contract_test.gd` | current-source | `d8f3acb9569a7a9e56992a6ff290692323e1fb2b4e81afb9883ae4baf8755822` |
| `newtests/f09_room_password_session_handoff.md` | report | `0954a53272db2170807050dbb4832c231c5c2fb89c16fc590871b67e220d6008` |
| `newtests/host_room_choice_request_handoff.md` | report | `880c706d0eeedecc7b16a11b7743212928eb82a636f89417bd400b4b9d6be9f5` |
| `newtests/host_room_start_request_handoff.md` | report | `0c1e4df10fe59daf218ed300a2c0c61084eca7192fa555789ab0720de2447ed8` |
| `newtests/identity_ack_session_wiring_handoff.md` | report | `160d08a980766c17e025671b0da445a7287fec14bc3f4da456d2455e21f7d3c8` |
| `newtests/join_shape_session_wiring_evidence/join-green-verified.json` | manifest | `d7c9d7086b3b4182274b93b8b82aede62d64dcfe70c7688efb146df6912cada3` |
| `newtests/join_shape_session_wiring_handoff.md` | report | `cb6e31f6d791c9917c433f64e1b77269ccd0b2e8698493014035670ead7cee0d` |
| `newtests/local_battle_power_display_handoff.md` | report | `27fd0a1cccfc9229da6fed7604b469ad9cd85aecbd29f7bb9fcc2bb8c20b83c5` |
| `newtests/pending_announcements_projection_test.gd` | current-source | `ce1ba3d430db63af04c8ab93aa7e319b65af68e271bd5da212bc83c6f6e0a79d` |
| `newtests/round74_cleanup_handoff_result.md` | report | `e297f232c389cd8e23ffdd5776bdc87de5951a76c62de964ac5a787a9f6edf05` |
| `newtests/round74_host_preview_handoff.md` | report | `3d8293766a47cdf692666cca3fd622186faaaa704d08b2cea82c39f9acab5b45` |
| `newtests/round74_public_battle_text_handoff.md` | report | `da82c85d14944546b94cdc9f2b268244e6a9894de2f76a9803dbcb5380250d8a` |
| `newtests/round74_scoreboard_handoff.md` | report | `172e97466a9ccf1fb039b1eb9cfa49a10161e32bb309a07bd033d5e1b50d7736` |
| `newtests/round74_shared_out_of_game_handoff.md` | report | `4aa262ae40d246da774d0a0c7fb7d469d4174aa0923e32ecc3d1e98d17e5c71d` |
| `newtests/round75_banner_browser_layer_handoff.md` | report | `8b6c9cb62ed303d311a736acc011c5f8ce3171d446fdf80fbdbf6810fc49bf0a` |
| `reports/refactoring/baseline-headless.json` | historical-baseline-original | `a69616cf51b8294c78b9a8b0e324ad30918720fb38eab477c29fa07973c47981` |
| `reports/refactoring/baseline.txt` | historical-baseline-original | `57f10b96b566a85d4b2513ea15b401f09cae9c0ee716b0ee29e003b06699f172` |
| `reports/refactoring/build-cost.json` | historical-baseline-original | `e9c732a1723f989987377061683824eada257c2122d430e3266cab24b59f3532` |
| `reports/refactoring/server-room-lifecycle.md` | historical-reference-current-bytes | `5e3247f2ba4aa74755306d476c5021ffdb6dee7c0798fed3548358a8866ab29d` |
| `reports/refactoring/window-logs/first-run/baseline-window.json` | historical-baseline-original | `c9e5fa9649f8e3f09a3f6c132f3cb6db6e1eb2b6b7cf2802d64f41ef12e75a43` |
| `scripts/debug/debug_adapters/debug_map_adapter.gd` | historical-reference-current-bytes | `7bea69a095dd2aa356c6b9631ff327f2498ff1975bc1383a0c71c30d3282cca2` |
| `scripts/game_scene/battle_board_v2.gd` | final-current-source | `1e183b3dda933944a45d7161053554e6477b4f25e0d436bc892c08d21ea620ee` |
| `scripts/game_scene/battle_io/battle_host_lifecycle.gd` | historical-reference-current-bytes | `ac3011654a8ccae7b230d693632fbdab40032c857c2b684a1da4430b5a499605` |
| `scripts/game_scene/battle_io/local_battle_commands.gd` | historical-reference-current-bytes | `9f307a0010f35a992050a5ac248afda7ce604ecf4f609bd291409c108dc0cbfd` |
| `scripts/game_scene/battle_io/local_battle_source.gd` | historical-reference-current-bytes | `bcf2c7b03a48bdffbec8483f768c6005146ff2ca1f555b323fa783e87d0e1657` |
| `scripts/game_scene/battle_io/network_battle_commands.gd` | historical-reference-current-bytes | `43bb53535f3e64a9d0b730d77b6e2abf489a77aa15349bcd03d8ba4535f5758a` |
| `scripts/game_scene/battle_io/network_battle_source.gd` | historical-reference-current-bytes | `659dccfd291d429ef59f5b9649bc965123d2f7dda3f6cfb6d3cfefb7e48aff2e` |
| `scripts/game_scene/battle_io/shared_view_sections.gd` | final-current-source | `da6882e21ad24ecd43bc9d52dd8821dd462e281b6634c2fd425e0526ab0295c8` |
| `scripts/game_scene/native_choice_renderer.gd` | historical-reference-current-bytes | `8a785a0850cc1651fdf49a976df06e9b95beefea80fb725c2a7a0b4b7812144c` |
| `scripts/game_scene/tactical_board_ui.gd` | historical-reference-current-bytes | `3063aca824df5c4561cf08588c4e77d14588a3777e48397d33823e5b6a15acda` |
| `scripts/io/native_method_contract.gd` | historical-reference-current-bytes | `c22ffd6012cf39b2b80e915bf526c8459a2c1f5888503961cd8502cef5505c85` |
| `scripts/io/temporary_cleanup_native_delete.gd` | historical-reference-current-bytes | `5b8b404ade4af5942977d1af352d67ac3db01ba9ec01b4776c1b04ee81659396` |
| `scripts/match/effect_checkpoint.gd` | historical-reference-current-bytes | `65d5e293d6e6d8be6142b0caf65e6096c8cfd791576de6b089de88c0e8a8488b` |
| `scripts/match/match_command_dispatcher.gd` | historical-reference-current-bytes | `6e23d647c6b2e68c3b289902c4b96a987167cac10c0ee2b26b4ee3d24cab634b` |
| `scripts/match/match_driver.gd` | historical-reference-current-bytes | `8f76ea384e5ade542a4f3a8f39c8817423f043e305790f01d0596e50e1429307` |
| `scripts/match/match_replay.gd` | historical-reference-current-bytes | `851f77f939974d3f51eea51b70feda9c2593c0ee700e265bb4e090b78419d175` |
| `scripts/match/match_seat_query.gd` | historical-reference-current-bytes | `f7688104a9c0f51a998a2c6637a556563fd40e62025cdf8acd92ad9a827718be` |
| `scripts/match/rule_state.gd` | historical-reference-current-bytes | `b18b4cff2b4f3bff128a0645c91459d037477f6fe8503b418f8d057e59020b02` |
| `scripts/match/view_builder.gd` | historical-reference-current-bytes | `9a7ed25688ded565bce41b0a8b7473f8067553b55629fbb7d7ce88a276ec831e` |
| `scripts/match/view_mirror.gd` | historical-reference-current-bytes | `8007a3cc6e2e1ed0bb319ba3e1b3bd21fb825e7b9bc24f3f212a724c514eef20` |
| `scripts/net/authority/match_authority.gd` | historical-reference-current-bytes | `d4aec6e62c09bb7e9137ffd9d5d6d97c8329f2f720a4bc65d5e66b4eaf7710f3` |
| `scripts/net/content/blob_receiver.gd` | historical-reference-current-bytes | `4286dc14ef4f46a9837bf0bedbeba159e3bff57b9fcb26f1db77858999010bba` |
| `scripts/net/identity/client_identity_inbox.gd` | historical-reference-current-bytes | `cfcd2ac03f0585ff1c9013888b085c7c2dde52ded3dbf157a5c045ec59962f7a` |
| `scripts/net/identity/host_identity_request_codec.gd` | current-source | `3cf4c8ee29f22b310265ccd8bbf1d81bc1e612b7a9f767f02318a84513113116` |
| `scripts/net/identity/resume_ack_transaction.gd` | current-source | `37148da5003a901dac6f69e6e47d89ecbfea44b1b86dfccf0ab4d398b8294954` |
| `scripts/net/server/heartbeat_publication_policy.gd` | historical-reference-current-bytes | `b45b13235d422711cdece9d4af79e315a85d69fb7614fd4519747ff9871fc4ab` |
| `scripts/net/server/server_bootstrap.gd` | historical-reference-current-bytes | `6dbf5dfda785de5b11cab76f01e725317821eff51be37a4fbfba4bae5e978a3b` |
| `scripts/net/server/server_console_channel.gd` | historical-reference-current-bytes | `afbfd5a071a2fcb062555f00fcd9ac08dbe476a04ad3fd6efc2c7142373af3c3` |
| `scripts/net/server/server_gateway.gd` | historical-reference-current-bytes | `6c37eb25356bb1bbea22b7c0abf1c270c542745a2460f7d503bba740d6532cc1` |
| `scripts/net/server/server_room_manager.gd` | historical-reference-current-bytes | `ea4f181aacb86400ec4c46143298cf7edab3ceed952a1ba12ba78ef81f9123e4` |
| `scripts/net/server/server_room_worker.gd` | historical-reference-current-bytes | `a1d935675ce6d6a3f804ac9000104b15d95c2c279c8cf13c459acdd3920107eb` |
| `scripts/net/server/server_shutdown.gd` | historical-reference-current-bytes | `7526d0b8fd7d427a04a67085f462425f845e883a3210ee8017a0a30963b60227` |
| `scripts/net/server/temporary_cleanup_executor.gd` | historical-reference-current-bytes | `2619e8131365435a27f2862a86588aa55b7defa4e592e9bf8e2617a4a3c4acea` |
| `scripts/net/server/temporary_cleanup_ledger.gd` | historical-reference-current-bytes | `62c42e4d427efa5a54d4942c02255f45902610c52227621ee9b2350c8b59b5ac` |
| `scripts/net/session/authority_host_client.gd` | final-current-source | `4a145ffa7f6960aa8b9e808fa3539686d4d23ab2cd366316a1684c1d67098d75` |
| `scripts/net/session/client_match_inbox.gd` | historical-reference-current-bytes | `cf9a54204cfc5f5b68ff17742deac4a60882b7b51d1a057a6e5d9d2c2aaf95c2` |
| `scripts/net/session/host_content_inbox.gd` | final-current-source | `ca724fa5e1a57ea2f5db6ae7982dac50a5524e6b41a5acb83cd3b0bd6af7882a` |
| `scripts/net/session/host_guard_inbox.gd` | historical-reference-current-bytes | `e2042626210bd12dbedd63ddf6369216a741791696a68465d89b7391ae480832` |
| `scripts/net/session/host_match_request_inbox.gd` | final-current-source | `285463a2699b9393cc1d27e5f50820d70d3dbeec47a71eca32cc279a758a42db` |
| `scripts/net/session/host_room_inbox.gd` | final-current-source | `fb4a14e16b28d8ab2d844176014aff528c476e4b9223fb512bda4f5dadacc799` |
| `scripts/net/session/host_room_password_request.gd` | current-source | `71106339b98abd39bbed6cce3d6dc1afba83c8c24698dc57e8b2a6a2ee38e615` |
| `scripts/net/session/lobby_session.gd` | final-current-source | `e07db399d36ac77d8f2458644b1fb75901882a5d39f89d7d6f8770ad16d5c5f3` |
| `scripts/net/ui/network_choice_panel.gd` | historical-reference-current-bytes | `a48412ca6c0738bbf4bf4222a42dfaa3e557137124cca3d1d020a77720c0aa2a` |
| `scripts/net/ui/notification_inbox.gd` | historical-reference-current-bytes | `b764d5d6300ac93fcd0130e448c40d80e9acbd5228c4d62781b6650ea9d22fe0` |
| `scripts/net/ui/v2_view_presenter.gd` | final-current-source | `81285a188f225449e7bdac8f3f955a8a3c196d83c79152e0888afd98d94d55f6` |
| `scripts/net/validation/room_data_preparation.gd` | historical-reference-current-bytes | `12918b213f39bd88ae4f8cfbb9e949f75359e91e7ac999d7177b95b5c2b7b16a` |
| `scripts/net/validation/room_data_validation_worker.gd` | historical-reference-current-bytes | `7d5f26444bd5adeeef2eefa3e0071c7a765a19d0e4d52dec8a5b7f21aa12b16e` |
| `scripts/system/ai/temp/dummy_bot.gd` | historical-reference-current-bytes | `94aec64c19a6c7f73e76d63ac1a3a5273279af11e109bb91334967a4600f7e72` |
| `scripts/system/area_action_rules.gd` | historical-reference-current-bytes | `409d569acaf4c4ba646ef44bb516878c3f70f4e74b5f7797e7d02a2235adce8a` |
| `scripts/system/global/climax_resolver.gd` | historical-reference-current-bytes | `0aab398b99a56f6014203ef99199b802671dbf22aa628e4944ee86718f6b8c37` |
| `scripts/system/global/content_environment.gd` | historical-reference-current-bytes | `fdc139c595c143b68a3168f93eb2ee4d992d899230c9546025a962eb8580c363` |
| `scripts/system/global/effect_manager.gd` | final-current-source | `626754ecdacb21cc22353e53ae743bd74a9f0586a85c8e0bb5b849ebc4bb1d68` |
| `scripts/system/global/game_data_manager.gd` | historical-reference-current-bytes | `d8cb5112300a319c64eee3da6eb008bf2cc98631a39f4916cfd972327833b1c1` |
| `scripts/system/global/game_progress.gd` | final-current-source | `0db25f9e17b9da91c248201d6be5c67eb7081b58295d49142b3824286cac4978` |
| `scripts/system/global/load_game.gd` | historical-reference-current-bytes | `2a78f90ac18bd76ea2ea3181349d069874bda5df3ce8280134e17f9ef17c92e5` |
| `scripts/ui/text/card_desc_text.gd` | historical-reference-current-bytes | `80c62325ac4287c57fee1b8bdb32043a1cffdfb490971076ac9f23217e5431ba` |
| `scripts/ui/text/choice_text.gd` | historical-reference-current-bytes | `f4211b3acc56e8258d3ba94e463d17abdfed50b1292aa97a8f73f1c91c812f21` |
| `scripts/ui/text/cost_text.gd` | historical-reference-current-bytes | `c432cd4bd5db8a4a89e5210de26b92719b263c00b79a61415012bd559e118c73` |
| `scripts/ui/text/game_log_text.gd` | historical-reference-current-bytes | `bafdb571773d81b2955c0a204624ed9c766c4705b5db7ccea951a054ae2ed7a8` |
| `tests/audit_commit_test.gd` | historical-reference-current-bytes | `8314b5f395fc10754aef482f174a5256aec31cbf6ec0454be0f909a333af8fa7` |
| `tests/battle_board_v2_test.gd` | historical-reference-current-bytes | `048d1b7261d6a07fb9d2c47894d7f7afe2dd69915c5e77cbae1757c4009726de` |
| `tests/battle_broadcast_test.gd` | historical-reference-current-bytes | `9429f2ab529445385df1f92c888929e7c0e8ffbefe8328de00c8701936578bd2` |
| `tests/battle_play_groups_test.gd` | historical-reference-current-bytes | `5238a6b955e7f1136c19b641277e29d823e279dc2bca321b5c34091354acfedb` |
| `tests/broadcast_policy_boundary_test.gd` | historical-reference-current-bytes | `5009d13113a51a2f2c9d1a35d3d789c60732e2cf4fb9c443c3167c6a3381b7d5` |
| `tests/climax_elimination_test.gd` | historical-reference-current-bytes | `ea6e9f926d784858cd1e3db0339671f97925107b7f26ab7e05d58bbb647b68ba` |
| `tests/debug_console_test.gd` | historical-reference-current-bytes | `af0afb984702f5313c68a0ec69b7b88baee9ee8f399a63f8e1baf1831e525382` |
| `tests/deferred_transaction_facts_test.gd` | historical-reference-current-bytes | `a162839e178649913bd8eb898e5fdcd2df5f907a04a30a6d09862680b60ca7dc` |
| `tests/full_game_test.gd` | historical-reference-current-bytes | `1c2f011a6f0bd78c53ffd4d57c6d79a128d6529be9b26e34c0e1dc210cef1641` |
| `tests/loader_error_boundary_test.gd` | historical-reference-current-bytes | `800b1288267fb86efa3a7d2d8ddd6ecdfc769d37382d7e1165f84fff25a08497` |
| `tests/natural_game_over_test.gd` | historical-reference-current-bytes | `37b4f651fe738b5521df55177ed8644dba05457fb75a3e27ade49212cbd18666` |
| `tests/net_server_gateway_restart_test.gd` | historical-reference-current-bytes | `f5c25d584886153de2f2363cdc2f91384a05346b3278eeb9d55e6ad7e518cbcd` |
| `tests/notification_projection_test.gd` | historical-reference-current-bytes | `f3354986d7bdeb335fb1c66838694ad9694baa0d2ffe7346ce2b66680b4ca899` |
| `tests/notification_reconnect_baseline_test.gd` | historical-reference-current-bytes | `b165ad8af93bec582a3bdaf53afd7f31d099c56946ea30d8aec0fbece0ba129b` |
| `tests/pending_board_power_test.gd` | final-current-source | `3d548ab7b83cc2ee7920c539275ad8fc37cbceb7e3cc2b42adfb2b7189a41e7f` |
| `tests/player_name_test.gd` | historical-reference-current-bytes | `f5ca4f1284501be6b2a738d45565b8c96a7950072560b070785a43ae5ecc178d` |
| `tests/player_query_purity_test.gd` | historical-reference-current-bytes | `93f53cb9404c829a2a0cfbd29dbc1879504e0f2538003efe3bc293c8205e2768` |
| `tests/player_shown_name_golden_test.gd` | historical-reference-current-bytes | `625cab523ca0d51875752cb1b732d9bb3ca52bdb7bdd6dd27a08f611cfd106e1` |
| `tests/refactor_area_golden_test.gd` | historical-reference-current-bytes | `84d553858a7780e9482552efc8cd2d0f362737f1eadb26d071ae50d68b9daf32` |
| `tests/refactor_build_cost_probe.gd` | historical-reference-current-bytes | `b519a60eb63090fab85d732ee0a876dad53dc7e95871be48063b677e53f6a33b` |
| `tests/refactor_kernel_state_boundaries_test.gd` | historical-reference-current-bytes | `0537cdb13f3d13f076acf2a0cf6413c0a57ec9ca1558b8445b4a12c07f81d97b` |
| `tests/refactor_text_golden_test.gd` | historical-reference-current-bytes | `4a7dbdfd40f840c990d2df13b5de6b681c253dda57331f855d8a77c989fbc332` |
| `tests/server_shutdown_close_handoff_test.gd` | historical-reference-current-bytes | `43883d7c045e424fded389ec2359e5ef7416e063f84c7c4d185ab567bad83394` |
| `tests/turn_order_test.gd` | historical-reference-current-bytes | `8a75d129a4c701314ae69d8510d4a612c5e037304e4ee626c0c81e4174744bfd` |
| `tests/validation_pipeline_performance_test.gd` | historical-reference-current-bytes | `4c8a757983ca369e168c61c5a69092459f74009816b99ed421fa715cbcc27507` |
| `tools/check_inventory_drift.py` | historical-reference-current-bytes | `3d23b702d8d4ea4b5aeb3511975b2c887b36d72e3e1c87c7d5d839b14b891d67` |
| `tools/check_layer_deps.py` | final-current-source | `a8271e946890cbc1a58dcdf54b75ecc8078542be55c838df33d093f284d2be05` |
| `tools/classify_player_data_calls.py` | historical-reference-current-bytes | `533d3fc58fe652ea14161d6154a1262a62c736dfde745670a71e7de5a58a1a1e` |
| `tools/copy_data_after_export.py` | historical-reference-current-bytes | `3210a8de8d6afb24a9d7cf6c49b8c9df21f65b5ad5154227c83c0d4fb6a6ebd0` |
| `tools/diagnostics/round63_observer_lock_contract.py` | historical-reference-current-bytes | `04c220442e23d10005ad0e4bf314bdd07a2ee172836a1ba3106d664983576765` |
| `tools/diagnostics/round63_observer_lock_contract_test.py` | historical-reference-current-bytes | `926b224c90f3a38e09ae79808b8fa40af26d0651b4cd86dcafb0cc33cbdd5c90` |
| `tools/list_presenter_private_access.py` | historical-reference-current-bytes | `38a083f0c190d70ac3a5e9dc4c44fd364328f1cac984fcc5b1a1d90aa7cb0f18` |
| `tools/release/freeze_prepare.py` | historical-reference-current-bytes | `d82162e28f2c465a07ac83f25f8b795705e89e9c04b4fdee370beeaf003d28fc` |
| `tools/release/package_audit.py` | historical-reference-current-bytes | `238e1ebf15475ff4b7e24ac94a03e4e3068fd77289bdc147281728a0b5c37887` |
| `tools/release/release_prepare.py` | historical-reference-current-bytes | `a098ec5a66b7ec15cd378f7e86b5e5bdbfbe496e801e85f6b9abae121d8522bf` |
| `tools/release/round56_three_role_freeze.py` | historical-reference-current-bytes | `8d11ce8b073d70ee2e5aebc2e35247c5c7d7b46484bced7f3a316571584004e1` |
| `tools/release/runtime_audit.py` | historical-reference-current-bytes | `aeaf6938152b65e638fba80ff1bd27bfca2c29aa4144c3004d86539c4919ffda` |
| `tools/run_refactor_headless_baseline.py` | historical-reference-current-bytes | `3d13d0efa73a8e85120e43b85a32cbd1da51b280cca3bc23c8f67528008518bd` |
| `tools/run_refactor_window_baseline.py` | historical-reference-current-bytes | `df27a57ab9c2fcfe0ea17e3280ff214b856df7d82f3d77e9c188389dd4d5355e` |
| `tools/tests/test_check_layer_deps.py` | final-current-source | `951b3b906ce305d4bd47b0a2f8f6e98cdcabfc28a5cd0269674a17f6628a1ed6` |
| `tools/tests/test_round29_integrated_evidence.py` | historical-reference-current-bytes | `a4fcd8ad322b745b8b762ea2cb13dc6b9b8e527ee1745b56dbbc0a4390faa0b6` |
| `tools/tests/test_round50_candidate_selection.py` | historical-reference-current-bytes | `b57a8c0418e7b0e8c194f5a2cb5a2ca850fc25c1fbc7fe3c16ee47afd227e254` |
| `tools/tests/test_round64_release_runtime_entry.py` | historical-reference-current-bytes | `1704ad4e0c83b45be80cc72637ec7c14d9fcac66fac067d5f14facc45173af1c` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/round73-user-stop-readback.json` | manifest | `3a4fa2e05764f8a1dd8fc48cc467378fb97e8a1d36a5e25878c0537a8eee81f6` |
| `E:/scratch/isolated-1105873e41cd4f6a94a999e65ac6af50/manifest.json` | manifest | `d439e06fd4a92592211d306dfa292ba2af90c04c699bdd3fb52ee19b5bcc85b4` |
| `E:/scratch/isolated-7ee7ee28648c4e36a3b71869a8234316/manifest.json` | manifest | `645697d418d79b1ea18d1310d14eb9558d221490c1312968adda28cb26e79fb9` |
| `E:/scratch/isolated-b3cc1bfe631149fa94f6a7c789f25491/manifest.json` | manifest | `4b76b2d85bef24ec2443f3ae835ca2e0b7117976a92bbba25108dff52a19d4cd` |
| `E:/scratch/isolated-da02984e532f43a08e445aca142ddebb/manifest.json` | manifest | `435f93e9bfe5a2b032b6ec1611907ab54e3a1d12fc28d25d3e2d4a798b1116a6` |
| `E:/scratch/isolated-ed9fd487c32d490087e239301371f838/manifest.json` | manifest | `3fe0e659cee9c97850805779026548d1aa04a193098d772302beb8fc48efb14f` |
| `E:/scratch/local-battle-power-display-green/isolated-e99ec50251254d4cbbadf00ef6819751/manifest.json` | manifest | `27f64c84919507dd649b88edec1bb2ff9331400ff758580a2bbe377ca4cfa4f5` |
| `E:/scratch/pw-5ed75bc6/evidence/identity-ack-green-verified.json` | manifest | `74e13cd8786f0446d4346dc82d844dd0b039af44f518e64430ef373f4869129a` |
| `E:/scratch/pw-8ba2bf92/evidence/final-verified.json` | manifest | `e9d11146fd279dd32180ee720af97032d534e93d02ee0b00879b336c02414c3d` |
| `E:/scratch/pw-9051221c/evidence/final-green-verified.json` | manifest | `ec375add8dd61e030cf3274009d36401d6484bd4f61465d108f777e9f13ab1cc` |
| `E:/scratch/pw-e392b13a/evidence/green-verified.json` | manifest | `3efbb683b8efe6551539198935821a4d2ca30f4622467c3cde096dbb2ccb9ec4` |
| `E:/scratch/round60-fixture-f8a66eb3fde84cabb78eae5ee64eb735/manifest.json` | manifest | `5e156b65d75419aa423fba7b2d9159a001b9ebd55e52eff15f1b417e86a582c2` |
| `E:/scratch/round60-play-groups-final/isolated-712950fb4ee8428f99c67381c531b90c/manifest.json` | manifest | `74f08007985f83c6ee0673bfd0294453c071259fd1ca2cf8faad3ba9181f2d01` |
| `E:/scratch/round61-resource-proof-486a085c8e55481eb659d22b62f13990/isolated-4c99f2d34a8648169e9acb80e4e053ba/manifest.json` | manifest | `158e65ae2a0bd45a5dddbab95886aa8429e0aabcab99b1323d4a76160362f6d5` |
| `E:/scratch/round74-out-of-game-targeted/isolated-6abdb4949a1344738b8ad5600e69836b/manifest.json` | manifest | `93dfe6474cab919ebe609fad6a689f3720cff5b18c1171896c42723d3d9a8b9e` |
| `E:/scratch/round74-public-battle-text-green-final/isolated-9b9d249cd6a04fb08802724c1cddde79/manifest.json` | manifest | `1502842ed50bedf459be98113a7258817f418d9693bb45c6df96bb67eb13bf4b` |
| `E:/scratch/round75-banner-layer-green/isolated-3c728ddd530e4aed907f0e63e3d56515/manifest.json` | manifest | `ea3355e38488bb88d8c0a2cc43ef8b5283da306b6cf7b5bc91044c7b30fc40a7` |

### 实际全文读/解析的诊断日志（精确路径，不扩大范围）

| 路径 | SHA256 |
|---|---|
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-active_choice_source_command_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-active_choice_source_command_test.stdout.log` | `fdade97aa74294f9d19301381da29a3013b59d48ed7428eae24037f124619549` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-assembly_publish_lifecycle_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-assembly_publish_lifecycle_test.stdout.log` | `dc761c2c4e538ee126eaee6bd30fb9f1ac5d3e69d1341a4bd744f188c3400bc0` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-battle_board_activation_command_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-battle_board_activation_command_test.stdout.log` | `71f778d57d64490e8e7a0ddb526729d482dfc08d1e3b496b579d0c66b885d548` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-battle_board_end_command_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-battle_board_end_command_test.stdout.log` | `1b6faf4269c0eef19350827c3ca030aa805e9c48096aee02a89007c228b54293` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-battle_board_v2_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-battle_board_v2_test.stdout.log` | `aa86dc806655038f8b7c7dc11feb72b7dffec691bdb39eb68b499c99bce4cf95` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-battle_command_adapter_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-battle_command_adapter_test.stdout.log` | `2aef16a435db4565ecbfcff97627cefaec14138f8410fbdec7d3040a81202006` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-battle_play_groups_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-battle_play_groups_test.stdout.log` | `c6134bf6721fabb96cdc71c192e45374ec2a6b48437f2b78f6576c0b9b73ef6e` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-card_choice_source_command_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-card_choice_source_command_test.stdout.log` | `062af109ef4bac23d13047cb96af9119e1647a88fe4e8a8e696a8acea79ba7d0` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-client_identity_inbox_contract_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-client_identity_inbox_contract_test.stdout.log` | `6ca9180500caaa96b38fcee13e4dcab3e5bdc464c4eb8a76e658014a4eb01ad4` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-client_match_inbox_contract_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-client_match_inbox_contract_test.stdout.log` | `7f4074dc5a8877055d87ab58371ed7bdb254a723a85ea5eeca4f628d2eb5053e` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-command_spell_source_activation_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-command_spell_source_activation_test.stdout.log` | `5ceccc82f09f544fc3e7f4d23a7283066e5a3b58522002f38ba98b3a6515b6a5` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-content_environment_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-content_environment_test.stdout.log` | `293e0ff7f3fa45b25cc43c0f2f9bc585cbf98a95b1f28d510f4b33d1104642c3` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-deploy_rules_layer_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-deploy_rules_layer_test.stdout.log` | `ddd7665e922920a0f4a8a281fd57274883f88c23f979640334e7da215b29d4b0` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-gateway_bind_failure_test.stderr.log` | `49425bf96f31115e26c5c51b6d7cfcf035aa05051553ca2eec339adc3110018a` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-gateway_bind_failure_test.stdout.log` | `128cbaeab42776f529e2d4b307432dfb4cd9d41c328df72a09c6956753e60769` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-gateway_deferred_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-gateway_deferred_test.stdout.log` | `c642f3c756fb83762a6140b6d8b17983c8e028ceeaf91f6373e219fd0741c4d4` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-gateway_disconnect_safe_close_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-gateway_disconnect_safe_close_test.stdout.log` | `8df6ca8d72acc6d304faac286778580d17c13dfa22b35c13580a033cc7e65b61` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-gateway_instance_binding_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-gateway_instance_binding_test.stdout.log` | `ccac0db6250c3b109d1ca4f3b1f6dce43850f8f62334362e4b2da221ab6650ed` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-gateway_relisten_acceptance_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-gateway_relisten_acceptance_test.stdout.log` | `3e326420f5c5c7c28cf3db7b01e2f60644e31e3c08468322760023dbb2a1f1f0` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-host_guard_inbox_contract_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-host_guard_inbox_contract_test.stdout.log` | `cd9c1c09f5a2eef0cd329f104985f5d75724c4b069db590d61c175162bf69218` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-host_room_inbox_contract_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-host_room_inbox_contract_test.stdout.log` | `3ca08f80fe83c9b285b69a924f410b7b5975dcc07d5be2580fe1c4da8b11c2a8` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-lobby_content_environment_restore_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-lobby_content_environment_restore_test.stdout.log` | `24544172eb67e078e51d3c3d59508952c5d73de3f947d42e6d494dad4ca3f04f` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-location_choice_source_command_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-location_choice_source_command_test.stdout.log` | `f9ced26fd17a5f283d933e19607fce4a9b1d9c9474d0750a15a331d57e495b3e` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-mana_spend_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-mana_spend_test.stdout.log` | `de67af2159a548e6d704d3e859bba54c5b2097022de369833b71aec30e04e4b7` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-match_command_dispatcher_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-match_command_dispatcher_test.stdout.log` | `0b4d1f402a2ecf53f7aba3260d1ced9ab2066088273a398498d8233a273ace33` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-match_command_result_protocol_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-match_command_result_protocol_test.stdout.log` | `60acfec355c8a8ae1844763e3d32feb1b294dcad37137d43e7248547a5b85146` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-match_commands_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-match_commands_test.stdout.log` | `cab503dccd8e62efbe353cc03526659f9c0c6f6bf5717beca3bafbf511217312` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-match_view_privacy_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-match_view_privacy_test.stdout.log` | `9f8a8314030cae1fea6fc6a7ddb1df1957d851257b05736d4f7dc78211a200d2` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-match_view_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-match_view_test.stdout.log` | `13dd056407eb314ba7435dce56f71f06a9f1fbb12cd126d84544bb29357337ca` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-mirror_spell_negative_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-mirror_spell_negative_test.stdout.log` | `4ccb100f2f6615f795c6e3a981cf9537452aea6d0f4d8defb7a174b170be1922` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_authority_ui_preview_feedback_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_authority_ui_preview_feedback_test.stdout.log` | `4d98c8fed81d3f5b1b45b7d89df991bcf274104bfae3681bd006c41cdd088c9f` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_background_validation_feedback_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_background_validation_feedback_test.stdout.log` | `8962bfa755fac5a6dc3fa951905e297cfee6bcc28ec9bae6713372746e82d89a` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_blob_authorization_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_blob_authorization_test.stdout.log` | `8f633071f19cf6e04e5c9afbd5d924fb5bb0867c744a613e694cc74336a4e4b3` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_blob_concurrent_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_blob_concurrent_test.stdout.log` | `429604f8573c36deb9de8ec1c34763a0c35fc36dc387d811d5bd189db568f1b6` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_blob_send_authorization_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_blob_send_authorization_test.stdout.log` | `468114130c4920efcde55c76b620a3d8c9024b1cae2f2fcce7d552fabd437d86` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_blob_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_blob_test.stdout.log` | `20999db7009c3bda22b64beee81f5b181617644f06ee80e4c8c9cc76b2de4996` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_cards_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_cards_test.stdout.log` | `4dfe9e56687dd8af555418493e93680aa47ab7f9ca4696691a7f41352c1f00a1` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_data_sync_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_data_sync_test.stdout.log` | `6a105ba39568364406ebc17300bc93826d00fcaa5336e3290c6573ae1a5a617c` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_data_validation_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_data_validation_test.stdout.log` | `4b8b0253a719b903130b1ece7ba99a3f3215d29bb5e32ba5395aab54ff182334` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_guard_rollback_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_guard_rollback_test.stdout.log` | `ed81a4a754f7dd34553c6b17bd8f06ccd6cf4e8d7302ce4f81224cb0e89ae554` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_locations_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_locations_test.stdout.log` | `a80532a73fb20c765e5a67d40087c9a1e284b36e654a5a6a9f9228c1e5ddbc6e` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_move_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_move_test.stdout.log` | `c5aca5b70f3055b221d2082774c9dd78511c648b423031296b42f3baea1132cd` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_parallel_validation_feedback_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_parallel_validation_feedback_test.stdout.log` | `33510567930e70d8b060719dbbbaa70da33aac1ade881b8747fea9ab958e46e3` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_pending_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_pending_test.stdout.log` | `f10770f63862257f7b2abdd75c677e3c845e482bbe1fd60fbef29e9dcaaf0f31` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_resume_identity_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_resume_identity_test.stdout.log` | `cbc3a384ed8e3663b3ca894ae575c2cc519c741032deb769036fe733e0801a42` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_runtime_guard_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_runtime_guard_test.stdout.log` | `ba2f0fff55c9470b9f1d00a8965b6a31f26488bb2ed22269a30d5554cb022255` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_selection_settings_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_selection_settings_test.stdout.log` | `b7b145dcb09cc2de9f8e8a5e56089b9419533509c8b321d31ea160ec9df913c8` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_server_discovery_validation_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_server_discovery_validation_test.stdout.log` | `a3a50a51be8dfff70bb8826ead07e58b9ca654cb4f7f990c98fc182b888bc526` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_server_gateway_restart_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_server_gateway_restart_test.stdout.log` | `10a6f713e9107111b2efd9184b18d6504a39378d8677306e2760ce2afaedc344` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_server_gateway_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_server_gateway_test.stdout.log` | `81dd351ada6c1243c0064497a6d177dd86344eeac6ab71346c889a54c590e83b` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_validation_hard_timeout_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_validation_hard_timeout_test.stdout.log` | `b2efe95c32673383156db32b5526724bca060b649f68c715fe9e3f6c7ff2d7f8` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_validation_io_feedback_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_validation_io_feedback_test.stdout.log` | `ca44f788afa1fbad1435cc666b4c0127728b6a971de0987fed6eb39bbce17a58` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_validation_io_measure_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_validation_io_measure_test.stdout.log` | `4f4ab982edf5f2678c16a99cded5e10adb1d7547a11b43fcaad0b645cef8cdf1` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_validation_simulation_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_validation_simulation_test.stdout.log` | `20d02d613fc7ccb83514d933f37280d48d6e86a0d60f551d1e6a4ad73917f745` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_validation_task_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_validation_task_test.stdout.log` | `4a29e7266a7cfbff863f89807c8ebe6d1e084cd01e41b4cf84f57d8e7efa6896` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_worker_startup_contract_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-net_worker_startup_contract_test.stdout.log` | `7e8e5fbfc0bde6610c8ccfc3e944a3d9023e2bb664a0de1a51a42f931e96c851` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-newspecial_spell_materialization_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-newspecial_spell_materialization_test.stdout.log` | `81dd53e1b66dd042cfe6c0a0635aceff12f09a9e3b55ec5285671a71352ca200` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-player_choice_source_command_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-player_choice_source_command_test.stdout.log` | `44355bd5e2f8903f743531a89934da3a2c2937d15350c720d6f3187e360e6df9` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-regular_play_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-regular_play_test.stdout.log` | `68c31425e11198e04edd2947aca2d6f277d7c7f41323c23ca52694eed452f07c` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-room_data_preparation_consumer_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-room_data_preparation_consumer_test.stdout.log` | `8a84f323c89743c7e00b157e39a7f85d17e7fc0af050aea6b494acee379d1f17` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-room_data_preparation_dependencies_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-room_data_preparation_dependencies_test.stdout.log` | `fb9bd3f177b93c057f5debb71fc1428f9bdd5c13af47db949d2a7e8cb343c7b4` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-round28-command-migration_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-round28-command-migration_test.stdout.log` | `e6464818e664ee8da3965f3a1ba8c0c6ba7d07838d9bc334aba81332f7371732` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-round29-shared-presentation_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-round29-shared-presentation_test.stdout.log` | `4072c72f6a819171057969726f5bb701c7013bd821a785b8c0a8ee53c7f75249` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-round39_restore_transaction_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-round39_restore_transaction_test.stdout.log` | `d80a35e6270caf62d6e3f981f86c77c9210308d79a19cf1136169933e503764a` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-rule_guard_chain_rollback_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-rule_guard_chain_rollback_test.stdout.log` | `442db1f0f313e8601e9d1b684fd27631712f1fa5d9a9a2cdc176ea13a95dc868` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-rule_guard_continuation_occurrence_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-rule_guard_continuation_occurrence_test.stdout.log` | `25f968dd8625c10a89f579803e28c276dbf4bc990de51b7c7a35b201c875c635` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-rule_guard_rollback_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-rule_guard_rollback_test.stdout.log` | `53cb772d0db94d360cf0ff148aaff97c704febb60fabe6513b159757dcda3798` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-rule_guard_root_transaction_v2_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-rule_guard_root_transaction_v2_test.stdout.log` | `a5bafb2b2e43db33b5432a180e13d6d3728603935e5464c0b47f0a1e28048f83` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-shared_spell_view_contract_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-shared_spell_view_contract_test.stdout.log` | `e4e35892a966496c9e2048075a6a7ce4156569b22f4e32c7b4e891eebbbc750e` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-validation_checkpoint_reader_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-validation_checkpoint_reader_test.stdout.log` | `846e7257157395dd9729df45c5251fe06e1748d0326734b653586041ea67fcba` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-worker_content_environment_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/complete-worker_content_environment_test.stdout.log` | `86b8d1c21d070588ca3eacf3479c1d708da8aef55ab83637dc3d4d73173849fc` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/import.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/import.stdout.log` | `6e70c1cab843a9c9717fa2536deaa5ad4807a5d2724e1ae6f414f542e9cf2708` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/prerequisite-worker_content_environment_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/prerequisite-worker_content_environment_test.stdout.log` | `12ccee56eac5ecfd7334bfb8814a35da7b6d8ca9482fc8b858b5f7daf762869f` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/probe.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/probe.stdout.log` | `2e7589f646bf63aa3e2785479259c69820a09894d4a9faeb68545855a65a0f6b` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/required-round50_finished_lobby_tight_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/evidence/required-round50_finished_lobby_tight_test.stdout.log` | `9fea491818397f3fb3a4d6e916598e53c95447c1950cb130ae7984f2168e7028` |
| `E:/scratch/local-battle-power-display-green/isolated-e99ec50251254d4cbbadf00ef6819751/evidence/import.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/local-battle-power-display-green/isolated-e99ec50251254d4cbbadf00ef6819751/evidence/import.stdout.log` | `e383967853462938d5742a8d71cbe84fc1ccfd74159ababd0af8b80d76e8b8da` |
| `E:/scratch/local-battle-power-display-green/isolated-e99ec50251254d4cbbadf00ef6819751/evidence/local_battle_power_display_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/local-battle-power-display-green/isolated-e99ec50251254d4cbbadf00ef6819751/evidence/local_battle_power_display_test.stdout.log` | `c208045c8b277b863e83e36c222d05f8f280600d31c53c222c79cb0bb93ff1f4` |
| `E:/scratch/local-battle-power-display-green/isolated-e99ec50251254d4cbbadf00ef6819751/evidence/probe.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/local-battle-power-display-green/isolated-e99ec50251254d4cbbadf00ef6819751/evidence/probe.stdout.log` | `26625c97bb1995c7dc18edb043f5d98d2900658cc73daac47f5591de6bb0f163` |
| `E:/scratch/pw-5ed75bc6/evidence/identity-ack-final-test-red.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/pw-5ed75bc6/evidence/identity-ack-final-test-red.stdout.log` | `31b074d0314a13b862ced4145845fd45958907cd3af3519eccb1b2ee8d002c92` |
| `E:/scratch/pw-5ed75bc6/evidence/identity-ack-green.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/pw-5ed75bc6/evidence/identity-ack-green.stdout.log` | `907d3bb7d1d0eba2d3cf72affdbc1e77df3ec3110143ff98dd9c0e81b26511e9` |
| `E:/scratch/pw-5ed75bc6/evidence/identity-ack-red.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/pw-5ed75bc6/evidence/identity-ack-red.stdout.log` | `31b074d0314a13b862ced4145845fd45958907cd3af3519eccb1b2ee8d002c92` |
| `E:/scratch/pw-8ba2bf92/evidence/final.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/pw-8ba2bf92/evidence/final.stdout.log` | `f42d7bdf29d346b0b6919cb5bf26d0963956e1939087fd340e81c4f6b4292003` |
| `E:/scratch/pw-8ba2bf92/evidence/green-fixed.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/pw-8ba2bf92/evidence/green-fixed.stdout.log` | `f42d7bdf29d346b0b6919cb5bf26d0963956e1939087fd340e81c4f6b4292003` |
| `E:/scratch/pw-8ba2bf92/evidence/green.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/pw-8ba2bf92/evidence/green.stdout.log` | `427207ca488d333145e24a9bc133abe496ac015bc758b54e19cd4c8378466234` |
| `E:/scratch/pw-8ba2bf92/evidence/initial.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/pw-8ba2bf92/evidence/initial.stdout.log` | `0d5ba1f9871753f32e7f1b2fc5a42d166716b6f1040791d970b08e5f5ccd7773` |
| `E:/scratch/pw-8ba2bf92/evidence/mutation.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/pw-8ba2bf92/evidence/mutation.stdout.log` | `2ddd5196a0f56b07bac703eb2e638c4c536292e3406077712cc4bc22ea7f44d7` |
| `E:/scratch/pw-9051221c/evidence/final-green.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/pw-9051221c/evidence/final-green.stdout.log` | `8564a18c6dadf0f0f4e441638a849e8b1f181f6c957495447228b98ccad2558a` |
| `E:/scratch/pw-9051221c/evidence/green.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/pw-9051221c/evidence/green.stdout.log` | `4342ebd2bd401ed66f876c28b0ae9c8b678a4c9f077a4e813db57b9ed246c6dc` |
| `E:/scratch/pw-9051221c/evidence/red.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/pw-9051221c/evidence/red.stdout.log` | `28d16c25769d63311c4a18a98992d838d516b23c9e2271c8fce56dc20a68467b` |
| `E:/scratch/pw-e392b13a/evidence/green.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/pw-e392b13a/evidence/green.stdout.log` | `2ac8b93f751c1716250c0c015b95ee36b8af67898dccb387101726fdc5989467` |
| `E:/scratch/pw-e392b13a/evidence/initial.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/pw-e392b13a/evidence/initial.stdout.log` | `bb15530dceb58babc1ea787286d7a45933a0cd7212e278c83e2345b8d0db763a` |
| `E:/scratch/pw-e392b13a/evidence/mutation.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/pw-e392b13a/evidence/mutation.stdout.log` | `851b66b254a6b64ff4b0537ea5e8627f4a50a6049a582b921651e1c1a2ec6f2c` |
| `E:/scratch/round74-out-of-game-targeted/isolated-6abdb4949a1344738b8ad5600e69836b/evidence/import.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/round74-out-of-game-targeted/isolated-6abdb4949a1344738b8ad5600e69836b/evidence/import.stdout.log` | `47b3f1e2ee7863f4d3447e838b005014bcb4567adaccb3d2aadc6c0eccf4cb54` |
| `E:/scratch/round74-out-of-game-targeted/isolated-6abdb4949a1344738b8ad5600e69836b/evidence/probe.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/round74-out-of-game-targeted/isolated-6abdb4949a1344738b8ad5600e69836b/evidence/probe.stdout.log` | `3c1a83b4e4252aec78d021094d56c6eacc2186e2cf36202a3e44ec9900b86097` |
| `E:/scratch/round74-out-of-game-targeted/isolated-6abdb4949a1344738b8ad5600e69836b/evidence/round74_shared_out_of_game_test-window.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/round74-out-of-game-targeted/isolated-6abdb4949a1344738b8ad5600e69836b/evidence/round74_shared_out_of_game_test-window.stdout.log` | `2879a5c1825348cc4dd9ac2f5d10b9037e3b1fef14c8c46ae3166b0e9b87bb36` |
| `E:/scratch/round74-out-of-game-targeted/isolated-6abdb4949a1344738b8ad5600e69836b/evidence/round74_shared_out_of_game_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/round74-out-of-game-targeted/isolated-6abdb4949a1344738b8ad5600e69836b/evidence/round74_shared_out_of_game_test.stdout.log` | `c6ebb0af9c592bada13c35ad01754fd1724c87e4182018394cca860b965ab116` |
| `E:/scratch/round74-public-battle-text-green-final/isolated-9b9d249cd6a04fb08802724c1cddde79/evidence/import.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/round74-public-battle-text-green-final/isolated-9b9d249cd6a04fb08802724c1cddde79/evidence/import.stdout.log` | `e383967853462938d5742a8d71cbe84fc1ccfd74159ababd0af8b80d76e8b8da` |
| `E:/scratch/round74-public-battle-text-green-final/isolated-9b9d249cd6a04fb08802724c1cddde79/evidence/probe.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/round74-public-battle-text-green-final/isolated-9b9d249cd6a04fb08802724c1cddde79/evidence/probe.stdout.log` | `10a56120035475f4cc97898d04132a78e6b637225be2a0c3d41dd4b45151796c` |
| `E:/scratch/round74-public-battle-text-green-final/isolated-9b9d249cd6a04fb08802724c1cddde79/evidence/round74_public_battle_text_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/round74-public-battle-text-green-final/isolated-9b9d249cd6a04fb08802724c1cddde79/evidence/round74_public_battle_text_test.stdout.log` | `0778c51a0b4dd171d7d6dfc9b4009e87c4addbae0f91b40ef39e954e0ec6dab4` |
| `E:/scratch/round75-banner-layer-green/isolated-3c728ddd530e4aed907f0e63e3d56515/evidence/import.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/round75-banner-layer-green/isolated-3c728ddd530e4aed907f0e63e3d56515/evidence/import.stdout.log` | `0087587e70d05d93fda73b91e66f1716bb3121dce41b35de3948ca58dccf70fa` |
| `E:/scratch/round75-banner-layer-green/isolated-3c728ddd530e4aed907f0e63e3d56515/evidence/probe.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/round75-banner-layer-green/isolated-3c728ddd530e4aed907f0e63e3d56515/evidence/probe.stdout.log` | `a30fca6df1c1941a3fc0c558596b927157ec0c8ea0a5e9731630e464f3e1a2b8` |
| `E:/scratch/round75-banner-layer-green/isolated-3c728ddd530e4aed907f0e63e3d56515/evidence/round75_banner_browser_layer_test-window.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/round75-banner-layer-green/isolated-3c728ddd530e4aed907f0e63e3d56515/evidence/round75_banner_browser_layer_test-window.stdout.log` | `9b82c9dae436bf771ffc39f70cc87f231f0c4a7c8c96334d87a1cad71ce81b8c` |
| `E:/scratch/round75-banner-layer-green/isolated-3c728ddd530e4aed907f0e63e3d56515/evidence/round75_banner_browser_layer_test.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/round75-banner-layer-green/isolated-3c728ddd530e4aed907f0e63e3d56515/evidence/round75_banner_browser_layer_test.stdout.log` | `bee8171c881ee022cbfaba0fa49b8f25f9a950f8ab8fe1080c573aa5ee428b8d` |

### 本轮执行命令（非Godot）

```text
git status --short
git rev-parse HEAD
TMPDIR=E:/scratch TEMP=E:/scratch TMP=E:/scratch PYTHONDONTWRITEBYTECODE=1 python -B tools/check_layer_deps.py --json
TMPDIR=E:/scratch TEMP=E:/scratch TMP=E:/scratch PYTHONDONTWRITEBYTECODE=1 python -B -m unittest tools.tests.test_check_layer_deps -v
```

最后gate原stdout：`{"status": "FAIL", "exit_code": 1, "root": "E:/Projects/Godot/FateDominationGame-master", "findings": 4, "allowlist": 5, "new": [], "stale": [{"rule": "private", "path": "tests/pending_board_power_test.gd", "line": 99, "target": "EffectManager._pending_announcements"}], "rules": {"layer": 4}}`。单元的真实exit1/failures4如§1；本轮没有任何游戏场景执行命令。辅助读取/hash脚本位于`E:/scratch/delivery-matrix-refresh/`，不作为长期仓库生产工具交付。

## 历史附录：刷新前矩阵全文（仅历史，不是当前状态）

> 刷新前原文SHA256：`93410d937d40ac6abf50c17554dee5fee6ef44cf66ed209033611c4be25360a7`。以下完整保留所有历史路径、hash、旧数量、旧失败和原任务缺口；**旧“当前/本次/完成”均指其原时间，不用于覆盖上文。**

<details>
<summary>展开刷新前原矩阵（完整保留历史证据引用）</summary>

# 原重构方案交付矩阵（A01–G05）

> 扫描起点：2026-10-10T14:42:43.329967；收尾首次hash重算：2026-10-10T14:53:16.046548；文档生成：2026-10-10T14:59:05.913870。源为 `E:/Projects/Godot/FateDominationGame-master` 的可变工作树，HEAD `8c0f946faf6cc0cd3f04f12f66f5a99a413088ca`，**不是冻结版、不是该提交的已提交源码、不是sourcePASS/releasePASS。**

## 1. 口径与结论

- 唯一新写入本文；原 `docs/refactoring-plan.md`（303行）与 `docs/refactoring-execution.md`（309行）只读。已重读hermesWarning与技能refactoring-gates。未运行Godot/GUI、未修改源码/tests/gate/preset/DLL、未提交。
- 原复选框只表示计划文档未同步，不表示功能未做；轮数只用于找到原件，不计完成。以当前文件/符号、真实测试源码、manifest与原stdout/stderr/结果为证据。历史docs仅索引。
- 状态：**完成**＝该原子任务自身产物/静态退休或历史基线任务已证实，不扩成当前整链通过；**实现待验**＝实现/接线存在，但当前共同依赖冻结、直接专项或窗口最低门缺；**部分**＝有实做但原结构/消费者/分类判据未闭合；**未做**＝目标实现不存在；**阻断**＝具体前置/真实红项阻止交付。未做不用于把未验冒成未实现。
- 多数实现有独立专项通过，但没有可拼成当前完整交付的同源证据，因此保守标实现待验；这不是宣称它们都坏，也不是把源码重写一遍的待办清单。
- ID程序展开核对：**126行、126唯一、缺失0、重复0**，含D02–D12/E09–E13逐项与C10a–d、D19b/D20b–d、E05b/E07b–e。A/B/C/D/E/F/G分别 8/32/19/26/20/16/5。状态：完成10、实现待验102、部分10、未做0、阻断4。数量不是完成百分比。
- 已决D1–D6、Q01–Q03不重问；默认模拟15秒、原Godot引擎与正式DLL保持。自动清理无proof应保守禁用，**不把必须启用自动清理算真人包前提**。完整重构目标仍保留F09/F15等尾项，不能未经批准自行删人测范围。
- 当前重点：D21仍28函数含network_session；D22起扫691→收尾679行仍非薄壳；F05起扫private许可46→收尾实访问42/许可46、4stale；F09仍16inline主机kind；F15完整registry/跨进程排他proof缺；G05正式同源包未验。

### 可变树的本次真实漂移（不声称冻结）

起扫1127份scripts/tools/tests .gd/.py原字节，收尾重算发现以下14份已有文件变化；另发现两个新consumer依赖后定点读取。对board/presenter、bootstrap/console、cleanup executor及release工具已重读差异并更新矩阵。测试/执行器漂移不自动继承旧PASS。此表只描述两次观测，后续actor仍可继续写。

| 文件 | 起扫SHA256 | 收尾已读SHA256 | 行数变化 |
|---|---|---|---|
| `scripts/game_scene/battle_board_v2.gd` | `e72859ee5807c3dbd533507392633dca6234ca19142e669d847b125ee09df709` | `43b7be1d30dd785dbc3ef5cde0f02bed50e75f939944d0f64e08f1afc2007906` | 6631→6638 |
| `scripts/net/server/server_bootstrap.gd` | `77b86fec2477de5ccddcd8e95cc6556cbadf872b67f5b4eca1d251a68be2f56b` | `6dbf5dfda785de5b11cab76f01e725317821eff51be37a4fbfba4bae5e978a3b` | 229→227 |
| `scripts/net/server/server_console_channel.gd` | `9eea95ad15fc0f4e04c3d9edfe0071a523e1f44a23558b324ceab818de16da02` | `afbfd5a071a2fcb062555f00fcd9ac08dbe476a04ad3fd6efc2c7142373af3c3` | 436→431 |
| `scripts/net/server/temporary_cleanup_executor.gd` | `e11bf2d764b9c43a89795152623ededc23d654ee0878d8b087b6c09beadf58a0` | `2619e8131365435a27f2862a86588aa55b7defa4e592e9bf8e2617a4a3c4acea` | 36→66 |
| `scripts/net/ui/v2_view_presenter.gd` | `7b6dfe7d484a3eb5a6482df9f25fcc0b9df50d21bce3c5d5dc65370fd36bf966` | `dff5b30f48655ad8637218d082717df0da6a543cad37fd643fe35f2d8b259a6e` | 691→679 |
| `tools/diagnostics/round63_observer_lock_contract.py` | `fb6a2c046ea3ec507351d7f21ea5019e136371135e9106e0565f02115df08153` | `784d55678147ed59c2eaf5250e8053c92f4d427f3586a26f7e8d29daa119031d` | 504→533 |
| `tools/diagnostics/round63_observer_lock_contract_test.py` | `efac66d1568b0eafef53bbb36c758815fac5f3e9622d78319e8f5a43fbf095ac` | `5196af8bd56a28c6ee40ead0dfc5b7e1faf5c91a1a2d435f592489fdd09bfb2e` | 27→37 |
| `tools/release/round56_three_role_freeze.py` | `1672aace0cef562147debb849550957810182dece543b62eac592016d17bad38` | `38eee23540bcfb09dfd7dcb008e6d1c1b8a7943f236347f5d95a6a010695880a` | 392→736 |
| `tools/tests/test_round29_integrated_evidence.py` | `1e5ce1951af672673d90ace71482057369d199bfca490a75ab79e6c18f3d44cc` | `36454654c09bbb078af6a044f044c9d0924cc53f3c7307d42e417a23bca3d054` | 3299→3468 |
| `tools/tests/test_round50_candidate_selection.py` | `f77319517aeed0ed5eaef9eff62957955b300e6abe6d1dedd94177f97a66dc0a` | `b57a8c0418e7b0e8c194f5a2cb5a2ca850fc25c1fbc7fe3c16ee47afd227e254` | 308→308 |
| `tools/tests/test_round64_release_runtime_entry.py` | `7b32bd1d7e2d5e86e9cbe78433ccfaf3a7587be4eb083554d6de2e4bccee7b59` | `cd31b89c339184767ad7746ee5c7e838cac653ee7bae1ea8c836693b313d4b28` | 18→116 |
| `tests/audit_commit_test.gd` | `e0c428e778e73ba76f47edc7800d74c49fc145d4e2dfef4afd8a61c43f99c251` | `8314b5f395fc10754aef482f174a5256aec31cbf6ec0454be0f909a333af8fa7` | 159→160 |
| `tests/battle_play_groups_test.gd` | `5ba88f8f4b24186149300e5c8d38102cd28c3d16bf689640d48943c61e718a03` | `7d45aef748fc024fbfc11f12d09ce7202b0550fd518d72bf13a34dfdb84f30c6` | 290→317 |
| `tests/deferred_transaction_facts_test.gd` | `81e7ce581c630efc61b121ad775070cbfe896384a0bd6c1248ccb78115f5f8d1` | `a162839e178649913bd8eb898e5fdcd2df5f907a04a30a6d09862680b60ca7dc` | 152→153 |

- 起扫gate：50 findings=layer4+private46，50许可，NEW0/STALE0。收尾gate：46 findings=layer4+private42，50许可，NEW0/STALE4，**当前gate未绿**。stale为audit_commit_test的_begin_guard_transaction/_release_guard_transactions与deferred_transaction_facts_test的_queue_time_point_batch/_release_guard_transactions各1条。应由唯一gate写者读当前锚点后退休，本轮不改gate。
- bootstrap四条是原plan明确允许的组合根路由，不要求删除；其源码抽取native方法声明不是新增UI反向依赖。
- 新 `native_method_contract.gd` 只集中原四类13方法最低合同，不授registry/清理能力；新 `temporary_cleanup_native_delete.gd` 为显式可选删除能力，当前ledger未注入，默认拒绝不变。

## 2. 真实原件、来源指纹与结果（分冻结，不串PASS）

以下manifest已直接读取并算原字节SHA；E58声明1270份日志/归档摘要和E60-fixture的24份摘要逐项读回均相等。另实际读取各scope的stdout/stderr，E62expectednegative两场13条ERROR是精确故障检出证据，不是生产ERROR豁免。**本文没有重跑旧专项**。

| 证据ID | 原件路径 | SHA256 | 真实范围/结果 |
|---|---|---|---|
| E58 | `E:/scratch/isolated-1105873e41cd4f6a94a999e65ac6af50/manifest.json` | `d439e06fd4a92592211d306dfa292ba2af90c04c699bdd3fb52ee19b5bcc85b4` | 原完整headless98 executed/unique98，pass87/strict86/red11；RESULT声明checks5542，实际CHECK5455；sourcePASS/releasePASS=false。日志相对evidence/complete-<suite>.stdout.log及.stderr.log。 |
| E60-fixture | `E:/scratch/round60-fixture-f8a66eb3fde84cabb78eae5ee64eb735/manifest.json` | `5e156b65d75419aa423fba7b2d9159a001b9ebd55e52eff15f1b417e86a582c2` | 六命令/待答生命周期专项passed=true，46+74+21+65+37+65=308；原六RED保留；evidence/<suite>.stdout.log。生产复用原路径但不是整树同冻结。 |
| E60-groups | `E:/scratch/round60-play-groups-final/isolated-712950fb4ee8428f99c67381c531b90c/manifest.json` | `74f08007985f83c6ee0673bfd0294453c071259fd1ca2cf8faad3ba9181f2d01` | 真实headless56/window58、空失败；完整四组可见画面仍未验收。evidence/headless.stdout.log与window.stdout.log。 |
| E61-resource | `E:/scratch/round61-resource-proof-486a085c8e55481eb659d22b62f13990/isolated-4c99f2d34a8648169e9acb80e4e053ba/manifest.json` | `158e65ae2a0bd45a5dddbab95886aa8429e0aabcab99b1323d4a76160362f6d5` | relay22 exit0，worker45属prerequisite另账；resource_proof_passed=true、完整candidate passed=false。不算已重验98套累计。 |
| E62-loader | `E:/scratch/isolated-da02984e532f43a08e445aca142ddebb/manifest.json` | `435f93e9bfe5a2b032b6ec1611907ab54e3a1d12fc28d25d3e2d4a798b1116a6` | 七模式最终原件：62/9/9/45/30/34/21合计210，passed=true；expectednegative_extra底层拒额外ERROR，外层验证检出。204 child场关闭模拟，不能冒原15秒完整性能链。 |
| E62-recover | `E:/scratch/isolated-7ee7ee28648c4e36a3b71869a8234316/manifest.json` | `645697d418d79b1ea18d1310d14eb9558d221490c1312968adda28cb26e79fb9` | restart唯一runs1、exit1、checks51/4失败；root/worker trace保留；恢复first-cancel原生peer_disconnected→锁存取消→fail-closed，根因仍unknown。 |
| GUI55 | `E:/HermesScratch/round55-gui-first-divergence/final-ef684b20cc224fc3a049d90caac1209e/manifest.json` | `8a808a1097a1aab665a3632d2298e2a3216388a9e4d64f4b309c59ef1626b266` | 原同冻结非headless host16/3失败、net57/0、countdown72/0；不是currentUIchainGREEN，不借前host17补绿。 |
| PKG52 | `E:/FateCandidates/round52-current-roles-20261010-sa1/manifest.json` | `5a6f9013bbb09a29798a12b999ca1428222f0e3c061f1caf7fd005c0b72230f0` | TWO_CURRENT_ROLE_ARTIFACTS_AVAILABLE_SIGNALING_COLD_FAILED_STOPPED；仅两游戏角色，signal首次cold失败停，无最终三角色同源包。 |
| PKG54-runtime | `E:/Caches/Hermes/cache/scratch/round54-packaged-protocol-first-worker-sa3/actualruntime.json` | `145bf48d45450c5269a1a01ec99beed0063d16cbc408a713f5dfb6d79f81646f` | BLOCKED_GATEWAY_STOP_AFTER_SAVED_LOBBY_NATIVE_RELEASE；真实RSA/editor客户端→READY→空大厅save/EXITED/release，gateway stop真实失败，旧28100保留，非正式两client开局证明。 |
| N59 | `E:/FateDiagnostics/round59-native-runtime-20261010-3/metadata.json` | `ca2a0f0b59c1dc864fa07780a0dc0d1d2c51fbce07d9be579fcf88842410b9ae` | 隔离DLL source→DLL构建来源metadata；候选DLL9c14...不等于正式DLL92a4...，不授自动清理。 |
| N59-functional | `E:\FateDiagnostics\round59-native-runtime-20261010-3\functional.json` | `0a81a3398903b33f1e81ec068c81e0463852b73415a0ce5c8c126a4daf6e7588` | 隔离native功能原件；checks数组包含实际ok项和真实SKIP，应分账；不是生产部署。 |
| N59-result | `E:\FateDiagnostics\round59-native-runtime-20261010-3\result.json` | `39cb2647ddf037e491b67354ce8bc869f4469a5429ea8c6fd3461e953c4ad814` | ok=true、not_production_package=true、no_automatic_cleanup_green=true；隔离原生验收不算F15整链。 |

### 原冻结与本扫描比较

下面计数仅比较每份manifest声明中与起扫1127份.gd/.py交集的原字节SHA，**不是其全部物理依赖集合**。初扫相等不替后续漂移复验；收尾14变化表优先，不把E62初扫相等冒当前冻结。

| 原件 | 起扫交集相等 | 起扫交集漂移 | 生产GD漂移 |
|---|---:|---:|---|
| E58 | 531 | 14 | `scripts/system/global/load_game.gd`、`scripts/net/validation/room_data_validation_worker.gd` |
| E60-fixture | 418 | 2 | `scripts/net/validation/room_data_validation_worker.gd`、`scripts/system/global/load_game.gd` |
| E60-groups | 410 | 2 | `scripts/net/validation/room_data_validation_worker.gd`、`scripts/system/global/load_game.gd` |
| E61-resource | 415 | 2 | `scripts/net/validation/room_data_validation_worker.gd`、`scripts/system/global/load_game.gd` |
| E62-loader | 418 | 0 | 无（仅此初扫交集） |
| E62-recover | 423 | 0 | 无（仅此初扫交集） |

- E58两生产漂移是新loader与validation worker，另12份测试漂移；六夹具/出牌组/relay后续专项只能解决各自旧项，不把它们加回E58生成新的“完整PASS”。
- E62-loader在其scope正确化缺roster扫描报告/环境还原，但不能消除E58pipeline发布失败、shutdown新实例写入失败、恢复断线或窗口缺口。
- 旧baseline初始采集与golden不是现代冻结证据：baseline-headless.json SHA `a69616cf51b8294c78b9a8b0e324ad30918720fb38eab477c29fa07973c47981`；六窗口原件 `reports/refactoring/window-logs/first-run/baseline-window.json`，顶层同名只一套，不代它。A06/A07在E58选集未执行，历史文字摘要仅索引。
- G01真实旧candidate package-client.json SHA `ebf472660e583ef0fe3b642b8d03637bba984804fba2efd4e66e47128e5886df`、package-server.json SHA `59716271668e06bca812a1983aacd698d7b4a5fd01d1a180dfc327a0a429c315`，各PCK索引1095项且无_mcp_game_helper/godot_ai文件名、blockers=[]；仍是旧包的静态检查，不覆盖新源。
- 原正式DLLSHA `92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd`。新候选native9c14...与正式库分账。

## 3. A01–G05逐项交付矩阵

表内文件为当前已读源码定位；全部SHA在§6。测试简称按 `tests/<简称>_test.gd/.tscn` 定位，已含 `_test` 的名字不再追加。`-- window`仅指场景自己的窗口分支，countdown正式config分支须按原manifest入口，不机械拼同一参数。

最低复验由下一获准执行者在物理E自有隔离工程执行：保持原引擎/DLL、`--fixed-fps 60`、完整stdout/stderr、精确退出码/RESULT、parent/child错误、Job/原回执归档；普通 `--headless --path <freeze> --scene res://tests/<name>.tscn`，窗口去headless并用真实输入/原生画面。不是调用原plan中只过滤RESULT的管道。对实现待验先复验接线，不因未勾选重复重写。

### A 批

| ID | 状态 | 当前文件/符号 | 已读实现与原件证据 | 待验最低动作/交接 |
|---|---|---|---|---|
| A01 | 完成 | `tools/check_inventory_drift.py:54::compare` | 原 `reports/refactoring/baseline.txt` 记录383/383、new/gone/drift空及HEAD；这是一开始的基线，不是当前无漂移。 | 无基线补造；以后迁移按本矩阵hash定位，不更新旧inventory抹漂移。 |
| A02 | 完成 | `tools/run_refactor_headless_baseline.py:1` | 原baseline-headless.json实际24/24、21绿3红；逐红字段记录net_pending绑定缺失、net_cards JSON类型、mana退出资源残留。 | 原基线任务已做；最终候选改用当前选集，不再重做初始基线。 |
| A03 | 完成 | `tools/run_refactor_window_baseline.py:1` | 原window-logs/first-run/baseline-window.json六套真实exit0，checks14/50/62/57/30/34；area截图写失败保留为红，非六套全绿。顶层baseline-window.json只一套，不能以它计全量。 | 保留初始基线；当前窗口按D15/D20b/C10d验收，不借无源码hash历史GUI。 |
| A04 | 实现待验 | `tools/check_layer_deps.py:245::scan` | 起扫layer4/NEW0/STALE0；收尾生产路由仍4，但测试actor移走4访问令整体gate STALE4，当前门不能报告PASS。 | 唯一gate写者核对audit_commit/deferred_transaction_facts共4消失锚点并退休；跑gate+自身单测，bootstrap4保留。 |
| A05 | 实现待验 | `tools/check_layer_deps.py:300::evaluate` | 起扫private findings46/许可46；收尾实际42/许可46，生产私有0，4 stale（非生产回潮），不把未退休许可当当前PASS。 | 按F05精确退休4测试锚点后同冻结gate；其它测试/诊断许可不为数字强删。 |
| A06 | 实现待验 | `tests/refactor_text_golden_test.gd:73::run` | 原text.json与capture/compare测试存在；历史text-golden.md仅索引；E58选集没有此测试，不冒历史日志摘要为当前PASS。 | 同冻结compare原text golden，保存原stdout/RESULT；不重新capture吞差异。 |
| A07 | 实现待验 | `tests/refactor_area_golden_test.gd:143::run` | 原areas.json与自然终局/锁样本测试存在；历史记录272步/11回合不充抵当前；E58未选此测试。 | 同冻结compare到自然终局；隔离预期突变须红→恢复绿，不改共享生产。 |
| A08 | 完成 | `tests/refactor_build_cost_probe.gd:1` | 原build-cost-exclusive.log及build-cost.json；实际每阶段/席位100次采样实现存在。C01采纳是已决性能策略，不是本次长局性能PASS。 | 不重复无收益微优化；C09验证同刷新build一次/显式invalidate及视角隔离。 |

### B 批

| ID | 状态 | 当前文件/符号 | 已读实现与原件证据 | 待验最低动作/交接 |
|---|---|---|---|---|
| B01 | 实现待验 | `scripts/system/area_action_rules.gd:35::block_reason` | 七职责公开静态函数全部存在；E58 area专项未列入。 | 解析AREA并compare A07，保持MoveLocation原operation不改。 |
| B02 | 实现待验 | `scripts/game_scene/tactical_board_ui.gd:3146::area_action_block_reason_for`; `scripts/game_scene/tactical_board_ui.gd:3132::_estimate_move_cost` | 七旧签名均转发AREA；旧UI仍是测试兼容壳。 | A07 + area_lock_window + misc_rules_fix；确认旧签名调用不变。 |
| B03 | 实现待验 | `scripts/match/match_driver.gd:1` | 当前driver引用AreaActionRules，反向UI层许可已退休；gate生产无此finding。 | match_driver_headless + A07，绑定driver/AREA/source hash。 |
| B04 | 实现待验 | `scripts/net/authority/match_authority.gd:593::pending_for`; `scripts/net/authority/match_authority.gd:282::_submit` | AREA现由QUERY/DISP使用；AUTH无旧LocationQuery。E58 net_move11/net_locations7/net_pending20空失败，仅原冻结。 | 当前同冻结重跑这三专项，确认位置入口仍经dispatcher。 |
| B05 | 实现待验 | `scripts/game_scene/battle_board_v2.gd:1` | board现AreaActionRules.block_reason；不再TacticalBoardUI。 | 真实area_lock_window -- window，读可见拒绝文案。 |
| B06 | 实现待验 | `scripts/game_scene/battle_board_v2.gd:1`; `scripts/system/area_action_rules.gd:125::first_effect_location_target` | board直接调用AREA估费/落点；E58 board53绿，bellerophon不在选集。 | board + bellerophon_edges，同冻结验证常规/效果移动。 |
| B07 | 实现待验 | `scripts/debug/debug_adapters/debug_map_adapter.gd:1` | 当前56–58直接估费并返回“魔力不足”；tests/debug_console_test.gd存在对应断言。E58未选。 | debug_console零魔力移动明确拒绝，并检查扣费前拒绝；需要原RED→GREEN原件而非只说新增测试。 |
| B08 | 实现待验 | `scripts/ui/text/card_desc_text.gd:1` | 独立CardDescText含shown_name/card_desc/token_desc及两常量。 | 解析 + A06 compare；测试本人/公开卡授权先于格式化。 |
| B09 | 实现待验 | `scripts/ui/text/cost_text.gd:1` | effect_cost_items/attach_line存在；格式化与规则执行分离。 | 解析 + A06费用空串/前导换行compare。 |
| B10 | 实现待验 | `scripts/ui/text/game_log_text.gd:7::line` | 独立日志格式化已存在且姓名走EffectManager；临时名字副本已撤。 | A06 compare全部日志及胜者文案差异审阅，不重新capture。 |
| B11 | 实现待验 | `scripts/ui/text/choice_text.gd:1`; `scripts/game_scene/native_choice_renderer.gd:1` | ChoiceText.card_confirm存在，native renderer复用；历史window50非当前。 | native_choices_window -- window，真实card-confirm文本/点击。 |
| B12 | 实现待验 | `scripts/game_scene/tactical_board_ui.gd:2727::_build_card_desc`; `scripts/game_scene/tactical_board_ui.gd:3776::_resolve_effect_cost_items`; `scripts/game_scene/tactical_board_ui.gd:4637::_format_game_log_line` | 旧UI文字函数转发，常量别名存在。 | A06 + reported_ui + number_display，保留小数/整数显示合同。 |
| B13 | 实现待验 | `scripts/match/view_builder.gd:343::card_view`; `scripts/match/view_builder.gd:222::public_log` | 无旧CardText预加载；CardDescText/CostText/GameLogText消费在公开投影。E58 match_view226/privacy137绿。 | 当前match_view/privacy及A06，确保隐私授权不下放文本模块。 |
| B14 | 实现待验 | `scripts/match/match_seat_query.gd:15::_card_choice_confirm_text` | 原AUTH私有正文已随C04迁QUERY，调用ChoiceText.card_confirm，许可退休。 | net_pending，核对真实秘密选择确认文本。 |
| B15 | 实现待验 | `scripts/match/match_seat_query.gd:22::pending` | pending费用文本走CostText.attach_line/effect_cost_items；AUTH旧UI引用已退休。 | net_pending + native_choices_window -- window。 |
| B16 | 实现待验 | `scripts/game_scene/battle_board_v2.gd:1` | board卡/BUFF/费用/日志使用独立文本（D迁移后部分改view）而不是旧UI。 | board + native_choices_window -- window；核对显示不重算隐私数据。 |
| B17 | 完成 | `scripts/game_scene/battle_board_v2.gd:1` | 本次源码检索TacticalBoardUI引用0、const0；gate无board旧依赖。只完成移除该const的静态要求。 | 最终解析board，不借本项宣称统一UI已完成。 |
| B18 | 实现待验 | `scripts/system/global/game_data_manager.gd:32::find_player_data` | find_player_data仅get(id,{})，get_player_data创建入口保持。 | player_query_purity，对不存在玩家keys前后相等。 |
| B19 | 实现待验 | `tests/player_query_purity_test.gd:1` | keys不变反例测试存在；不是初始未勾选=未写。E58未列此测试。 | 当前公开find/build/name/block_reason四入口纯度专项。 |
| B20 | 实现待验 | `scripts/system/area_action_rules.gd:35::block_reason` | find_player_data且空数据返回玩家不存在。 | player_query_purity + A07，保留原有效玩家语义。 |
| B21 | 实现待验 | `scripts/game_scene/battle_board_v2.gd:1` | board读取已迁find/source；原handwritten has-get模式不作完成凭据。 | board未知玩家/观战座位纯度。 |
| B22 | 实现待验 | `scripts/system/global/effect_manager.gd:671::player_shown_name` | 姓名查找find且未知玩家返回“玩家 %d”，不创建。 | player_name + player_query_purity，存在/缺失两方向。 |
| B23 | 实现待验 | `scripts/net/authority/match_authority.gd:282::_submit`; `scripts/match/match_seat_query.gd:90::actions`; `scripts/match/match_command_dispatcher.gd:29::_dispatch` | AUTH已抽离读取到QUERY/DISP，find接口覆盖规则查询/座位拒绝。E58三个net专项原冻结绿。 | net_move/net_cards/net_authority_ui_preview_feedback当前同冻结复验。 |
| B24 | 部分 | `tools/classify_player_data_calls.py:311::build_report` | 落盘358调用分类已过期；本次只读重算397：只读28/需创建1/未知368，scripts176且未知148。unknown保留，不伪称已全分类。 | 唯一工具写者按当前源码/初始化调用链逐个补语义分类；operations本批不动，先交148个生产未知的精确清单。 |
| B25 | 完成 | `tests/player_shown_name_golden_test.gd:1` | 原docs/refactoring-golden/player_names.json真实72条旧实现结果仍在；现测试明确never recaptured并逐项审阅D5变化。差异产物任务已完成。 | 保留旧golden；B26验证统一口径，不再询问D5。 |
| B26 | 实现待验 | `scripts/system/global/effect_manager.gd:671::player_shown_name`; `scripts/ui/text/game_log_text.gd:7::line` | has→find；get_shown_name→_name→“玩家 %d”，日志无私有姓名副本。 | player_shown_name_golden + A06 + player_name，所有批准差异逐条记录。 |
| B27 | 实现待验 | `scripts/system/global/game_progress.gd:207::end_game` | game_progress私有姓名壳已随B32删除，直接调用EM。 | turn_order/player_name，胜者通知未知ID不创建玩家。 |
| B28 | 实现待验 | `scripts/system/global/climax_resolver.gd:1` | climax直接EM，无旧创建副作用姓名壳。 | climax_elimination + purity。 |
| B29 | 实现待验 | `scripts/game_scene/tactical_board_ui.gd:4898::_player_shown_name_by_id` | 旧静态姓名函数只转发EM。 | A06 + player_shown_name_golden。 |
| B30 | 实现待验 | `scripts/game_scene/tactical_board_ui.gd:3480::_player_shown_name` | 旧实例姓名转发EM，回退“玩家%d”→“玩家 %d”是批准可见变化。 | reported_ui，明确无空格旧文案差异，不用静态grep替代可见文本。 |
| B31 | 实现待验 | `scripts/game_scene/battle_board_v2.gd:678::_player_name` | 已进入D后续目标：从source.players读取，不在网络读取规则全局。 | board + 顶栏/横幅/战果榜实际窗口名字检查。 |
| B32 | 完成 | `scripts/system/global/game_progress.gd:1`; `scripts/system/global/climax_resolver.gd:1` | 两文件私有_player_shown_name定义/调用均0，直接统一EM；这是删壳静态任务完成。 | B27/B28行为证据另验，不复造兼容壳。 |

### C 批

| ID | 状态 | 当前文件/符号 | 已读实现与原件证据 | 待验最低动作/交接 |
|---|---|---|---|---|
| C01 | 完成 | `scripts/game_scene/battle_io/local_battle_source.gd:27::invalidate`; `scripts/game_scene/battle_board_v2.gd:610::refresh_all_ui` | 采用显式invalidate+同刷新复用，已决。原28组2800样本仅原基准；不是粗略状态key全局缓存。 | C09单周期构建次数/视角切换专项，actions/pending不得缓存成合法性结论。 |
| C02 | 部分 | `tools/list_presenter_private_access.py:258::build` | 四类工具存在但原plan附录仍空；落盘68成员124引用绑定旧hash，本次词法57成员86引用，不能引用原75/177作当前数字。 | 唯一文档/工具写者按当前hash刷新四类与退休锚点，勿覆盖别人的plan。 |
| C03 | 实现待验 | `scripts/system/global/effect_manager.gd:1932::is_card_selection_valid`; `scripts/system/global/effect_manager.gd:799::location_option_origin_allowed` | 公开包装及AUTH/DISP消费；许可已退休；E58直接专项有原冻结PASS。 | net_pending 当前同冻结复验，保留peer/seq/审计边界。 |
| C04 | 实现待验 | `scripts/match/match_seat_query.gd:22::pending`; `scripts/net/authority/match_authority.gd:593::pending_for` | AUTH仅observer/started门后QUERY.pending；ChoiceText/成本/落点声明已迁；E58直接专项有原冻结PASS。 | net_pending + net_locations 当前同冻结复验，保留peer/seq/审计边界。 |
| C05 | 实现待验 | `scripts/match/match_seat_query.gd:90::actions`; `scripts/net/authority/match_authority.gd:620::actions_for` | 座位actions与flip_modes抽离AUTH；E58直接专项有原冻结PASS。 | net_cards + net_move 当前同冻结复验，保留peer/seq/审计边界。 |
| C06 | 实现待验 | `scripts/match/match_seat_query.gd:54::preview`; `scripts/net/authority/match_authority.gd:600::preview_group` | seq/id门留AUTH，合法性/费用preview在QUERY；E58直接专项有原冻结PASS。 | net_authority_ui_preview_feedback 当前同冻结复验，保留peer/seq/审计边界。 |
| C07 | 实现待验 | `scripts/game_scene/battle_io/local_battle_source.gd:1` | read_view缓存副本，invalidate/refresh/set_seat与actions/pending/preview公开入口存在。 | battle_source_adapter + player_query_purity；同刷新build一次、观察者隔离。 |
| C08 | 实现待验 | `scripts/game_scene/battle_io/network_battle_source.gd:1` | 读取session match/actions/pending并转changed；不执行规则。 | battle_source_adapter，close/reconnect后断旧信号并清视图。 |
| C09 | 实现待验 | `scripts/game_scene/battle_board_v2.gd:315::_ready`; `scripts/game_scene/battle_board_v2.gd:610::refresh_all_ui` | ready一次选择source，生产渲染已实际消费，不仅骨架；E58 board53，历史GUI55不替当前。 | board + net_v2_browsing -- window + build计数/视角专项。 |
| C10 | 实现待验 | `scripts/game_scene/battle_board_v2.gd:3030::_fill_buff_rows`; `scripts/match/view_builder.gd:264::buff_views` | BUFF只Dictionary；本地/网络都view，源码中无BaseBuff双渲染分支。 | C10a–d合并同冻结验收，特别说明文本与本方/对手隐私。 |
| C10a | 实现待验 | `scripts/match/view_builder.gd:264::buff_views` | card子投影含description/image/zoom_kind/visible/concealed，BUFF active独立字段。 | match_view_privacy，非本人隐藏与本人内容齐全。 |
| C10b | 实现待验 | `scripts/game_scene/battle_board_v2.gd:2966::_bind_ops`; `scripts/game_scene/battle_board_v2.gd:3030::_fill_buff_rows`; `scripts/net/ui/v2_view_presenter.gd:212::refresh` | board/presenter调用传view.buffs，不再BaseBuff数组。 | board + shared-presentation，记录两调用输入真实类型。 |
| C10c | 完成 | `scripts/game_scene/battle_board_v2.gd:3030::_fill_buff_rows` | 函数仅接受Dictionary投影并跳过非Dictionary；BaseBuff分支0。 | C10d保留真实窗口，不把删分支算整体显示验收。 |
| C10d | 实现待验 | `tests/battle_board_v2_test.gd:1`; `tests/refactor_text_golden_test.gd:1` | E58 board53 PASS，但A06不在选集，当前BUFF窗口未同源验收。 | board+A06；本方与对手BUFF悬浮逐字检查，非headless。 |
| C11 | 实现待验 | `scripts/game_scene/battle_board_v2.gd:1646::_bind_situation_and_piles` | 扫描内actor把事件弃牌来源浏览移至board._open_event_discard(source.event_discard_by_source)，presenter两函数撤；起扫与收尾hash均记录，未验新变化。 | board+net_v2_browsing窗口：分类/标题/开合、隐私/顺序及旧调用消失；只认迁移后hash证据。 |
| C12 | 实现待验 | `scripts/game_scene/battle_board_v2.gd:954::_bind_sigils`; `scripts/game_scene/battle_board_v2.gd:2321::_bind_self` | 资源/令咒由view声明；E58shared_spell_view87/mirror73绿 | board+shared_spell_view+mirror负向，并看资源/自定义令咒图；最终同冻结gate。 |
| C13 | 实现待验 | `scripts/game_scene/battle_board_v2.gd:1168::_bind_rivals`; `scripts/game_scene/battle_board_v2.gd:1175::_bind_rival_order` | common顺位控制复用节点，presenter只调board；E58shared-presentation142绿 | 重复刷新instance_id相等且不重播动画；browsing窗口；最终同冻结gate。 |
| C14 | 实现待验 | `scripts/game_scene/battle_board_v2.gd:1092::_bind_shared_phase_view`; `scripts/game_scene/battle_board_v2.gd:5672::_bind_residue_entries` | shared timeline/residue已消费view；仍有network布尔及阶段回调差异，不冒D21完成 | shared-presentation+net_v2_residue_phase窗口，阶段清理/残留复用；最终同冻结gate。 |
| C15 | 实现待验 | `scripts/game_scene/battle_board_v2.gd:2066::_bind_strips`; `scripts/game_scene/battle_board_v2.gd:5736::_bind_groups` | areas/location.players/played减residue统一绑定；E60-groups56/58专项有原件但完整画面未验 | net_v2_area窗口，正常process飞牌、扇形展开/收拢中间帧及四组完整可见；最终同冻结gate。 |

### D 批

| ID | 状态 | 当前文件/符号 | 已读实现与原件证据 | 待验最低动作/交接 |
|---|---|---|---|---|
| D01 | 实现待验 | `scripts/match/match_command_dispatcher.gd:29::_dispatch`; `scripts/net/authority/match_authority.gd:282::_submit` | 当前dispatch有 `set_concealed` 校验/执行；AUTH保留peer、seq、管理/guard门。E58 dispatcher313及net_cards有真实原冻结结果，不按kind数量冒完成。 | 当前dispatcher+net_cards专项；set_concealed参数/座位/拒绝无副作用正反例。 |
| D02 | 实现待验 | `scripts/match/match_command_dispatcher.gd:29::_dispatch`; `scripts/net/authority/match_authority.gd:282::_submit` | 当前dispatch有 `cancel_choice` 校验/执行；AUTH保留peer、seq、管理/guard门。E58 dispatcher313及net_pending有真实原冻结结果，不按kind数量冒完成。 | 当前dispatcher+net_pending专项；cancel_choice参数/座位/拒绝无副作用正反例。 |
| D03 | 实现待验 | `scripts/match/match_command_dispatcher.gd:29::_dispatch`; `scripts/net/authority/match_authority.gd:282::_submit` | 当前dispatch有 `location_choice` 校验/执行；AUTH保留peer、seq、管理/guard门。E58 dispatcher313及net_locations有真实原冻结结果，不按kind数量冒完成。 | 当前dispatcher+net_locations专项；location_choice参数/座位/拒绝无副作用正反例。 |
| D04 | 实现待验 | `scripts/match/match_command_dispatcher.gd:29::_dispatch`; `scripts/net/authority/match_authority.gd:282::_submit` | 当前dispatch有 `activate` 校验/执行；AUTH保留peer、seq、管理/guard门。E58 dispatcher313及net_pending有真实原冻结结果，不按kind数量冒完成。 | 当前dispatcher+net_pending专项；activate参数/座位/拒绝无副作用正反例。 |
| D05 | 实现待验 | `scripts/match/match_command_dispatcher.gd:29::_dispatch`; `scripts/net/authority/match_authority.gd:282::_submit` | 当前dispatch有 `player_choice` 校验/执行；AUTH保留peer、seq、管理/guard门。E58 dispatcher313及net_pending有真实原冻结结果，不按kind数量冒完成。 | 当前dispatcher+net_pending专项；player_choice参数/座位/拒绝无副作用正反例。 |
| D06 | 实现待验 | `scripts/match/match_command_dispatcher.gd:29::_dispatch`; `scripts/net/authority/match_authority.gd:282::_submit` | 当前dispatch有 `card_choice` 校验/执行；AUTH保留peer、seq、管理/guard门。E58 dispatcher313及net_pending有真实原冻结结果，不按kind数量冒完成。 | 当前dispatcher+net_pending专项；card_choice参数/座位/拒绝无副作用正反例。 |
| D07 | 实现待验 | `scripts/match/match_command_dispatcher.gd:29::_dispatch`; `scripts/net/authority/match_authority.gd:282::_submit` | 当前dispatch有 `option_choice` 校验/执行；AUTH保留peer、seq、管理/guard门。E58 dispatcher313及net_pending有真实原冻结结果，不按kind数量冒完成。 | 当前dispatcher+net_pending专项；option_choice参数/座位/拒绝无副作用正反例。 |
| D08 | 实现待验 | `scripts/match/match_command_dispatcher.gd:29::_dispatch`; `scripts/net/authority/match_authority.gd:282::_submit` | 当前dispatch有 `active_choice` 校验/执行；AUTH保留peer、seq、管理/guard门。E58 dispatcher313及net_pending有真实原冻结结果，不按kind数量冒完成。 | 当前dispatcher+net_pending专项；active_choice参数/座位/拒绝无副作用正反例。 |
| D09 | 实现待验 | `scripts/match/match_command_dispatcher.gd:29::_dispatch`; `scripts/net/authority/match_authority.gd:282::_submit` | 当前dispatch有 `move` 校验/执行；AUTH保留peer、seq、管理/guard门。E58 dispatcher313及net_move有真实原冻结结果，不按kind数量冒完成。 | 当前dispatcher+net_move专项；move参数/座位/拒绝无副作用正反例。 |
| D10 | 实现待验 | `scripts/match/match_command_dispatcher.gd:29::_dispatch`; `scripts/net/authority/match_authority.gd:282::_submit` | 当前dispatch有 `play_group` 校验/执行；AUTH保留peer、seq、管理/guard门。E58 dispatcher313及net_cards有真实原冻结结果，不按kind数量冒完成。 | 当前dispatcher+net_cards专项；play_group参数/座位/拒绝无副作用正反例。 |
| D11 | 实现待验 | `scripts/match/match_command_dispatcher.gd:29::_dispatch`; `scripts/net/authority/match_authority.gd:282::_submit` | 当前dispatch有 `end_action` 校验/执行；AUTH保留peer、seq、管理/guard门。E58 dispatcher313及net_pending有真实原冻结结果，不按kind数量冒完成。 | 当前dispatcher+net_pending专项；end_action参数/座位/拒绝无副作用正反例。 |
| D12 | 实现待验 | `scripts/match/match_command_dispatcher.gd:29::_dispatch`; `scripts/net/authority/match_authority.gd:282::_submit` | 当前dispatch有 `deploy` 校验/执行；AUTH保留peer、seq、管理/guard门。E58 dispatcher313及net_locations有真实原冻结结果，不按kind数量冒完成。 | 当前dispatcher+net_locations专项；deploy参数/座位/拒绝无副作用正反例。 |
| D13 | 实现待验 | `scripts/game_scene/battle_io/local_battle_commands.gd:55::submit`; `scripts/game_scene/battle_board_v2.gd:5488::_run_battle_command` | local同步dispatch后result(request_id,ok,reason)；桥内13个MatchCommands执行原语是真正执行端，不是UI绕过。E58adapter29 PASS。 | adapter专项；submit前关联、同步回执早于返回、拒绝不扣费。 |
| D14 | 实现待验 | `scripts/game_scene/battle_io/network_battle_commands.gd:20::submit`; `scripts/net/session/lobby_session.gd:1` | 真正request_completed协议已存在，不再仅把request_rejected当完成；E58protocol39 PASS。 | protocol+adapter：close/reconnect代际、unknown、不自动重发、同号旧回执不结算新请求。 |
| D15 | 部分 | `scripts/game_scene/battle_board_v2.gd:5452::_submit_battle_command`; `scripts/game_scene/battle_board_v2.gd:5488::_run_battle_command`; `scripts/net/ui/v2_view_presenter.gd:547::card_input`; `scripts/net/ui/v2_view_presenter.gd:636::confirm_area`; `scripts/net/ui/network_choice_panel.gd:1` | board桥外旧_commands调用0、桥内13；presenter.card_input翻面与confirm_area战区、panel._send_choice仍直发session.match_command，非全交互共同commands。扫描内presenter691→679，仅事件弃牌迁出；E60六夹具308绿只属headless命令专项。 | 唯一BB/PR/panel写者迁翻面、部署/移动和网络待答到共同commands；保留确认seq、真实完成回执、取消独立语义；两模式真实连续点击/拒绝窗口。 |
| D16 | 实现待验 | `scripts/game_scene/battle_board_v2.gd:2847::_held_card_playable`; `scripts/game_scene/battle_board_v2.gd:2522::_held_playable_signature`; `scripts/game_scene/battle_board_v2.gd:2826::_manual_effects_of` | 共同actions/当前组合preview驱动提示，无这些函数network_session分支；manual仍按来源解析对象属兼容，不是私有合法性重算。 | refactor_held_actions + 当前组候选变化/无合法mode/组上限/旧异步preview失效。 |
| D17 | 实现待验 | `scripts/game_scene/battle_board_v2.gd:3714::_bind_mana_cost_preview`; `scripts/game_scene/battle_board_v2.gd:3718::_render_group_cost_preview` | 本地QUERY.preview、网络group_preview统一render；presenter旧费用重复已撤。 | refactor_group_projection + source-adapter，选牌/hidden变化/旧预览拒绝；两模式实际费用浮窗。 |
| D18 | 部分 | `scripts/game_scene/battle_board_v2.gd:3608::_show_effect_modal`; `scripts/game_scene/battle_board_v2.gd:4077::_show_player_select_panel`; `scripts/net/ui/network_choice_panel.gd:1` | 四类待答已声明化，native renderer与source消费存在；但网络panel仍自己持发送/result锁，未完全仅作为pending→renderer输入。不是四类未做。 | 四类每种真实ENet+本地公开pending/submit/cancel，统一命令适配后拒绝不清pending、min0空集不当cancel。 |
| D19 | 实现待验 | `tests/natural_game_over_test.gd:48::run_local`; `scripts/game_scene/battle_board_v2.gd:3417::_check_game_over` | 真实MatchDriver合法推进到自然终局的测试存在，不是手设game_over；E58选集未包含。 | natural_game_over单机：game_end唯一、Board一次、say一次、日志不弹、场景保留。 |
| D19b | 实现待验 | `tests/natural_game_over_test.gd:88::run_network` | 真实ENet authority自然推进网络终局；E60所有权专项人工终局不能替它。 | natural_game_over联机真实推进；保留无额外LogBrowser与四条终局断言。 |
| D20 | 实现待验 | `scripts/net/ui/v2_view_presenter.gd:88::show_game_over`; `scripts/game_scene/battle_board_v2.gd:3417::_check_game_over` | presenter只转唯一board终局入口，无旧自动打开LogBrowser代码。 | natural_game_over网络红→绿的当前原件，确认日志只由用户主动打开。 |
| D20b | 实现待验 | `scripts/game_scene/battle_board_v2.gd:505::_update_board_return_controls`; `scripts/game_scene/battle_io/battle_host_lifecycle.gd:1` | 场景Board两个return按钮及host lifecycle已落地；GUI55 host16有3红，E60headless真实owner补8项不是当前GUIPASS。 | 正式两模式非headless真实点击：真实accepted+大厅match_reset+同Session移交；主菜单真实close。不得重设_network_session_transferred。 |
| D20c | 实现待验 | `scripts/game_scene/battle_board_v2.gd:3417::_check_game_over`; `scripts/game_scene/battle_board_v2.gd:678::_player_name`; `scripts/game_scene/battle_board_v2.gd:710::_score_sorted_ids`; `scripts/net/ui/v2_view_presenter.gd:88::show_game_over` | 终局/名字/胜负排序从source统一；网络仅读view后调用board，不再另开日志。 | natural_game_over双路径及一次展示，源码/测试/场景hash同冻结。 |
| D20d | 实现待验 | `scripts/net/session/lobby_session.gd:760::_receive`; `scripts/net/authority/match_authority.gd:160::finish_match_to_lobby` | match_finished_lobby认证owner、seq、自然game_over门、规则清理、room迁移真实成功才_deliver_match_result。E58receipt16绿；E60owner公开request通过。 | 同冻结GUI走房主返回，所有客户match_reset，非房主等待/拒绝，不用大厅快照冒accepted。 |
| D21 | 部分 | `scripts/game_scene/battle_board_v2.gd:1` | 本次network_session出现在28函数；8个初始化/生命周期/调试候选、2个适配器帮助函数待边界审阅，另外18个明显业务/展示分支仍在，详下表。候选不等于新增层许可，原4类门未满足。 | 先完成D15与source能力字段，再唯一board写者删下面剩余分支；每个职责闭包net_v2输入窗口，不许删必要生命周期。 |
| D22 | 部分 | `scripts/net/ui/v2_view_presenter.gd:212::refresh`; `scripts/net/ui/v2_view_presenter.gd:577::_bind_hand`; `scripts/net/ui/v2_view_presenter.gd:547::card_input`; `scripts/net/ui/v2_view_presenter.gd:615::area_input`; `scripts/net/ui/v2_view_presenter.gd:636::confirm_area` | 起扫691行57成员86引用；收尾另actor撤事件弃牌两函数后679行57成员84引用。仍有手牌/浏览/战区/selection反馈/整屏refresh，未达到仅等待/继承/guard薄壳。 | D15/D21消费者迁出后逐符号退休；对新679行hash复验，不引用起扫691的旧PASS。 |

### E 批

| ID | 状态 | 当前文件/符号 | 已读实现与原件证据 | 待验最低动作/交接 |
|---|---|---|---|---|
| E01 | 实现待验 | `scripts/system/global/effect_manager.gd:435::push_message`; `scripts/system/global/effect_manager.gd:481::push_effect_result`; `scripts/system/global/effect_manager.gd:73::latest_allocated_message_serial` | 单调MessageRecordStream共享发布，reset/事务不复用serial；明确int64耗尽拒绝。 | notification_identity专项：pop/return/clear/reset/rollback不会旧ID复用；不篡规则hash。 |
| E02 | 实现待验 | `scripts/match/view_builder.gd:277::notifications_for`; `scripts/net/authority/match_authority.gd:41::bind_notification_boundary`; `scripts/match/view_mirror.gd:1` | epoch:serial稳定身份与strict mirror字段；after_serial绑定重连水位。 | notification_projection+privacy，删除前项、同文不同ID、多观察者、跨局不碰撞。 |
| E03 | 实现待验 | `scripts/net/ui/notification_inbox.gd:12::ingest`; `scripts/net/ui/network_choice_panel.gd:1` | 按ID去重且seen裁到当前通知集；本地统一面板生命周期代际分离。 | notification_panel_identity：同文两次、同snapshot不重入、裁剪后重现语义；不能据seen有界称权威队列有界。 |
| E04 | 实现待验 | `scripts/net/authority/match_authority.gd:41::bind_notification_boundary`; `scripts/system/global/effect_manager.gd:73::latest_allocated_message_serial`; `scripts/match/view_builder.gd:277::notifications_for` | 认证重绑固定已分配水位，不从队列max猜；D3在线不重不漏、断线不补发已决。 | notification_reconnect_baseline：认证后首view前新发保留、旧消息不补；恢复/新局水位不碰撞。 |
| E05 | 实现待验 | `scripts/system/global/game_progress.gd:1`; `scripts/net/authority/match_authority.gd:34::declare_broadcast_confirmation`; `scripts/net/session/authority_host_client.gd:1` | requires_confirm显式能力已在正式组合根/host/manager/worker/session/authority传递；默认false，不按headless/人数猜。 | broadcast_policy_boundary+真实lobby创建前显式true/false；读worker顶层配置及当前规则屏障。 |
| E05b | 实现待验 | `scripts/system/global/game_progress.gd:431::_effects_block_progress`; `scripts/system/global/game_progress.gd:1` | 推进按requires_confirm而不是展示Node存活；注册消费者只供UI。 | battle_broadcast+full_game，headless/AI默认false不阻塞。 |
| E06 | 实现待验 | `scripts/match/rule_state.gd:36::_roots`; `scripts/match/effect_checkpoint.gd:63::restore`; `scripts/match/match_replay.gd:237::restore` | 不捕获Node引用；规则bool/pending/confirmed保留，transport batch排除哈希/回滚后换发。 | broadcast_policy_boundary+match_replay+真实恢复旧batch拒绝；不以E62恢复失败充通过。 |
| E07 | 实现待验 | `scripts/match/view_builder.gd:99::broadcast_view`; `scripts/match/view_mirror.gd:1` | pending/batch_id/confirmers/confirmed全部公开投影且镜像类型校验。 | match_view/privacy及错误字段拒绝，确认私有数据未泄露。 |
| E07b | 实现待验 | `scripts/match/match_command_dispatcher.gd:29::_dispatch`; `scripts/system/global/game_progress.gd:474::confirm_battle_broadcast_batch` | confirm_broadcast按seat/当前batch/资格/未确认校验，再真实命令执行。 | broadcast网络两真人各自确认解除；旧batch/重放/非资格拒绝不扣费。 |
| E07c | 实现待验 | `scripts/net/authority/match_authority.gd:457::_step_broadcast_confirmation`; `scripts/game_scene/battle_io/local_battle_commands.gd:34::tick_broadcast_confirmation` | controller明确分类AI并按原节奏confirm，真人不自动确认。 | 真实1真人6AI屏障：AI逐个后仍等真人，再真人确认续行。 |
| E07d | 实现待验 | `scripts/net/session/lobby_session.gd:2136::_confirm_absent_broadcast`; `scripts/net/authority/match_authority.gd:210::confirm_absent_broadcast` | 授权断线未确认候选/同seq同batch校验与审计facts已接，不猜断线列表授UI权限。 | 真实断线仍等待；房主代确认审计事实，非房主/已复连/旧候选拒绝。 |
| E07e | 实现待验 | `scripts/game_scene/battle_board_v2.gd:4302::_broadcast_absent_declaration`; `scripts/game_scene/battle_board_v2.gd:4167::_update_battle_broadcast`; `scripts/game_scene/battle_board_v2.gd:5452::_submit_battle_command` | source.broadcast_view驱动继续及代断线按钮；本人走commands，代确认管理请求仍Session专属。 | 正式lobby→独立worker显式true→实际真人/代断线点击→batch解除→规则续行；单机/联机各非headless。 |
| E08 | 实现待验 | `scripts/system/global/content_environment.gd:7::install`; `scripts/system/global/content_environment.gd:19::restore` | 只切两个全局变量并返回/还原token，无新增隐藏宿主状态；E62content30 PASS且扫描相等。 | 最终同源ContentEnvironment正常/中途失败/嵌套token值和身份还原专项。 |
| E09 | 实现待验 | `scripts/net/session/lobby_session.gd:1453::_prepare_rule_data` | lobby准备已调用ContentEnvironment；原plan E09–E13写法含6位置，E13明确含两个worker，不丢验证点。E58lobby1544，E62worker45/content30是各自冻结。 | lobby_content_environment_restore；失败后还原（room worker进程级安装不要求restore），实际恢复终局另看F16阻断。 |
| E10 | 实现待验 | `scripts/net/session/lobby_session.gd:1496::_restore_room_rules` | lobby规则采用已调用ContentEnvironment；原plan E09–E13写法含6位置，E13明确含两个worker，不丢验证点。E58lobby1544，E62worker45/content30是各自冻结。 | lobby_content_environment_restore；失败后还原（room worker进程级安装不要求restore），实际恢复终局另看F16阻断。 |
| E11 | 实现待验 | `scripts/net/session/lobby_session.gd:1748::restore_local_match`; `scripts/net/session/lobby_session.gd:1902::_fail_closed_restore` | lobby恢复/终局收尾已调用ContentEnvironment；原plan E09–E13写法含6位置，E13明确含两个worker，不丢验证点。E58lobby1544，E62worker45/content30是各自冻结。 | lobby_content_environment_restore + restart；失败后还原（room worker进程级安装不要求restore），实际恢复终局另看F16阻断。 |
| E12 | 实现待验 | `scripts/net/authority/match_authority.gd:530::restore_archive` | authority存档恢复已调用ContentEnvironment；原plan E09–E13写法含6位置，E13明确含两个worker，不丢验证点。E58lobby1544，E62worker45/content30是各自冻结。 | net_server_gateway_restart；失败后还原（room worker进程级安装不要求restore），实际恢复终局另看F16阻断。 |
| E13 | 实现待验 | `scripts/net/server/server_room_worker.gd:287::_load_process_content`; `scripts/net/validation/room_data_validation_worker.gd:124::_inspect_loaded_content` | room worker进程安装与validation worker临时安装已调用ContentEnvironment；原plan E09–E13写法含6位置，E13明确含两个worker，不丢验证点。E58lobby1544，E62worker45/content30是各自冻结。 | worker_content_environment + loader_error_boundary；失败后还原（room worker进程级安装不要求restore），实际恢复终局另看F16阻断。 |
| E14 | 实现待验 | `scripts/system/global/load_game.gd:22::_ready`; `scripts/net/server/server_bootstrap.gd:1` | LoadGame._ready不再场景路由；bootstrap统一四种角色路径。layer4合法许可保持。 | 当前同源client/server实际EXE各启动，worker/validation入口真实执行；不能借旧PKG52。 |
| E15 | 实现待验 | `scripts/net/validation/room_data_preparation.gd:37::_init`; `scripts/net/session/lobby_session.gd:1` | settings/humans/blobs/publish/download显式注入，旧session.room._humans耦合撤；生产消费者已构造。E62dependencies34+真实child报告补严格门。 | preparation_consumer/dependencies同冻结，替换旧准备器断信号/取消任务/别名消费，正常204与缺roster报告。 |

### F 批

| ID | 状态 | 当前文件/符号 | 已读实现与原件证据 | 待验最低动作/交接 |
|---|---|---|---|---|
| F01 | 实现待验 | `scripts/system/global/effect_manager.gd:139::capture_transaction_state`; `scripts/system/global/effect_manager.gd:148::restore_transaction_state`; `scripts/match/effect_checkpoint.gd:1` | transaction边界公开capture/restore，checkpoint无直接内核容器读取；当前gate生产私有0，E58相邻guard专项有原冻结结果。 | match_replay+guard rollback，恢复保留原对象/失败记录同冻结；故障不能被checkpoint回滚吞掉。 |
| F02 | 实现待验 | `scripts/system/global/effect_manager.gd:158::paused_runs_snapshot`; `scripts/match/rule_state.gd:36::_roots` | paused_runs_snapshot公开接口已消费；当前gate生产私有0，E58相邻guard专项有原冻结结果。 | kernel_state_boundaries+规则hash/root等价同冻结；故障不能被checkpoint回滚吞掉。 |
| F03 | 实现待验 | `scripts/system/global/effect_manager.gd:192::mark_guard_audit_failed`; `scripts/match/match_replay.gd:34::_confirm_audit`; `scripts/net/authority/match_authority.gd:54::confirm_audit` | 审计失败公开方法替旧私有调用；当前gate生产私有0，E58相邻guard专项有原冻结结果。 | guard audit失败负向+match_replay同冻结；故障不能被checkpoint回滚吞掉。 |
| F04 | 实现待验 | `scripts/system/global/effect_manager.gd:2712::effect_fact_actor_id`; `scripts/system/global/effect_manager.gd:2727::effect_source_name`; `scripts/net/authority/match_authority.gd:306::guard_diagnostic` | 公开effect actor/name已消费，生产对应许可退休；当前gate生产私有0，E58相邻guard专项有原冻结结果。 | net_runtime_guard及guard_diagnostic投影同冻结；故障不能被checkpoint回滚吞掉。 |
| F05 | 部分 | `scripts/system/ai/temp/dummy_bot.gd:32::capture_attempts`; `scripts/match/effect_checkpoint.gd:63::restore`; `tools/check_layer_deps.py:1` | DummyBot三公开方法与生产消费完成；起扫private许可46=tests14+scratch32，收尾实际42=tests10+scratch32，但许可仍46、4stale。三必要fault-injection保持明确窄许可，不强删负向。 | gate唯一写者精确退休audit_commit/deferred_transaction_facts的4旧锚点；继续公共观察迁移而保留必要故障注入合同，不删bootstrap4。 |
| F06 | 实现待验 | `scripts/net/session/client_match_inbox.gd:14::receive`; `scripts/net/session/lobby_session.gd:760::_receive` | 五kind移入inbox，仅4match状态与signals；Session还做来源/生命周期门。E58inbox45绿。 | client_match_inbox + net_server_one_round + net_v2，close/reconnect/selection reset不丢事件。 |
| F07 | 实现待验 | `scripts/net/content/blob_receiver.gd:16::receive_client`; `scripts/net/session/lobby_session.gd:760::_receive` | blob_error/blob_chunk客户端在blobs.receive_client，Session只收返回error；hostprovider链另外仍在Session。E58blob相关各专项绿。 | net_blob/authorization/send/concurrent；实际坏chunk、重复、取消不放宽预算。 |
| F08 | 实现待验 | `scripts/net/identity/client_identity_inbox.gd:13::receive`; `scripts/net/session/lobby_session.gd:742::_receive_client_identity` | 客户端8种身份消息已无状态协调器；host身份管理尚F09，不把客户端拆分当整个身份边界完成。E58identity58/resume26绿。 | 真实认证/复连/继承负向全套；重连水位与request代际联验，E62失败保持阻断。 |
| F09 | 部分 | `scripts/net/session/lobby_session.gd:760::_receive`; `scripts/net/session/host_room_inbox.gd:1`; `scripts/net/session/host_content_inbox.gd:1`; `scripts/net/session/host_guard_inbox.gd:1` | 已迁room4/content3/guard4；主机match正文仍16种kind（12标签组），以及认证/发布/状态提交仍Session。Session2189行，不用拆出三个文件冒22种全部迁完。 | 剩余identity、match/selection、server数据/room_password各单职责协调器；保留认证→member→barrier→授权→执行→审计→发布顺序，共享Session唯一接线者。 |
| F10 | 完成 | `reports/refactoring/server-room-lifecycle.md` | 真实只读生命周期状态/字段/读写表产物已存在；本项只要求文档，不是manager拆分完成。 | 后续使用当前MAN符号重新定位，不拿旧状态表行号作当前运行证明。 |
| F11 | 实现待验 | `scripts/net/server/server_room_manager.gd:205::runtime_admission_error`; `scripts/net/server/server_room_manager.gd:196::_active_runtime_count`; `scripts/net/server/server_room_manager.gd:658::recover_room`; `scripts/net/server/server_room_manager.gd:192::_approved_root` | quota按运行资源，UNKNOWN不当释放；批准根显式注入、恢复重验当前policy。E58approved-root47绿。 | runtime_admission创建/休眠/恢复/UNKNOWN+配置变更负向；完整恢复仍F16红。 |
| F12 | 阻断 | `scripts/net/server/server_shutdown.gd:1`; `scripts/net/server/server_room_manager.gd:372::release_process_for_binding`; `scripts/net/server/server_console_channel.gd:1` | 安全save/receipt/EXITED/release与紧急stop已分离；但E58main86有2失败：recover新实例“房间状态写入失败，未关闭”。E62真实失败结束也未释放登记。 | 唯一shutdown/manager写者定位新instance/request写入失败，保留原response/evidence字节；当前真实save→EXITED→release→gateway正常stop整链，禁止强杀掩盖。 |
| F13 | 实现待验 | `scripts/net/server/server_room_manager.gd:511::poll`; `scripts/net/server/server_room_manager.gd:640::startup_status` | 监督/曾ready与首次startup分离，旧deadline不可套新能力丢失；字段接线已存在。 | 能力丢失/恢复/实例替换/关闭监督组合真worker，bound instance复核；UNKNOWN不强杀。 |
| F14 | 实现待验 | `scripts/net/server/heartbeat_publication_policy.gd:1`; `scripts/net/server/server_room_manager.gd:65::_poll_heartbeat` | 心跳重试/持续失效降级及安全close路径独立；期限来自显式部署。 | heartbeat_runtime_integration：写失败→成功、持续故障、保存未决；原engine不换、不自设新超时。 |
| F15 | 阻断 | `scripts/net/server/temporary_cleanup_ledger.gd:120::_cleanup`; `scripts/net/server/server_console_channel.gd:38::poll_cleanup_schedule` | policy/ledger/scheduler存在，poll仍preview/blocked/removed0。扫描中executor新接显式remove_verified/evidence且默认缺适配器拒绝；ledger尚未传，缺完整registry/跨进程排他及正式DLL部署proof。 | 全量重构闭包：本机完整registry+跨进程排他→ledger intent/recovery事务→已验native adapter正式接入与同HANDLE删除读回；人测包可明确未启用，不以启用自动清理为前提。 |
| F16 | 阻断 | `scripts/net/server/server_room_manager.gd:416::create_room`; `scripts/net/server/server_room_manager.gd:658::recover_room`; `scripts/net/server/server_gateway.gd:1`; `scripts/net/server/server_room_worker.gd:1` | 真实创建/保存已做；E62同当前hash恢复first-cancel=ENet peer_disconnected→Session取消→fail-closed，51检查4false/exit1，原生断线根因unknown。无恢复提交/ACK/终局/尾save/hash。 | 唯一transport/session恢复链写者先捕具体不应断线原因并修最小闭包；再原目标恢复→自然终局→真实管理save/readback/journal尾hash，正确性与60秒性能分别报。 |

### G 批

| ID | 状态 | 当前文件/符号 | 已读实现与原件证据 | 待验最低动作/交接 |
|---|---|---|---|---|
| G01 | 部分 | `tools/release/package_audit.py:140::pck_index`; `tools/release/package_audit.py:47::audit` | PKG52两角色真实PCK index及package-client/server.json blockers=[]，含helper检查；只当前旧候选，无最终同源三角色PCK原件。 | 最终三角色各包重新index，读project.binary中autoload与禁止资源，并核对同一source/各PCK/DLL。 |
| G02 | 实现待验 | `tools/release/freeze_prepare.py:31::transform_project`; `tools/release/freeze_prepare.py:122::transform` | 正式冻结转换剔helper与开发插件且candidate包审计无blocker；共享export_presets.cfg四preset均未直接加godot_ai排除（改用冻结转换路径），不能声称原plan字面两preset补丁已做。 | 明确批准freeze转换作为发行路径；最终实际包project.binary+索引证明开发autoload不在，不改开发project。 |
| G03 | 实现待验 | `tools/copy_data_after_export.py:68::resolve_output_dir` | 显式项目与唯一preset/输出目录解析已实现；本次--project repo无输出实际exit2，未写目录。未运行成功copy以守唯一新doc写权。 | 隔离新E输出验证显式preset/输出成功、缺/双参数/未知preset拒绝与数据hash；无默认first preset。 |
| G04 | 部分 | `tools/release/release_prepare.py:1`; `tools/release/round56_three_role_freeze.py:1` | 扫描中同源工具392→736行，新增显式artifact-manifest phase executor（client/server/status/signaling-ready/negative）。源码宣称IMPLEMENTED_NOTRUN，runtime_verdict即使各phasePASS也仅PARTIAL_NOT_THREE_ROLE_PASS；完整发行client RSA/GUI仍独立缺口。 | 唯一release写者先验新phase编排的拒绝/哈希/原生/状态/关停，再接两个正式导出client认证开局与同源三角色all链；新E根须main当前ready token，不能旧PCK混绿。 |
| G05 | 阻断 | `tools/release/round56_three_role_freeze.py:695::main`; `tools/release/runtime_audit.py:96::run_role` | 没有最终同源三角色正式包真实验收。新phase executor已经写出但本矩阵未执行/未读到其新runtime原件；旧PKG52两游戏角色+另signal不等于同源。 | 同一获准源三角色实际制作；两正式client开局/请求，server保存→退出/释放→正常stop，signalREADY/缺配置精确exit2及禁止游戏消息；逐角色EXE/PCK/DLL原件hash齐全。 |

## 4. 六个关键判据展开

### D21：仅允许四类，不许以新helper名称扩许可

原允许分类是ready适配器选择、exit_tree生命周期、return_to_*生命周期、debug能力差异。helper若确属这些职责可由唯一写者证明并移宿主；**不能把渲染/输入/合法性/命令发送叫生命周期而免迁**。下面28函数为network_session词法命中清单（注释/字符串之外本次源码函数体），不含只有_source_is_local等分支，因此是下界。

| 当前函数 | 分支角色 | 下一最小边界 |
|---|---|---|
| `battle_board_v2.gd:315::_ready` | 初始化/宿主生命周期/调试候选（仍需核对原4类） | 宿主能力/会话所有权显式声明，不能删合理close/transfer |
| `battle_board_v2.gd:453::_default_area_index` | 业务/展示/交互残余，须迁共同consumer | 移source/view/actions或共同commands，保持真实seq/回执 |
| `battle_board_v2.gd:466::_bind_host_lifecycle` | 初始化/宿主生命周期/调试候选（仍需核对原4类） | 宿主能力/会话所有权显式声明，不能删合理close/transfer |
| `battle_board_v2.gd:479::_read_network_lobby_state` | 初始化/宿主生命周期/调试候选（仍需核对原4类） | 宿主能力/会话所有权显式声明，不能删合理close/transfer |
| `battle_board_v2.gd:482::_read_finished_lobby_request` | 初始化/宿主生命周期/调试候选（仍需核对原4类） | 宿主能力/会话所有权显式声明，不能删合理close/transfer |
| `battle_board_v2.gd:505::_update_board_return_controls` | 初始化/宿主生命周期/调试候选（仍需核对原4类） | 宿主能力/会话所有权显式声明，不能删合理close/transfer |
| `battle_board_v2.gd:524::_process` | 业务/展示/交互残余，须迁共同consumer | 移source/view/actions或共同commands，保持真实seq/回执 |
| `battle_board_v2.gd:610::refresh_all_ui` | 业务/展示/交互残余，须迁共同consumer | 移source/view/actions或共同commands，保持真实seq/回执 |
| `battle_board_v2.gd:1092::_bind_shared_phase_view` | 业务/展示/交互残余，须迁共同consumer | 移source/view/actions或共同commands，保持真实seq/回执 |
| `battle_board_v2.gd:1822::_on_strip_gui_input` | 业务/展示/交互残余，须迁共同consumer | 移source/view/actions或共同commands，保持真实seq/回执 |
| `battle_board_v2.gd:1919::_input` | 业务/展示/交互残余，须迁共同consumer | 移source/view/actions或共同commands，保持真实seq/回执 |
| `battle_board_v2.gd:2007::_select_scroll` | 业务/展示/交互残余，须迁共同consumer | 移source/view/actions或共同commands，保持真实seq/回执 |
| `battle_board_v2.gd:2321::_bind_self` | 业务/展示/交互残余，须迁共同consumer | 移source/view/actions或共同commands，保持真实seq/回执 |
| `battle_board_v2.gd:2442::_layout_held_group` | 业务/展示/交互残余，须迁共同consumer | 移source/view/actions或共同commands，保持真实seq/回执 |
| `battle_board_v2.gd:2692::_on_held_card_input` | 业务/展示/交互残余，须迁共同consumer | 移source/view/actions或共同commands，保持真实seq/回执 |
| `battle_board_v2.gd:2762::_on_held_effect_pressed` | 业务/展示/交互残余，须迁共同consumer | 移source/view/actions或共同commands，保持真实seq/回执 |
| `battle_board_v2.gd:2908::_bind_hand_card` | 业务/展示/交互残余，须迁共同consumer | 移source/view/actions或共同commands，保持真实seq/回执 |
| `battle_board_v2.gd:3080::_held_input_available` | 业务/展示/交互残余，须迁共同consumer | 移source/view/actions或共同commands，保持真实seq/回执 |
| `battle_board_v2.gd:3484::_return_to_main_menu` | 初始化/宿主生命周期/调试候选（仍需核对原4类） | 宿主能力/会话所有权显式声明，不能删合理close/transfer |
| `battle_board_v2.gd:3496::set_debug_console_enabled` | 初始化/宿主生命周期/调试候选（仍需核对原4类） | 宿主能力/会话所有权显式声明，不能删合理close/transfer |
| `battle_board_v2.gd:4302::_broadcast_absent_declaration` | 业务/展示/交互残余，须迁共同consumer | 移source/view/actions或共同commands，保持真实seq/回执 |
| `battle_board_v2.gd:5147::_bind_power_hover` | 业务/展示/交互残余，须迁共同consumer | 移source/view/actions或共同commands，保持真实seq/回执 |
| `battle_board_v2.gd:5452::_submit_battle_command` | 业务/展示/交互残余，须迁共同consumer | 移source/view/actions或共同commands，保持真实seq/回执 |
| `battle_board_v2.gd:5510::_rebuild_battle_commands` | 适配器helper待边界审阅，不自动获许可 | 移source/view/actions或共同commands，保持真实seq/回执 |
| `battle_board_v2.gd:5607::_stop_battle_commands` | 初始化/宿主生命周期/调试候选（仍需核对原4类） | 宿主能力/会话所有权显式声明，不能删合理close/transfer |
| `battle_board_v2.gd:5615::_battle_command_input_available` | 业务/展示/交互残余，须迁共同consumer | 移source/view/actions或共同commands，保持真实seq/回执 |
| `battle_board_v2.gd:5625::_network_battle_input_available` | 适配器helper待边界审阅，不自动获许可 | 移source/view/actions或共同commands，保持真实seq/回执 |
| `battle_board_v2.gd:5914::_on_played_card_input` | 业务/展示/交互残余，须迁共同consumer | 移source/view/actions或共同commands，保持真实seq/回执 |

程序分类：8个候选 + 2个适配器帮助函数待审 + 18个明显残余 = 28。旧29函数不再是当前总数；“名字不在旧清单”不证明已统一。

### D22：691并不是完成状态

初扫691行、57成员/86引用；扫描内事件弃牌两个函数移出后679行、57成员/84引用（词法工具重算）。`refresh`仍调多处分屏渲染、`_bind_hand`仍独有网络手牌绑定，card/area/confirm仍直Session。逐调用方完成共享消费后才能退休，不能因少12行宣布D22完成。

### F05：生产内核边界与测试故障注入分账

起扫许可46：scratch/transaction-return-consumers32、tests14。收尾实访问42：scratch32、tests10；许可仍46而非已清零。DummyBot capture/restore/clear生产接线存在。当前4stale应退休；合理负向fault-injection窄例外不可为清零随意删除或新增生产getter绕过。bootstrap4属layer而不是private，不能混入“内核必须清零”指标。

### F09：实际尚存的主机inline kind

已迁 `host_room_inbox` 4（ready/settings/transfer/kick）、`host_content_inbox` 3（catalog/data_ack/blob_request）、`host_guard_inbox` 4。客户端inbox/identity是F06/F08，不能借它们充抵主机完整拆分。

Session._receive剩余16个inline kind（12标签组）：`begin_match`、`broadcast_confirm_absent`、`choose_master`、`identity_ack`、`identity_candidates`、`identity_inherit`、`join`、`match_command`、`match_finished_lobby`、`preview_group`、`room_password`、`server_data_cancel`、`server_data_catalog`、`server_data_commit`、`server_data_prepare`、`start`。

此外provider blob响应与catalog fragment预门仍组合根；按真实职责决定迁移，不按“22 kinds”旧估计做减法。身份/比赛/数据各协调器不保存反向Session强引用，认证seq/member/生命周期与最终状态提交仍由Session单写。

### F15：新native能力不等于本机自动清理proof

`poll_cleanup_schedule`只preview，due时显式blocked/removed_files=0，missing_capabilities仍complete_instance_registry/cross_process_file_exclusion。ledger._cleanup检查完整实例/文件独占proof；这些不能由manager.rooms或新bool自证。扫描中executor改为显式remove_verified/evidence且默认无能力拒绝，ledger尚未注入，不追认“接了新wrapper就可删”。N59隔离native结果明确not_production_package/no_automatic_cleanup_green，正式DLL仍旧字节。真人包保持未启用可交付边界，但用户完整重构目标的生产proof闭包不能消失。

### G05：正式三角色同源包未验

旧PKG52只有client/server，纯signal后独立source/构建scope不能拼入。扫描中run-formal从固定NOTIMPLEMENTED拒绝推进为实现phase executor，然而新源码runtime_verdict明确只给PARTIAL_NOT_THREE_ROLE_PASS，formal_exported_client_RSA=NOTRUN；server阶段复用editor RSA且仅空大厅save，不是两个正式client对局保存。缺完整正式client认证/开局、真实游戏server保存关停、统一当前source三角色制作及逐角色发行原件。制作token批准、静态导出、正式运行四阶段分开，不把exit0当G05完成。

## 5. 给main的生产剩余闭包（交付优先级；仅9条）

不是继续全域审计任务；可分别指派独立owner，但共享board/presenter/panel、Session、manager/console等文件只能唯一写者，接口生产→消费串行交接。先真人人测关键路径，最后完整重构尾项；未决因果保留明确停止条件。

1. **P0 恢复数据面/取消闭包（F16）** — `enet_transport.gd`/`LobbySession`/`server_gateway.gd`唯一写者。复用E62实际认证/save-close/recover入口，用一次窄自然路径及一次已认证连接真实关闭负向捕具体不应断开的调用或原生原因；根因明确才最小修复。保持取消锁、隐私、ACK、票据、完整哈希，随后原目标恢复→自然终局→终末save/hash。原生为何断线仍unknown，不把4.95秒poll gap猜成timeout。

2. **P0 保存关停闭包（F12/F16/G05）** — shutdown/manager/console唯一写者；与恢复Session写者接口串行。以新instance/request复现“房间状态写入失败”，在finally前保留批准原response/状态/错误与路径身份，确认保存→EXITED→release→gateway stop；UNKNOWN/缺回执不强杀、不forget。旧E58response已缺失，不能补造。

3. **P1 共同交互提交闭包（D15/D18）** — board/presenter/network_choice_panel唯一写者。迁剩余翻面、部署/移动、网络待答到共同command adapter，保留原确认seq和真实权威完成关联；拒绝恢复可点、双击不二扣、重连unknown、不自动重发、min0空集不当cancel。每类小专项+真实两模式窗口。

4. **P1 共同展示/薄壳闭包（D21/D22，C11–15）** — 上项交接后同一board/presenter写者，不并写。把source视图/动作能力驱动共同refresh/hand/浏览/area输入，迁本地MapData/GameData差异；源适配器显式能力承载差别。只留4类允许分支及等待/身份/guard壳。新事件弃牌迁移须验标题/分类/隐私/开合，正常process下完整四组/扇形中帧可见。

5. **P1 内容发布/严格错误闭包（E15/G05）** — assembler/validation入口/证据采集器分文件唯一写者。采用本轮已接loader error_sink，不再旧scope豁免缺roster ERROR；保留正常204及负向真实child报告。针对真实发布rename系统返回保留同线程调用结果，不把成功LastError残值当旧失败原因、不随机重试。若新采集器抗锁合同已有actor交付，先读确切原件再并入当前冻结，不重派全域审计。

6. **P1 同源发行执行闭包（G04/G05）** — release工具唯一写者，source/main授权与GUI执行者串行。新artifact-manifest phase executor只部分能力：client opening、editor RSA空大厅、status、signal正负；补两个正式发行client真实认证/开局及游戏server保存关停。主签当前证据token后新E根三角色cold/import/export；同源各EXE/PCK/DLL和正式入口原件齐全，不借旧PKG52+signal。

7. **P2 最终合并验收闭包（跨A–G）** — main冻结/runner所有权单写；唯一窗口执行者。生产写者交接后冻结当前真实选集（纳入新loader等场景，不能硬抄98）。加入A06/A07、purity/name、自然双路径终局及各必需harness/窗口；程序对账selected/executed/unique/pass/strict/red/blocked/not_run，父子日志ERROR分账。逐套所有权/归档/释放/安全回收，保留未批准缓存和records。此是可执行门，不是又一轮泛审计。

8. **P3 Session剩余职责闭包（F09）** — Session共享唯一接线者；独立无状态协调器可另写后串行接线。先迁16种inline kind的身份管理、match/selection、server数据及密码职责；Session保留连接认证、seq、稳定member、生命周期与提交/发布顺序。不改变房主/恢复政策，分别用真实正负请求、身份/恢复专项验收，不能按2189行或22种历史估算宣称完成。

9. **P3 可选本机清理生产proof闭包（F15）** — registry/排他proof所有者→ledger→native adapter串行接线；不与console/manager另写者撞文件。建立完整实例登记、跨进程文件排他和同instance保存消费/退出proof，持久化intent/recovery后才注入remove_verified与历史批准身份。实际正式DLL部署及拒绝/成功读回全验。缺声明/UNKNOWN/链接/当前实例/正式存档不得删；人测包可显式保持未启用，不构成人测前提。

非生产尾账另交测试/gate或工具owner：F05当前4stale精确退休；B24实际生产148未知调用完成语义分类；C02四类group与当前SHA对齐。它们不能笼统塞进“生产耦合46未修”，也不能以报告数字清零取代上述9闭包。

## 6. 本矩阵引用文件的已读SHA256

这是逐文件扫描指纹索引，供下一写者核对漂移；**不是封存清单/导出授权/运行时PASS**。下面已知扫描变化采用重读后的字节；未重读文件采用起扫字节。原始证据本身的SHA另见§2。不读取身份私钥、用户存档、凭据或全盘扫描。

| 文件 | SHA256（最后已读字节） |
|---|---|
| `addons/fate_server_signals/bin/libfate_server_signals.windows.template_release.x86_64.dll` | `92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd` |
| `addons/fate_server_signals/src/process_owner_binding.cpp` | `7cf222556703e32baa341236e437448a6e4150e9507186107820f1b3d5aae8d3` |
| `addons/fate_server_signals/src/process_owner_core.cpp` | `0e7dc7f94845dc23bd7c6d853d90e5995ae1581539a785f60511f197f7a29d8a` |
| `addons/fate_server_signals/src/process_tree_owner_core.cpp` | `c51a6a352210e2094fae87f62292e094390ae4513c0f69254fc616136ed04c2f` |
| `addons/fate_server_signals/src/temporary_cleanup_core.cpp` | `79127c379c9ce81bfd0cc889f6d97ac4aa1fa53a042e7c24fdd2d63095d6e024` |
| `assets/scenes/game_scene/battle_board_v2.tscn` | `39a681e1f00578e2a2d7278b241262a72a78afe99937d99553c6ebf615c0fb6d` |
| `export_presets.cfg` | `f8f6afbbeb520f780deab5d7f7d5a59e9f5b2f33e02db4cb64c6823a428da091` |
| `project.godot` | `986a066adc6f0d1346d19612538780abaf2ce4d3cdfef4342db653a0b53d8c8a` |
| `reports/refactoring/server-room-lifecycle.md` | `5e3247f2ba4aa74755306d476c5021ffdb6dee7c0798fed3548358a8866ab29d` |
| `scripts/debug/debug_adapters/debug_map_adapter.gd` | `7bea69a095dd2aa356c6b9631ff327f2498ff1975bc1383a0c71c30d3282cca2` |
| `scripts/game_scene/battle_board_v2.gd` | `43b7be1d30dd785dbc3ef5cde0f02bed50e75f939944d0f64e08f1afc2007906` |
| `scripts/game_scene/battle_io/battle_host_lifecycle.gd` | `ac3011654a8ccae7b230d693632fbdab40032c857c2b684a1da4430b5a499605` |
| `scripts/game_scene/battle_io/local_battle_commands.gd` | `9f307a0010f35a992050a5ac248afda7ce604ecf4f609bd291409c108dc0cbfd` |
| `scripts/game_scene/battle_io/local_battle_source.gd` | `bcf2c7b03a48bdffbec8483f768c6005146ff2ca1f555b323fa783e87d0e1657` |
| `scripts/game_scene/battle_io/network_battle_commands.gd` | `43bb53535f3e64a9d0b730d77b6e2abf489a77aa15349bcd03d8ba4535f5758a` |
| `scripts/game_scene/battle_io/network_battle_source.gd` | `659dccfd291d429ef59f5b9649bc965123d2f7dda3f6cfb6d3cfefb7e48aff2e` |
| `scripts/game_scene/native_choice_renderer.gd` | `8a785a0850cc1651fdf49a976df06e9b95beefea80fb725c2a7a0b4b7812144c` |
| `scripts/game_scene/tactical_board_ui.gd` | `9c9d61642bf619c4012fced2b0244eebe89cf642be700f4418be82a0e4522ed9` |
| `scripts/io/native_method_contract.gd` | `c22ffd6012cf39b2b80e915bf526c8459a2c1f5888503961cd8502cef5505c85` |
| `scripts/io/temporary_cleanup_native_delete.gd` | `5b8b404ade4af5942977d1af352d67ac3db01ba9ec01b4776c1b04ee81659396` |
| `scripts/match/effect_checkpoint.gd` | `65d5e293d6e6d8be6142b0caf65e6096c8cfd791576de6b089de88c0e8a8488b` |
| `scripts/match/match_command_dispatcher.gd` | `6e23d647c6b2e68c3b289902c4b96a987167cac10c0ee2b26b4ee3d24cab634b` |
| `scripts/match/match_driver.gd` | `8f76ea384e5ade542a4f3a8f39c8817423f043e305790f01d0596e50e1429307` |
| `scripts/match/match_replay.gd` | `851f77f939974d3f51eea51b70feda9c2593c0ee700e265bb4e090b78419d175` |
| `scripts/match/match_seat_query.gd` | `f7688104a9c0f51a998a2c6637a556563fd40e62025cdf8acd92ad9a827718be` |
| `scripts/match/rule_state.gd` | `b18b4cff2b4f3bff128a0645c91459d037477f6fe8503b418f8d057e59020b02` |
| `scripts/match/view_builder.gd` | `5d570263ec5c31ccd2f5e08b7116dda951be828607819a59cbdea301022979e9` |
| `scripts/match/view_mirror.gd` | `deb091a12f6eb47693934a24653e9b5594e675ee5811aebbcc538bd8bdaeabbf` |
| `scripts/net/authority/match_authority.gd` | `7490fce77446e887afbad073da2ab1c16f538f877231b71adc1cc6d87241c43c` |
| `scripts/net/content/blob_receiver.gd` | `4286dc14ef4f46a9837bf0bedbeba159e3bff57b9fcb26f1db77858999010bba` |
| `scripts/net/identity/client_identity_inbox.gd` | `cfcd2ac03f0585ff1c9013888b085c7c2dde52ded3dbf157a5c045ec59962f7a` |
| `scripts/net/server/heartbeat_publication_policy.gd` | `b45b13235d422711cdece9d4af79e315a85d69fb7614fd4519747ff9871fc4ab` |
| `scripts/net/server/server_bootstrap.gd` | `6dbf5dfda785de5b11cab76f01e725317821eff51be37a4fbfba4bae5e978a3b` |
| `scripts/net/server/server_console_channel.gd` | `afbfd5a071a2fcb062555f00fcd9ac08dbe476a04ad3fd6efc2c7142373af3c3` |
| `scripts/net/server/server_gateway.gd` | `c93b92cba86fa317c7f8eed027d3ae73dc544650869e142d2ad38dcb084a4112` |
| `scripts/net/server/server_room_manager.gd` | `fadbeb892cfce741d62b95ff1c452d86b883d9a39c811851318d4a97f3799d53` |
| `scripts/net/server/server_room_worker.gd` | `2c93c8ef26e48a32e37d098beb43590114fd1c8494ab785c8ccc08741bc85a4a` |
| `scripts/net/server/server_shutdown.gd` | `7526d0b8fd7d427a04a67085f462425f845e883a3210ee8017a0a30963b60227` |
| `scripts/net/server/temporary_cleanup_ledger.gd` | `387d17b398eefa76d81794af97de98cd1ac673bfa4bf626ad0f5dd298778d1c5` |
| `scripts/net/session/authority_host_client.gd` | `4a145ffa7f6960aa8b9e808fa3539686d4d23ab2cd366316a1684c1d67098d75` |
| `scripts/net/session/client_match_inbox.gd` | `cf9a54204cfc5f5b68ff17742deac4a60882b7b51d1a057a6e5d9d2c2aaf95c2` |
| `scripts/net/session/host_content_inbox.gd` | `c0adf22f1d09d0b19b69f0a0f6b5ca0b1d7e304405226fb009b836924128f5ce` |
| `scripts/net/session/host_guard_inbox.gd` | `e2042626210bd12dbedd63ddf6369216a741791696a68465d89b7391ae480832` |
| `scripts/net/session/host_room_inbox.gd` | `5a5b41713c5c2eaee08242e1c4c56a2970b946009ca2ea57c18c18f69c275cca` |
| `scripts/net/session/lobby_session.gd` | `11b0f98a6cf68a8b441680ba2d24741be39c9a7c470aa6569e9fbe711a0dbf56` |
| `scripts/net/ui/network_choice_panel.gd` | `a48412ca6c0738bbf4bf4222a42dfaa3e557137124cca3d1d020a77720c0aa2a` |
| `scripts/net/ui/notification_inbox.gd` | `b764d5d6300ac93fcd0130e448c40d80e9acbd5228c4d62781b6650ea9d22fe0` |
| `scripts/net/ui/v2_view_presenter.gd` | `dff5b30f48655ad8637218d082717df0da6a543cad37fd643fe35f2d8b259a6e` |
| `scripts/net/validation/room_data_preparation.gd` | `12918b213f39bd88ae4f8cfbb9e949f75359e91e7ac999d7177b95b5c2b7b16a` |
| `scripts/net/validation/room_data_validation_worker.gd` | `a3d94c8af2723022d62420ed5cf81486711425c72c7a90232e246f2ce05d793a` |
| `scripts/system/ai/temp/dummy_bot.gd` | `94aec64c19a6c7f73e76d63ac1a3a5273279af11e109bb91334967a4600f7e72` |
| `scripts/system/area_action_rules.gd` | `409d569acaf4c4ba646ef44bb516878c3f70f4e74b5f7797e7d02a2235adce8a` |
| `scripts/system/global/climax_resolver.gd` | `0aab398b99a56f6014203ef99199b802671dbf22aa628e4944ee86718f6b8c37` |
| `scripts/system/global/content_environment.gd` | `fdc139c595c143b68a3168f93eb2ee4d992d899230c9546025a962eb8580c363` |
| `scripts/system/global/effect_manager.gd` | `56eff4380b1a63a35dc802a913565159a2c295c4dfae17b931b0c93ad70fecd8` |
| `scripts/system/global/game_data_manager.gd` | `d8cb5112300a319c64eee3da6eb008bf2cc98631a39f4916cfd972327833b1c1` |
| `scripts/system/global/game_progress.gd` | `8ba402ae1e1a34a8d65ab16bd8732b0d76a027c9ed4634f3b28e1f551d343c42` |
| `scripts/system/global/load_game.gd` | `2a78f90ac18bd76ea2ea3181349d069874bda5df3ce8280134e17f9ef17c92e5` |
| `scripts/ui/text/card_desc_text.gd` | `80c62325ac4287c57fee1b8bdb32043a1cffdfb490971076ac9f23217e5431ba` |
| `scripts/ui/text/choice_text.gd` | `f4211b3acc56e8258d3ba94e463d17abdfed50b1292aa97a8f73f1c91c812f21` |
| `scripts/ui/text/cost_text.gd` | `c432cd4bd5db8a4a89e5210de26b92719b263c00b79a61415012bd559e118c73` |
| `scripts/ui/text/game_log_text.gd` | `bafdb571773d81b2955c0a204624ed9c766c4705b5db7ccea951a054ae2ed7a8` |
| `tests/battle_board_v2_test.gd` | `048d1b7261d6a07fb9d2c47894d7f7afe2dd69915c5e77cbae1757c4009726de` |
| `tests/battle_broadcast_test.gd` | `9429f2ab529445385df1f92c888929e7c0e8ffbefe8328de00c8701936578bd2` |
| `tests/broadcast_policy_boundary_test.gd` | `5009d13113a51a2f2c9d1a35d3d789c60732e2cf4fb9c443c3167c6a3381b7d5` |
| `tests/climax_elimination_test.gd` | `ea6e9f926d784858cd1e3db0339671f97925107b7f26ab7e05d58bbb647b68ba` |
| `tests/debug_console_test.gd` | `af0afb984702f5313c68a0ec69b7b88baee9ee8f399a63f8e1baf1831e525382` |
| `tests/full_game_test.gd` | `1c2f011a6f0bd78c53ffd4d57c6d79a128d6529be9b26e34c0e1dc210cef1641` |
| `tests/loader_error_boundary_test.gd` | `800b1288267fb86efa3a7d2d8ddd6ecdfc769d37382d7e1165f84fff25a08497` |
| `tests/natural_game_over_test.gd` | `37b4f651fe738b5521df55177ed8644dba05457fb75a3e27ade49212cbd18666` |
| `tests/net_server_gateway_restart_test.gd` | `f5c25d584886153de2f2363cdc2f91384a05346b3278eeb9d55e6ad7e518cbcd` |
| `tests/notification_projection_test.gd` | `f3354986d7bdeb335fb1c66838694ad9694baa0d2ffe7346ce2b66680b4ca899` |
| `tests/notification_reconnect_baseline_test.gd` | `b165ad8af93bec582a3bdaf53afd7f31d099c56946ea30d8aec0fbece0ba129b` |
| `tests/player_name_test.gd` | `f5ca4f1284501be6b2a738d45565b8c96a7950072560b070785a43ae5ecc178d` |
| `tests/player_query_purity_test.gd` | `93f53cb9404c829a2a0cfbd29dbc1879504e0f2538003efe3bc293c8205e2768` |
| `tests/player_shown_name_golden_test.gd` | `625cab523ca0d51875752cb1b732d9bb3ca52bdb7bdd6dd27a08f611cfd106e1` |
| `tests/refactor_area_golden_test.gd` | `84d553858a7780e9482552efc8cd2d0f362737f1eadb26d071ae50d68b9daf32` |
| `tests/refactor_build_cost_probe.gd` | `b519a60eb63090fab85d732ee0a876dad53dc7e95871be48063b677e53f6a33b` |
| `tests/refactor_kernel_state_boundaries_test.gd` | `0537cdb13f3d13f076acf2a0cf6413c0a57ec9ca1558b8445b4a12c07f81d97b` |
| `tests/refactor_text_golden_test.gd` | `4a7dbdfd40f840c990d2df13b5de6b681c253dda57331f855d8a77c989fbc332` |
| `tests/server_shutdown_close_handoff_test.gd` | `43883d7c045e424fded389ec2359e5ef7416e063f84c7c4d185ab567bad83394` |
| `tests/turn_order_test.gd` | `8a75d129a4c701314ae69d8510d4a612c5e037304e4ee626c0c81e4174744bfd` |
| `tests/validation_pipeline_performance_test.gd` | `4c8a757983ca369e168c61c5a69092459f74009816b99ed421fa715cbcc27507` |
| `tools/check_inventory_drift.py` | `3d23b702d8d4ea4b5aeb3511975b2c887b36d72e3e1c87c7d5d839b14b891d67` |
| `tools/check_layer_deps.py` | `627a526d28f41f2ff224c0de7356ffa169cb491b1e86d2a52ffb76f1df09a1d0` |
| `tools/classify_player_data_calls.py` | `d4e229bde8d923e0beb8231ffcb4f73526e167eaf7f7fab6adfe18b02c32754f` |
| `tools/copy_data_after_export.py` | `3210a8de8d6afb24a9d7cf6c49b8c9df21f65b5ad5154227c83c0d4fb6a6ebd0` |
| `tools/list_presenter_private_access.py` | `38a083f0c190d70ac3a5e9dc4c44fd364328f1cac984fcc5b1a1d90aa7cb0f18` |
| `tools/release/freeze_prepare.py` | `d82162e28f2c465a07ac83f25f8b795705e89e9c04b4fdee370beeaf003d28fc` |
| `tools/release/package_audit.py` | `1a37ceb88732ce083989789eb3133322dd60495c0506df51064243ecd1309789` |
| `tools/release/release_prepare.py` | `a098ec5a66b7ec15cd378f7e86b5e5bdbfbe496e801e85f6b9abae121d8522bf` |
| `tools/release/round56_three_role_freeze.py` | `38eee23540bcfb09dfd7dcb008e6d1c1b8a7943f236347f5d95a6a010695880a` |
| `tools/release/runtime_audit.py` | `aeaf6938152b65e638fba80ff1bd27bfca2c29aa4144c3004d86539c4919ffda` |
| `tools/run_refactor_headless_baseline.py` | `3d13d0efa73a8e85120e43b85a32cbd1da51b280cca3bc23c8f67528008518bd` |
| `tools/run_refactor_window_baseline.py` | `df27a57ab9c2fcfe0ea17e3280ff214b856df7d82f3d77e9c188389dd4d5355e` |

### 本次验证的命令/操作边界

- `git status --short`、`git rev-parse HEAD`真实exit0，原工作树已有大量变更。本轮未撤销/暂存任何变更。
- Python只读调用 `check_layer_deps.scan/evaluate`（不执行write main）；`list_presenter_private_access.scan`、`classify_player_data_calls.build_report`（内存，不覆盖旧reports）；SHA用原字节hashlib计算。
- `python -B tools/copy_data_after_export.py --project E:/Projects/Godot/FateDominationGame-master`实际exit2，原stderr“必须且只能显式传入输出目录或 --preset 名称”，没有触达copy_data，不写输出目录。成功复制路径保持待验。
- 写前program核验126唯一ID、缺0/重复0；E58/E60原件SHA读回、现有符号定位及扫描内变化差异已核对。没启动任何Godot、GUI、worker或正式EXE，旧28100不在本次操作范围。
- 原plan/execution写前SHA仍等于本次读取时SHA；只新建本文，不改共享旧文档。

### 剩余未知/验收层

- ENet恢复首次断线的原生原因未知；只有native callback→cancel因果已证实。
- 旧发布rename失败未获唯一根因证明；新fresh成功/移除observer持锁风险不能覆盖旧失败。
- E58shutdown缺失原response/evidence无法恢复；当前新实例保存失败仍需新原件闭包，不用历史283绿抹红。
- 当前全量同源、自然双路径终局、完整窗口画面与正式三角色两client对局尚未验；新actor修改的runtime/cleanup/浏览/测试未自动继承任何PASS。

</details>
