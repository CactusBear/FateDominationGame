# Round33 integrated candidate

**同一候选副本串行整合；不宣称最终 freeze。top passed=false。**
manifest：`E:\Projects\Godot\FateDominationGame-master\reports\refactoring\round33-integrated-b9fbd2011963493eaf6b76f02032de1e\manifest.json`；独占所有权 manifest：`E:\scratch\isolated-b9fbd2011963493eaf6b76f02032de1e\manifest.json`。
执行命令：`python -B tools/tests/test_round29_integrated_evidence.py --round33`。
全部真实 Godot headless、fixed-fps 60、每套180秒、Windows Job仅自有PID；没有窗口输入验收。

## 选择与总计
读取原39实际记录及原52 selected_suites，再与 round32 补13和实际存在的新场景去重；仅复用名字，旧结果不参与本次计数。
选择=66；执行=66；专属判定通过=54；严格零错误通过=53；合法唯一 RESULT checks 合计=4060；原始 CHECK事件=3921；engine/assertion错误行=59；import错误=0。
缺套：`[]`；红项：`["battle_board_end_command_test", "gateway_deferred_test", "gateway_disconnect_safe_close_test", "net_server_gateway_test", "net_server_gateway_restart_test", "net_validation_io_feedback_test", "net_background_validation_feedback_test", "net_server_discovery_validation_test", "net_validation_simulation_test", "net_validation_hard_timeout_test", "local_spell_restore_test", "client_match_inbox_contract_test"]`；顶层拒绝原因：`["current_suite_failure", "current_source_drift", "source_final_drift"]`。
双 RESULT 的套件不计入合法唯一 RESULT checks；其原始 RESULT 全文保留，未删除第二行或充抵通过数。
选择清单：
```json
{
  "names": [
    "round28-command-migration_test",
    "battle_board_end_command_test",
    "battle_board_activation_command_test",
    "active_choice_source_command_test",
    "card_choice_source_command_test",
    "location_choice_source_command_test",
    "battle_command_adapter_test",
    "match_command_dispatcher_test",
    "match_command_result_protocol_test",
    "match_commands_test",
    "net_pending_test",
    "net_cards_test",
    "net_move_test",
    "net_locations_test",
    "net_authority_ui_preview_feedback_test",
    "battle_board_v2_test",
    "battle_play_groups_test",
    "deploy_rules_layer_test",
    "mana_spend_test",
    "regular_play_test",
    "player_choice_source_command_test",
    "client_identity_inbox_contract_test",
    "host_room_inbox_contract_test",
    "net_selection_settings_test",
    "net_runtime_guard_test",
    "net_resume_identity_test",
    "gateway_deferred_test",
    "gateway_disconnect_safe_close_test",
    "gateway_instance_binding_test",
    "net_server_gateway_test",
    "net_server_gateway_restart_test",
    "net_data_validation_test",
    "net_validation_io_feedback_test",
    "net_validation_io_measure_test",
    "net_background_validation_feedback_test",
    "net_server_discovery_validation_test",
    "content_environment_test",
    "worker_content_environment_test",
    "gateway_relisten_acceptance_test",
    "net_validation_task_test",
    "net_validation_simulation_test",
    "net_validation_hard_timeout_test",
    "net_parallel_validation_feedback_test",
    "room_data_preparation_consumer_test",
    "room_data_preparation_dependencies_test",
    "lobby_content_environment_restore_test",
    "net_data_sync_test",
    "net_blob_test",
    "net_blob_authorization_test",
    "net_blob_send_authorization_test",
    "net_blob_concurrent_test",
    "net_worker_startup_contract_test",
    "host_guard_inbox_contract_test",
    "net_guard_rollback_test",
    "rule_guard_root_transaction_v2_test",
    "rule_guard_rollback_test",
    "rule_guard_chain_rollback_test",
    "rule_guard_continuation_occurrence_test",
    "round29-shared-presentation_test",
    "shared_spell_view_contract_test",
    "local_spell_restore_test",
    "mirror_spell_negative_test",
    "match_view_test",
    "match_view_privacy_test",
    "client_match_inbox_contract_test",
    "gateway_bind_failure_test"
  ],
  "old_actual_count": 39,
  "old_selected_count": 52,
  "supplement_count": 13,
  "selected_count": 66,
  "missing_from_old_selection": [],
  "policy": "Historical names only; every result is rerun in one new candidate freeze."
}
```

## 隔离、导入与20线程
真实 main/worker user://随机token、物理E路径、独立PID和child exit0已由verify_probe读回；原回执摘要在manifest。
```json
[
  {
    "path": "E:/scratch/isolated-b9fbd2011963493eaf6b76f02032de1e/generated/appdata/FateDomination",
    "pid": 21536,
    "role": "main",
    "token": "b9fbd2011963493eaf6b76f02032de1e",
    "worker_pool_max_threads": 20,
    "physical_path": "E:\\scratch\\isolated-b9fbd2011963493eaf6b76f02032de1e\\generated\\appdata\\FateDomination",
    "probe_sha256": "66e6de93f78c6eac28775da0155f395dd44cd6542ac9059d3354b3d4eaecfd3c",
    "receipt_sha256": "0cd908b7e95bdf5a02060e5723d58073dd4eba7faf38bc1d1e7bf08e71a44fbb"
  },
  {
    "path": "E:/scratch/isolated-b9fbd2011963493eaf6b76f02032de1e/generated/appdata/FateDomination",
    "pid": 31088,
    "role": "worker",
    "token": "b9fbd2011963493eaf6b76f02032de1e",
    "worker_pool_max_threads": 20,
    "physical_path": "E:\\scratch\\isolated-b9fbd2011963493eaf6b76f02032de1e\\generated\\appdata\\FateDomination",
    "probe_sha256": "66e6de93f78c6eac28775da0155f395dd44cd6542ac9059d3354b3d4eaecfd3c",
    "receipt_sha256": "c6480dda3884ea3680d90f0ff119b4c0e0c1f9fe17e4a6ca813cc07fdcd62d35"
  }
]
```
import exit=0；errors=[]。
唯一副本转换仍限 `[editor]` 两项VCS字段；threading原文不变，实际主/worker worker_pool_max_threads均要求20。
```json
{
  "scope": "isolated_project_copy_only",
  "authorized_section": "[editor]",
  "authorized_fields": [
    "version_control/plugin_name",
    "version_control/autoload_on_startup"
  ],
  "reason": "Disable development VCS autoload only in the isolated freeze before import.",
  "operations": [
    {
      "field": "version_control/plugin_name",
      "action": "remove",
      "original": "version_control/plugin_name=\"GitPlugin\"",
      "transformed": null
    },
    {
      "field": "version_control/autoload_on_startup",
      "action": "replace",
      "original": "version_control/autoload_on_startup=true",
      "transformed": "version_control/autoload_on_startup=false"
    }
  ],
  "source_sha256": "986a066adc6f0d1346d19612538780abaf2ce4d3cdfef4342db653a0b53d8c8a",
  "transformed_sha256": "72e82db409d55d2ba67c4402b8ecf80a0804ca9129308793bc1a15b4352deb7b",
  "editor_before_sha256": "08c164108100adfbea21181b36809c1949ce3602325b6f44dfd63a2061706380",
  "editor_after_sha256": "0955fbdf9e85c7b3f880b2e3a76460cbe90c1c50f05f1d6ab48c961d160da192",
  "changed_sections": [
    "[editor]"
  ],
  "unauthorized_changes": [],
  "path": "project.godot",
  "source_file_sha256": "986a066adc6f0d1346d19612538780abaf2ce4d3cdfef4342db653a0b53d8c8a",
  "frozen_before_sha256": "986a066adc6f0d1346d19612538780abaf2ce4d3cdfef4342db653a0b53d8c8a",
  "frozen_after_sha256": "72e82db409d55d2ba67c4402b8ecf80a0804ca9129308793bc1a15b4352deb7b",
  "authorized_paths": [
    "project.godot"
  ],
  "source_unchanged_after_transform": true,
  "threading_before": "[threading]\n\nworker_pool/max_threads=20\n",
  "threading_after": "[threading]\n\nworker_pool/max_threads=20\n",
  "threading_unchanged": true,
  "worker_pool_max_threads_20": true,
  "verified": true
}
```

## 正向38与独立bind负向7
gateway_relisten_acceptance_test要求38 checks及全日志零错误。gateway_bind_failure_test单列，要求7 checks、精确六行stderr、冻结源码hash和第13行调用绑定；通用analyze仍拒绝这个原生ERROR。没有全局忽略。

## F06 duplicate RESULT：唯一测试owner交接
`tests/client_match_inbox_contract_test.gd` 正常成功路径第149行输出original阶段RESULT，await reconnect_contract后第151行再输出累计RESULT；不是引擎重复转发。
交接唯一 test owner：F06 client inbox contract 写入者（由主代理路由）；整合代理仅保留冻结源码/日志，不修改该测试，也不放宽重复RESULT。另有status=GREEN/RED裸值不符合严格JSON值协议，需要同一owner同时处理，不能靠解析器放宽。

## 全量suite结果
|suite|exit|checks|CHECK事件|通过/分类|errors / reasons|
|---|---:|---:|---:|---|---|
|round28-command-migration_test|0|66|66|True / positive||
|battle_board_end_command_test|1|9|9|False / positive|ERROR: Couldn't create an ENet host.; ERROR: Couldn't create an ENet host.; ERROR: Couldn't create an ENet host.; ERROR: Couldn't create an ENet host.; ERROR: Couldn't create an ENet host.; ERROR: Couldn't create an ENet host.; ERROR: Couldn't create an ENet host.; ERROR: Couldn't create an ENet host.; ERROR: Couldn't create an ENet host.; ERROR: Couldn't create an ENet host.; ERROR: Couldn't create an ENet host.; ERROR: Couldn't create an ENet host.; ERROR: Couldn't create an ENet host.; ERROR: Couldn't create an ENet host.; ERROR: Couldn't create an ENet host.; ERROR: Couldn't create an ENet host.; ERROR: Couldn't create an ENet host.; ERROR: Couldn't create an ENet host.; ERROR: Couldn't create an ENet host.; ERROR: Couldn't create an ENet host.; nonzero_exit; result_failures; engine_or_assertion_error; false_check; |
|battle_board_activation_command_test|0|21|21|True / positive||
|active_choice_source_command_test|0|65|65|True / positive||
|card_choice_source_command_test|0|18|18|True / positive||
|location_choice_source_command_test|0|37|37|True / positive||
|battle_command_adapter_test|0|29|29|True / positive||
|match_command_dispatcher_test|0|313|313|True / positive||
|match_command_result_protocol_test|0|39|39|True / positive||
|match_commands_test|0|17|17|True / positive||
|net_pending_test|0|20|20|True / positive||
|net_cards_test|0|7|7|True / positive||
|net_move_test|0|11|11|True / positive||
|net_locations_test|0|7|7|True / positive||
|net_authority_ui_preview_feedback_test|0|8|8|True / positive||
|battle_board_v2_test|0|53|53|True / positive||
|battle_play_groups_test|0|43|43|True / positive||
|deploy_rules_layer_test|0|22|22|True / positive||
|mana_spend_test|0|45|45|True / positive||
|regular_play_test|0|54|54|True / positive||
|player_choice_source_command_test|0|65|65|True / positive||
|client_identity_inbox_contract_test|0|58|0|True / positive||
|host_room_inbox_contract_test|0|34|34|True / positive||
|net_selection_settings_test|0|7|7|True / positive||
|net_runtime_guard_test|0|34|34|True / positive||
|net_resume_identity_test|0|26|26|True / positive||
|gateway_deferred_test|1|None|0|False / positive|SCRIPT ERROR: Invalid access to property or key '_recovery_probe' on a base object of type 'RefCounted (StubLink)'.; SCRIPT ERROR: Invalid access to property or key '_recovery_probe' on a base object of type 'RefCounted (StubLink)'.; SCRIPT ERROR: Invalid access to property or key '_recovery_probe' on a base object of type 'RefCounted (StubLink)'.; SCRIPT ERROR: Invalid access to property or key 'message_received' on a base object of type 'RefCounted (StubLink)'.; SCRIPT ERROR: Invalid access to property or key '_recovery_probe' on a base object of type 'RefCounted (StubLink)'.; SCRIPT ERROR: Invalid access to property or key '_recovery_probe' on a base object of type 'RefCounted (StubLink)'.; SCRIPT ERROR: Invalid access to property or key 'message_received' on a base object of type 'RefCounted (StubLink)'.; SCRIPT ERROR: Invalid access to property or key '_recovery_probe' on a base object of type 'RefCounted (StubLink)'.; SCRIPT ERROR: Invalid access to property or key '_recovery_probe' on a base object of type 'RefCounted (StubLink)'.; SCRIPT ERROR: Invalid access to property or key '_recovery_probe' on a base object of type 'RefCounted (StubLink)'.; SCRIPT ERROR: Invalid access to property or key '_recovery_probe' on a base object of type 'RefCounted (StubTransport)'.; SCRIPT ERROR: Invalid access to property or key '_recovery_probe' on a base object of type 'RefCounted (StubTransport)'.; SCRIPT ERROR: Invalid access to property or key '_recovery_probe' on a base object of type 'RefCounted (StubLink)'.; SCRIPT ERROR: Invalid access to property or key '_recovery_probe' on a base object of type 'RefCounted (StubLink)'.; SCRIPT ERROR: Invalid access to property or key '_recovery_probe' on a base object of type 'RefCounted (StubLink)'.; SCRIPT ERROR: Invalid access to property or key 'message_received' on a base object of type 'RefCounted (StubLink)'.; SCRIPT ERROR: Invalid access to property or key '_recovery_probe' on a base object of type 'RefCounted (StubTransport)'.; SCRIPT ERROR: Invalid access to property or key 'rooms' on a base object of type 'RefCounted (StubManager)'.; SCRIPT ERROR: Invalid access to property or key 'rooms' on a base object of type 'RefCounted (StubManager)'.; SCRIPT ERROR: Invalid access to property or key 'rooms' on a base object of type 'RefCounted (StubManager)'.; SCRIPT ERROR: Invalid access to property or key '_recovery_probe' on a base object of type 'RefCounted (StubLink)'.; SCRIPT ERROR: Invalid access to property or key 'message_received' on a base object of type 'RefCounted (StubLink)'.; SCRIPT ERROR: Invalid access to property or key 'rooms' on a base object of type 'RefCounted (StubManager)'.; SCRIPT ERROR: Invalid access to property or key '_recovery_probe' on a base object of type 'RefCounted (StubLink)'.; SCRIPT ERROR: Invalid access to property or key 'message_received' on a base object of type 'RefCounted (StubLink)'.; SCRIPT ERROR: Invalid access to property or key 'rooms' on a base object of type 'RefCounted (StubManager)'.; SCRIPT ERROR: Invalid access to property or key 'rooms' on a base object of type 'RefCounted (StubManager)'.; ERROR: 响应→延迟错误→关闭顺序; ERROR: 重复项只通知/关闭一次; ERROR: 再次 poll 不重复清理; ERROR: 公网重复断线合并; ERROR: 公网 poll 退出后 detach; ERROR: 公网断线不增加内部错误通知; ERROR: 静默清理保持无额外响应; nonzero_exit; invalid_result: Expecting value: line 1 column 1 (char 0); engine_or_assertion_error; |
|gateway_disconnect_safe_close_test|0|None|0|False / positive|invalid_result: invalid field; |
|gateway_instance_binding_test|0|20|0|True / positive||
|net_server_gateway_test|1|4|4|False / positive|nonzero_exit; result_failures; false_check; |
|net_server_gateway_restart_test|1|1|1|False / positive|nonzero_exit; result_failures; false_check; |
|net_data_validation_test|0|13|13|True / positive||
|net_validation_io_feedback_test|0|None|0|False / positive|invalid_result: invalid field; |
|net_validation_io_measure_test|0|9|9|True / positive||
|net_background_validation_feedback_test|125|None|0|False / execution_failure|SCRIPT ERROR: Invalid assignment of property or key 'session' with value of type 'RefCounted (MatchLobbySession)' on a base object of type 'RefCounted (room_data_preparation.gd)'.; nonzero_exit; expected_one_stdout_result; engine_or_assertion_error; timeout|
|net_server_discovery_validation_test|1|5|5|False / positive|nonzero_exit; result_failures; false_check; |
|content_environment_test|0|30|0|True / positive||
|worker_content_environment_test|0|45|0|True / positive||
|gateway_relisten_acceptance_test|0|38|38|True / positive||
|net_validation_task_test|0|31|31|True / positive||
|net_validation_simulation_test|1|15|15|False / positive|nonzero_exit; result_failures; false_check; |
|net_validation_hard_timeout_test|1|13|13|False / positive|nonzero_exit; result_failures; false_check; |
|net_parallel_validation_feedback_test|0|9|9|True / positive||
|room_data_preparation_consumer_test|0|50|50|True / positive||
|room_data_preparation_dependencies_test|0|34|34|True / positive||
|lobby_content_environment_restore_test|0|1544|1544|True / positive||
|net_data_sync_test|0|14|14|True / positive||
|net_blob_test|0|42|42|True / positive||
|net_blob_authorization_test|0|58|58|True / positive||
|net_blob_send_authorization_test|0|14|14|True / positive||
|net_blob_concurrent_test|0|20|20|True / positive||
|net_worker_startup_contract_test|0|15|15|True / positive||
|host_guard_inbox_contract_test|0|72|72|True / positive||
|net_guard_rollback_test|0|39|39|True / positive||
|rule_guard_root_transaction_v2_test|0|58|58|True / positive||
|rule_guard_rollback_test|0|18|18|True / positive||
|rule_guard_chain_rollback_test|0|17|17|True / positive||
|rule_guard_continuation_occurrence_test|0|54|54|True / positive||
|round29-shared-presentation_test|0|142|142|True / positive||
|shared_spell_view_contract_test|0|87|87|True / positive||
|local_spell_restore_test|125|None|14|False / execution_failure|ERROR: Index p_index = 0 is out of bounds ((int)data.children_cache.size() - data.internal_children_front_count_cache - data.internal_children_back_count_cache = 0).; ERROR: Index p_index = 0 is out of bounds ((int)data.children_cache.size() - data.internal_children_front_count_cache - data.internal_children_back_count_cache = 0).; SCRIPT ERROR: Cannot call method 'get_global_rect' on a null value.; nonzero_exit; expected_one_stdout_result; engine_or_assertion_error; false_check; timeout|
|mirror_spell_negative_test|0|73|73|True / positive||
|match_view_test|0|224|224|True / positive||
|match_view_privacy_test|0|137|137|True / positive||
|client_match_inbox_contract_test|0|None|0|False / positive|expected_one_stdout_result; |
|gateway_bind_failure_test|0|7|7|True / scoped_bind_negative|ERROR: Couldn't create an ENet host.; |

## 红项精确证据
### battle_board_end_command_test
实际命令：`["E:\\scratch\\isolated-b9fbd2011963493eaf6b76f02032de1e\\generated\\Godot.exe", "--headless", "--fixed-fps", "60", "--path", "E:\\scratch\\isolated-b9fbd2011963493eaf6b76f02032de1e\\generated\\project", "--scene", "res://tests/battle_board_end_command_test.tscn"]`
RESULT：
```text
RESULT checks=9 failures=["真实 ENet host"]
```
错误：
```text
ERROR: Couldn't create an ENet host.
ERROR: Couldn't create an ENet host.
ERROR: Couldn't create an ENet host.
ERROR: Couldn't create an ENet host.
ERROR: Couldn't create an ENet host.
ERROR: Couldn't create an ENet host.
ERROR: Couldn't create an ENet host.
ERROR: Couldn't create an ENet host.
ERROR: Couldn't create an ENet host.
ERROR: Couldn't create an ENet host.
ERROR: Couldn't create an ENet host.
ERROR: Couldn't create an ENet host.
ERROR: Couldn't create an ENet host.
ERROR: Couldn't create an ENet host.
ERROR: Couldn't create an ENet host.
ERROR: Couldn't create an ENet host.
ERROR: Couldn't create an ENet host.
ERROR: Couldn't create an ENet host.
ERROR: Couldn't create an ENet host.
ERROR: Couldn't create an ENet host.
```
冻结失败目标源码：`evidence/failed-source/battle_board_end_command_test.gd`；完整日志：`evidence/battle_board_end_command_test.stdout.log` / stderr.log。
### gateway_deferred_test
实际命令：`["E:\\scratch\\isolated-b9fbd2011963493eaf6b76f02032de1e\\generated\\Godot.exe", "--headless", "--fixed-fps", "60", "--path", "E:\\scratch\\isolated-b9fbd2011963493eaf6b76f02032de1e\\generated\\project", "--scene", "res://tests/gateway_deferred_test.tscn"]`
RESULT：
```text
RESULT gateway_deferred_scheduler checks=16 failures=7 scope=scheduling_unit_only
```
错误：
```text
SCRIPT ERROR: Invalid access to property or key '_recovery_probe' on a base object of type 'RefCounted (StubLink)'.
SCRIPT ERROR: Invalid access to property or key '_recovery_probe' on a base object of type 'RefCounted (StubLink)'.
SCRIPT ERROR: Invalid access to property or key '_recovery_probe' on a base object of type 'RefCounted (StubLink)'.
SCRIPT ERROR: Invalid access to property or key 'message_received' on a base object of type 'RefCounted (StubLink)'.
SCRIPT ERROR: Invalid access to property or key '_recovery_probe' on a base object of type 'RefCounted (StubLink)'.
SCRIPT ERROR: Invalid access to property or key '_recovery_probe' on a base object of type 'RefCounted (StubLink)'.
SCRIPT ERROR: Invalid access to property or key 'message_received' on a base object of type 'RefCounted (StubLink)'.
SCRIPT ERROR: Invalid access to property or key '_recovery_probe' on a base object of type 'RefCounted (StubLink)'.
SCRIPT ERROR: Invalid access to property or key '_recovery_probe' on a base object of type 'RefCounted (StubLink)'.
SCRIPT ERROR: Invalid access to property or key '_recovery_probe' on a base object of type 'RefCounted (StubLink)'.
SCRIPT ERROR: Invalid access to property or key '_recovery_probe' on a base object of type 'RefCounted (StubTransport)'.
SCRIPT ERROR: Invalid access to property or key '_recovery_probe' on a base object of type 'RefCounted (StubTransport)'.
SCRIPT ERROR: Invalid access to property or key '_recovery_probe' on a base object of type 'RefCounted (StubLink)'.
SCRIPT ERROR: Invalid access to property or key '_recovery_probe' on a base object of type 'RefCounted (StubLink)'.
SCRIPT ERROR: Invalid access to property or key '_recovery_probe' on a base object of type 'RefCounted (StubLink)'.
SCRIPT ERROR: Invalid access to property or key 'message_received' on a base object of type 'RefCounted (StubLink)'.
SCRIPT ERROR: Invalid access to property or key '_recovery_probe' on a base object of type 'RefCounted (StubTransport)'.
SCRIPT ERROR: Invalid access to property or key 'rooms' on a base object of type 'RefCounted (StubManager)'.
SCRIPT ERROR: Invalid access to property or key 'rooms' on a base object of type 'RefCounted (StubManager)'.
SCRIPT ERROR: Invalid access to property or key 'rooms' on a base object of type 'RefCounted (StubManager)'.
SCRIPT ERROR: Invalid access to property or key '_recovery_probe' on a base object of type 'RefCounted (StubLink)'.
SCRIPT ERROR: Invalid access to property or key 'message_received' on a base object of type 'RefCounted (StubLink)'.
SCRIPT ERROR: Invalid access to property or key 'rooms' on a base object of type 'RefCounted (StubManager)'.
SCRIPT ERROR: Invalid access to property or key '_recovery_probe' on a base object of type 'RefCounted (StubLink)'.
SCRIPT ERROR: Invalid access to property or key 'message_received' on a base object of type 'RefCounted (StubLink)'.
SCRIPT ERROR: Invalid access to property or key 'rooms' on a base object of type 'RefCounted (StubManager)'.
SCRIPT ERROR: Invalid access to property or key 'rooms' on a base object of type 'RefCounted (StubManager)'.
ERROR: 响应→延迟错误→关闭顺序
ERROR: 重复项只通知/关闭一次
ERROR: 再次 poll 不重复清理
ERROR: 公网重复断线合并
ERROR: 公网 poll 退出后 detach
ERROR: 公网断线不增加内部错误通知
ERROR: 静默清理保持无额外响应
```
冻结失败目标源码：`evidence/failed-source/gateway_deferred_test.gd`；完整日志：`evidence/gateway_deferred_test.stdout.log` / stderr.log。
### gateway_disconnect_safe_close_test
实际命令：`["E:\\scratch\\isolated-b9fbd2011963493eaf6b76f02032de1e\\generated\\Godot.exe", "--headless", "--fixed-fps", "60", "--path", "E:\\scratch\\isolated-b9fbd2011963493eaf6b76f02032de1e\\generated\\project", "--scene", "res://tests/gateway_disconnect_safe_close_test.tscn"]`
RESULT：
```text
RESULT gateway_disconnect_safe_close PASS errors=0
```
错误：
```text

```
冻结失败目标源码：`evidence/failed-source/gateway_disconnect_safe_close_test.gd`；完整日志：`evidence/gateway_disconnect_safe_close_test.stdout.log` / stderr.log。
### net_server_gateway_test
实际命令：`["E:\\scratch\\isolated-b9fbd2011963493eaf6b76f02032de1e\\generated\\Godot.exe", "--headless", "--fixed-fps", "60", "--path", "E:\\scratch\\isolated-b9fbd2011963493eaf6b76f02032de1e\\generated\\project", "--scene", "res://tests/net_server_gateway_test.tscn"]`
RESULT：
```text
RESULT checks=4 failures=["服务端明确 worker ready 后再等大厅快照", "routed logical peer identity receives room ownership"]
```
错误：
```text

```
冻结失败目标源码：`evidence/failed-source/net_server_gateway_test.gd`；完整日志：`evidence/net_server_gateway_test.stdout.log` / stderr.log。
### net_server_gateway_restart_test
实际命令：`["E:\\scratch\\isolated-b9fbd2011963493eaf6b76f02032de1e\\generated\\Godot.exe", "--headless", "--fixed-fps", "60", "--path", "E:\\scratch\\isolated-b9fbd2011963493eaf6b76f02032de1e\\generated\\project", "--scene", "res://tests/net_server_gateway_restart_test.tscn"]`
RESULT：
```text
RESULT checks=1 failures=["测试组合入口批准物理scratch：需要显式 FATE_TEST_SCRATCH_ROOT 及首个输出根参数"]
```
错误：
```text

```
冻结失败目标源码：`evidence/failed-source/net_server_gateway_restart_test.gd`；完整日志：`evidence/net_server_gateway_restart_test.stdout.log` / stderr.log。
### net_validation_io_feedback_test
实际命令：`["E:\\scratch\\isolated-b9fbd2011963493eaf6b76f02032de1e\\generated\\Godot.exe", "--headless", "--fixed-fps", "60", "--path", "E:\\scratch\\isolated-b9fbd2011963493eaf6b76f02032de1e\\generated\\project", "--scene", "res://tests/net_validation_io_feedback_test.tscn"]`
RESULT：
```text
RESULT validation_io failures=0 []
```
错误：
```text

```
冻结失败目标源码：`evidence/failed-source/net_validation_io_feedback_test.gd`；完整日志：`evidence/net_validation_io_feedback_test.stdout.log` / stderr.log。
### net_background_validation_feedback_test
实际命令：`["E:\\scratch\\isolated-b9fbd2011963493eaf6b76f02032de1e\\generated\\Godot.exe", "--headless", "--fixed-fps", "60", "--path", "E:\\scratch\\isolated-b9fbd2011963493eaf6b76f02032de1e\\generated\\project", "--scene", "res://tests/net_background_validation_feedback_test.tscn"]`
RESULT：
```text

```
错误：
```text
SCRIPT ERROR: Invalid assignment of property or key 'session' with value of type 'RefCounted (MatchLobbySession)' on a base object of type 'RefCounted (room_data_preparation.gd)'.
```
冻结失败目标源码：`evidence/failed-source/net_background_validation_feedback_test.gd`；完整日志：`evidence/net_background_validation_feedback_test.stdout.log` / stderr.log。
### net_server_discovery_validation_test
实际命令：`["E:\\scratch\\isolated-b9fbd2011963493eaf6b76f02032de1e\\generated\\Godot.exe", "--headless", "--fixed-fps", "60", "--path", "E:\\scratch\\isolated-b9fbd2011963493eaf6b76f02032de1e\\generated\\project", "--scene", "res://tests/net_server_discovery_validation_test.tscn"]`
RESULT：
```text
RESULT checks=5 failures=["发现只登记有效房间，坏端口路径及恢复状态逐项拒绝", "坏配置不能部分登记或启动进程"]
```
错误：
```text

```
冻结失败目标源码：`evidence/failed-source/net_server_discovery_validation_test.gd`；完整日志：`evidence/net_server_discovery_validation_test.stdout.log` / stderr.log。
### net_validation_simulation_test
实际命令：`["E:\\scratch\\isolated-b9fbd2011963493eaf6b76f02032de1e\\generated\\Godot.exe", "--headless", "--fixed-fps", "60", "--path", "E:\\scratch\\isolated-b9fbd2011963493eaf6b76f02032de1e\\generated\\project", "--scene", "res://tests/net_validation_simulation_test.tscn"]`
RESULT：
```text
RESULT checks=15 failures=["nonblocking wrapper accepts error-free complete engine load"]
```
错误：
```text

```
冻结失败目标源码：`evidence/failed-source/net_validation_simulation_test.gd`；完整日志：`evidence/net_validation_simulation_test.stdout.log` / stderr.log。
### net_validation_hard_timeout_test
实际命令：`["E:\\scratch\\isolated-b9fbd2011963493eaf6b76f02032de1e\\generated\\Godot.exe", "--headless", "--fixed-fps", "60", "--path", "E:\\scratch\\isolated-b9fbd2011963493eaf6b76f02032de1e\\generated\\project", "--scene", "res://tests/net_validation_hard_timeout_test.tscn"]`
RESULT：
```text
RESULT checks=13 failures=["explicit chosen data assembles under approved scratch root"]
```
错误：
```text

```
冻结失败目标源码：`evidence/failed-source/net_validation_hard_timeout_test.gd`；完整日志：`evidence/net_validation_hard_timeout_test.stdout.log` / stderr.log。
### local_spell_restore_test
实际命令：`["E:\\scratch\\isolated-b9fbd2011963493eaf6b76f02032de1e\\generated\\Godot.exe", "--headless", "--fixed-fps", "60", "--path", "E:\\scratch\\isolated-b9fbd2011963493eaf6b76f02032de1e\\generated\\project", "--scene", "res://tests/local_spell_restore_test.tscn"]`
RESULT：
```text

```
错误：
```text
ERROR: Index p_index = 0 is out of bounds ((int)data.children_cache.size() - data.internal_children_front_count_cache - data.internal_children_back_count_cache = 0).
ERROR: Index p_index = 0 is out of bounds ((int)data.children_cache.size() - data.internal_children_front_count_cache - data.internal_children_back_count_cache = 0).
SCRIPT ERROR: Cannot call method 'get_global_rect' on a null value.
```
冻结失败目标源码：`evidence/failed-source/local_spell_restore_test.gd`；完整日志：`evidence/local_spell_restore_test.stdout.log` / stderr.log。
### client_match_inbox_contract_test
实际命令：`["E:\\scratch\\isolated-b9fbd2011963493eaf6b76f02032de1e\\generated\\Godot.exe", "--headless", "--fixed-fps", "60", "--path", "E:\\scratch\\isolated-b9fbd2011963493eaf6b76f02032de1e\\generated\\project", "--scene", "res://tests/client_match_inbox_contract_test.tscn"]`
RESULT：
```text
RESULT client_match_inbox_contract_original checks=34 failures=0
RESULT client_match_inbox_contract_test checks=45 failures=0 status=GREEN
```
错误：
```text

```
冻结失败目标源码：`evidence/failed-source/client_match_inbox_contract_test.gd`；完整日志：`evidence/client_match_inbox_contract_test.stdout.log` / stderr.log。

## 漂移与回收
源码最终相对候选漂移：`["scripts/game_scene/battle_board_v2.gd", "scripts/net/validation/room_data_validation_worker.gd"]`。
源码套件期间并行漂移：`[["net_background_validation_feedback_test", ["scripts/net/validation/room_data_validation_worker.gd"]], ["lobby_content_environment_restore_test", ["scripts/game_scene/battle_board_v2.gd"]], ["net_blob_authorization_test", ["scripts/net/validation/room_data_validation_worker.gd"]]]`。
冻结副本漂移：`[]`。
并行UI/mirror修改不会回灌候选；后续源树不是这个版本。只记录candidate，不拼39+13不同版本或反复整批重跑。
清理=generated_removed；generated存在=False；源Godot hash未变=True；自有全部进程退出/日志释放=True。
archive日志摘要读回一致=True；两份旧manifest字节未变=True。大副本（E引擎/项目/import缓存/APPDATA）已按自有生成树回收，保留最小原始证据。
未改generic runner、production、游戏tests或旧证据；未git add/commit。

## 收尾补充：精确owner交接与执行器后补丁

以下仅补充诊断，不重写本次manifest、原始日志或通过数。`aggregator.py`为本次真正执行版本；`post-run-aggregator.py`为结束后补齐restart首参数的版本。后补丁经过4个Python单测、严格parser及round32配置转换单测（全部exit0），没有重跑Godot或将该红项升级。

|红项|已核实诊断 / 唯一写入者交接|
|---|---|
|battle_board_end_command_test|本次PID35708算出51708–51727，全部处于Windows UDP排除段51674–51773；20次ENet bind都真实失败。交该测试唯一owner复用安全端口夹具，不能全局忽略ENet错误。`evidence/windows-udp-excluded-ranges.log`已归档。|
|gateway_deferred_test|旧StubLink/StubTransport缺`_recovery_probe`，StubLink还缺`message_received`等正式契约；生产Gateway第701/419/398行暴露SCRIPT ERROR，RESULT还含裸scope值。交调度测试唯一owner，不由整合器削弱生产契约。|
|gateway_disconnect_safe_close_test|实际exit0，但仅`RESULT ... PASS errors=0`，没有正整数checks及显式failures/failed，严格协议拒绝；交该测试唯一owner规范唯一RESULT。|
|net_server_gateway_test|stdout明确`SERVER_ROOM_CREATE_FAILED`：批准数据根必须由本机部署入口显式提供；测试未给manager批准根。交该测试唯一owner补正式部署夹具，不放宽生产批准根门。|
|net_server_gateway_restart_test|整合器原命令漏首个输出根参数；继承的`net_server_match_test.fixture_directory`同时要求环境批准根与首参数。已在自有`suite_command`补参数并单测；本次原失败仍保留，未声称运行通过。|
|net_validation_io_feedback_test|实际exit0，但`RESULT validation_io failures=0 []`缺checks且尾部不符合字段协议；交该测试唯一owner，不按zero-exit冒充通过。|
|net_background_validation_feedback_test|第8行仍给已解耦preparation对象赋`session`，SCRIPT ERROR后没有RESULT，单套180s由自有Job终止、实际exit125；交该测试唯一owner适配真实公开入口并短路失败。|
|net_server_discovery_validation_test|发现预期与当前严格恢复配置不符（5 checks/2 failures）；还有副本外硬编码目录。交该测试唯一owner按正式schema/批准根及显式独占scratch迁移，不能按旧预期降低恢复校验。|
|net_validation_simulation_test|完整清单装配通过，但独立真实校验无法发布完整会话目录，15 checks/1 failure；交validation/task模块owner查路径发布及候选会话状态。|
|net_validation_hard_timeout_test|13 checks/1 failure：真实批准内容装配失败；`ASSEMBLY_DIAGNOSTIC reproduced=true`且错误字段空，不能判成超时通过。交validation/assembly及该测试唯一owner保留诊断、定位实际拒绝原因。|
|local_spell_restore_test|注入specials后实际卡行为空，第69/82行get_child越界，第96行null调用，随后180s终止exit125；交令咒共享UI/该测试唯一owner核实真实声明入口，并先防级联异常。不能把headless注入当GUI点击验收。|
|client_match_inbox_contract_test（F06）|本次真实exit0但两行RESULT为34/45 checks，第二行还有裸`status=GREEN`。第149/151行成功路径双输出，唯一F06 test owner同时修输出唯一性与JSON值协议；整合器不放宽。|

本次与round32冻结共同的2104个文件摘要完全一致，仅增加119个明确测试依赖文件；这是源码字节比较，不是借旧13套成功充抵本次。比较证据：`evidence/round32-common-source-comparison.json`。本次simulation/hard-timeout转红仍是真实结果，需要模块owner定位，不通过不同运行拼PASS。

主代理另已报告GUI菜单99项双链成功，但令咒点击`pending={}`、仅zoom未到权威发动；该根因专项由独立owner处理，不在本报告标记已验收，也未修改其游戏tests。源码最终并行漂移为`battle_board_v2.gd`及`room_data_validation_worker.gd`，本候选不可代表这些后续修改。

## 副本外旧夹具与保守回收边界

主/worker真实user://均已核验物理E独占路径；但旧测试存在硬编码绝对输出，不能宣称所有测试写入均纳入generated预算。已消费的`lobby-content-environment-34220-2937435`通过本次真实PID、冻源码、创建时间、退出记录和整树无链接复核，逐文件核对正式素材摘要后手动回收：616文件、288696606字节，其中611文件确认正式来源保持不变；剩余5项仅为已消费的测试cache/tag计划。源PID34220的CIM读回为空，删除后精确根不存在。清理计划/回执为`external-lobby-cleanup-plan.json`与`external-lobby-cleanup-receipt.json`，不伪装成generic runner的token-owned清理。

两个无PID/token回执小目录保守保留：`E:/Projects/Godot/FateDomination/test/discovery-2676638`（891字节），`.../concurrent-blob-1980007`（0字节）。没有盲删同前缀旧任务或正式存档。所有大副本、独占E引擎、生成APPDATA/import缓存及已消费的大型外部测试素材副本已回收；这不证明旧测试绝对路径隔离已经修复，须由对应测试owner迁移。

后补丁摘要、单测日志摘要、保留项和清理边界：`post-run-supplement.json`；本次候选结论保持**passed=false**。
