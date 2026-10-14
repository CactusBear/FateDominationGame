# Round42 整合候选（不是最终交付）

结论：headless_candidate_passed=False；release_passed=false。
manifest：`E:\Projects\Godot\FateDominationGame-master\reports\refactoring\round42-integrated-68eeb9d161c54e47ab9e25b4fa18cc6b\manifest.json`；所有权：`E:\scratch\isolated-68eeb9d161c54e47ab9e25b4fa18cc6b\manifest.json`。
命令：`python -B tools/tests/test_round29_integrated_evidence.py --round42 --complete-candidate`；仅自有Windows Job PID，无窗口。
阶段策略=complete_only_current_freeze；当前完整结果不充抵或合并任何历史focused记录。
## 选择与分阶段结果
原66项+显式新增后=71；分类：pure_headless=68，GUI=1，长正确性=1，精确bind负向=1；要求headless集合=70。
聚焦=0/0；完整回归实际=39/70（聚焦记录不充抵完整记录）；停止原因=complete_first_failure。
精确阶段=complete；前置错误=none；实际聚焦执行数=0；focused=0不代表业务PASS或FAIL。
import：`{"exit": 0, "errors": []}`；最终源码漂移：`[]`。
安全可运行headless=70；未授权不得执行=[]；即使安全集合通过，也不将缺失套件升级为全候选PASS。
完整选集及分类见manifest.selection；唯一新freeze，未修生产/游戏tests/generic runner。
## 实际结果
|phase|suite|exit|checks|passed|原因|
|---|---|---:|---:|---|---|
|complete|assembly_publish_lifecycle_test|0|66|True||
|complete|round28-command-migration_test|0|66|True||
|complete|battle_board_end_command_test|0|38|True||
|complete|battle_board_activation_command_test|0|21|True||
|complete|active_choice_source_command_test|0|65|True||
|complete|card_choice_source_command_test|0|18|True||
|complete|location_choice_source_command_test|0|37|True||
|complete|battle_command_adapter_test|0|29|True||
|complete|match_command_dispatcher_test|0|313|True||
|complete|match_command_result_protocol_test|0|39|True||
|complete|match_commands_test|0|17|True||
|complete|net_pending_test|0|20|True||
|complete|net_cards_test|0|7|True||
|complete|net_move_test|0|11|True||
|complete|net_locations_test|0|7|True||
|complete|net_authority_ui_preview_feedback_test|0|8|True||
|complete|battle_board_v2_test|0|53|True||
|complete|battle_play_groups_test|0|43|True||
|complete|deploy_rules_layer_test|0|22|True||
|complete|mana_spend_test|0|45|True||
|complete|regular_play_test|0|54|True||
|complete|player_choice_source_command_test|0|65|True||
|complete|client_identity_inbox_contract_test|0|58|True||
|complete|host_room_inbox_contract_test|0|34|True||
|complete|net_selection_settings_test|0|7|True||
|complete|net_runtime_guard_test|0|34|True||
|complete|net_resume_identity_test|0|26|True||
|complete|gateway_deferred_test|0|16|True||
|complete|gateway_disconnect_safe_close_test|0|7|True||
|complete|gateway_instance_binding_test|0|20|True||
|complete|net_server_gateway_test|0|19|True||
|complete|net_server_gateway_restart_test|0|61|True||
|complete|net_data_validation_test|0|13|True||
|complete|net_validation_io_feedback_test|0|23|True||
|complete|net_validation_io_measure_test|0|9|True||
|complete|net_background_validation_feedback_test|0|25|True||
|complete|net_server_discovery_validation_test|0|33|True||
|complete|content_environment_test|0|30|True||
|complete|worker_content_environment_test|125|None|False|nonzero_exit;expected_one_stdout_result;engine_or_assertion_error|
精确失败：`worker_content_environment_test`；原始RESULT=[]；错误=["FAIL: static loading scope completes", "FAIL: actual copied roster loaded", "FAIL: real snapshot written inside scope", "FAIL: invalid simulation still completes reporting scope", "FAIL: real simulation rejects invalid options", "FAIL: real asynchronous simulation completes content scope", "FAIL: await suspension keeps temporary content environment installed", "FAIL: real progress report exists while simulation awaits", "SCRIPT ERROR: Invalid access to property or key 'performance' on a base object of type 'Dictionary'.", "SCRIPT ERROR: Invalid access to property or key 'performance' on a base object of type 'Dictionary'.", "SCRIPT ERROR: Invalid access to property or key 'performance' on a base object of type 'Dictionary'.", "SCRIPT ERROR: Invalid access to property or key 'random_simulation' on a base object of type 'Dictionary'.", "ERROR: Parse JSON failed. Error at line 0: Unknown error getting token"]；源码与完整日志在evidence。
## 完整回归输出根安全门
```json
[]
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
    "scripts/game_scene/battle_board_v2.gd": "93bbe403d3aee4bd59349d55d9dad7416a24ff6b444af390e2fbb606df16e888",
    "scripts/game_scene/tactical_board_ui.gd": "9c9d61642bf619c4012fced2b0244eebe89cf642be700f4418be82a0e4522ed9"
  },
  "version_gap": "No retained execution-time source manifest found alongside round37 GUI log; current hashes do not prove that run version.",
  "counts_as_current_pass": false
}
```
local_spell_restore保留完整鼠标GUI边界，不重跑错误模式、不跳断言、不算headless功能失败或PASS。
## Restart性能与完整正确性
历史round39真实600s correctness exit0/61项与60s performance RED分列；原始日志已读回并绑定输入hash，source_bindings见manifest.history。不是本轮完整集合通过，也没有重复历史长计算。
本轮完整阶段如启动，长场景仅执行一次600s correctness；当前实际次数=1。
## 发行阻断与收尾
native冷import发行仍阻断：round39已证宿主EditorHelp cleanup后deferred doc->generate空对象异常0xC0000005；无新正式DLL/两次fresh GREEN/export。当前整合headless import不替代发行冷导入门。
未完成GUI执行时版本绑定、实际GUI/发行EXE/跨机/跨网；引擎修复分支仍需用户确认；不叫最终交付或发行GREEN。
cleanup=generated_removed；generated_exists=False；源engine未变=True；先归档摘要读回=True。
汇总拒绝原因：`["incomplete_or_duplicate_current_suites", "current_suite_failure"]`；worker错误：`[]`。
## 当前原生授权与精确负向分类
统一静态预检在所有suite之前完成；显式Python仅作只读安装解释器，所有生成/fixture/source/引擎根要求无链接物理E。
当前 helper SHA256=`ace59ea3704270aab0bc66f0fbfedd385621b192944242c16867be80cc6ca689`；原生调用回执=10。scope原字节、环境、argv、父PID/创建时间/Job成员、7份scan/2份identity/1份lock回执均独立保留。
assembly必需66项门未改；出现ASSEMBLY_NATIVE_SKIP即拒绝。历史round38日志不计本轮PASS。
child ERROR原始列表原样保留，strict拒绝仍false；只对源码hash、34项唯一RESULT、单卡manifest、完整两段回溯、负向report及自有Job退出全部相符的dependencies分支分类。任何额外ERROR、坏hash/manifest或不同suite均不豁免。
```json
[]
```

## 首红精确根因与唯一owner交接

**完整阶段39/70：38套通过、1套首红、31套未执行。** 合法RESULT checks合计1459；完整单阶段focused=0/0不是全0执行，也不充抵之前独立聚焦18/18、604 checks。

本节以下相对路径均指归档根`reports/refactoring/round42-integrated-68eeb9d161c54e47ab9e25b4fa18cc6b/`。

`manifest.json` SHA256=`de95e54d7cdb2d7b1a5efd8355d28a791a211bb29347ecc7d56eb81919e27185`；原自动报告副本=`automatically-generated-report.md`；精确输入/前后hash/未跑31名/交接=`diagnostic-summary.json`。原manifest和日志未改。

首红PID25996，180s看门狗触发，自有Job终止exit125，含收尾184.849s；RESULT=[]，不虚造其checks或PASS。八个失败断言完整列在前文及stdout。

最早错误是`Invalid access to property or key 'performance' on a base object of type 'Dictionary'`：测试`report():21`仅构造ok/errors/masters/servants/loop_analysis，缺performance；79/89/98行绕过正式worker入口直接调用`_inspect_loaded_content`，生产123行写`report.performance.release_usec`立即异常。正式`_ready`在59行先设置`report.performance=timing`再于61行调用，夹具漏了该契约。其后测试99行读取未生成的random_simulation、42行解析空进度报告是连锁错误；run异常中断未finish，所以看门狗终止。

**不是已证实的生产环境恢复缺陷。** 123行早于125行environment.install，异常发生时该调用尚未安装内容环境；LOCALAPPDATA已显式配置到当前UUID物理E生成树，不是因首参数缺失写旧根；测试直接调用内部方法，也没有进入权威身份握手。真实main38624/child3220的物理E user回执、实际pool20及child exit0已前置读回；冷import无错误。不能据本异常把路径/身份/20pool或install/restore说成产品根因。

原stdout hash=`64cdc9e8ce1d3969b58ba594755aa959fb2083130443ed7325ad88ec8d2eb01f`；stderr hash=`1de2904ea65b714ff7d75baaab7fc2b08416283c4b4d6a6ed90f8879ce4053ff`。完整源before/after、frozen before/after和复制归档hash均相等，副本在`diagnostic-source/`：

|文件|SHA256|
|---|---|
|tests/worker_content_environment_test.gd|`44bae34e5cf96d3bf19a7322848aa9f252e2bd8471c82050a72dc0eee9eba954`|
|tests/worker_content_environment_test.tscn|`e2356e646f00e5e31825029b203502047658f746bd683483729a076b230b56f7`|
|scripts/net/validation/room_data_validation_worker.gd|`86e281f0c0987e7b76a2736373bb046ec9e0c278bef71d0d82424fe8da407a9c`|
|scripts/system/global/content_environment.gd|`fdc139c595c143b68a3168f93eb2ee4d992d899230c9546025a962eb8580c363`|

**交接主代理分配`tests/worker_content_environment_test.gd`唯一owner：**先让report夹具满足现行生产报告契约，保留真实异步恢复、无效配置、rename拒绝及全部断言；仅单套隔离RED/GREEN，不因本报告再跑整批。整合owner对此游戏测试和production无写权，未加容错或删必需分支。

未跑31套见manifest.summary.missing；两已修输出根套件也在当前完整候选未执行，不能拿owner独立1544/20结果升级本候选PASS。

## 独立原生66项与输入追溯

当前完整assembly PID22900、exit0、唯一66项RESULT、stderr0 bytes、ASSEMBLY_NATIVE_SKIP=false；测试hash仍`df499eff188d781c57b90a5ded679b9c0cc732f7ace9d8ca87e0cb607c14792b`，未改测试或66门。

- stdout hash=`130a1b4f501021e4ad3866b342329b8f2bd51aac31c484697bc41c8e95c14233`；stderr空hash=`e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`。
- `native-audit/`的7 scan/2 identity/1 lock原argv、父PID/创建时间、Job成员和结果均保留，caller均22900、duplicate_failures=[]；外部占锁child32872，真实ready PID一致、share_flags=3，released=true，实际exit0断言通过。
- helper用`NtQueryInformationProcess/ProcessHandleInformation`仅查询授权进程，不枚举系统所有句柄、不启debug privilege、不扫描外部PID、不做发布回退/重试。
- 当前scope原字节/hash和helper在`native-input/`；fixture限定该suite generated/f子树，source精确frozen project/data；匹配执行器PID+创建时间、直接Godot父PID、自有E引擎/hash和Job，任一拒绝即不查句柄。
- `native-negative-cli/`真实拒绝C根、越界、旧token、非自有PID、坏scope hash均exit2/无stdout；另一个独占E生成树中的真实junction也在查句柄前拒绝，链接及generated已回收。mklink本地化stdout有编码解码异常，未视为干净输出；拒绝和清理回执独立成立。
- 204清单从原stdout提取原字节，不重造：`native-input/reconstructed-manifest.raw.json` 52,029 bytes，hash=`98469b47c4526f17a50633b3279567d17339fa61ed3895954e7ba9b3de58d568`，声明95,949,242 bytes，与round41原hash相同。
- round38真实调用参数/hash在`historical-native-input/trace.json`：verify24/25行配置scratch helper/sys.executable；游戏29行scan(PID,fixture,staging,data)，40行identity(parent)，111行create_process lock(fixture,file,ready,release)。历史PID29796/exit0仅历史，不计当前PASS；历史Python只保留sys.executable表达式，没有虚称字面环境快照。
- 原helper 5,243 bytes/hash=`a392dd1ada99ad63a522e3690bd7db50353fbe4a1690f32b50681246b8fb6ede`；现已迁入可维护源码，当前hash见前文。当前执行不依赖已回收scratch。

## 单元、修改、尝试与收尾

仅写聚合器、`test_round40_selection.py`、新`tools/diagnostics/assembly_native_probe.py`及本报告；production/游戏tests/generic runner只读，未commit。实际与round41前后diff/hash在`change-evidence/`。

`unit-evidence/`保留有效RED：缺统一预检/helper、缺阶段停止原因、缺owner绑定/精确负向分类、缺非选中契约场景；随后GREEN。最终选择/协议/变换单元17项PASS、parser-only PASS。完整前静态一次检查71套及四份路径owner交接hash，blockers=[]；不按无旧字面根便自动放行。

本轮各尝试单列，不能合并PASS：
1. `209dfbe7d04a4b1dbdb7743b3703fc0b`：freeze复制battle_board_v2并发漂移、0业务执行；属于前置阻断，不是业务FAIL/PASS。原错误/hash及prelaunch清理回执保留，578,049,380 bytes已回收。
2. `278ce6b21ee646e9bae7ded5f6d654e7`：实际聚焦18/18、604 checks，完整0/70；路径识别仍保守阻断，dependencies单卡负向worker原ERROR独立保留。3,986,117,544 bytes已回收。
3. `4af2daba08d140c480e2b4040e06fa92`：静态发现契约tscn未冻结后主动停止，完成3套，未记录/部分日志不计PASS；精确自有引擎/Python UUID进程查询为空后回收909,091,119 bytes。后已显式冻结该契约，并让基础前置红在任何suite前停止。
4. 当前`68eeb9d161c54e47ab9e25b4fa18cc6b`：39/70首红停止，41条根进程全部退出/ActiveProcesses0/日志句柄释放；归档hash再次逐项读回相等，回收2,904,843,644 bytes后generated不存在，源D引擎未变。

完整候选首红后没有继续或整批重跑。GUI版本/发行EXE/冷import修复两次fresh门/跨机跨网仍未交付；本轮headless不替代发行门，不宣称历史assembly根因已根治。
