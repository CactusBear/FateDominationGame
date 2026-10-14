# 历史静态草稿（已失效，禁止用作最终执行计划）

本文件对应 v2；生成期间源码漂移，最终 parser-only 回读 exit1。最终交付是 `docs/current-regression-inventory-plan-v4.md` 与 `E:/scratch/current-regression-inventory-plan-v4.json`（独立 parser-only exit0）。v1/v2/v3 JSON 保留作失败记录，不覆盖、不执行。


全部套件状态均为 **planned / notrun**。未启动 Godot、未导包、未导入、未执行任何业务套件。

## 范围与可执行门

- 本计划保留全部 formal scene 清单；最终命令只执行现有入口的完整 headless 选集，不代替 GUI、native standalone、独立 loader 或提取 harness。
- scope: `headless`；计数：`{"formal_scenes": 103, "headless_scenes": 101, "native_standalone": 2, "programs": 105, "required_harness_steps": 1, "supplementary_gui": 1, "independent_loader_modes": 2, "parallel_allowed_suites": 5, "categories": {"short_headless": 95, "long_correctness": 2, "gui_required": 2, "known_engine_negative": 1, "native_integration": 1, "performance": 2}}`。
- 正常 execution gate: `false`；原因：`producer/source dependency mismatch: scripts/system/global/effect_manager.gd`。
- 现有 schema 保留 sourcePASS=false / releasePASS=false；not_run 是原入口兼容值，新增清单只用 planned/notrun。
- 源码或执行器改变后 hash 门会拒绝此计划，必须重新生成；本次未复制冻结输入。
- 使用 jobs=2；CPU reservation=2、memory reservation=2147483648 bytes、disk reservation=4294967296 bytes。固定原 aggregate owner 上限8589934592 bytes不变；这些是调度 reservation，不是 OS 内存/CPU硬限额。
- 长套标记只来自 long_correctness 分类；性能类单列，预算不代表测得耗时。
- 必须先导包，等待用户通知后才能运行；不要现在执行下方命令。

## 最终回归命令（等待用户通知）

```bash
python -B tools/tests/test_round29_integrated_evidence.py --round71 --execute-prepared E:/scratch/current-regression-inventory-plan-v2.json --approved-root E:/scratch --collect-failures --jobs 2 --cpu-budget 2 --memory-budget-bytes 2147483648 --disk-budget-bytes 4294967296 --cancel-file E:/scratch/current-regression-inventory-plan-v2.cancel
```

取消：创建命令中的 --cancel-file 文件；运行前该文件必须不存在。未创建该文件，也未接触已有 runtime owner。

## Parser-only 校验

```bash
TMPDIR=E:/scratch TEMP=E:/scratch TMP=E:/scratch python -B tools/generate_regression_plan_inventory.py --parser-only E:/scratch/current-regression-inventory-plan-v2.json
```

静态校验记录：`{"parser_only_exit_code": 0, "schema_and_hashes_validated": true, "actual_entry_cli_parsed": true, "scheduler_arguments": {"jobs": 2, "cpu_budget": 2, "memory_budget_bytes": 2147483648, "disk_budget_bytes": 4294967296, "cancel_file": "E:/scratch/current-regression-inventory-plan-v2.cancel"}, "execution_gate_satisfied": false, "execution_gate_error": "producer/source dependency mismatch: scripts/system/global/effect_manager.gd", "status": "planned", "execution_status": "notrun", "godot_launch_count": 0, "cold_import_count": 0, "suite_execution_count": 0, "validation_boundary": "No freeze copy, import, attempt receipt or suite execution. proof=True used only for structural validation; normal readiness gate reported separately.", "allowed_readonly_subprocesses": ["python.exe", "git", "git"]}`。

## 套件来源与扫描规则

```json
{
  "baseline_manifest": {
    "path": "reports/refactoring/round42-integrated-68eeb9d161c54e47ab9e25b4fa18cc6b/manifest.json",
    "sha256": "de95e54d7cdb2d7b1a5efd8355d28a791a211bb29347ecc7d56eb81919e27185",
    "fields_used": [
      "selected_suites",
      "selection.names",
      "selection.headless"
    ],
    "historical_results_used": false
  },
  "entry": {
    "path": "tools/tests/test_round29_integrated_evidence.py",
    "sha256": "a4fcd8ad322b745b8b762ea2cb13dc6b9b8e527ee1745b56dbbc0a4390faa0b6",
    "symbols": [
      "ROUND50_ADDITIONS",
      "ROUND50_EXTRACTED_HARNESSES",
      "ROUND64_BASELINE_CHECKS",
      "ROUND70_REQUIRED_CHECKS",
      "build_round50_selection",
      "round71_validate_selection",
      "ROUND71_CALLER_PARALLEL_SAFE",
      "round71_parallel_resource_policy",
      "round71_prepare",
      "round71_validate_prepared",
      "round73_headless_preflight"
    ]
  },
  "executor_hashes": {
    "tools/tests/test_round29_integrated_evidence.py": "a4fcd8ad322b745b8b762ea2cb13dc6b9b8e527ee1745b56dbbc0a4390faa0b6",
    "tools/run_isolated_godot_test.py": "a048b2291ab5d0548501489cb3dd7b701b2e0f89c75480804b185376479801bb",
    "tools/diagnostics/assembly_native_probe.py": "ace59ea3704270aab0bc66f0fbfedd385621b192944242c16867be80cc6ca689"
  },
  "rules": [
    "Names/order: baseline original 70 headless + local_spell_restore GUI, then landed explicit ROUND50_ADDITIONS and current ROUND70_REQUIRED_CHECKS. Extracted harnesses separate; missing declared inputs are blockers.",
    "Categories: existing build_round50_selection explicit branches. Long flag means category long_correctness only, not a timeout prediction. performance separate; never classify from name.",
    "Parallel: existing complete-phase policy, jobs>1, short_headless and explicit five-name allowlist; prerequisite and all other suites exclusive.",
    "Production dependency scan: project.godot/scripts/assets/data/game_data/addons/json_maker/icon.svg; existing round50_excluded prunes generated outputs, logs, key/credential roots before byte reads.",
    "Tests: selected tests/<suite>.gd + .tscn, declared harness inputs, round42_explicit_dependencies; recursively resolve literal res loads, extends and static resources. Literal declared outputs excluded. No glob-all include of unrelated tests.",
    "tests recursive .gd/.tscn/.py excluded hashes are drift inventory only, not automatic selection.",
    "headless scope uses existing round73_headless_preflight: preserves formal inventory but excludes GUI-only inputs/requirements from the execution scope. Full GUI/native/loader/harness rows remain separately planned."
  ]
}
```

## 完整 formal scene 清单

| # | suite | scene | 分类 | 长套 | 允许并行 | headless选中 | 状态 |
|---:|---|---|---|---|---|---|---|
| 1 | `round28-command-migration_test` | `res://tests/round28-command-migration_test.tscn` | short_headless | False | False | True | planned/notrun |
| 2 | `battle_board_end_command_test` | `res://tests/battle_board_end_command_test.tscn` | short_headless | False | False | True | planned/notrun |
| 3 | `battle_board_activation_command_test` | `res://tests/battle_board_activation_command_test.tscn` | short_headless | False | False | True | planned/notrun |
| 4 | `active_choice_source_command_test` | `res://tests/active_choice_source_command_test.tscn` | short_headless | False | False | True | planned/notrun |
| 5 | `card_choice_source_command_test` | `res://tests/card_choice_source_command_test.tscn` | short_headless | False | False | True | planned/notrun |
| 6 | `location_choice_source_command_test` | `res://tests/location_choice_source_command_test.tscn` | short_headless | False | False | True | planned/notrun |
| 7 | `battle_command_adapter_test` | `res://tests/battle_command_adapter_test.tscn` | short_headless | False | False | True | planned/notrun |
| 8 | `match_command_dispatcher_test` | `res://tests/match_command_dispatcher_test.tscn` | short_headless | False | False | True | planned/notrun |
| 9 | `match_command_result_protocol_test` | `res://tests/match_command_result_protocol_test.tscn` | short_headless | False | False | True | planned/notrun |
| 10 | `match_commands_test` | `res://tests/match_commands_test.tscn` | short_headless | False | False | True | planned/notrun |
| 11 | `net_pending_test` | `res://tests/net_pending_test.tscn` | short_headless | False | False | True | planned/notrun |
| 12 | `net_cards_test` | `res://tests/net_cards_test.tscn` | short_headless | False | True | True | planned/notrun |
| 13 | `net_move_test` | `res://tests/net_move_test.tscn` | short_headless | False | True | True | planned/notrun |
| 14 | `net_locations_test` | `res://tests/net_locations_test.tscn` | short_headless | False | True | True | planned/notrun |
| 15 | `net_authority_ui_preview_feedback_test` | `res://tests/net_authority_ui_preview_feedback_test.tscn` | short_headless | False | False | True | planned/notrun |
| 16 | `battle_board_v2_test` | `res://tests/battle_board_v2_test.tscn` | short_headless | False | False | True | planned/notrun |
| 17 | `battle_play_groups_test` | `res://tests/battle_play_groups_test.tscn` | short_headless | False | False | True | planned/notrun |
| 18 | `deploy_rules_layer_test` | `res://tests/deploy_rules_layer_test.tscn` | short_headless | False | False | True | planned/notrun |
| 19 | `mana_spend_test` | `res://tests/mana_spend_test.tscn` | short_headless | False | False | True | planned/notrun |
| 20 | `regular_play_test` | `res://tests/regular_play_test.tscn` | short_headless | False | False | True | planned/notrun |
| 21 | `player_choice_source_command_test` | `res://tests/player_choice_source_command_test.tscn` | short_headless | False | False | True | planned/notrun |
| 22 | `client_identity_inbox_contract_test` | `res://tests/client_identity_inbox_contract_test.tscn` | short_headless | False | False | True | planned/notrun |
| 23 | `host_room_inbox_contract_test` | `res://tests/host_room_inbox_contract_test.tscn` | short_headless | False | False | True | planned/notrun |
| 24 | `net_selection_settings_test` | `res://tests/net_selection_settings_test.tscn` | short_headless | False | False | True | planned/notrun |
| 25 | `net_runtime_guard_test` | `res://tests/net_runtime_guard_test.tscn` | short_headless | False | False | True | planned/notrun |
| 26 | `net_resume_identity_test` | `res://tests/net_resume_identity_test.tscn` | short_headless | False | False | True | planned/notrun |
| 27 | `gateway_deferred_test` | `res://tests/gateway_deferred_test.tscn` | short_headless | False | False | True | planned/notrun |
| 28 | `gateway_disconnect_safe_close_test` | `res://tests/gateway_disconnect_safe_close_test.tscn` | short_headless | False | False | True | planned/notrun |
| 29 | `gateway_instance_binding_test` | `res://tests/gateway_instance_binding_test.tscn` | short_headless | False | False | True | planned/notrun |
| 30 | `net_server_gateway_test` | `res://tests/net_server_gateway_test.tscn` | short_headless | False | False | True | planned/notrun |
| 31 | `net_server_gateway_restart_test` | `res://tests/net_server_gateway_restart_test.tscn` | long_correctness | True | False | True | planned/notrun |
| 32 | `net_data_validation_test` | `res://tests/net_data_validation_test.tscn` | short_headless | False | True | True | planned/notrun |
| 33 | `net_validation_io_feedback_test` | `res://tests/net_validation_io_feedback_test.tscn` | short_headless | False | False | True | planned/notrun |
| 34 | `net_validation_io_measure_test` | `res://tests/net_validation_io_measure_test.tscn` | short_headless | False | False | True | planned/notrun |
| 35 | `net_background_validation_feedback_test` | `res://tests/net_background_validation_feedback_test.tscn` | short_headless | False | False | True | planned/notrun |
| 36 | `net_server_discovery_validation_test` | `res://tests/net_server_discovery_validation_test.tscn` | short_headless | False | False | True | planned/notrun |
| 37 | `content_environment_test` | `res://tests/content_environment_test.tscn` | short_headless | False | False | True | planned/notrun |
| 38 | `worker_content_environment_test` | `res://tests/worker_content_environment_test.tscn` | short_headless | False | False | True | planned/notrun |
| 39 | `gateway_relisten_acceptance_test` | `res://tests/gateway_relisten_acceptance_test.tscn` | short_headless | False | False | True | planned/notrun |
| 40 | `net_validation_task_test` | `res://tests/net_validation_task_test.tscn` | short_headless | False | False | True | planned/notrun |
| 41 | `net_validation_simulation_test` | `res://tests/net_validation_simulation_test.tscn` | short_headless | False | False | True | planned/notrun |
| 42 | `net_validation_hard_timeout_test` | `res://tests/net_validation_hard_timeout_test.tscn` | short_headless | False | False | True | planned/notrun |
| 43 | `net_parallel_validation_feedback_test` | `res://tests/net_parallel_validation_feedback_test.tscn` | short_headless | False | False | True | planned/notrun |
| 44 | `room_data_preparation_consumer_test` | `res://tests/room_data_preparation_consumer_test.tscn` | short_headless | False | False | True | planned/notrun |
| 45 | `room_data_preparation_dependencies_test` | `res://tests/room_data_preparation_dependencies_test.tscn` | short_headless | False | False | True | planned/notrun |
| 46 | `lobby_content_environment_restore_test` | `res://tests/lobby_content_environment_restore_test.tscn` | short_headless | False | False | True | planned/notrun |
| 47 | `net_data_sync_test` | `res://tests/net_data_sync_test.tscn` | short_headless | False | False | True | planned/notrun |
| 48 | `net_blob_test` | `res://tests/net_blob_test.tscn` | short_headless | False | False | True | planned/notrun |
| 49 | `net_blob_authorization_test` | `res://tests/net_blob_authorization_test.tscn` | short_headless | False | False | True | planned/notrun |
| 50 | `net_blob_send_authorization_test` | `res://tests/net_blob_send_authorization_test.tscn` | short_headless | False | False | True | planned/notrun |
| 51 | `net_blob_concurrent_test` | `res://tests/net_blob_concurrent_test.tscn` | short_headless | False | False | True | planned/notrun |
| 52 | `net_worker_startup_contract_test` | `res://tests/net_worker_startup_contract_test.tscn` | short_headless | False | True | True | planned/notrun |
| 53 | `host_guard_inbox_contract_test` | `res://tests/host_guard_inbox_contract_test.tscn` | short_headless | False | False | True | planned/notrun |
| 54 | `net_guard_rollback_test` | `res://tests/net_guard_rollback_test.tscn` | short_headless | False | False | True | planned/notrun |
| 55 | `rule_guard_root_transaction_v2_test` | `res://tests/rule_guard_root_transaction_v2_test.tscn` | short_headless | False | False | True | planned/notrun |
| 56 | `rule_guard_rollback_test` | `res://tests/rule_guard_rollback_test.tscn` | short_headless | False | False | True | planned/notrun |
| 57 | `rule_guard_chain_rollback_test` | `res://tests/rule_guard_chain_rollback_test.tscn` | short_headless | False | False | True | planned/notrun |
| 58 | `rule_guard_continuation_occurrence_test` | `res://tests/rule_guard_continuation_occurrence_test.tscn` | short_headless | False | False | True | planned/notrun |
| 59 | `round29-shared-presentation_test` | `res://tests/round29-shared-presentation_test.tscn` | short_headless | False | False | True | planned/notrun |
| 60 | `shared_spell_view_contract_test` | `res://tests/shared_spell_view_contract_test.tscn` | short_headless | False | False | True | planned/notrun |
| 61 | `local_spell_restore_test` | `res://tests/local_spell_restore_test.tscn` | gui_required | False | False | False | planned/notrun |
| 62 | `mirror_spell_negative_test` | `res://tests/mirror_spell_negative_test.tscn` | short_headless | False | False | True | planned/notrun |
| 63 | `match_view_test` | `res://tests/match_view_test.tscn` | short_headless | False | False | True | planned/notrun |
| 64 | `match_view_privacy_test` | `res://tests/match_view_privacy_test.tscn` | short_headless | False | False | True | planned/notrun |
| 65 | `client_match_inbox_contract_test` | `res://tests/client_match_inbox_contract_test.tscn` | short_headless | False | False | True | planned/notrun |
| 66 | `gateway_bind_failure_test` | `res://tests/gateway_bind_failure_test.tscn` | known_engine_negative | False | False | True | planned/notrun |
| 67 | `newspecial_spell_materialization_test` | `res://tests/newspecial_spell_materialization_test.tscn` | short_headless | False | False | True | planned/notrun |
| 68 | `command_spell_source_activation_test` | `res://tests/command_spell_source_activation_test.tscn` | short_headless | False | False | True | planned/notrun |
| 69 | `round39_restore_transaction_test` | `res://tests/round39_restore_transaction_test.tscn` | short_headless | False | False | True | planned/notrun |
| 70 | `assembly_publish_lifecycle_test` | `res://tests/assembly_publish_lifecycle_test.tscn` | native_integration | False | False | True | planned/notrun |
| 71 | `validation_checkpoint_reader_test` | `res://tests/validation_checkpoint_reader_test.tscn` | short_headless | False | False | True | planned/notrun |
| 72 | `round47_host_lifecycle_test` | `res://tests/round47_host_lifecycle_test.tscn` | short_headless | False | False | True | planned/notrun |
| 73 | `round47_host_lifecycle_board_test` | `res://tests/round47_host_lifecycle_board_test.tscn` | long_correctness | True | False | True | planned/notrun |
| 74 | `round47_presenter_power_test` | `res://tests/round47_presenter_power_test.tscn` | short_headless | False | False | True | planned/notrun |
| 75 | `server_data_status_inbox_contract_test` | `res://tests/server_data_status_inbox_contract_test.tscn` | short_headless | False | False | True | planned/notrun |
| 76 | `server_data_status_inbox_approval_test` | `res://tests/server_data_status_inbox_approval_test.tscn` | short_headless | False | False | True | planned/notrun |
| 77 | `deployment_approved_root_test` | `res://tests/deployment_approved_root_test.tscn` | short_headless | False | False | True | planned/notrun |
| 78 | `server_simulation_default_budget_test` | `res://tests/server_simulation_default_budget_test.tscn` | short_headless | False | False | True | planned/notrun |
| 79 | `validation_countdown_contract_test` | `res://tests/validation_countdown_contract_test.tscn` | short_headless | False | False | True | planned/notrun |
| 80 | `server_validation_countdown_test` | `res://tests/server_validation_countdown_test.tscn` | gui_required | False | False | False | planned/notrun |
| 81 | `round47_public_test_observer_test` | `res://tests/round47_public_test_observer_test.tscn` | short_headless | False | False | True | planned/notrun |
| 82 | `command_spell_test` | `res://tests/command_spell_test.tscn` | short_headless | False | False | True | planned/notrun |
| 83 | `ask_player_option_test` | `res://tests/ask_player_option_test.tscn` | short_headless | False | False | True | planned/notrun |
| 84 | `requirement_null_test` | `res://tests/requirement_null_test.tscn` | short_headless | False | False | True | planned/notrun |
| 85 | `session_restart_test` | `res://tests/session_restart_test.tscn` | short_headless | False | False | True | planned/notrun |
| 86 | `debug_console_pause_test` | `res://tests/debug_console_pause_test.tscn` | short_headless | False | False | True | planned/notrun |
| 87 | `round47_worker_launch_route_test` | `res://tests/round47_worker_launch_route_test.tscn` | short_headless | False | False | True | planned/notrun |
| 88 | `round47_worker_launch_lifecycle_test` | `res://tests/round47_worker_launch_lifecycle_test.tscn` | short_headless | False | False | True | planned/notrun |
| 89 | `round50_validation_launch_route_test` | `res://tests/round50_validation_launch_route_test.tscn` | short_headless | False | False | True | planned/notrun |
| 90 | `net_server_cli_test` | `res://tests/net_server_cli_test.tscn` | short_headless | False | False | True | planned/notrun |
| 91 | `round50_finished_lobby_receipt_test` | `res://tests/round50_finished_lobby_receipt_test.tscn` | short_headless | False | False | True | planned/notrun |
| 92 | `net_server_cli_p2p_test` | `res://tests/net_server_cli_p2p_test.tscn` | short_headless | False | False | True | planned/notrun |
| 93 | `net_server_identity_cli_test` | `res://tests/net_server_identity_cli_test.tscn` | short_headless | False | False | True | planned/notrun |
| 94 | `net_server_cfg_test` | `res://tests/net_server_cfg_test.tscn` | short_headless | False | False | True | planned/notrun |
| 95 | `net_server_relay_cfg_test` | `res://tests/net_server_relay_cfg_test.tscn` | short_headless | False | False | True | planned/notrun |
| 96 | `validation_pipeline_performance_test` | `res://tests/validation_pipeline_performance_test.tscn` | performance | False | False | True | planned/notrun |
| 97 | `validation_stage_timing_test` | `res://tests/validation_stage_timing_test.tscn` | performance | False | False | True | planned/notrun |
| 98 | `server_shutdown_close_handoff_test` | `res://tests/server_shutdown_close_handoff_test.tscn` | short_headless | False | False | True | planned/notrun |
| 99 | `server_shutdown_close_handoff_pending_test` | `res://tests/server_shutdown_close_handoff_pending_test.tscn` | short_headless | False | False | True | planned/notrun |
| 100 | `net_server_shutdown_failure_test` | `res://tests/net_server_shutdown_failure_test.tscn` | short_headless | False | False | True | planned/notrun |
| 101 | `loader_error_boundary_test` | `res://tests/loader_error_boundary_test.tscn` | short_headless | False | False | True | planned/notrun |
| 102 | `round70_declared_card_backs_test` | `res://tests/round70_declared_card_backs_test.tscn` | short_headless | False | False | True | planned/notrun |
| 103 | `view_builder_non_card_objects_test` | `res://tests/view_builder_non_card_objects_test.tscn` | short_headless | False | False | True | planned/notrun |

## 独立与补充合同（不充 headless formal 数）

```json
{
  "native_standalone": [
    {
      "path": "tools/tests/test_temporary_cleanup_core.py",
      "class": "TemporaryCleanupCoreTests",
      "command": [
        "python",
        "-B",
        "tools/tests/test_temporary_cleanup_core.py"
      ],
      "counts_as_godot_pass": false
    },
    {
      "path": "tools/tests/test_process_tree_owner_core.py",
      "class": "ProcessTreeOwnerTests",
      "command": [
        "python",
        "-B",
        "tools/tests/test_process_tree_owner_core.py"
      ],
      "counts_as_godot_pass": false
    }
  ],
  "required_harness_steps": [
    {
      "suite": "round50_finished_lobby_tight_test",
      "execution_contract": {
        "kind": "extracted_harness",
        "helper": "tight_session.gd",
        "archive": "tight_session_extracted.gd",
        "runner": "tests/round50_finished_lobby_receipt_runner.py",
        "parent": "scripts/net/session/lobby_session.gd",
        "archive_hash_required": true,
        "counts_as_formal_scene": false,
        "required": true,
        "expected_checks": 6
      },
      "execution_status": "not_run"
    }
  ],
  "supplementary_gui": [
    {
      "suite": "round47_host_lifecycle_board_test",
      "argv": [
        "window"
      ],
      "counts_as_headless_pass": false
    }
  ],
  "independent_loader_modes": [
    {
      "suite": "loader_error_boundary_test",
      "mode": "expectednegative",
      "expected_checks": 9,
      "counts_as_formal_scene": false,
      "execution_status": "not_run",
      "runner": "tests/round62_loader_error_boundary_runner.py",
      "policy": "exact scoped six errors only; extra mode must reject extra real error"
    },
    {
      "suite": "loader_error_boundary_test",
      "mode": "expectednegative_extra",
      "expected_checks": 9,
      "counts_as_formal_scene": false,
      "execution_status": "not_run",
      "runner": "tests/round62_loader_error_boundary_runner.py",
      "policy": "exact scoped six errors only; extra mode must reject extra real error"
    }
  ]
}
```

## 阻断

```json
{
  "blockers": [],
  "integration_dependencies": [
    {
      "id": "modal_regression",
      "status": "NOTREADY",
      "execution_status": "not_run",
      "required_producers": [
        "scripts/game_scene/battle_board_v2.gd"
      ],
      "reason": "approved test/source/count contract absent",
      "required_for_execution": false
    },
    {
      "id": "cardback_privacy",
      "status": "READY",
      "execution_status": "not_run",
      "required_producers": [
        "scripts/match/view_builder.gd",
        "scripts/match/view_mirror.gd"
      ],
      "reason": "main approved round70 source/test contract; current full behavior not run",
      "required_suites": {
        "round70_declared_card_backs_test": 320,
        "view_builder_non_card_objects_test": 11,
        "match_view_privacy_test": 137,
        "mirror_spell_negative_test": 94
      },
      "producer_hashes": {
        "scripts/match/view_builder.gd": "9a7ed25688ded565bce41b0a8b7473f8067553b55629fbb7d7ce88a276ec831e",
        "scripts/match/view_mirror.gd": "8007a3cc6e2e1ed0bb319ba3e1b3bd21fb825e7b9bc24f3f212a724c514eef20"
      },
      "required_for_execution": true
    }
  ]
}
```
