# Round43 完整源码候选：一次70套证据

**headless_source_candidate_PASS=false；release_passed=false。实际70/70、unique70、分类通过69、业务RED1、missing=[]。Q03 Godot冷native导入引擎阻断仍在。**

不是preflight/import失败，更不是shell exit1表示70套全失败。worker前置45 checks/exit0/无ERROR；静态70无blocker；import exit0/errors=[]；完整集合执行完成，除assembly外所有根进程exit0，无超时、共享安全停止或本轮native crash。

## 同一freeze与计数
- run_id=`9128e0d5d8bf4625a717e7034b7112ee`；唯一新freeze；Round42历史39记录原字节保留，不充抵本轮。
- 原manifest：`reports/refactoring/round43-integrated-9128e0d5d8bf4625a717e7034b7112ee/manifest.json`，SHA256=`c123aea6bdfd32aa730301dff4777c52afb415ba400289afa315b77ad705e158`。
- 同一原始70只读重解析：`reports/refactoring/round43-integrated-9128e0d5d8bf4625a717e7034b7112ee/reparsed-manifest.json`，SHA256=`7983fb168f7d88574bcf9aa919d0be9865e5d5802d59cdc510ab7a2f0e6a808e`；未新执行Godot。
- 完整源码依赖=2238；source/freeze/运行期间漂移=[]；主/真实child物理E回执及实际pool20已读回。
- 合法RESULT checks=4553（含RED65）；原始CHECK事件=4400；严格stdout/stderr零ERROR通过=68。
- 原始ERROR共4个日志出现：bind stderr与自身godot.log各1、dependencies单卡负向worker2行。两份含ERROR的派生日志均精确scope验证；未知ERROR=0；原ERROR和strict=false保留，不设通用忽略。
- 前置worker45、独立GUI25均不计完整70的额外PASS。

真实完整执行（exit1）：
```text
python -B tools/tests/test_round29_integrated_evidence.py --round43 --complete-candidate --collect-failures
```
只读重解析（整体仍exit1，assembly红仍在）：
```text
python -B tools/tests/test_round29_integrated_evidence.py --round43-reparse reports/refactoring/round43-integrated-9128e0d5d8bf4625a717e7034b7112ee/manifest.json
```

## 全部当前RED与最小原输入
### 1. assembly_publish_lifecycle_test — 业务RED
- PID=32368、exit1、65 checks、两项失败；必需66门未降、无native skip、不是timeout或脚本ERROR。
- 原argv：`["E:/scratch/isolated-9128e0d5d8bf4625a717e7034b7112ee/generated/Godot.exe", "--headless", "--fixed-fps", "60", "--path", "E:/scratch/isolated-9128e0d5d8bf4625a717e7034b7112ee/generated/project", "--scene", "res://tests/assembly_publish_lifecycle_test.tscn", "--", "E:/scratch/isolated-9128e0d5d8bf4625a717e7034b7112ee/generated/f/complete-0"]`。
- 原RESULT：`RESULT checks=65 failures=["204完整清单真实发布；此断言不声称历史瞬时失败已根治", "真实完整准备链发布及独立规则加载校验完成"]`。
- 最短反馈输入是原场景、当前scope/local环境和原204清单；未新造复现或重跑。执行配置/场景/继承源码在`evidence/failed-source/complete-assembly_publish_lifecycle_test/`；生产消费者同执行hash副本在`diagnostic-source/`。
- 原stdout提取原字节清单：`native-input/reconstructed-manifest.raw.json`，204唯一项、52,029 bytes、声明95,949,242 bytes，SHA256=`98469b47c4526f17a50633b3279567d17339fa61ed3895954e7ba9b3de58d568`。与历史清单同字节，不拿历史成功消除此红。
- GD SHA256=`df499eff188d781c57b90a5ded679b9c0cc732f7ace9d8ca87e0cb607c14792b`；执行配置 SHA256=`72e82db409d55d2ba67c4402b8ecf80a0804ca9129308793bc1a15b4352deb7b`。全部最小输入hash见diagnostic-summary.json。
- formal-204：真实204写完、目标不存在、rename_attempted=true、rename_error=FAILED(1)；发布前自有matching_handles=[]/blocked_files=[]、父目录身份前后一致。准备链也在发布拒绝，worker_pid=-1，未继续规则校验/模拟。
- 当前原生7 scan/2 identity/1 lock回执、原scope/env/argv与caller/父PID/创建时间/Job在native-audit及native-input。快照不能排除瞬态外部影响；控制性MoveFileW错误5不是原失败GetLastError。根因未明、未根治、未加retry或放宽路径门。
- 原日志：`evidence/complete-assembly_publish_lifecycle_test.stdout.log` / `.stderr.log`（stderr空）。该套结束后仅继续独立套件，不重试此套。

### 2. restart性能 — 独立RED；正确性通过
- `net_server_gateway_restart_test`本轮仅一次，PID=30960、exit0/61项/failures=[]/无ERROR，实际235.459s，正确性门600s；未第二次长跑。
- 原60s性能门：`GATEWAY_PERFORMANCE_GATE {"budget_seconds":60,"elapsed_msec":60003,"passed":false}`。性能RED不由正确性GREEN抵消。
- 最小原输入：`diagnostic-source/tests/net_server_gateway_restart_test.gd/.tscn`、原argv末参数`E:/scratch/isolated-9128e0d5d8bf4625a717e7034b7112ee/generated/f/complete-31`、FATE_R39_CORRECTNESS=1；原worker config/recovery、实例身份、恢复comparison、控制请求/回执与journal均保留于worker/complete-31。
- 原Godot保存链真实核对自然终局、正式save、记录数与journal尾；此次再次读回原二进制journal及save hash，不用Python替代Godot规则验证。
- save：`worker/complete-31/server-match-30960-2959202/round39-final-save.json`，SHA256=`c62fdcde0696b4696657e989371dec7517c91f369e9692f04d775af4017734d9`。
- journal：`worker/complete-31/server-match-30960-2959202/workers/5de80e847da754276dd54dcd9cc1e2b9/matches/2026-10-10T04-46-53_263eeb83565049d2be975c65/match.log`，135,528 bytes；SHA256=`aca8ea000350463381925d4f6fadf970c7642cf5c7706d218557e68d351d68b9`，与save记录精确相同。
- records=194；tail_hash=`03238c219b4162e195a619fb0ec785093d8c896349436ddc23c89e5fb8e60502`；game_over=true；原control响应与保存回执逐字相等。

## 首次自动汇总误拒绝：修解析、不重跑
- 原manifest初判68通过，RED=assembly/restart，并把bind自身Godot文件日志副本当成未知worker ERROR。原manifest、原始日志和原自动报告`automatically-generated-report.md`未改。
- Windows反斜杠路径不匹配`/complete-31/`和`/round39-final-save.json`字符串，漏掉已经归档的save。现按受限路径组件解释并核对save/journal/index/control响应，未补造save。
- bind ERROR同时进入stderr和自身godot.log。仅对complete-65指定APPDATA日志、原六行trace、冻结源hash/第13行、七项CHECK/唯一RESULT、相同stdout及自有Job退出精确分类；额外ERROR、错误scope或坏hash仍拒绝，strict=false不改。
- 最终同一70原字节重解析为69通过/1业务RED；不是另一版本partial绿、没有拼历史PASS。当前仍不满足完整候选PASS。
- 执行前17项单元PASS；修收尾后20项PASS，包含fail1继续但整体false/default failfast、两种路径分隔、坏save hash、错误scope/extra ERROR拒绝、原manifest不变和完整70重解析。parser-only PASS；原RED/GREEN日志在unit-evidence。

## 精确ERROR scope
- gateway_bind_failure_test：exit0/7项；唯一ENet ERROR，回溯enet_transport.gd:44 → server_gateway.gd:51 → 测试:13，自身godot.log精确复制同一块；不放行其他ENet ERROR。
- room_data_preparation_dependencies_test：exit0/34项；单卡manifest、负向report、缺masters/servants两ERROR及完整回溯、三份固定源hash、自有Job退出全部一致。原worker日志/manifest/report和绑定见reparsed-manifest.worker_scoped_negatives。

## 独立同hash窗口（不记headless PASS）
- local_spell_restore_test：Round42 final4真实非headless25项/exit0/无ERROR；执行时2075依赖hash与当前源一致，差异=[]。
- 原manifest：`E:\Projects\Godot\FateDominationGame-master\reports\refactoring\round42-modal-zoom\final4\manifest.json`，SHA256=`fb68f7e707d9836aab815a4aad6a66761deaa6bcb189757a89be21d79dfda478`；完整绑定=`gui-independent-binding.json`。未用Round37缺hash历史记录充抵，未称本轮新窗口执行；原DPI/展开OS客户区等未验边界保留。

## 完整70实际记录
|suite|exit|checks|分类通过|
|---|---:|---:|---|
|assembly_publish_lifecycle_test|1|65|RED|
|round28-command-migration_test|0|66|PASS|
|battle_board_end_command_test|0|38|PASS|
|battle_board_activation_command_test|0|21|PASS|
|active_choice_source_command_test|0|65|PASS|
|card_choice_source_command_test|0|18|PASS|
|location_choice_source_command_test|0|37|PASS|
|battle_command_adapter_test|0|29|PASS|
|match_command_dispatcher_test|0|313|PASS|
|match_command_result_protocol_test|0|39|PASS|
|match_commands_test|0|17|PASS|
|net_pending_test|0|20|PASS|
|net_cards_test|0|7|PASS|
|net_move_test|0|11|PASS|
|net_locations_test|0|7|PASS|
|net_authority_ui_preview_feedback_test|0|8|PASS|
|battle_board_v2_test|0|53|PASS|
|battle_play_groups_test|0|43|PASS|
|deploy_rules_layer_test|0|22|PASS|
|mana_spend_test|0|45|PASS|
|regular_play_test|0|54|PASS|
|player_choice_source_command_test|0|65|PASS|
|client_identity_inbox_contract_test|0|58|PASS|
|host_room_inbox_contract_test|0|34|PASS|
|net_selection_settings_test|0|7|PASS|
|net_runtime_guard_test|0|34|PASS|
|net_resume_identity_test|0|26|PASS|
|gateway_deferred_test|0|16|PASS|
|gateway_disconnect_safe_close_test|0|7|PASS|
|gateway_instance_binding_test|0|20|PASS|
|net_server_gateway_test|0|19|PASS|
|net_server_gateway_restart_test|0|61|PASS|
|net_data_validation_test|0|13|PASS|
|net_validation_io_feedback_test|0|23|PASS|
|net_validation_io_measure_test|0|9|PASS|
|net_background_validation_feedback_test|0|25|PASS|
|net_server_discovery_validation_test|0|33|PASS|
|content_environment_test|0|30|PASS|
|worker_content_environment_test|0|45|PASS|
|gateway_relisten_acceptance_test|0|38|PASS|
|net_validation_task_test|0|31|PASS|
|net_validation_simulation_test|0|35|PASS|
|net_validation_hard_timeout_test|0|37|PASS|
|net_parallel_validation_feedback_test|0|9|PASS|
|room_data_preparation_consumer_test|0|50|PASS|
|room_data_preparation_dependencies_test|0|34|PASS|
|lobby_content_environment_restore_test|0|1544|PASS|
|net_data_sync_test|0|14|PASS|
|net_blob_test|0|42|PASS|
|net_blob_authorization_test|0|58|PASS|
|net_blob_send_authorization_test|0|14|PASS|
|net_blob_concurrent_test|0|20|PASS|
|net_worker_startup_contract_test|0|15|PASS|
|host_guard_inbox_contract_test|0|72|PASS|
|net_guard_rollback_test|0|39|PASS|
|rule_guard_root_transaction_v2_test|0|58|PASS|
|rule_guard_rollback_test|0|18|PASS|
|rule_guard_chain_rollback_test|0|17|PASS|
|rule_guard_continuation_occurrence_test|0|54|PASS|
|round29-shared-presentation_test|0|142|PASS|
|shared_spell_view_contract_test|0|87|PASS|
|mirror_spell_negative_test|0|73|PASS|
|match_view_test|0|222|PASS|
|match_view_privacy_test|0|137|PASS|
|client_match_inbox_contract_test|0|45|PASS|
|gateway_bind_failure_test|0|7|PASS(精确负向)|
|newspecial_spell_materialization_test|0|13|PASS|
|command_spell_source_activation_test|0|54|PASS|
|round39_restore_transaction_test|0|61|PASS|
|validation_checkpoint_reader_test|0|10|PASS|

## 清理与文件范围
- 73条真实根进程记录（probe/import/前置/完整70）；全部自有派生Job ActiveProcesses=0、exited=true、日志句柄释放，无预算/空间/隔离故障。
- 原日志/worker产物hash已归档读回；generated_removed、回查不存在；回收6413225126 bytes；D源引擎hash及旧选择/历史输入字节未变。
- 仅改聚合器tools/tests/test_round29_integrated_evidence.py、选择单元tools/tests/test_round40_selection.py与本报告；production/游戏tests/generic runner/native helper只读，未commit。执行时aggregator.py与修正后reparser.py分别保存，不伪称新解析器执行过70。
- 补充证据hash索引见delivery-evidence-index.json。Q03冷native导入、正式发行EXE、跨机/跨网发行门未由headless结果替代。
