# Round64：最终候选计数合同刷新（不是全量 PASS）

## 已验证结果

- 正式计划 **99 headless / 101 formal / 103 programs**；完整保留原98 headless，新增正式 `loader_error_boundary_test`。2个 GUI、2个 native standalone、1个 required extracted harness、2个独立 loader negative mode 分开计数。
- 最终有界小批 **actual=unique=strict-pass=7，CHECK=RESULT checks=370**：六旧迁移夹具308 + loader62。worker45只作前置，未冒计第八个正式场景；它本次是 quiet RESULT，不冒称观察了45条 CHECK。
- Python最终 **33 tests / exit0**（新5 + candidate16 + resource12）；严格 parser-only exit0。真实缺功能 AssertionError RED→GREEN 覆盖新增断言误红、loader遗漏、声明重复/遗漏以及小批计数分区；ERROR/false CHECK/重复 RESULT/重复显式 id/少原覆盖均拒绝。
- `sourcePASS=false / releasePASS=false / candidate passed=false`。本轮没有全98/99、GUI、native构建、release或真人跨机验收，没有改历史 manifest。

## 原98逐项对账与最低覆盖

完整98行，不靠手数：

`E:/scratch/round64-contract-audit-467f103f146e4dee91cd657355343db6/audit.json`

每行给出原真实 declared/observed、原pass、legacy minimum、当前 mandatory 和有据可读回的新增专项。原 manifest SHA仍为：

`d439e06fd4a92592211d306dfa292ba2af90c04c699bdd3fb52ee19b5bcc85b4`

原 **98actual/87pass/11RED** 不变。原无合法RESULT的行保持 null；原中断前 CHECK 不虚构成完整检查总数。新专项证据只用来声明覆盖合同，不把它的历史PASS计入新完整候选。

旧 `ROUND40_EXPECTED_CHECKS` 和 shutdown 86/36/161保持原值；当前 mandatory 为原98明示正整数下限、旧mandatory、新专项计数的逐项最大值，不会降低assembly66、restart61、worker45或shutdown283。历史 Round40 exact analyzer未改；当前Round50入口不再把新增检查误当回退。

|场景|旧覆盖边界|当前明示最低检查|本轮最终实测|
|---|---:|---:|---:|
|battle_board_end_command_test|38（原完整夹具）|46|46|
|round28-command-migration_test|66（继承父夹具）|74|74|
|battle_board_activation_command_test|21|21|21|
|active_choice_source_command_test|65|65|65|
|location_choice_source_command_test|37|37|37|
|player_choice_source_command_test|65|65|65|
|battle_play_groups_test|原Round58仅2条即中断；后续完整样本43|56|本轮不重跑，读回Round60正式56|
|loader_error_boundary_test|新增|62|62|

end/round28增加8条正式ownership检查，两处真实执行；原六文件的 `check(...)` 调用逐行多重计数比较 missing=[]。分组43是后来完成样本的下限，不是捏造原Round58总数；新56覆盖按Round60实际RESULT声明。relay原20条中断不能当完整门，后续完整22形成明示下限。原restart失败52不能将mandatory61降成52。

**计数增加可以通过；覆盖减少不可以。** 当前协议仍要求唯一合法stdout RESULT、明确零failures、exit0、无非预期ERROR；打印CHECK时 observed必须等于declared。六迁移、分组、loader和shutdown更要求实际CHECK输出，不接受空输出只报大数字。循环相同文案是事件，不机械去重；显式id重复仍拒绝。

## loader分区与真实API

- 正向普通scene：`res://tests/loader_error_boundary_test.tscn`，正式selected只增加这个名字。
- 动态参数按当前GD `get_cmdline_user_args` 注入：`-- <owned physical E output> green`。GD自己再创建 `loader-boundary-<pid>`；没有猜固定旧目录，也没有改GD/source。
- `expectednegative`、`expectednegative_extra` 仍在当前专属 `tests/round62_loader_error_boundary_runner.py` 内独立执行，9 checks各自计数，不进入普通scene、不进入完整门ERROR豁免。
- 本轮unit从真实归档重放该runner的四个实际分析函数（AST只取函数定义，不执行main）：准确六个operation/kind/path/message ERROR才允许；未知ERROR、脚本错、错路径、重复RESULT及少事件拒绝。extra归档的真实 `ROUND62_UNEXPECTED_EXTRA_ERROR`底层继续false。普通loader分析器对同一负向日志继续false。
- 本轮**没有新启动两个负向mode**，不将重放说成新负向Godot实跑。需要重新执行独立scope时现有合法命令是 `python -B tests/round62_loader_error_boundary_runner.py green`；它会单独冻结并执行该runner自己的全部专项，不能拿其指纹混入完整候选。

## 最终小批原件

最终唯一计绿样本：

`E:/scratch/isolated-bc9c4861e12e4f13b21dade618dc9b50/manifest.json`

SHA256：`e83b927206c0f5323a489ffe796a3b5201ca0e1fe5deb119dd5304fe69e7aa2b`

- 同根 `round64-verification-readback.json`：重新解析7套原始stdout/stderr、370事件、原档SHA、冻结hash、Job/句柄、字节占用和真实worker报告。
- `evidence/complete-<suite>.stdout.log/.stderr.log` 是未过滤原件；`worker/`保留两份真实validation report/manifest/logger。
- 1826个显式冻结依赖，只选七场景和worker45前置的真实测试闭包，不复制整个tests。源指纹 `82aead8eed33165498be120387d2da15c518ce16b3fbb502b8957218446e23f1`；执行末source/frozen drift均[]，读回时current drift也[]。
- 所有场景自然exit0，每root看门狗180秒；probe/import/前置/七场景合计10条root记录全部exited、Job active=0、日志句柄释放。没有全局kill，没触碰28100。
- loader真实单卡child拒绝exit1，report=0 masters/0 servants/三条精确结构化错误；真实204 child exit0，7 masters/8 servants/errors=[]。204明确loader-only、simulation.enabled=false，不冒充原15秒正式性能链；模板15/pool20未改。
- 原Godot SHA `ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424`；原正式DLL SHA `92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd`。没有替换DLL或引擎。

真实命令均exit0：

```text
python -B tools/tests/test_round29_integrated_evidence.py --parser-only
python -B -m unittest tools.tests.test_round64_candidate_contract tools.tests.test_round50_candidate_selection tools.tests.test_round61_runner_resource_accounting -v
python -B tools/tests/test_round29_integrated_evidence.py --round50 --contract-proof-seven-scenes --approved-root E:/scratch
python -B tools/tests/test_round64_candidate_contract.py --verify-proof E:/scratch/isolated-bc9c4861e12e4f13b21dade618dc9b50/manifest.json
python -B tools/tests/test_round64_candidate_contract.py --audit E:/scratch
python -B tools/tests/test_round29_integrated_evidence.py --round50 --preflight-only --approved-root E:/scratch
```

原始Python日志在 `E:/scratch/round64-units-final2.*.log`、`round64-parser-final.*.log`；最终实跑驱动日志在 `round64-seven-proof-final.*.log`。

### 保留的前序样本

1. `isolated-b1ce004afc274da989fd6ee9d81fbe7e`：probe/import/worker45已运行；生产owner在执行期间改变 `scripts/io/temporary_cleanup_native_delete.gd`，漂移门停止，正式七套actual0；exit1。未忽略漂移、未将前置计绿充抵目标。
2. `isolated-5cd40f60884d4fd4841f82b280554fc3`：七套370实跑成功，但proof selection继承了完整plan的program_count字段。新增unit真实RED（103≠9）后只修小批metadata计数，最终七套再次全新同冻结执行。前样本不拼接最终PASS、不覆写原件。

## 资源授权：只验证，不扩删除

资源机制12个原有单元本轮重新真实通过，包括cache/records/密钥/sharedfreeze保留、未知文件拒绝、坏archive、live Job、日志未释放、junction、源漂移与累计预算。没有新增可删文件类别，没有扩大prefix或总树删除权限。

本次七场景proof **不调用逐套reclamation，不删除生成树**；保护records/cache/config、共享freeze/engine全部原位置保留，继续算在同一owner预算。最终readback时owner **974013173 bytes / 8589934592 bytes**，不能由此保证完整99套不超过预算。顶层cleanup_not_verified和passed=false是有意保留边界；只 `contract_proof_passed=true`。不是清理失败后谎报全量通过。

## 源依赖与待执行最终冻结命令

完整计划只读preflight：`E:/scratch/round64-preflight-final.json`，status=selection_ready、launch=import=0。它不是源码稳定承诺。

- 完整2033依赖逐路径清单：`E:/scratch/round64-contract-audit-467f103f146e4dee91cd657355343db6/source-dependencies.txt`。
- 同根 `preflight.json` / `audit.json`保存逐文件SHA及模式/继承/helper闭包。包括当前scripts/generated依赖、selected .gd/.tscn、worker scene、正式DLL/扩展声明、项目、必要assets/data及extracted parent/runner；排除records/秘密/热重载DLL/旧运行产物。
- 执行器依赖另列：两个候选Python、generic `tools/run_isolated_godot_test.py`、`tools/diagnostics/assembly_native_probe.py`；本轮新unit/audit/readback工具为 `tools/tests/test_round64_candidate_contract.py`。
- 独立负向scope还依赖 `tests/round62_loader_error_boundary_runner.py`、loader GD/scene、LoadGame/validation worker及其静态闭包；不冒充正式scene依赖或同freeze信用。
- 独立native源清单/6份SHA在preflight.native_standalone：两个core cpp/hpp与 `tools/tests/temporary_cleanup_core_probe.cpp`、`tools/tests/process_tree_owner_core_probe.cpp`，必须另外执行，不能拿旧DLL替代standalone门。

**GUI/source owners确认停止写入以后**，重新做unit和只读preflight，再由唯一owner执行下列最终headless冻结命令（本轮未执行）：

```text
python -B tools/tests/test_round29_integrated_evidence.py --round50 --preflight-only --approved-root E:/scratch
python -B tools/tests/test_round29_integrated_evidence.py --round50 --complete-candidate --collect-failures --approved-root E:/scratch
```

调用时从新preflight重新取得当前依赖/hash，任何源/frozen漂移、未知回收文件、byte_budget仍立即安全停止；不提供把旧98 manifest当当前选集resume的命令。99 headless通过也不等于2个GUI、supplementary window、native standalone或发行总PASS；retained数据未获归档/删除许可时继续保留阻断。GUI owner仍写时本轮不执行全量freeze，不声称最终总PASS。

本轮仓库写入仅：两个授权candidate Python、新 `test_round64_candidate_contract.py`、本文。GD/native/release/其它tools均只读，无stage/commit。
