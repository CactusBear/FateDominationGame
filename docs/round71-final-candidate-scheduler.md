# Round71：最终候选冻结输入与既有 scheduler 接线

## 已完成及严格边界

- 复用 `run_round50_full`、Windows Job executor 和原资源回收，不新增 Godot/规则实现、不改 GD/gate/DLL。增加的函数只是输入冻结、批准清单绑定、模式命令及一次执行 adapter。
- parser-only 实际 PASS。完整 candidate16 + contract5 + resource12 = **33 tests PASS**；加 isolated runner17 与新 scheduler8，共 **58 tests：57 PASS、1 SKIP**。SKIP 是可选真实 Godot 单元；未设置 ISOLATED_GODOT，避免另启动额外场景。本轮真实行为由下面的两场景证明。
- 历史last99 schema仍 **99 headless / 101 formal / 103 programs**（--round50兼容入口）。当前 **--round71为101 headless / 103 formal / 105 programs**，新增320检查卡背专项及11检查non-card专项；mandatory 原下限全部保留。`worker_content_environment_test` 无 receipt 参数保持45；有 receipt 的56是不同调用合同，不能提高无参数路径下限或拼接信用。
- 原98原件仍87 PASS /11 RED，SHA `d439e06fd4a92592211d306dfa292ba2af90c04c699bdd3fb52ee19b5bcc85b4`，没有修改或重新计绿。当前只读目录大小15,167,056 bytes。
- 主代理中途批准round70后，卡背已 **READY / not_run**，新两scene明确required；privacy137 / mirror94更新为新声明卡背合同，未移除私密正面过滤。模态仍 **NOTREADY / not_run**；没有批准的当前board/GUI测试合同。测试名字/历史PASS/“checks>=1”均不构成 mandatory；不会因并行生产仍在变强行跑full。

## 解耦与入口

`--round71 --prepare-candidate OUTPUT` 只读取明确依赖，校验当前选择分区、重复项、派生计数和 mandatory，写出 `round71-frozen-candidate/v1`。写出成功只表示计划准备完成，输出含 `ready_for_full`，不冒称选择或行为通过。

`--freeze-inputs` 将该显式依赖复制到批准物理E根下精确UUID input owner。每个dependency copy后核验SHA，末尾源/目标再核验。隔离VCS转换仍只发生在执行副本，不改原文件。snapshot输入不含records/密钥；baseline仅以独立名字/manifest SHA参与选择，没有历史PASS信用。输入manifest、所有执行依赖与所有场景日志归档。

`--round71 --execute-prepared INPUT` 不重新从live取得一个“现在大概稳定”的版本；重验保存的源hash、选择/批准合同和执行器hash，复用原scheduler。可以直接由main提供批准清单。没有等待文件出现、pollchild或一小时full重试。独占 `round71-attempt-<plan_id>.json` 排斥并行执行与已启动失败再续跑；失败仍保留真实日志/Job。原continuation仅未启动套件逻辑保持原严格门，不在新入口使用。

本轮修复了一个实际parser前置误报：`failure_shot` 在同一函数内把literal输出路径赋给变量，再 `save_png(path)`，旧静态抓取把截图误列成输入。新解析只承认同函数明示literal写入；跨函数同名变量、load而非save、未知依赖仍不放行。未扩大ERROR白名单。

### main批准清单格式

```json
{
  "schema": "round71-approved-inputs/v1",
  "dependency_hashes": {"每个既有输入以及新增完整闭包的原始res相对路径": "准确64位小写SHA256"},
  "integrations": [
    {
      "id": "modal_regression",
      "suite": "真实已落地_test",
      "mode": "gui_required",
      "scene": "tests或newtests/真实场景.tscn",
      "script": "tests或newtests/真实脚本.gd",
      "minimum_checks": "由真实完整RESULT/CHECK证据批准的整数，不是占位1",
      "dependency_hashes": {"完整新增输入路径": "SHA256"},
      "producer_hashes": {"scripts/game_scene/battle_board_v2.gd": "同冻结源码SHA256"}
    }
  ]
}
```

另一个id为 `cardback_privacy`，producer必须同时准确绑定 `scripts/match/view_builder.gd` 和 `scripts/match/view_mirror.gd`。mode只能明确short_headless/gui_required，不猜文件名。新增scene可在newtests；真实命令scene路径已接到既有full runner，minimum也接到实际分析器。重复suite/id、缺闭包/RESULT、变更旧suite模式、源producer不匹配、旧packageartifacthash均拒绝。批准只给READY/not_run，不给PASS。已落地测试的依赖未批准则仍NOTREADY。

### 最终稳定后的准备及唯一执行命令

先由main审查批准清单（main-approved.json，不自动制造审批），再在稳定生产源码上准备：

```text
python -B tools/tests/test_round29_integrated_evidence.py --round71 --prepare-candidate E:/scratch/round71-final-approved-plan.json --approved-inputs E:/scratch/main-approved.json --approved-root E:/scratch --freeze-inputs
```

确认输出ready_for_full=true后，唯一候选执行命令：

```text
python -B tools/tests/test_round29_integrated_evidence.py --round71 --execute-prepared E:/scratch/round71-final-approved-plan.json --approved-root E:/scratch --collect-failures
```

这条仍是**完整headless candidate**，不是GUI/native standalone/export发行通过。当前formal103中两项GUI、另1 supplementary GUI、2 native standalone与2独立loader negative均保持单列，不能被headless代偿。批准新增项按实际模式重算counts；尚未落地项不加入选集。GUI合同可以冻结/列清单但本入口不擅自启动窗口，GUI同冻结验收交唯一窗口owner。两项native standalone命令为 `python -B tools/tests/test_temporary_cleanup_core.py`、`python -B tools/tests/test_process_tree_owner_core.py`；独立执行不能替代正式旧DLL能力验收。

追加批准前，已实际拒绝未批准计划：`E:/scratch/round71-final-pending-plan.json`，2035 dependencies。真实执行前置exit1，原因 `NOTREADY final integration dependencies; no Godot launched`；不是一个已运行红scene，没有执行99/GUI。

## 真正两场景proof（追加round70批准前执行器）

```text
python -B tools/tests/test_round29_integrated_evidence.py --round71 --prepare-candidate E:/scratch/round71-proof-plan.json --approved-root E:/scratch --proof-two-scenes --freeze-inputs
python -B tools/tests/test_round29_integrated_evidence.py --round71 --execute-prepared E:/scratch/round71-proof-plan.json --approved-root E:/scratch --proof-two-scenes
```

两条均exit0。1803显式dependencies；formal只有relay1，prerequisite worker另1，parent计划保留99/101/103。正式1/headless1/program1及categories已重算，不把未运行99计成当前proof。

| Scene | Exit | RESULT checks | 观察CHECK | 实际runtime回收 |
|---|---:|---:|---:|---:|
| worker_content_environment_test（无receipt参数） | 0 | 45 | 0（quiet RESULT） | 1131 bytes |
| net_server_relay_cfg_test | 0 | 22 | 22 | 1796 bytes |

不把quiet worker的45冒称观察到了45 CHECK。声明合计67，观察22。probe、import及两个scene共4个自有Job：全部退出、句柄释放、ActiveProcesses总计0。archive hash、冻结hash、执行时executor hash读回全部一致，worker ERROR=[]、final drift=[]。

- manifest：`E:/scratch/isolated-e4a1970f2c304057b1bd7b7f4392430c/manifest.json`
- manifest SHA：`067f83e8b8b08f2c1eb70df1b1222d69d66b0af5651ac26903647cf8c26e036c`
- 真实独立读回：同owner `round71-readback.json`
- resource_proof_passed=true；顶层candidate passed=false（明确保留shared freeze），sourcePASS=false、releasePASS=false。

两个373328-byte快照缓存保持原位置/identity/length、内容未读；shared engine/freeze/保护输入仍保留。读回时runtime owner **1,067,547,610 bytes**，准备input owner **592,277,998 bytes**，合计 **1,659,825,608 bytes**。8GiB **8,589,934,592 bytes**不变；input snapshot从runtime可用字节扣除，仍计同总预算，不搬出预算隐去。后续完整候选积累protectedretained仍可能byte_budget阻断，必须原样报告；records不得删除，本轮未授任何新删除权限。

## 真实Python验证命令

```text
ISOLATED_TEST_ROOT=E:/scratch python -B -m unittest tools.tests.test_round50_candidate_selection tools.tests.test_round64_candidate_contract tools.tests.test_round61_runner_resource_accounting tools.tests.test_isolated_godot_test tools.tests.test_round71_final_candidate_scheduler -v
python -B tools/tests/test_round29_integrated_evidence.py --parser-only
```

RED→GREEN覆盖变量截图输出、准备计划缺入口、批准newtests接线、一次执行拒重试、两场景count闭包和逐dependency坏copy。负向包括producer/source mismatch、旧packageartifacthash、重复选集/id/suite、错误derived counts、降低mandatory、伪造READY、缺落地场景、未获CHECK的新增integration、未知ERROR/SCRIPT ERROR/SHADER ERROR无豁免。Python synthetic wire只检验解析协议，不给Godot PASS信用。

## 当前完整程序清单（103 formal，全为新完整候选not_run）

模式计数：short_headless95、native_integration1、gui_required2、long_correctness2、performance2、known_engine_negative1。另native standalone2，所以programs105；required extracted harness1、independent loader modes2、supplementary GUI1是独立执行合同，不充正式场景。机器可读完整列表：`E:/scratch/round71-round70-program-list.json`。

| # | Suite | Mode | 原始/更新mandatory最小checks |
|---:|---|---|---:|
| 1 | `round28-command-migration_test` | short_headless | 74 |
| 2 | `battle_board_end_command_test` | short_headless | 46 |
| 3 | `battle_board_activation_command_test` | short_headless | 21 |
| 4 | `active_choice_source_command_test` | short_headless | 65 |
| 5 | `card_choice_source_command_test` | short_headless | 18 |
| 6 | `location_choice_source_command_test` | short_headless | 37 |
| 7 | `battle_command_adapter_test` | short_headless | 29 |
| 8 | `match_command_dispatcher_test` | short_headless | 313 |
| 9 | `match_command_result_protocol_test` | short_headless | 39 |
| 10 | `match_commands_test` | short_headless | 17 |
| 11 | `net_pending_test` | short_headless | 20 |
| 12 | `net_cards_test` | short_headless | 7 |
| 13 | `net_move_test` | short_headless | 11 |
| 14 | `net_locations_test` | short_headless | 7 |
| 15 | `net_authority_ui_preview_feedback_test` | short_headless | 8 |
| 16 | `battle_board_v2_test` | short_headless | 53 |
| 17 | `battle_play_groups_test` | short_headless | 56 |
| 18 | `deploy_rules_layer_test` | short_headless | 22 |
| 19 | `mana_spend_test` | short_headless | 45 |
| 20 | `regular_play_test` | short_headless | 54 |
| 21 | `player_choice_source_command_test` | short_headless | 65 |
| 22 | `client_identity_inbox_contract_test` | short_headless | 58 |
| 23 | `host_room_inbox_contract_test` | short_headless | 34 |
| 24 | `net_selection_settings_test` | short_headless | 7 |
| 25 | `net_runtime_guard_test` | short_headless | 34 |
| 26 | `net_resume_identity_test` | short_headless | 26 |
| 27 | `gateway_deferred_test` | short_headless | 16 |
| 28 | `gateway_disconnect_safe_close_test` | short_headless | 7 |
| 29 | `gateway_instance_binding_test` | short_headless | 20 |
| 30 | `net_server_gateway_test` | short_headless | 19 |
| 31 | `net_server_gateway_restart_test` | long_correctness | 61 |
| 32 | `net_data_validation_test` | short_headless | 13 |
| 33 | `net_validation_io_feedback_test` | short_headless | 23 |
| 34 | `net_validation_io_measure_test` | short_headless | 9 |
| 35 | `net_background_validation_feedback_test` | short_headless | 25 |
| 36 | `net_server_discovery_validation_test` | short_headless | 33 |
| 37 | `content_environment_test` | short_headless | 30 |
| 38 | `worker_content_environment_test` | short_headless | 45 |
| 39 | `gateway_relisten_acceptance_test` | short_headless | 38 |
| 40 | `net_validation_task_test` | short_headless | 31 |
| 41 | `net_validation_simulation_test` | short_headless | 35 |
| 42 | `net_validation_hard_timeout_test` | short_headless | 37 |
| 43 | `net_parallel_validation_feedback_test` | short_headless | 9 |
| 44 | `room_data_preparation_consumer_test` | short_headless | 50 |
| 45 | `room_data_preparation_dependencies_test` | short_headless | 34 |
| 46 | `lobby_content_environment_restore_test` | short_headless | 1544 |
| 47 | `net_data_sync_test` | short_headless | 14 |
| 48 | `net_blob_test` | short_headless | 42 |
| 49 | `net_blob_authorization_test` | short_headless | 58 |
| 50 | `net_blob_send_authorization_test` | short_headless | 14 |
| 51 | `net_blob_concurrent_test` | short_headless | 20 |
| 52 | `net_worker_startup_contract_test` | short_headless | 15 |
| 53 | `host_guard_inbox_contract_test` | short_headless | 72 |
| 54 | `net_guard_rollback_test` | short_headless | 39 |
| 55 | `rule_guard_root_transaction_v2_test` | short_headless | 115 |
| 56 | `rule_guard_rollback_test` | short_headless | 19 |
| 57 | `rule_guard_chain_rollback_test` | short_headless | 17 |
| 58 | `rule_guard_continuation_occurrence_test` | short_headless | 54 |
| 59 | `round29-shared-presentation_test` | short_headless | 142 |
| 60 | `shared_spell_view_contract_test` | short_headless | 87 |
| 61 | `local_spell_restore_test` | gui_required | GUI 合同另验 |
| 62 | `mirror_spell_negative_test` | short_headless | 94 |
| 63 | `match_view_test` | short_headless | 226 |
| 64 | `match_view_privacy_test` | short_headless | 137 |
| 65 | `client_match_inbox_contract_test` | short_headless | 45 |
| 66 | `gateway_bind_failure_test` | known_engine_negative | 7 |
| 67 | `newspecial_spell_materialization_test` | short_headless | 13 |
| 68 | `command_spell_source_activation_test` | short_headless | 54 |
| 69 | `round39_restore_transaction_test` | short_headless | 61 |
| 70 | `assembly_publish_lifecycle_test` | native_integration | 66 |
| 71 | `validation_checkpoint_reader_test` | short_headless | 10 |
| 72 | `round47_host_lifecycle_test` | short_headless | 33 |
| 73 | `round47_host_lifecycle_board_test` | long_correctness | 14 |
| 74 | `round47_presenter_power_test` | short_headless | 23 |
| 75 | `server_data_status_inbox_contract_test` | short_headless | 65 |
| 76 | `server_data_status_inbox_approval_test` | short_headless | 22 |
| 77 | `deployment_approved_root_test` | short_headless | 47 |
| 78 | `server_simulation_default_budget_test` | short_headless | 13 |
| 79 | `validation_countdown_contract_test` | short_headless | 21 |
| 80 | `server_validation_countdown_test` | gui_required | GUI 合同另验 |
| 81 | `round47_public_test_observer_test` | short_headless | 7 |
| 82 | `command_spell_test` | short_headless | 61 |
| 83 | `ask_player_option_test` | short_headless | 16 |
| 84 | `requirement_null_test` | short_headless | 14 |
| 85 | `session_restart_test` | short_headless | 30 |
| 86 | `debug_console_pause_test` | short_headless | 15 |
| 87 | `round47_worker_launch_route_test` | short_headless | 22 |
| 88 | `round47_worker_launch_lifecycle_test` | short_headless | 39 |
| 89 | `round50_validation_launch_route_test` | short_headless | 16 |
| 90 | `net_server_cli_test` | short_headless | 11 |
| 91 | `round50_finished_lobby_receipt_test` | short_headless | 16 |
| 92 | `net_server_cli_p2p_test` | short_headless | 13 |
| 93 | `net_server_identity_cli_test` | short_headless | 22 |
| 94 | `net_server_cfg_test` | short_headless | 18 |
| 95 | `net_server_relay_cfg_test` | short_headless | 22 |
| 96 | `validation_pipeline_performance_test` | performance | 259 |
| 97 | `validation_stage_timing_test` | performance | 23 |
| 98 | `server_shutdown_close_handoff_test` | short_headless | 86 |
| 99 | `server_shutdown_close_handoff_pending_test` | short_headless | 36 |
| 100 | `net_server_shutdown_failure_test` | short_headless | 161 |
| 101 | `loader_error_boundary_test` | short_headless | 62 |
| 102 | `round70_declared_card_backs_test` | short_headless | 320 |
| 103 | `view_builder_non_card_objects_test` | short_headless | 11 |

其他程序/模式：
- required extracted：`round50_finished_lobby_tight_test`，6 checks，真实Session+runner同冻结提取，archive必验，非formal。
- independent loader：`loader_error_boundary_test` 的 `expectednegative` / `expectednegative_extra`，各9 checks，不能混普通green或追加未知ERROR白名单。
- supplementary GUI：`round47_host_lifecycle_board_test -- window`，不充headless。
- native standalone：`TemporaryCleanupCoreTests` / `ProcessTreeOwnerTests`，不充Godot或正式DLL PASS。

## 追加round70主代理批准（当前最终schema）

- builder `9a7ed25688ded565bce41b0a8b7473f8067553b55629fbb7d7ce88a276ec831e`、mirror `8007a3cc6e2e1ed0bb319ba3e1b3bd21fb825e7b9bc24f3f212a724c514eef20` 与生产实读完全相等。新GD/scene及privacy/mirror测试SHA也与批准原始manifest相等。
- `round71_current_preflight` 通过既有builder的显式current_approved模式接线，不凑固定99。新卡背320和non-card11 required；privacy137、mirror94必须观察同量CHECK。旧match_view226保留，不为这次自然对局224而降低。
- 实际原始round70五场景日志重解析：320/137/94/224/11，总786。四项满足当前minimum；match_view224低于原226，故本候选重解析标FALSE，保留原round70自身通过及其原字节，不把786当本轮完整候选PASS。
- 原始round70 manifest SHA `7c20aa0240a70864ece8eb7c60e9080c37000bd434de138341353e154b62101a`；五项日志和真实CHECK均读取，没有再次启动五scene。新当前清单 `E:/scratch/round71-round70-program-list.json`、当前计划 `E:/scratch/round71-round70-current-plan.json`，2039 dependencies，cardback READY/not_run、modal NOTREADY/not_run、ready_for_full=false。
- 主批准后的改动仅候选声明/mandatory/source合同接线；此前两场景proof归档executor是批准前版本，**不宣称它与追加后的最终Python字节相同**。不为了刷同最终SHA而再启动Godot；本轮共实际两个业务scene、零GUI/零full。最终Python58 tests与parser已经重跑通过，原小proof的archive/Job0事实保留。
- 当前58 tests原始日志：`E:/scratch/round71-final-python.stdout.log`、`E:/scratch/round71-final-python.stderr.log`。

## 未完成/阻断

卡背主代理批准SHA已接线，新模态整链尚未提供；当前board仍有并行写入。GUI/native/export、多机和当前完整101 headless并未运行。完整候选可能因保护缓存、records、正式DLL能力或原独立红项拒绝，门不降低；真实小proof仅证明scheduler运行、归档、Job0，不证明这些验收层。
