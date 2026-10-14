# Round41 整合候选（不是最终交付）

结论：headless_candidate_passed=False；release_passed=false。
manifest：`E:\Projects\Godot\FateDominationGame-master\reports\refactoring\round41-integrated-6089e442d5f34217a8b70bd70b149e7b\manifest.json`；所有权：`E:\scratch\isolated-6089e442d5f34217a8b70bd70b149e7b\manifest.json`。
命令：`python -B tools/tests/test_round29_integrated_evidence.py --round41`；仅自有Windows Job PID，无窗口。
## 选择与分阶段结果
原66项+显式新增后=71；分类：pure_headless=68，GUI=1，长正确性=1，精确bind负向=1；要求headless集合=70。
聚焦计划18套，实际执行15套：14套严格通过（416 checks），assembly 36 checks 因缺必需原生探针分支而拒绝；完整回归实际=0/70（聚焦记录不充抵完整记录）；停止原因=focused_failure。未执行3套：gateway_relisten_acceptance_test、room_data_preparation_consumer_test、room_data_preparation_dependencies_test。
import：`{"exit": 0, "errors": []}`；最终源码漂移：`[]`。
安全可运行headless=68；未授权不得执行=["lobby_content_environment_restore_test", "net_blob_concurrent_test"]；即使安全集合通过，也不将缺失套件升级为全候选PASS。
完整选集及分类见manifest.selection；唯一新freeze，未修生产/游戏tests/generic runner。
## 实际结果
|phase|suite|exit|checks|passed|原因|
|---|---|---:|---:|---|---|
|focused|net_validation_hard_timeout_test|0|37|True||
|focused|validation_checkpoint_reader_test|0|10|True||
|focused|battle_board_end_command_test|0|38|True||
|focused|gateway_deferred_test|0|16|True||
|focused|gateway_disconnect_safe_close_test|0|7|True||
|focused|net_server_gateway_test|0|19|True||
|focused|net_validation_io_feedback_test|0|23|True||
|focused|net_background_validation_feedback_test|0|25|True||
|focused|net_server_discovery_validation_test|0|33|True||
|focused|net_validation_simulation_test|0|35|True||
|focused|client_match_inbox_contract_test|0|45|True||
|focused|newspecial_spell_materialization_test|0|13|True||
|focused|command_spell_source_activation_test|0|54|True||
|focused|round39_restore_transaction_test|0|61|True||
|focused|assembly_publish_lifecycle_test|0|36|False|expected_checks_66|
精确失败：`assembly_publish_lifecycle_test`；原始RESULT=["RESULT checks=36 failures=[]"]；错误=[]；源码与完整日志在evidence。

### 首红最短根因与完整输入交接（本轮不重跑）

- 冻结测试第25–27行 `_scan` 依赖 `HERMES_ASSEMBLY_PROBE` 与 `HERMES_ASSEMBLY_PYTHON`；第95–96行在 probe 为空时不添加 `external-file`，并打印跳分支标记。本轮 stdout 第27行实际为：`ASSEMBLY_NATIVE_SKIP explicit isolated native probe not configured; external-lock/handle-identity evidence unavailable`。聚合器没有显式配置这两个必需键；不是生产发布失败或 ERROR 豁免问题。
- 该分支证明运行时 `HERMES_ASSEMBLY_PROBE=""`（UTF-8 0 bytes）；没有保留完整执行时环境快照，不虚称 Python 键的精确值。36项全true且exit0也不能满足原生证据66项门；保持66，不修改游戏测试、不跳断言、不开始完整批次。
- 实际完整argv、冻结源hash、首红源码与日志：`evidence/failed-source/focused-assembly_publish_lifecycle_test.gd`（SHA256 `df499eff188d781c57b90a5ded679b9c0cc732f7ace9d8ca87e0cb607c14792b`）、`evidence/focused-assembly_publish_lifecycle_test.stdout.log` / `.stderr.log`；完整输入摘要在 `diagnostic-summary.json`。
- stdout 中全部204项批准清单原始JSON字节已经不截断提取到 `diagnostic-input/reconstructed-manifest.raw.json`：52,029 bytes，SHA256 `98469b47c4526f17a50633b3279567d17339fa61ed3895954e7ba9b3de58d568`；顺序、字段全部保留，声明字节总计95,949,242。该文件是原日志的字节提取，不是假造回执。
- 原66项执行所需的完整原生探针实现复制为 `diagnostic-input/native_probe.historical-reference-not-executed.py`：5,243 bytes，SHA256 `a392dd1ada99ad63a522e3690bd7db50353fbe4a1690f32b50681246b8fb6ede`。来源是round38归档；本轮没有执行它，不拿历史66项替代本轮36项。
- 交接主代理/聚合器owner：缺的是执行环境与白名单原生helper，不是规则修复。后续需要对helper字节、显式Python路径及当前UUID生成树作用域作独立参数/负向单元与真实Godot验证，不能仅补环境声明便升级本轮PASS。

## 完整回归输出根安全门
```json
[
  {
    "suite": "lobby_content_environment_restore_test",
    "path": "tests/lobby_content_environment_restore_test.gd",
    "line": 12,
    "source_sha256": "bb12f2bad7c9b8d64b7be9c2c3a1c4ad01148e2ef33da6bd1125fe0f9278e1c6",
    "reason": "unguarded absolute write root outside owned generated; no explicit root contract",
    "literal": "E:/Projects/Godot/FateDomination/test/lobby-content-environment-",
    "owner_handoff": "Main agent routes to unique game-test owner; integrated agent is read-only.",
    "required_contract": "OS.get_cmdline_user_args()[0], checked explicit physical E root; missing/unsafe root fails before any write.",
    "authorized_output": "E:/scratch/isolated-6089e442d5f34217a8b70bd70b149e7b/generated/f/complete-45",
    "suite_command_only_fix_possible": false
  },
  {
    "suite": "net_blob_concurrent_test",
    "path": "tests/net_blob_concurrent_test.gd",
    "line": 9,
    "source_sha256": "d9c07bed86d372aa3dea0a5ccd861f71795f478c28d9010dd0ed7aae75d0d143",
    "reason": "unguarded absolute write root outside owned generated; no explicit root contract",
    "literal": "E:/Projects/Godot/FateDomination/test/concurrent-blob-",
    "owner_handoff": "Main agent routes to unique game-test owner; integrated agent is read-only.",
    "required_contract": "OS.get_cmdline_user_args()[0], checked explicit physical E root; missing/unsafe root fails before any write.",
    "authorized_output": "E:/scratch/isolated-6089e442d5f34217a8b70bd70b149e7b/generated/f/complete-50",
    "suite_command_only_fix_possible": false
  }
]
```
上述未提供显式输出根的只读夹具不得写副本外旧目录；未擅自变换源码、创建junction或降低隔离门。唯一游戏测试owner由主代理路由：`lobby_content_environment_restore_test.gd:12` 与 `net_blob_concurrent_test.gd:9` 必须先实现并验证首个用户参数契约，再由聚合器添加 `-- <当前UUID/generated/f/complete-index>`；单纯传参目前无效。本轮列出的授权目录只是未执行计划，generated 已回收，不授权复用这些旧路径。
## GUI证据版本（不计本次PASS）
```json
{
  "suite": "local_spell_restore_test",
  "status": "REQUIRES_VERSION_BOUND_NON_HEADLESS_EVIDENCE",
  "log": "E:\\Projects\\Godot\\FateDominationGame-master\\reports\\refactoring\\main-review\\round37-final-local_spell_restore_test.log",
  "log_sha256": "276ae7d930464624b175cd7214282d2da2d949d49add3211feb0d5db16fe63c8",
  "recorded_checks": 25,
  "protocol_reparse": {
    "passed": true,
    "reasons": [],
    "result": {
      "checks": 25,
      "failures": [],
      "suite_prefix": null
    },
    "result_lines": [
      "RESULT checks=25 failures=[]"
    ],
    "errors": [],
    "raw_check_events": [
      "CHECK local old Control and 90x126 complete card restored true",
      "CHECK expanded local frame and badge have restored foreground layer true",
      "CHECK round badge center sits exactly on card bottom-right corner true",
      "CHECK badge reads true command spell balance true",
      "CHECK local count badge uses reduced size and type weight true",
      "CHECK local count badge is dark without bright glow true",
      "CHECK normal full card keeps explicit zoom declaration true",
      "CHECK declared specials are materialized as ordered held clones true",
      "CHECK private source exposes every complete held card with stable ids true",
      "CHECK public special projection keeps complete card faces without private effect objects true",
      "CHECK observer does not receive opponent private held cards true",
      "CHECK repeated binding does not duplicate instances or change ids true",
      "CHECK refresh preserves special card stable ids true",
      "CHECK all materialized specials retained while collapsed true",
      "CHECK hover expansion has intermediate animated width true",
      "CHECK expanded box exposes at most one special card true",
      "CHECK moving to expanded strip keeps it open true",
      "CHECK half-second refresh preserves hover and same special card node true",
      "CHECK special overflow has no visible scrollbar true",
      "CHECK restored open card box screenshot saved true",
      "CHECK real wheel scrolls hidden-bar special cards true",
      "CHECK real special card click requests its materialized engine effect true",
      "CHECK cancelling the real choice does not consume a command spell true",
      "CHECK leaving entire strip retracts to normal card true",
      "CHECK removing declarations clears special cards and closes strip true"
    ],
    "observed_checks": 25
  },
  "exit_zero_source": "round37-special-spell-takeover.md reports exit0; original standalone exit receipt unavailable",
  "non_headless_renderer_recorded": true,
  "historical_source_hash_binding": null,
  "current_capture_not_execution_binding": {
    "tests/local_spell_restore_test.gd": "dbbf0be8c648980eec2bb5c900b7acc1f179ac8ec5efeb4d37051395e0c398a8",
    "tests/local_spell_restore_test.tscn": "853190ec5fe0504bbae61e3973109e4c2428ea3394a8250e368d4dfe087a654a",
    "scripts/system/global/master_manager.gd": "3520e6a380d1da087e391fc26c972ed64e1c3bef21d644b7e31d6e187c6bd174",
    "scripts/game_scene/battle_board_v2.gd": "50171086aee3d1a85c2659f4410b2ab96efca6bc958a1fe59f2147b1780d74e3",
    "scripts/game_scene/tactical_board_ui.gd": "9c9d61642bf619c4012fced2b0244eebe89cf642be700f4418be82a0e4522ed9"
  },
  "version_gap": "No retained execution-time source manifest found alongside round37 GUI log; current hashes do not prove that run version.",
  "counts_as_current_pass": false
}
```
local_spell_restore保留完整鼠标GUI边界，不重跑错误模式、不跳断言、不算headless功能失败或PASS。
## Restart性能与完整正确性
历史round39真实600s correctness exit0/61项与60s performance RED分列；原始日志已读回并绑定输入hash，source_bindings见manifest.history。不是本轮完整集合通过，也没有重复历史长计算。
本轮完整阶段如启动，长场景仅执行一次600s correctness；当前实际次数=0。
## 发行阻断与收尾
native冷import发行仍阻断：round39已证宿主EditorHelp cleanup后deferred doc->generate空对象异常0xC0000005；无新正式DLL/两次fresh GREEN/export。当前整合headless import不替代发行冷导入门。
未完成GUI执行时版本绑定、实际GUI/发行EXE/跨机/跨网；引擎修复分支仍需用户确认；不叫最终交付或发行GREEN。
cleanup=generated_removed；generated_exists=False；源engine未变=True；先归档摘要读回=True。真实main/child probe PID29036/30520、各自读回物理E user://、实际池20、child exit0；17条根进程记录全部exited/ActiveProcesses=0/日志句柄释放。本轮唯一generated回收2,829,549,991 bytes。全部冻结白名单源文件在起始fingerprint→freeze→清理后无漂移，全部套件freezehash漂移=[]；原归档99项文件hash再次读回一致，补充输入摘要另列diagnostic-summary.json。

聚合器/选择/变换单元：`python -B -m unittest tools.tests.test_round40_selection tools.tests.test_round33_integrated_selection tools.tests.test_round32_freeze_editor_settings -v` → 10项PASS；`--parser-only` → PASS。原generic runner严格协议/预算/缺回执/路径/junction/Job/清理负向与真实自有派生Python生命周期另16项PASS（未冒称此单元为真实Godot全选集）。新reader/计数/安全分区均经历真实RED→GREEN单元，本轮Godot首红仍保留RED。production、游戏tests、generic runner摘要未改。

local_spell_restore明确是GUI，本执行器本轮没有运行；历史restart600s correctness仍是历史，当前运行次数0，不计新PASS，60s性能RED保留。
汇总拒绝原因：`["incomplete_or_duplicate_current_suites", "focused_incomplete", "focused_failure", "unsafe_full_output_contract"]`；worker错误：`[]`。
