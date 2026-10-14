# Round73：当前 headless 中途停止交接

## 最终状态

**stopped_by_user_workflow_change**。最新顺序为：实现完成 → 导出真人测试包 → 用户测试并通知后才允许全量回归。本任务已停止，不恢复、不补跑、不接性能优化；本任务未导出、未 GUI 验收。

| 口径 | 实际 |
|---|---:|
| 历史 headless 选集 → 当前选集 | 98 → 101 |
| 当前 formal / programs | 103 / 105 |
| executed / unique | 70 / 70 |
| PASS / strict PASS / RED | 69 / 68 / 1 |
| 未执行（不是失败） | 31 |
| 当前正在执行 | 0 |
| formal RESULT 声明 CHECK / 实际观察 CHECK | 4666 / 4513 |
| 自有 Godot Job / 仍活体 | 74 / 0 |
| sourcePASS / releasePASS / cleanup_verified | false / false / false |

另行已执行 prerequisite worker：声明45、观察0（quiet，无 receipt 模式）；required tight：声明6、观察6。不能把 quiet 声明数说成已观察 CHECK，也不把 prerequisite 或 tight 充入70个 formal。

## exit125 的准确原因与停止偏差

`proc_b722737f0058` 的125是用户调整流程后的 **scheduler 控制退出**，不是 Godot 业务异常、cold import AV 或某套件的退出码。当前最后一套 `validation_checkpoint_reader_test` 已自然 exit0并完成回收保留记录。74个记录 Job 全部 exited、ActiveProcesses=0、log_handles_released=true；实际 Python scheduler 的句柄快照已无 Godot Job/进程句柄，才终止 Python。

工具返回 PID29860 实为 bash wrapper；首次暂停仅暂停 wrapper，实际 Python PID7496仍在运行。纠正期间记录从66增至70；此停止延迟明确保留，不伪称收到指令后只完成一套。实际 Python 暂停后未再启动套件，没有强杀游戏、保存/恢复 worker。随后终止无活体 Job 的 Python并恢复 wrapper让工具自然返回125。原 manifest 没有改成“正常完成”。

## 真实失败与最早原因

### 业务 RED：gateway_relisten_acceptance_test

- exit1；RESULT/CHECK=30/30，原 mandatory38保持不变。
- 第一个 false：`独立 worker 真实句柄与就绪验证`；随后 `真实保存关闭请求在途` false。
- 夹具在 `tests/gateway_relisten_acceptance_test.gd:45–48` 等待 ready最多40000ms；公开 manager创建独立 worker 的前一个检查成功。
- 原 child engine log只有引擎启动与 helper banner，没有 ERROR。**能够确认的是独立 worker ready/句柄验证未达成；为何未 ready尚不能确认**，不能据此断言生产故障或旧DLL根因。
- 原件 stdout：`evidence/complete-gateway_relisten_acceptance_test.stdout.log`；stderr为空。资源 scope原位保留，可交后续 owner调查；本任务未修生产、未重跑此红项。

### 独立性能门 RED，不与 correctness互换

`net_server_gateway_restart_test` 已真实执行一次，600秒 correctness看门狗，exit0、61/61 CHECK通过。日志 `GATEWAY_PERFORMANCE_GATE {"budget_seconds":60,"elapsed_msec":60003,"passed":false}`：60秒性能门未过。已把真实历史执行补投影为 restart_current，不是重新执行。

### 全部 raw ERROR

唯一不同文本：`ERROR: Couldn't create an ENet host.`，属于既有 `gateway_bind_failure_test` 精确 scoped_bind_negative；该套件PASS但strict=false。没有新增白名单，没有额外 ERROR/SCRIPT ERROR/SHADER ERROR被吞掉。

归档中3次出现同一事件：
1. `evidence/complete-gateway_bind_failure_test.stderr.log:1`
2. `worker/runtime-10fc54eabc26446a948e6968faf91c37/artifacts/appdata/FateDomination/logs/godot.log:6`
3. `worker/runtime-10fc54eabc26446a948e6968faf91c37/stderr.log:1`

二进制 `.log` 按真实 `FATEJNL1` 识别并保存SHA，不用UTF-8 replacement吞字节，也不假装文本ERROR扫描；逐文件列表在独立 readback。

## 动态总数门已修并有真实结果

亲读 `tests/match_view_test.gd:74–81`：每个AI步骤检查一次mirror，末尾必须 `GameProgress.is_game_over`。226只留为历史随机样本，已从当前 mandatory_checks移出，不改成>=224。

当前门源绑定全部静态断言调用、最低标签多重集、observer[-1,0,1,2]、每observer3个玩家、固定隐私检查各12次与placeholder9次、连续step1..N、唯一 RESULT=真实 CHECK计数及最终terminal true。当前真实 `match_view_test` **225/225 PASS**：loop1..134无遗漏，静态最低91，终局最终true；少一个固定隐私、loop缺号、终局false/缺失、伪造总数及额外ERROR的Python负向均拒绝。225不再被旧226假门判红。

已执行 round70相关：privacy137/137、mirror94/94 PASS；required320卡背与11 non-card仍在未执行名单，不能遗漏或冒称通过。shutdown86保持原mandatory但未运行。其他真正固定mandatory未降低。

## 冻结、配置和历史原件

- 源仓库：`E:/Projects/Godot/FateDominationGame-master`；HEAD `8c0f946faf6cc0cd3f04f12f66f5a99a413088ca`，upfront工作树状态在plan/source_identity。
- 唯一 input owner：`E:/scratch/round71-input-d168a370b0614d339e45d5613aaef802`；2034显式依赖。
- source fingerprint：`d5409138d46f53318851070a8acd0ef3555b4bf103cf6b8545183a56acef078e`
- frozen fingerprint：`4965690c6f9b6f2cd684945ce99422bc92ce2b792487873ef4e033aee8ffc73b`
- 唯一授权转换为隔离副本的editor VCS字段；source project.godot SHA `986a066adc6f0d1346d19612538780abaf2ce4d3cdfef4342db653a0b53d8c8a`，转换后 `72e82db409d55d2ba67c4402b8ecf80a0804ca9129308793bc1a15b4352deb7b`。
- 主引擎 SHA `ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424`；正式旧DLL模板release SHA `92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd`，未替换。
- server.cfg SHA `351798e5909021fa472f2206bdc63c1a9271322c5800cbfdffb96e2b491301d5`。当前 roles=[game]、authority_host_mode=dedicated、bind=*、UDP24680、internal52000/128、storage=user://server_rooms、record_matches=true、transaction_log=true、shutdown30秒、identity_registry=user://server_players.json、恢复key mismatch拒绝/host_select继承、random simulation启用且15秒。实际主/worker探针均物理E、worker_pool20；未提高预算或线程，未使用用户28100。
- 最终源/冻结/input/executor drift均空；明确排除的GUI/其他测试变更也空。独立GUI不冒充headless；其NOTREADY状态未伪造READY。
- 历史98原件SHA保持 `d439e06fd4a92592211d306dfa292ba2af90c04c699bdd3fb52ee19b5bcc85b4`（原87 PASS/11 RED不改）。

## 调度与资源收尾证据

初次尝试没有Godot启动：native前置门错误遍历formal GUI名单，因独立GUI源已排除而报缺local_spell_restore。单元RED/GREEN后正确入口才真正运行；此零场景失败保留。

正确运行在31项后因control.json与tag_list.json回收未知停止；用户批准仅保护保留这两种producer输出，原stop manifest不改。同owner/freeze接续未启动70项，又在36项后遇到simulation.json与validation-data/tag_list.json未知停止。

用户随后批准系统性分离继续权限和删除权限：仅unknown_files回收拒绝且Job0、scope/receipt、无链接、无漂移、原8GiB配额都安全时，整scope原位保留，不读未知内容、不移动/删除，允许下一套。身份不明、live child、junction、漂移、byte_budget仍硬停；没有按*.json白名单。本次最终63个runtime retained_protected、8个 retained_unknown_scope（含prerequisite），没有新增删除保护数据权限。

独立收尾readback时计费 **5,862,772,642 bytes**，包含input owner；原8GiB **8,589,934,592 bytes**不变。所有保留文件的身份/长度已读回验证；131个保护文件只读metadata，未读配置/密钥/records内容。8个unknown scope：net_background_validation_feedback、net_server_discovery_validation、gateway_relisten_acceptance、net_parallel_validation_feedback、room_data_preparation_consumer、room_data_preparation_dependencies、lobby_content_environment_restore、round39_restore_transaction。精确scope UUID、完整保护路径/大小/identity在readback及manifest内。

共享freeze、engine、input与保护/未知scope均保留；cleanup_not_verified维持false验收。不同阶段executor SHA明确记录在parent链，不能把原31记录当作最终新executor的重新证明。

### 原件与独立收尾产物

- 当前owner：`E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7`
- 零场景失败：`E:/scratch/isolated-848afad0b86044809db678f5878daa05/manifest.json`，SHA `2021b13256910b127d2e885aab66cc90f0ca3486c345aa5d6465a7952d882d01`。
- 31项stop：当前owner `manifest.json`，SHA `0a6fd84e90db6eb7387e59de98122081aa5c304b64d8020546f44167be490707`。
- 36项stop：当前owner `round73-continuation-manifest.json`，SHA `ef1ad1c6ba1f57f9bfa9b4737fe6eb4de39cb7d9aaa82a97b3008b2ccfcbab13`。
- 70项原始进度：当前owner `round73-continuation-7d1e41e07ecf4ae0bfdeaef23f879593-manifest.json`，原件保留，未冒称finally完整结束。
- 独立停止readback：当前owner `round73-user-stop-readback.json`，SHA `3a4fa2e05764f8a1dd8fc48cc467378fb97e8a1d36a5e25878c0537a8eee81f6`。
- 停止控制/原生Job观察：`round73-user-stop-control.json`、`round73-user-stop-actual-native-observation.json`。首份wrapper观察单独保留，不能作为actual Python Job0信用。

## 70项真实执行明细

P=PASS/strict；N=既有精确负向PASS但非strict；R=RED。声明/观察分别记，quiet零观察不改写。

| # | Suite | 状态 | exit | 声明/观察 |
|---:|---|---|---:|---:|
|1|assembly_publish_lifecycle_test|P|0|66/66|
|2|round28-command-migration_test|P|0|74/74|
|3|battle_board_end_command_test|P|0|46/46|
|4|battle_board_activation_command_test|P|0|21/21|
|5|active_choice_source_command_test|P|0|65/65|
|6|card_choice_source_command_test|P|0|18/18|
|7|location_choice_source_command_test|P|0|37/37|
|8|battle_command_adapter_test|P|0|29/29|
|9|match_command_dispatcher_test|P|0|313/313|
|10|match_command_result_protocol_test|P|0|39/39|
|11|match_commands_test|P|0|17/17|
|12|net_pending_test|P|0|20/20|
|13|net_cards_test|P|0|7/7|
|14|net_move_test|P|0|11/11|
|15|net_locations_test|P|0|7/7|
|16|net_authority_ui_preview_feedback_test|P|0|8/8|
|17|battle_board_v2_test|P|0|53/53|
|18|battle_play_groups_test|P|0|65/65|
|19|deploy_rules_layer_test|P|0|22/22|
|20|mana_spend_test|P|0|45/45|
|21|regular_play_test|P|0|54/54|
|22|player_choice_source_command_test|P|0|65/65|
|23|client_identity_inbox_contract_test|P|0|58/0|
|24|host_room_inbox_contract_test|P|0|34/34|
|25|net_selection_settings_test|P|0|7/7|
|26|net_runtime_guard_test|P|0|34/34|
|27|net_resume_identity_test|P|0|26/26|
|28|gateway_deferred_test|P|0|16/16|
|29|gateway_disconnect_safe_close_test|P|0|7/7|
|30|gateway_instance_binding_test|P|0|20/0|
|31|net_server_gateway_test|P|0|19/19|
|32|net_server_gateway_restart_test|P（性能门未过）|0|61/61|
|33|net_data_validation_test|P|0|13/13|
|34|net_validation_io_feedback_test|P|0|23/23|
|35|net_validation_io_measure_test|P|0|9/9|
|36|net_background_validation_feedback_test|P|0|25/25|
|37|net_server_discovery_validation_test|P|0|33/33|
|38|content_environment_test|P|0|30/0|
|39|worker_content_environment_test|P|0|45/0|
|40|gateway_relisten_acceptance_test|R|1|30/30|
|41|net_validation_task_test|P|0|31/31|
|42|net_validation_simulation_test|P|0|35/35|
|43|net_validation_hard_timeout_test|P|0|37/37|
|44|net_parallel_validation_feedback_test|P|0|9/9|
|45|room_data_preparation_consumer_test|P|0|50/50|
|46|room_data_preparation_dependencies_test|P|0|34/34|
|47|lobby_content_environment_restore_test|P|0|1544/1544|
|48|net_data_sync_test|P|0|14/14|
|49|net_blob_test|P|0|42/42|
|50|net_blob_authorization_test|P|0|58/58|
|51|net_blob_send_authorization_test|P|0|14/14|
|52|net_blob_concurrent_test|P|0|20/20|
|53|net_worker_startup_contract_test|P|0|15/15|
|54|host_guard_inbox_contract_test|P|0|72/72|
|55|net_guard_rollback_test|P|0|39/39|
|56|rule_guard_root_transaction_v2_test|P|0|115/115|
|57|rule_guard_rollback_test|P|0|19/19|
|58|rule_guard_chain_rollback_test|P|0|17/17|
|59|rule_guard_continuation_occurrence_test|P|0|54/54|
|60|round29-shared-presentation_test|P|0|142/142|
|61|shared_spell_view_contract_test|P|0|87/87|
|62|mirror_spell_negative_test|P|0|94/94|
|63|match_view_test|P|0|225/225|
|64|match_view_privacy_test|P|0|137/137|
|65|client_match_inbox_contract_test|P|0|45/45|
|66|gateway_bind_failure_test|N|0|7/7|
|67|newspecial_spell_materialization_test|P|0|13/13|
|68|command_spell_source_activation_test|P|0|54/54|
|69|round39_restore_transaction_test|P|0|61/61|
|70|validation_checkpoint_reader_test|P|0|10/10|

## 31项未执行名单

```
round47_host_lifecycle_test
round47_host_lifecycle_board_test
round47_presenter_power_test
server_data_status_inbox_contract_test
server_data_status_inbox_approval_test
deployment_approved_root_test
server_simulation_default_budget_test
validation_countdown_contract_test
round47_public_test_observer_test
command_spell_test
ask_player_option_test
requirement_null_test
session_restart_test
debug_console_pause_test
round47_worker_launch_route_test
round47_worker_launch_lifecycle_test
round50_validation_launch_route_test
net_server_cli_test
round50_finished_lobby_receipt_test
net_server_cli_p2p_test
net_server_identity_cli_test
net_server_cfg_test
net_server_relay_cfg_test
validation_pipeline_performance_test
validation_stage_timing_test
server_shutdown_close_handoff_test
server_shutdown_close_handoff_pending_test
net_server_shutdown_failure_test
loader_error_boundary_test
round70_declared_card_backs_test
view_builder_non_card_objects_test
```

formal另2项GUI（local_spell_restore、server_validation_countdown）、2项native standalone、supplementary GUI及两个独立loader-negative模式均未执行，不受headless代偿。

## 本任务改动和写权释放

只修改Python执行器和专属单元，新增本报告；全部生产GD、游戏tests、native、engine只读。停止指令后仅做停止控制与readback，不再单测/启动场景。之前完整Python组合62 tests（61 PASS/1 SKIP）；最后安全门专项27 PASS及parser-only PASS，均在停止指令之前。

| 文件 | 最终SHA256 | 状态 |
|---|---|---|
|tools/tests/test_round29_integrated_evidence.py|f13b4fe2a0e5a5bf0ff81a1d5850a21ed4960ce5325b4c59600e2ea61312a53e|修改：源绑定语义门、显式headless、授权保留/continuation|
|tools/tests/test_round71_final_candidate_scheduler.py|a160244412887e9efbfbc1bc962808402a336ce0f4672fc766ab81fb411ebd4e|修改：RED/GREEN与负向|
|tools/tests/test_round50_candidate_selection.py|b57a8c0418e7b0e8c194f5a2cb5a2ca850fc25c1fbc7fe3c16ee47afd227e254|只读未修改|

**本任务结束并释放上述执行器/单元写权。** 后续actor可以开始其实现/优化，但不得因实现完成自行恢复本轮全量；先交真人测试包，等用户通知。
