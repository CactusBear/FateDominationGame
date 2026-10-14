# 可立即替换11处的逐条核验与替换回执

结论：9处已等价替换（6文件）；2处因独立oracle/无副作用断言强度不能保留，未改并归入“需要新增公开能力”。生产源码、前端、gate与允许清单均未由本任务修改；未删断言、未运行全量/测速/窗口、未接触PID 17120/28100。

## 原审计完整11条清单与处理

源：`E:/hermes-scratch/private-read-audit-20261010/latest/inventory.json`，取 `reads[].category == 可立即替换`，精确11条。全部7个消费者文件的修改前SHA256与审计source_sha256一致。原inventory保持不动，分类纠正记录于本目录changes.json/receipt.json。

|文件:行|被读私有成员|生产owner|审计公开入口|决定|
|---|---|---|---|---|
|`newtests/play_affordance_rule_audit_test.gd:75`|`card._attributes`|`scripts/system/base_card.gd`|has_attribute(原参数)（scripts/system/base_card.gd:88）|等价替换|
|`scratch/transaction-return-consumers/transaction_return_consumers_test.gd:280`|`authority._revision`|`scripts/net/authority/match_authority.gd`|current_revision()（scripts/net/authority/match_authority.gd:33）|等价替换|
|`tests/authority_revision_query_test.gd:18`|`authority._revision`|`scripts/net/authority/match_authority.gd`|current_revision()（scripts/net/authority/match_authority.gd:33）|不改：需要新增公开能力（独立oracle）|
|`tests/authority_revision_query_test.gd:40`|`authority._revision`|`scripts/net/authority/match_authority.gd`|current_revision()（scripts/net/authority/match_authority.gd:33）|不改：需要新增公开能力（独立oracle）|
|`tests/climax_gated_ability_test.gd:62`|`clone._attributes`|`scripts/system/base_card.gd`|has_attribute(原参数)（scripts/system/base_card.gd:88）|等价替换|
|`tests/match_finished_authority_test.gd:59`|`authority._revision`|`scripts/net/authority/match_authority.gd`|current_revision()（scripts/net/authority/match_authority.gd:33）|等价替换|
|`tests/match_finished_authority_test.gd:63`|`authority._revision`|`scripts/net/authority/match_authority.gd`|current_revision()（scripts/net/authority/match_authority.gd:33）|等价替换|
|`tests/match_finished_authority_test.gd:83`|`authority._revision`|`scripts/net/authority/match_authority.gd`|current_revision()（scripts/net/authority/match_authority.gd:33）|等价替换|
|`tests/match_finished_authority_test.gd:86`|`authority._revision`|`scripts/net/authority/match_authority.gd`|current_revision()（scripts/net/authority/match_authority.gd:33）|等价替换|
|`tests/refactor_net_area_diagnostic.gd:180`|`diagnostic_host.match_authority._revision`|`scripts/net/authority/match_authority.gd`|current_revision()（scripts/net/authority/match_authority.gd:33）|等价替换|
|`tests/servant_skill_eight_magic_test.gd:85`|`current._attributes`|`scripts/system/base_card.gd`|has_attribute(原参数)（scripts/system/base_card.gd:88）|等价替换|

## 等价性与断言强度

- `scripts/system/base_card.gd:88–89`：`func has_attribute(attribute:String) -> bool: return _attributes.has(attribute)`。SPECIAL/NOBLE_PHANTASM参数均为原参数；只替换数组has访问链，不改变条件、否定、短路位置或夹具写入。没有副作用。
- `scripts/net/authority/match_authority.gd:33–34`：`func current_revision() -> int: return _revision`。没有状态写入、签发、审计或规则推进；返回相同int值。原`> 0`、相等、`revision + 1`比较、诊断字典key和其它私有快照均保留。
- `tests/authority_revision_query_test.gd:18`明确注释独立旧语义oracle（16行），被用于32/33/37行验证公开入口准确性。改为被测公开入口会把“对内部水位的精确读取”退化为同入口重复一致，无法同强度检测错误实现。
- 同文件40行是查询前后内部水位未改的快照比较（38–47行）；改为被测入口会丧失独立内部状态观测，不能以其它重复查询或删断言替代。因此18/40行均不改、归入“需要新增公开能力”；本轮不新增生产入口。
- 逐文件比对修改前原字节与预期九处原位替换，确认修改后逐字一致；无额外格式化、断言删除或语义修改。

## 改动位置与完整SHA256

|文件:行（行号未变化）|改前SHA256|改后SHA256|
|---|---|---|
|`newtests/play_affordance_rule_audit_test.gd:75`|`32c27a860c02edb90aedf2af342e23ee3f876f625b08fc3441092774aec10302`|`fa11eb29a52a29eed20a2761f5600fa7d9403ee19f56570892cfb8db1f88b404`|
|`scratch/transaction-return-consumers/transaction_return_consumers_test.gd:280`|`535c8b56dd43606ace9f5c13e7465aa9381812f40a074a92257fd906fb1cbad5`|`59f6a72cd1512e17bf4177d96825e61cb6bbb25c20b7190f4f23fde2a03b7bb1`|
|`tests/climax_gated_ability_test.gd:62`|`638f827688cf28ffaa19910cc96ec8d87ce0d469e41cd596ba3d0a3e6706af62`|`1bf260e3b0cbd96d8ecf667ec527c7ea5bc10f9a0e5c7a66105edcacab2b6360`|
|`tests/match_finished_authority_test.gd:59,63,83,86`|`a1ecfb78c144607a52deb77795d1285fd5967d924951fd6ea4325ac0138ffb06`|`7e0de23a0ff0e9d2a119faab24b7d655d53e91a951858b7b4c7551c28dd8b5dd`|
|`tests/refactor_net_area_diagnostic.gd:180`|`a0964fdf276e12326bf63eddb9ea719943de0c5070b65e08d216f078837e0fd3`|`e7eb3f96da06646e4920c51b5f6f25910e864bb55e4bbdb56f7cc9dc89ace557`|
|`tests/servant_skill_eight_magic_test.gd:85`|`8758eadfc12064ba6109a338f7005dc13ee91e35747f674c26d0ae13d1a3a861`|`489814c473f58f66f1d8b3246c52b7d5cb05ebcdde0fc2a098e9ce55fe5b9a95`|

未改：`tests/authority_revision_query_test.gd:18,40`；改前后SHA256均为 `f0b94b7f89843a3a7ad7222982b7d04362f327d06596005a89986fdef8e59d24`。

## 真实套件结果

引擎：`E:/scratch/round51-engine/Godot_v4.7.2-stable_win64.exe`，复制为独占E盘Godot.exe，SHA256：`ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424`。
执行器：本目录`run_selected.py`，复用仓库的OwnedJob挂起分配/恢复、600s每进程看门狗和严格日志分析，不更改生产或gate。显式依赖冻结、APPDATA/LOCALAPPDATA/TEMP/TMP/TMPDIR及user/worker探针均在本次E盘生成树；不碰其它进程。
真实命令：`python E:/hermes-scratch/private-read-replacement-20261010/run_selected.py`。每个场景命令详见manifest，统一`--headless --fixed-fps 60 --path <独占冻结项目> --scene res://<下表套件>.tscn`。
导入：exit 0，ERROR=[]。日志、真实CHECK、RESULT、完整argv、Job进程回执保存在：`E:\hermes-scratch\private-read-replacement-20261010\selected-082e42f9c79b4ce0b772276292acb817\evidence`。

|套件|实际CHECK|exit|ERROR|Job0|RESULT/结论|
|---|---:|---:|---|---|---|
|`newtests/play_affordance_rule_audit_test`|438|0|`[]`|True|`RESULT play_affordance_rule_audit checks=438 failures=[]`；逻辑通过|
|`tests/climax_gated_ability_test`|11|0|`[]`|True|`RESULT checks=11 failures=[]`；逻辑通过|
|`tests/servant_skill_eight_magic_test`|26|0|`[]`|True|`RESULT checks=26 failures=[]`；逻辑通过|
|`tests/match_finished_authority_test`|29|0|`[]`|True|`RESULT checks=29 failures=[]`；逻辑通过|
|`tests/authority_revision_query_test`|52|0|`[]`|True|`RESULT authority_revision_query checks=52 failures=[]`；逻辑通过|
|`tests/refactor_net_area_diagnostic`|0|0|`[]`|True|`RESULT checks=0 failures=[] window_only=true`；原有headless/window-only跳过，不计通过|
|`scratch/transaction-return-consumers/transaction_return_consumers_test`|61|0|`[]`|True|`RESULT transaction_return_consumers checks=61 failures=[]`；逻辑通过|

通过逻辑套件：6，实际CHECK合计：617；CHECK false=0，SCRIPT ERROR/ERROR=0。所有自有进程exited、ActiveProcesses=0且日志句柄释放；生成树已删除，最小日志/manifest保留。

**验收边界**：区域诊断运行函数在headless主动返回`RESULT checks=0 failures=[] window_only=true`，180行诊断读取未执行；只能确认原位替换的静态语义与导入成功，不冒称窗口诊断验收。总执行器exit 1、manifest.passed=false，原因是这个真实跳过且当前生产依赖发生源漂移；未弱化正整数CHECK门。
冻结副本最终漂移=[]。运行期间外部写者修改`scripts/net/session/lobby_session.gd`；本任务未写该文件。具体测试SHA与当前SHA见receipt.json。因此上述6项是同一冻结版本的真实通过，不宣称当前工作树或发行全绿，也不在热文件持续修改期间重复启动复验。

## Gate owner归属证据

`tools/check_layer_deps.py:25–29`的OWNERS仅：
- `EffectManager` → `scripts/system/global/effect_manager.gd`
- `GameProgress` → `scripts/system/global/game_progress.gd`
- `DummyBot` → `scripts/system/ai/temp/dummy_bot.gd`

`tools/check_layer_deps.py:253–256`的private规则要求接收标识符位于OWNERS，且当前路径非该owner自身，才登记私有访问。此次11条的owner只有BaseCard/NetworkMatchAuthority，均不在上述3个owner路径中；inventory的11条gate_owner也全部false。
**归属数=0/11；此次替换不能减少现有允许清单。** Gate与允许清单未改，未运行全量gate扫描。Gate SHA256：`5dabf762ded90d5e0a6151ba1a50468c14f9029c3f2478ef996c9f6fb6bcf0be`，与执行器冻结前后读回一致。

## 产物

- `before.json`及`before/`：修改前完整11条清单与7个消费者原字节。
- `changes.json`：9处改动、2处未改重分类、完整改前后SHA256与owner集合。
- `migration.patch`：仅本任务6文件9处的精确差异，不包含已有脏树修改。
- `receipt.json`：最终消费者SHA读回、生产公开入口指纹、源漂移与6项通过统计。
- `run_selected.py`：仅E盘、仅指定7场景、600s、OwnedJob的执行器。
- `latest-run.json`及`selected-*/manifest.json/evidence/*.log`：真实执行记录。
