# Round40 整合候选（不是最终交付）

结论：headless_candidate_passed=False；release_passed=false。
manifest：`E:\Projects\Godot\FateDominationGame-master\reports\refactoring\round40-integrated-aca3c9e86a3a48859ec012706d7e9237\manifest.json`；所有权：`E:\scratch\isolated-aca3c9e86a3a48859ec012706d7e9237\manifest.json`。
命令：`python -B tools/tests/test_round29_integrated_evidence.py --round40`；仅自有Windows Job PID，无窗口。
## 选择与分阶段结果
原66项+新增4项=70；分类：pure_headless=67，GUI=1，长正确性=1，精确bind负向=1；实际headless集合=69。
聚焦计划17套，实际执行9套：8套严格通过、1套因引擎错误拒绝；通过项合计196 checks，合法RESULT总计233 checks（失败套37项不计PASS）。完整回归实际=0/69（聚焦记录不充抵完整记录）；停止原因=focused_failure。未执行的8套为：client_match_inbox_contract_test、newspecial_spell_materialization_test、command_spell_source_activation_test、round39_restore_transaction_test、assembly_publish_lifecycle_test、gateway_relisten_acceptance_test、room_data_preparation_consumer_test、room_data_preparation_dependencies_test；不能宣称这些已在本轮复验。
import：`{"exit": 0, "errors": []}`；最终源码漂移：`[]`。
完整选集及分类见manifest.selection；唯一新freeze，未修生产/游戏tests/generic runner。
## 实际结果
|phase|suite|exit|checks|passed|原因|
|---|---|---:|---:|---|---|
|focused|battle_board_end_command_test|0|38|True||
|focused|gateway_deferred_test|0|16|True||
|focused|gateway_disconnect_safe_close_test|0|7|True||
|focused|net_server_gateway_test|0|19|True||
|focused|net_validation_io_feedback_test|0|23|True||
|focused|net_background_validation_feedback_test|0|25|True||
|focused|net_server_discovery_validation_test|0|33|True||
|focused|net_validation_simulation_test|0|35|True||
|focused|net_validation_hard_timeout_test|0|37|False|engine_or_assertion_error|
精确失败：`net_validation_hard_timeout_test`；原始RESULT=["RESULT checks=37 failures=[]"]；错误=["ERROR: Parse JSON failed. Error at line 0: Unknown error getting token"]；源码与完整日志在evidence。

### 首红精确定位（交测试owner，不重跑大集合）

- 真实 stderr 回溯唯一来源：`tests/net_validation_hard_timeout_test.gd:29::_poll_complete_task` → `tests/net_validation_task_test.gd:82::run`。这是主管测试轮询中的 `JSON.parse_string(FileAccess.get_file_as_string(path))`，不是 worker 日志错误，也不是通用聚合器误报。
- 第28行只判断 `FileAccess.file_exists(report.json)`，未保留打开错误、读到的具体字节或 quiet parser 返回值；存在检查不能保证下一次读取必定成功。确切的读入异常字节及其时间点没有保留，不能进一步断言是空文件、共享锁、替换瞬间还是非法写入。
- `room_data_validation_worker.gd:155–163::_write_report` 当前源码是 `.tmp`写入/flush/close后rename；因此不能用这条测试读取错误直接指控生产在原地半写report.json。正式worker日志没有引擎/脚本错误。
- 该套37项CHECK全部true、唯一RESULT、exit0仍严格拒绝：不是规则硬超时功能断言失败。不能加全局JSON ERROR豁免、选择性重跑至绿或以round38历史37项顶替。
- 冻结源SHA256：hard-timeout测试 `1630a3e830849e9e0d10c541494239ded2dad9ca0b57eb7e522a82b8ca7d002a`；父测试 `5003903e53542705bdb9fd54e44d1ecbf7f5de9c4a3023501f83a735a4a9525f`；worker `86e281f0c0987e7b76a2736373bb046ec9e0c278bef71d0d82424fe8da407a9c`。全源前后无漂移，供唯一测试owner补齐读失败观测与规范失败处理；本代理没有写权限，不改其断言/源码。

## 完整回归输出根安全门
```json
[
  {
    "suite": "lobby_content_environment_restore_test",
    "path": "tests/lobby_content_environment_restore_test.gd",
    "line": 12,
    "source_sha256": "bb12f2bad7c9b8d64b7be9c2c3a1c4ad01148e2ef33da6bd1125fe0f9278e1c6",
    "reason": "unguarded absolute write root outside owned generated; no explicit root contract",
    "literal": "E:/Projects/Godot/FateDomination/test/lobby-content-environment-"
  },
  {
    "suite": "net_blob_concurrent_test",
    "path": "tests/net_blob_concurrent_test.gd",
    "line": 9,
    "source_sha256": "d9c07bed86d372aa3dea0a5ccd861f71795f478c28d9010dd0ed7aae75d0d143",
    "reason": "unguarded absolute write root outside owned generated; no explicit root contract",
    "literal": "E:/Projects/Godot/FateDomination/test/concurrent-blob-"
  }
]
```
上述未提供显式输出根的只读夹具不得写副本外旧目录；未擅自变换源码、创建junction或降低隔离门。
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
未完成GUI执行时版本绑定、实际GUI/发行EXE/跨机/跨网；不叫最终交付。
cleanup=generated_removed；generated_exists=False；源engine未变=True；先归档摘要读回=True。收尾独立复核11条根进程记录均exited、ActiveProcesses=0、日志句柄释放；源文件全部仍等于冻结原始hash；归档全部日志再次SHA256读回一致；唯一generated回收1,677,585,352 bytes。真实main/worker探针PID33268/28076，均物理E且实际池20，child退出0；回执hash见manifest。

聚合器/选择/变换单测实际执行：`python -B -m unittest tools.tests.test_round40_selection tools.tests.test_round33_integrated_selection tools.tests.test_round32_freeze_editor_settings -v` → 8项PASS/exit0；`--parser-only` → PASS。新分类及严格协议新增项均实际经历RED→GREEN，原bind局部负向/导入/漂移/进程/清理负向门未放宽。
汇总拒绝原因：`["incomplete_or_duplicate_current_suites", "focused_incomplete", "focused_failure", "unsafe_full_output_contract"]`；worker错误：`[]`。
