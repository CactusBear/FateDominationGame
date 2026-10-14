# Round50 候选选择与前置契约

**selection_blocked；sourcePASS=false；releasePASS=false。**

本轮只读内存快照预检，Godot启动=0、cold import=0、业务执行=0。生产、游戏tests、native与其它actor文件均只读；未跑旧70或新全量，不等待其它actor，不合并历史69/72通过记录。

## 亲读的基线与可对账选集
基线：`reports/refactoring/round42-integrated-68eeb9d161c54e47ab9e25b4fa18cc6b/manifest.json`，SHA256=`de95e54d7cdb2d7b1a5efd8355d28a791a211bb29347ecc7d56eb81919e27185`。只复用名字：原70 headless + 独立GUI local_spell_restore，共71个场景。旧suite执行/通过记录不参与本轮结果。
当前真实选择=97个Godot场景，其中headless=95；另有2个native standalone程序，program_count=99；board补充窗口调用=1（同一程序另一模式，不加program_count）。冻结输入=2010个，精确测试闭包=227个文件。计数由Python去重、分区和实文件核对。

|模式|数量|边界|
|---|---:|---|
|short_headless|89|逻辑专项；不声称鼠标/画面通过|
|native_integration|1|正式GDExtension；assembly mandatory66不删除、不允许SKIP|
|gui_required|2|必须非headless，不计headless通过|
|long_correctness|2|自然终局/完整恢复，不冒充性能达标|
|performance|2|完整数据实测单列；不缩15秒预算|
|known_engine_negative|1|沿原精确绑定分类；严格ERROR原记录保留|

另有两组native standalone能力单元，只核验实际Python类与对应CPP/HPP/probe源已落盘；没有执行、没有把独立能力当生产DLL或Godot集成通过。正式board窗口分支还需要独立实际 `-- window`，headless按钮信号不代替GUI。

## 当前阻断（不充PASS）
```json
[
  {
    "suite": "round50_finished_lobby_tight_test",
    "reason": "not landed",
    "missing": [
      "tight_session.gd"
    ]
  },
  {
    "suite": "server_data_status_inbox_approval_test",
    "path": "tests/net_server_data_approval_test.gd",
    "reason": "effective absolute root not injected",
    "source": "var local_root:String = \"E:/Projects/Godot/FateDomination/test/server_approval-%d/data\" % Time.get_ticks_usec()"
  },
  {
    "suite": "round47_worker_launch_lifecycle_test",
    "reason": "standalone fixture requires root sibling /engine/; generic mandatory66 engine layout is generated/Godot.exe; owner must parameterize actual binary contract"
  }
]
```
被独立harness生成、而工程内缺依赖的诊断场景仅列blocked，不补造源码/场景，也不加入可执行名字计数。已落盘的receipt测试已亲读定义并加入；这不是其行为已通过。JSON/CFG均为当前生产read_configuration支持入口，因此不把JSON配置夹具误报为格式阻断。

## 冻结与输出根规则
- 生产输入显式限定 project.godot、scripts（其下已落盘generated自然纳入）、assets、data、game_data、addons、json_maker、icon.svg；测试只复制所选gd/tscn及继承/静态真实helper/子场景闭包。拒绝整个tests，排除旧baseline夹具、.godot、reports/runtime_reports、records、secrets、credentials、keys、.env、pem/key/pfx/p12及旧插件更新备份。
- res://写输出仅在将来的自有freeze；显式argv[0]根消费者仍收到批准物理E fixture root。每suite的APPDATA/LOCALAPPDATA/FATE_TEST_SCRATCH_ROOT在自有E根；子进程继承。批准数据是同一freeze/project/data；身份测试密钥只在自有夹具，不读取用户秘密库。
- inherited helper、Observer、root契约与必要assets/native DLL必须是实际输入；所有源字节先snapshot SHA256，再核对后读漂移。未变更生产15秒默认与pool20。当前owner根合同绑定见下表。
- preflight-only不复制项目/引擎、不mkdir；只读取源/hash、调用本进程Win32 identity、打开已批准E父根检测FILE_ADD_SUBDIRECTORY访问，并启动安装Python做无落盘模块检查。预检成功不是实际main/worker user://探针通过。
- 将来完整候选先再次核对源snapshot，再冻结；唯一允许转换仍仅副本[editor]两个VCS字段。actual main/worker user://物理E、PID/token、child exit0、pool20与Job退出/句柄释放仍为执行前/后的独立硬门。
- 默认failfast。显式collect-failures只在自有进程退出、ActiveProcesses=0、句柄释放、预算安全且无source/frozen drift后继续独立专项；fail1/pass2仍整体FALSE。不扩ERROR忽略；仅复用既有精确负向分类函数。
- 保存真实stdout/stderr、worker错误日志和验证report/manifest，排除密钥、注册库、worker配置、正式records。所有历史证据只读，不凭旧69/72充抵同一freeze结果。

```json
{
  "blockers": [],
  "bindings": [
    {
      "path": "tests/lobby_content_environment_restore_test.gd",
      "owner_sha256": "57bee431227486ac2f60fc44c41bc3aeb28da6d24d56473ba233fdb58130ba3f",
      "frozen_sha256": "57bee431227486ac2f60fc44c41bc3aeb28da6d24d56473ba233fdb58130ba3f",
      "matches_owner": true
    },
    {
      "path": "tests/net_blob_concurrent_test.gd",
      "owner_sha256": "5b4cc1b2740239b158e8dc0a087c17d0e1fa668d906f31c4d2103243d31d0b1d",
      "frozen_sha256": "5b4cc1b2740239b158e8dc0a087c17d0e1fa668d906f31c4d2103243d31d0b1d",
      "matches_owner": true
    },
    {
      "path": "tests/isolated_fixture_root_contract_test.gd",
      "owner_sha256": "5415dd3fbc1aaa94a6a1624b0c935eb70a0e3f8d3201c282dde78cb585a18c82",
      "frozen_sha256": "5415dd3fbc1aaa94a6a1624b0c935eb70a0e3f8d3201c282dde78cb585a18c82",
      "matches_owner": true
    },
    {
      "path": "tests/isolated_fixture_root_contract_test.tscn",
      "owner_sha256": "b0f802bc0ad27020ee1db9af71e8fd5c008b89548159a94355e04b5eb32bda4c",
      "frozen_sha256": "b0f802bc0ad27020ee1db9af71e8fd5c008b89548159a94355e04b5eb32bda4c",
      "matches_owner": true
    }
  ],
  "handoff": "E:\\Projects\\Godot\\FateDominationGame-master\\docs\\round42-explicit-fixture-roots.md",
  "handoff_sha256": "f0b4ad111f041736821da1d61d6b1c285c356c1f24e49534b1e06c482766f98f"
}
```

## 当前真实Python验证
- 第一段RED：候选builder缺失，1项AssertionError，exit1；实现后exit0。
- 第二段RED：mode command/preflight缺失，2项有效AssertionError，exit1；实现后exit0。
- 第三段RED：guarded full entry缺失，1项AssertionError，exit1；实现后blocked拒绝路径通过，未分配freeze、未启动Godot。
- 最终单元命令：`python -B tools/tests/test_round50_candidate_selection.py`，6项全部通过，exit0；严格parser及既有collect-failures专项均exit0。两份Python均AST可解析。只有完整入口的blocked拒绝路径已实测，真正Godot执行分支未跑。
- 严格parser：`python -B tools/tests/test_round29_integrated_evidence.py --parser-only`，exit0。
- 旧collect-failures契约专项：`python -B -m unittest tools.tests.test_round40_selection.Round40Tests.test_round43_collect_failures_preserves_failfast_and_aggregate_red -v`，1项、exit0；没有运行旧70。
- 真实CLI preflight：`python -B tools/tests/test_round29_integrated_evidence.py --round50 --preflight-only --approved-root E:/scratch`；exit1，snapshot_drift=[]。

当前native前置读回：
```json
{
  "helper_sha256": "ace59ea3704270aab0bc66f0fbfedd385621b192944242c16867be80cc6ca689",
  "actual_definitions": [
    "access",
    "process_identity",
    "safe",
    "validate_caller",
    "validate_paths",
    "within"
  ],
  "authorization_plan_valid": true,
  "parent_add_directory_win32_error": 0,
  "python_launch_exit": 0,
  "python_verified": true,
  "own_process_identity": {
    "pid": 6948,
    "parent": 11872,
    "creation": "134360693277466865",
    "image": "C:\\Users\\Administrator\\AppData\\Local\\hermes\\tools\\python-3.14.7+202****0901-win32-x64\\python.exe",
    "in_job": false
  },
  "actual_main_worker_user_probe_executed": false,
  "mandatory66_executed": false
}
```

## 主代理稳定版本后的一次完整headless命令
须先关闭上述独占owner blocker；不要直接拿本轮并行变动的版本进入冷import。入口遇blocker即exit1，既不freeze也不执行。
```text
python -B tools/tests/test_round29_integrated_evidence.py --round50 --complete-candidate --approved-root E:/scratch --collect-failures
```
去掉 `--collect-failures` 即默认failfast。未来真实执行分支本轮没有运行，只有拒绝前置路径已实测；不能宣称执行分支已完成整合验收。此命令运行当前完整headless选集，不运行GUI/native standalone；其状态仍单列，不输出sourcePASS/releasePASS。restart完整正确性一次600s，原性能门另记；performance专项一次600s watchdog，不改变生产模拟预算。native66保留原门。
GUI须由唯一窗口执行者另作同hash/同冻结证据；server_validation_countdown只允许非headless，argv为 `-- --config <实际E user_data>/countdown.cfg`，不得设FATE_COUNTDOWN_COMPLETION_ONLY跳过零预算/取消覆盖。board真实窗口须 `-- window`。本轮未执行这些命令。
两组独立native命令（未执行；不计headless数量）：
```text
python -B tools/tests/test_temporary_cleanup_core.py
python -B tools/tests/test_process_tree_owner_core.py
```

## 实际所选场景（不是PASS表）
|scene|模式|继承输入|配置writer|
|---|---|---|---|
|round28-command-migration_test|short_headless|tests/round28-command-migration_test.gd, tests/battle_board_end_command_test.gd, tests/card_selection_owner_test.gd||
|battle_board_end_command_test|short_headless|tests/battle_board_end_command_test.gd, tests/card_selection_owner_test.gd||
|battle_board_activation_command_test|short_headless|tests/battle_board_activation_command_test.gd, tests/battle_board_end_command_test.gd, tests/card_selection_owner_test.gd||
|active_choice_source_command_test|short_headless|tests/active_choice_source_command_test.gd||
|card_choice_source_command_test|short_headless|tests/card_choice_source_command_test.gd||
|location_choice_source_command_test|short_headless|tests/location_choice_source_command_test.gd, tests/card_choice_source_command_test.gd||
|battle_command_adapter_test|short_headless|tests/battle_command_adapter_test.gd, tests/card_selection_owner_test.gd||
|match_command_dispatcher_test|short_headless|tests/match_command_dispatcher_test.gd, tests/card_selection_owner_test.gd||
|match_command_result_protocol_test|short_headless|tests/match_command_result_protocol_test.gd, tests/card_selection_owner_test.gd||
|match_commands_test|short_headless|tests/match_commands_test.gd, tests/match_driver_headless_test.gd||
|net_pending_test|short_headless|tests/net_pending_test.gd, tests/match_journal_test.gd||
|net_cards_test|short_headless|tests/net_cards_test.gd, tests/card_selection_sources_test.gd, tests/card_selection_owner_test.gd||
|net_move_test|short_headless|tests/net_move_test.gd, tests/card_selection_owner_test.gd||
|net_locations_test|short_headless|tests/net_locations_test.gd, tests/card_selection_owner_test.gd||
|net_authority_ui_preview_feedback_test|short_headless|tests/net_authority_ui_preview_feedback_test.gd, tests/match_journal_test.gd||
|battle_board_v2_test|short_headless|tests/battle_board_v2_test.gd||
|battle_play_groups_test|short_headless|tests/battle_play_groups_test.gd||
|deploy_rules_layer_test|short_headless|tests/deploy_rules_layer_test.gd||
|mana_spend_test|short_headless|tests/mana_spend_test.gd, tests/masters_audit_fix_test.gd||
|regular_play_test|short_headless|tests/regular_play_test.gd||
|player_choice_source_command_test|short_headless|tests/player_choice_source_command_test.gd||
|client_identity_inbox_contract_test|short_headless|tests/client_identity_inbox_contract_test.gd||
|host_room_inbox_contract_test|short_headless|tests/host_room_inbox_contract_test.gd||
|net_selection_settings_test|short_headless|tests/net_selection_settings_test.gd, tests/net_lobby_test.gd, tests/match_journal_test.gd||
|net_runtime_guard_test|short_headless|tests/net_runtime_guard_test.gd, tests/match_journal_test.gd||
|net_resume_identity_test|short_headless|tests/net_resume_identity_test.gd, tests/net_runtime_guard_test.gd, tests/match_journal_test.gd||
|gateway_deferred_test|short_headless|tests/gateway_deferred_test.gd||
|gateway_disconnect_safe_close_test|short_headless|tests/gateway_disconnect_safe_close_test.gd||
|gateway_instance_binding_test|short_headless|tests/gateway_instance_binding_test.gd||
|net_server_gateway_test|short_headless|tests/net_server_gateway_test.gd, tests/net_lobby_test.gd, tests/match_journal_test.gd||
|net_server_gateway_restart_test|long_correctness|tests/net_server_gateway_restart_test.gd, tests/net_server_recovery_midmatch_test.gd, tests/net_server_recovery_match_test.gd, tests/net_server_archive_match_test.gd, tests/net_server_match_test.gd, tests/match_journal_test.gd||
|net_data_validation_test|short_headless|tests/net_data_validation_test.gd, tests/match_journal_test.gd||
|net_validation_io_feedback_test|short_headless|tests/net_validation_io_feedback_test.gd, tests/match_journal_test.gd||
|net_validation_io_measure_test|short_headless|tests/net_validation_io_measure_test.gd, tests/match_journal_test.gd||
|net_background_validation_feedback_test|short_headless|tests/net_background_validation_feedback_test.gd, tests/match_journal_test.gd||
|net_server_discovery_validation_test|short_headless|tests/net_server_discovery_validation_test.gd, tests/match_journal_test.gd||
|content_environment_test|short_headless|tests/content_environment_test.gd||
|worker_content_environment_test|short_headless|tests/worker_content_environment_test.gd||
|gateway_relisten_acceptance_test|short_headless|tests/gateway_relisten_acceptance_test.gd, tests/match_journal_test.gd||
|net_validation_task_test|short_headless|tests/net_validation_task_test.gd, tests/net_recovery_state_test.gd, tests/match_journal_test.gd||
|net_validation_simulation_test|short_headless|tests/net_validation_simulation_test.gd, tests/net_validation_task_test.gd, tests/net_recovery_state_test.gd, tests/match_journal_test.gd||
|net_validation_hard_timeout_test|short_headless|tests/net_validation_hard_timeout_test.gd, tests/net_validation_task_test.gd, tests/net_recovery_state_test.gd, tests/match_journal_test.gd||
|net_parallel_validation_feedback_test|short_headless|tests/net_parallel_validation_feedback_test.gd, tests/match_journal_test.gd||
|room_data_preparation_consumer_test|short_headless|tests/room_data_preparation_consumer_test.gd, tests/match_journal_test.gd||
|room_data_preparation_dependencies_test|short_headless|tests/room_data_preparation_dependencies_test.gd, tests/match_journal_test.gd||
|lobby_content_environment_restore_test|short_headless|tests/lobby_content_environment_restore_test.gd, tests/restore_atomicity_fault_test.gd, tests/net_lobby_test.gd, tests/match_journal_test.gd||
|net_data_sync_test|short_headless|tests/net_data_sync_test.gd, tests/net_lobby_test.gd, tests/match_journal_test.gd||
|net_blob_test|short_headless|tests/net_blob_test.gd, tests/match_journal_test.gd||
|net_blob_authorization_test|short_headless|tests/net_blob_authorization_test.gd, tests/match_journal_test.gd||
|net_blob_send_authorization_test|short_headless|tests/net_blob_send_authorization_test.gd, tests/match_journal_test.gd||
|net_blob_concurrent_test|short_headless|tests/net_blob_concurrent_test.gd, tests/match_journal_test.gd||
|net_worker_startup_contract_test|short_headless|tests/net_worker_startup_contract_test.gd, tests/match_journal_test.gd||
|host_guard_inbox_contract_test|short_headless|tests/host_guard_inbox_contract_test.gd, tests/net_guard_rollback_test.gd, tests/net_runtime_guard_test.gd, tests/match_journal_test.gd||
|net_guard_rollback_test|short_headless|tests/net_guard_rollback_test.gd, tests/net_runtime_guard_test.gd, tests/match_journal_test.gd||
|rule_guard_root_transaction_v2_test|short_headless|tests/rule_guard_root_transaction_v2_test.gd, tests/match_journal_test.gd||
|rule_guard_rollback_test|short_headless|tests/rule_guard_rollback_test.gd, tests/match_journal_test.gd||
|rule_guard_chain_rollback_test|short_headless|tests/rule_guard_chain_rollback_test.gd, tests/match_journal_test.gd||
|rule_guard_continuation_occurrence_test|short_headless|tests/rule_guard_continuation_occurrence_test.gd, tests/match_journal_test.gd||
|round29-shared-presentation_test|short_headless|tests/round29-shared-presentation_test.gd||
|shared_spell_view_contract_test|short_headless|tests/shared_spell_view_contract_test.gd, tests/match_journal_test.gd||
|local_spell_restore_test|gui_required|tests/local_spell_restore_test.gd||
|mirror_spell_negative_test|short_headless|tests/mirror_spell_negative_test.gd, tests/match_journal_test.gd||
|match_view_test|short_headless|tests/match_view_test.gd, tests/match_journal_test.gd||
|match_view_privacy_test|short_headless|tests/match_view_privacy_test.gd, tests/match_journal_test.gd||
|client_match_inbox_contract_test|short_headless|tests/client_match_inbox_contract_test.gd||
|gateway_bind_failure_test|known_engine_negative|tests/gateway_bind_failure_test.gd, tests/match_journal_test.gd||
|newspecial_spell_materialization_test|short_headless|tests/newspecial_spell_materialization_test.gd||
|command_spell_source_activation_test|short_headless|tests/command_spell_source_activation_test.gd||
|round39_restore_transaction_test|short_headless|tests/round39_restore_transaction_test.gd, tests/restore_atomicity_fault_test.gd, tests/net_lobby_test.gd, tests/match_journal_test.gd||
|assembly_publish_lifecycle_test|native_integration|tests/assembly_publish_lifecycle_test.gd, tests/net_recovery_state_test.gd, tests/match_journal_test.gd||
|validation_checkpoint_reader_test|short_headless|tests/validation_checkpoint_reader_test.gd||
|round47_host_lifecycle_test|short_headless|tests/round47_host_lifecycle_test.gd||
|round47_host_lifecycle_board_test|long_correctness|tests/round47_host_lifecycle_board_test.gd||
|round47_presenter_power_test|short_headless|tests/round47_presenter_power_test.gd||
|server_data_status_inbox_contract_test|short_headless|tests/server_data_status_inbox_contract_test.gd||
|server_data_status_inbox_approval_test|short_headless|tests/server_data_status_inbox_approval_test.gd, tests/net_server_data_approval_test.gd, tests/net_lobby_test.gd, tests/match_journal_test.gd||
|deployment_approved_root_test|short_headless|tests/deployment_approved_root_test.gd||
|server_simulation_default_budget_test|short_headless|tests/server_simulation_default_budget_test.gd||
|validation_countdown_contract_test|short_headless|tests/validation_countdown_contract_test.gd||
|server_validation_countdown_test|gui_required|tests/server_validation_countdown_test.gd||
|round47_public_test_observer_test|short_headless|tests/round47_public_test_observer_test.gd||
|command_spell_test|short_headless|tests/command_spell_test.gd||
|ask_player_option_test|short_headless|tests/ask_player_option_test.gd||
|requirement_null_test|short_headless|tests/requirement_null_test.gd||
|session_restart_test|short_headless|tests/session_restart_test.gd||
|debug_console_pause_test|short_headless|tests/debug_console_pause_test.gd||
|round47_worker_launch_route_test|short_headless|tests/round47_worker_launch_route_test.gd||
|round47_worker_launch_lifecycle_test|short_headless|tests/round47_worker_launch_lifecycle_test.gd||
|round50_validation_launch_route_test|short_headless|tests/round50_validation_launch_route_test.gd||
|net_server_cli_test|short_headless|tests/net_server_cli_test.gd, tests/match_journal_test.gd|tests/net_server_cli_test.gd|
|round50_finished_lobby_receipt_test|short_headless|tests/round50_finished_lobby_receipt_test.gd||
|net_server_cli_p2p_test|short_headless|tests/net_server_cli_p2p_test.gd, tests/net_server_cli_test.gd, tests/match_journal_test.gd|tests/net_server_cli_test.gd|
|net_server_identity_cli_test|short_headless|tests/net_server_identity_cli_test.gd, tests/net_server_cfg_test.gd, tests/net_server_cli_test.gd, tests/match_journal_test.gd|tests/net_server_identity_cli_test.gd|
|net_server_cfg_test|short_headless|tests/net_server_cfg_test.gd, tests/net_server_cli_test.gd, tests/match_journal_test.gd|tests/net_server_cfg_test.gd|
|net_server_relay_cfg_test|short_headless|tests/net_server_relay_cfg_test.gd, tests/net_server_cfg_test.gd, tests/net_server_cli_test.gd, tests/match_journal_test.gd|tests/net_server_relay_cfg_test.gd|
|validation_pipeline_performance_test|performance|tests/validation_pipeline_performance_test.gd, tests/net_recovery_state_test.gd, tests/match_journal_test.gd||
|validation_stage_timing_test|performance|tests/validation_stage_timing_test.gd||

所有场景执行状态均not_run；后续actor新落盘文件不会靠扫描整个tests自动加入，需继续亲读真实场景/函数定义后显式更新。
本轮写权仅三个文件：本报告、tools/tests/test_round29_integrated_evidence.py、tools/tests/test_round50_candidate_selection.py。tests/tools可能被ignore，未修改ignore、未stage/commit。
