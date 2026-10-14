# Round29 核心共同回归：最终原始证据

**整体 passed=false；不能作为最终冻结 PASS。**
证据：`E:\scratch\isolated-58a7a37b252b4755a7a62919f6db433e\manifest.json`
实际39套记录（严格通过22）；选择52套，缺13套；Validation20执行7/20，另有预检失败旧尝试独立保留，不充抵最终套数。
全生产只读，唯一代码为 tools/tests/test_round29_integrated_evidence.py。相同E独占快照；物理主/child user://回执、随机token、不同PID、child exit0均读回核验；Windows Job只管理自有进程；单套180s，无窗口。
每套实际命令/exit/错误、源码及快照前后hash、并行漂移均在manifest。快照全程未漂移；源码并行变化不借专项记录拼接PASS。

## Round28原始检验
D15真实20套/913 checks与summary一致；严格通过14/20，6套重复CHECK标签被拒绝。仅4项事后hash，不能证明全部20套运行的版本绑定。
D15相对当前漂移：["scripts/game_scene/battle_board_v2.gd"]
F09原始8组JSON与日志读回归档；F06双RESULT严格拒绝。F09源码hash差异：["E:\\Projects\\Godot\\FateDominationGame-master\\scripts\\net\\session\\lobby_session.gd"]
发行v3全部5个原始step日志已读取归档；原freeze、exe/PCK已按原cleanup回收，实包不可再次验hash。保留audit/index只是历史证据，不宣称运行验证或重新校验实包。

## Gateway负向精确绑定
gateway_relisten真实exit0、41 checks、无失败；stderr唯一错误为 `ERROR: Couldn't create an ENet host.`，唯一回溯为测试第92行明确占端口负向调用。测试源码hash与本次快照一致，占端口/拒绝监听/保持关闭/恢复监听断言均true，完整stderr精确6行匹配，绑定之外零错误。
负向绑定核验=True；原始strict passed仍false，整体passed=false。没有全局忽略ENet错误；无跨stdout/stderr时间顺序证据。

## 39套真实结果
|套件|exit|checks|严格通过|真实错误/拒绝原因|
|---|---:|---:|---|---|
|round28-command-migration_test|1|37|False|ERROR: Couldn't create an ENet host.; ERROR: Couldn't create an ENet host.; ERROR: Couldn't create an ENet host.; ERROR: Couldn't create an ENet host.; ERROR: Couldn't create an ENet host.; ERROR: Couldn't create an ENet host.; ERROR: Couldn't create an ENet host.; ERROR: Couldn't create an ENet host.; ERROR: Couldn't create an ENet host.; ERROR: Couldn't create an ENet host.; ERROR: Couldn't create an ENet host.; ERROR: Couldn't create an ENet host.; ERROR: Couldn't create an ENet host.; ERROR: Couldn't create an ENet host.; ERROR: Couldn't create an ENet host.; ERROR: Couldn't create an ENet host.; ERROR: Couldn't create an ENet host.; ERROR: Couldn't create an ENet host.; ERROR: Couldn't create an ENet host.; ERROR: Couldn't create an ENet host.; nonzero_exit; result_failures; engine_or_assertion_error; false_check; |
|battle_board_end_command_test|0|38|True||
|battle_board_activation_command_test|0|21|True||
|active_choice_source_command_test|0|65|False|duplicate_check; |
|card_choice_source_command_test|0|18|True||
|location_choice_source_command_test|0|37|False|duplicate_check; |
|battle_command_adapter_test|0|29|True||
|match_command_dispatcher_test|0|313|False|duplicate_check; |
|match_command_result_protocol_test|0|39|False|duplicate_check; |
|match_commands_test|0|17|True||
|net_pending_test|0|20|True||
|net_cards_test|0|7|True||
|net_move_test|0|11|True||
|net_locations_test|0|7|True||
|net_authority_ui_preview_feedback_test|0|8|True||
|battle_board_v2_test|0|53|True||
|battle_play_groups_test|125|None|False|ERROR: Index p_index = 0 is out of bounds ((int)data.children_cache.size() - data.internal_children_front_count_cache - data.internal_children_back_count_cache = 0).; SCRIPT ERROR: Cannot call method 'has_meta' on a null value.; nonzero_exit; expected_one_stdout_result; engine_or_assertion_error; false_check; timeout|
|deploy_rules_layer_test|0|22|True||
|mana_spend_test|0|45|False|duplicate_check; |
|regular_play_test|0|54|True||
|player_choice_source_command_test|0|65|False|duplicate_check; |
|client_identity_inbox_contract_test|0|58|True||
|host_room_inbox_contract_test|0|34|True||
|net_selection_settings_test|0|7|True||
|net_runtime_guard_test|0|34|True||
|net_resume_identity_test|0|26|True||
|gateway_deferred_test|1|None|False|SCRIPT ERROR: Invalid access to property or key '_recovery_probe' on a base object of type 'RefCounted (StubLink)'.; SCRIPT ERROR: Invalid access to property or key '_recovery_probe' on a base object of type 'RefCounted (StubLink)'.; SCRIPT ERROR: Invalid access to property or key '_recovery_probe' on a base object of type 'RefCounted (StubLink)'.; SCRIPT ERROR: Invalid access to property or key 'message_received' on a base object of type 'RefCounted (StubLink)'.; SCRIPT ERROR: Invalid access to property or key '_recovery_probe' on a base object of type 'RefCounted (StubLink)'.; SCRIPT ERROR: Invalid access to property or key '_recovery_probe' on a base object of type 'RefCounted (StubLink)'.; SCRIPT ERROR: Invalid access to property or key 'message_received' on a base object of type 'RefCounted (StubLink)'.; SCRIPT ERROR: Invalid access to property or key '_recovery_probe' on a base object of type 'RefCounted (StubLink)'.; SCRIPT ERROR: Invalid access to property or key '_recovery_probe' on a base object of type 'RefCounted (StubLink)'.; SCRIPT ERROR: Invalid access to property or key '_recovery_probe' on a base object of type 'RefCounted (StubLink)'.; SCRIPT ERROR: Invalid access to property or key '_recovery_probe' on a base object of type 'RefCounted (StubTransport)'.; SCRIPT ERROR: Invalid access to property or key '_recovery_probe' on a base object of type 'RefCounted (StubTransport)'.; SCRIPT ERROR: Invalid access to property or key '_recovery_probe' on a base object of type 'RefCounted (StubLink)'.; SCRIPT ERROR: Invalid access to property or key '_recovery_probe' on a base object of type 'RefCounted (StubLink)'.; SCRIPT ERROR: Invalid access to property or key '_recovery_probe' on a base object of type 'RefCounted (StubLink)'.; SCRIPT ERROR: Invalid access to property or key 'message_received' on a base object of type 'RefCounted (StubLink)'.; SCRIPT ERROR: Invalid access to property or key '_recovery_probe' on a base object of type 'RefCounted (StubTransport)'.; SCRIPT ERROR: Invalid access to property or key 'rooms' on a base object of type 'RefCounted (StubManager)'.; SCRIPT ERROR: Invalid access to property or key 'rooms' on a base object of type 'RefCounted (StubManager)'.; SCRIPT ERROR: Invalid access to property or key 'rooms' on a base object of type 'RefCounted (StubManager)'.; SCRIPT ERROR: Invalid access to property or key '_recovery_probe' on a base object of type 'RefCounted (StubLink)'.; SCRIPT ERROR: Invalid access to property or key 'message_received' on a base object of type 'RefCounted (StubLink)'.; SCRIPT ERROR: Invalid access to property or key 'rooms' on a base object of type 'RefCounted (StubManager)'.; SCRIPT ERROR: Invalid access to property or key '_recovery_probe' on a base object of type 'RefCounted (StubLink)'.; SCRIPT ERROR: Invalid access to property or key 'message_received' on a base object of type 'RefCounted (StubLink)'.; SCRIPT ERROR: Invalid access to property or key 'rooms' on a base object of type 'RefCounted (StubManager)'.; SCRIPT ERROR: Invalid access to property or key 'rooms' on a base object of type 'RefCounted (StubManager)'.; ERROR: 响应→延迟错误→关闭顺序; ERROR: 重复项只通知/关闭一次; ERROR: 再次 poll 不重复清理; ERROR: 公网重复断线合并; ERROR: 公网 poll 退出后 detach; ERROR: 公网断线不增加内部错误通知; ERROR: 静默清理保持无额外响应; nonzero_exit; invalid_result: Expecting value: line 1 column 1 (char 0); engine_or_assertion_error; |
|gateway_disconnect_safe_close_test|0|None|False|invalid_result: invalid field; |
|gateway_instance_binding_test|0|20|True||
|net_server_gateway_test|1|4|False|nonzero_exit; result_failures; false_check; |
|net_server_gateway_restart_test|1|1|False|nonzero_exit; result_failures; false_check; |
|net_data_validation_test|0|13|True||
|net_validation_io_feedback_test|0|None|False|invalid_result: invalid field; |
|net_validation_io_measure_test|0|9|False|duplicate_check; |
|net_background_validation_feedback_test|125|None|False|SCRIPT ERROR: Invalid assignment of property or key 'session' with value of type 'RefCounted (MatchLobbySession)' on a base object of type 'RefCounted (room_data_preparation.gd)'.; nonzero_exit; expected_one_stdout_result; engine_or_assertion_error; timeout|
|net_server_discovery_validation_test|1|5|False|nonzero_exit; result_failures; false_check; |
|content_environment_test|0|30|True||
|worker_content_environment_test|0|45|True||
|gateway_relisten_acceptance_test|0|41|False|ERROR: Couldn't create an ENet host.; engine_or_assertion_error; |

## 未完成与并行漂移
未完成13套：net_validation_task_test, net_validation_simulation_test, net_validation_hard_timeout_test, net_parallel_validation_feedback_test, room_data_preparation_consumer_test, room_data_preparation_dependencies_test, lobby_content_environment_restore_test, net_data_sync_test, net_blob_test, net_blob_authorization_test, net_blob_send_authorization_test, net_blob_concurrent_test, net_worker_startup_contract_test
Validation20为聚合器明确列出的20套选择；未检索到历史唯一清单，不能冒称既定全量。
本次有界失败：外层工具420s截断，随后复用原快照恢复；预检夹具缺显式根的旧失败归档保留；补齐夹具根重试时旧日志归档同名导致WinError183，批次停止并保守回收，13套缺失。该聚合器重名问题现已改为UUID归档，未重跑伪造补齐结果。
单套180s timeout：battle_play_groups_test, net_background_validation_feedback_test
源码运行期间漂移：[["regular_play_test", ["scripts/game_scene/battle_board_v2.gd"]], ["net_resume_identity_test", ["scripts/game_scene/battle_board_v2.gd"]], ["net_server_gateway_test", ["scripts/net/ui/v2_view_presenter.gd"]], ["net_server_gateway_restart_test", ["scripts/net/ui/v2_view_presenter.gd"]], ["net_background_validation_feedback_test", ["scripts/game_scene/battle_board_v2.gd"]]]
清理后源码hash相对快照差异（不是运行末刻）：["scripts/game_scene/battle_board_v2.gd", "scripts/net/ui/v2_view_presenter.gd", "tests/net_process_full_game_test.gd"]

## 归档与回收
generated已删除，读回不存在；单份E主引擎、项目副本、APPDATA和import缓存均回收，D源引擎hash未变。删除字节=1100821480。
保留manifest、全部真实日志/历史原始证据及精确hash绑定的网关专项源码。tests/reports可能被忽略，未git add、未提交；项目内只新增聚合器与本报告。


---

# Round29 核心共同回归证据
这是补跑独立快照，仅补充失败/缺口证据，不与前39套拼为冻结PASS。

结论：未达到冻结 PASS

证据 manifest：`E:\scratch\isolated-b773afee4fab4cd3917423d551a240ef\manifest.json`
全部生产只读；同一独占 E 快照、单套 180 秒；主/worker 真实 user:// 回执、Windows Job 自有进程。未开窗口。
Validation20 为本报告显式列出的20套选择，未找到历史唯一清单，不冒称既定全量。
套件 RESULT 前缀解析仅在本聚合器；缺/重复 RESULT、重复字段或 CHECK、false CHECK、非法计数、非零 exit 和引擎错误均拒绝。

|套件|真实 exit|checks|严格判定|错误/原因|
|---|---:|---:|---|---|
|net_validation_task_test|0|31|True||
|net_validation_simulation_test|0|35|True||
|net_validation_hard_timeout_test|1|13|False|nonzero_exit; result_failures; false_check; |
|net_parallel_validation_feedback_test|0|9|True||
|room_data_preparation_consumer_test|1|28|False|nonzero_exit; result_failures; false_check; |
|room_data_preparation_dependencies_test|0|34|False|duplicate_check; |
|lobby_content_environment_restore_test|0|1544|False|duplicate_check; |
|net_data_sync_test|1|8|False|nonzero_exit; result_failures; false_check; |
|net_blob_test|0|42|False|duplicate_check; |
|net_blob_authorization_test|1|4|False|nonzero_exit; result_failures; false_check; |
|net_blob_send_authorization_test|125|None|False|SCRIPT ERROR: Invalid access to property or key '788681313' on a base object of type 'Dictionary'.; nonzero_exit; expected_one_stdout_result; engine_or_assertion_error; false_check; timeout|
|net_blob_concurrent_test|0|20|False|duplicate_check; |
|net_worker_startup_contract_test|0|15|False|duplicate_check; |

Round28-D15 原始复核：套数=20，checks=913，严格通过=14；原有仅4项事后源码hash，不能证明20套完整冻结绑定。
其他28原始日志/JSON归档在 evidence/round28-originals；F06多RESULT严格拒绝，不拼接不同版本或子摘要。
与Round28源码hash差异、release源码/冻结/PCK实际读回、每套前后源码和冻结hash及并行漂移详见manifest。
本次最终源码漂移：`["scripts/net/session/lobby_session.gd", "scripts/net/ui/v2_view_presenter.gd"]`
清理：generated_removed；异常：无
tests与reports可能被忽略；未git add或修改忽略规则。完整证据在仓库外独占路径，不丢弃失败日志。
