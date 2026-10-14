# A06 / A07 compare 与 A07 负向证据

## 结论

- 已证实：最后测试冻结的 A06 compare 11/11、A07 compare 25/25 全绿；正常 compare 无 golden 差异。
- 已证实：同一冻结中把 AreaActionRules.move_lock_reason 函数体仅改为 return ""，A07 为 exit 1、22 CHECK、两条锁拒绝断言失败；无引擎 ERROR。副本恢复原字节和 SHA 后 A07 compare 再次 25/25 全绿。
- 未证实：测试期间其他并行写入者改变了源码，所以最后测试冻结不等于交付时活体仓库终态；不得据此把整个当前终态或矩阵无条件标成通过。见“源码并行漂移”。
- 未证实：干净冷导入/全量/窗口/真人输入/发行门；本轮仅指定两个 headless golden 专项。
- 未使用 capture，未改任何测试断言、生产仓库或 golden；新建本报告及证据目录。日志中的 godot_ai game_helper “registered mcp capture”是既有运行时插件启动信息，不是 golden capture 分支。

## 环境与冻结

- Godot: 4.7.2.stable.official.ed1daf0bf；仅执行独占 E 盘非 console 引擎副本。
- 源目录：`E:\Projects\Godot\FateDominationGame-master`
- 唯一隔离根：`E:\scratch\isolated-68b556faf22044668ffd2caae802b640`；generated 已在 Job0、日志解锁、证据归档后删除。
- 实际 user:// 主/派生探针落于本 UUID 的 generated/appdata/FateDomination，实读回执、worker exit 0；首轮 probe 证据见 snapshot1。
- 每进程执行器看门狗 600s；本次无执行器超时。原测试自己的 180s 约束/断言保持原字节且均通过。
- 子进程 APPDATA/LOCALAPPDATA/TEMP/TMP/TMPDIR 显式指向 E 盘生成子树；未修改全局环境。PID 17120/28100 未被纳入或操作。
- 副本只有 project.godot 的编辑器设置最小转换：关闭 VCS 自动启动和编辑器 MCP 插件；application/autoload/threading 与测试逻辑未改。原工程 config SHA 与副本转换 SHA 分列于 manifest。
- 源码清单包含 1412 个显式依赖，完整逐文件 SHA 在 evidence/source-before.json 与 manifest.json；非硬链接副本。
- 最后冻结源码 SHA256：`d1b4529f888da521ebbdb8cc44af70411950f1f2ec323b3a8731398e9e3cdc9e`
- 编码：按 path->sha 的字典以 json.dumps(sort_keys=True,separators=(",",":")) 序列化为 UTF-8，再 SHA256。该值标识测试冻结，不是 Git 提交。
- 引擎 SHA256：`ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424`

## 两个原套件与真实命令

### A06-compare

- 原套件：`res://tests/refactor_text_golden_test.tscn`
- 命令：`E:\scratch\isolated-68b556faf22044668ffd2caae802b640\generated\Godot.exe --headless --fixed-fps 60 --path E:\scratch\isolated-68b556faf22044668ffd2caae802b640\generated\project --scene res://tests/refactor_text_golden_test.tscn`
- 结果：PASS；exit=0；CHECK=11；ERROR=0；Job ActiveProcesses=0；日志句柄已释放。
- RESULT：`RESULT refactor_text_golden checks=11 failures=[]`
- 原 stdout/stderr：`evidence/A06-compare.stdout.log` / `evidence/A06-compare.stderr.log`

```text
CHECK fixed-seed seven-seat game starts true
CHECK three complete rounds reached true
CHECK step budget not exhausted true
CHECK round 1 has real logs true
CHECK round 2 has real logs true
CHECK round 3 has real logs true
CHECK card coverage nonempty true
CHECK BUFF coverage nonempty true
CHECK effect coverage nonempty true
CHECK golden is readable JSON object true
CHECK golden matches exactly true
```

### A07-compare

- 原套件：`res://tests/refactor_area_golden_test.tscn`
- 命令：`E:\scratch\isolated-68b556faf22044668ffd2caae802b640\generated\Godot.exe --headless --fixed-fps 60 --path E:\scratch\isolated-68b556faf22044668ffd2caae802b640\generated\project --scene res://tests/refactor_area_golden_test.tscn`
- 结果：PASS；exit=0；CHECK=25；ERROR=0；Job ActiveProcesses=0；日志句柄已释放。
- RESULT：`RESULT checks=25 failures=[]`
- 原 stdout/stderr：`evidence/A07-compare.stdout.log` / `evidence/A07-compare.stderr.log`

```text
CHECK fixed seed seven seat match starts true
CHECK natural complete game reached true
CHECK step guard not exhausted true
CHECK 180 second wall budget respected true
CHECK legal deployments recorded true
CHECK battles recorded true
CHECK natural game_end recorded true
CHECK no game UI instantiated true
CHECK fixture places origin true
CHECK real area_locked declaration loads true
CHECK fixture lock recognized by engine true
CHECK locked target rejection text true
CHECK locked target excludes effect landing true
CHECK passing locked area stays legal true
CHECK fixture places origin true
CHECK real area_locked declaration loads true
CHECK fixture lock recognized by engine true
CHECK locked origin rejection text true
CHECK fixture places origin true
CHECK real area_locked declaration loads true
CHECK fixture lock recognized by engine true
CHECK lock does not forbid deployment true
CHECK captured golden exists true
CHECK golden parses as dictionary true
CHECK baseline equals actual queries:  true
```

### A07-empty-lock-negative

- 原套件：`res://tests/refactor_area_golden_test.tscn`
- 命令：`E:\scratch\isolated-68b556faf22044668ffd2caae802b640\generated\Godot.exe --headless --fixed-fps 60 --path E:\scratch\isolated-68b556faf22044668ffd2caae802b640\generated\project --scene res://tests/refactor_area_golden_test.tscn`
- 结果：RED；exit=1；CHECK=22；ERROR=0；Job ActiveProcesses=0；日志句柄已释放。
- RESULT：`RESULT checks=22 failures=["locked target rejection text", "locked origin rejection text"]`
- 原 stdout/stderr：`evidence/A07-empty-lock-negative.stdout.log` / `evidence/A07-empty-lock-negative.stderr.log`

```text
CHECK fixed seed seven seat match starts true
CHECK natural complete game reached true
CHECK step guard not exhausted true
CHECK 180 second wall budget respected true
CHECK legal deployments recorded true
CHECK battles recorded true
CHECK natural game_end recorded true
CHECK no game UI instantiated true
CHECK fixture places origin true
CHECK real area_locked declaration loads true
CHECK fixture lock recognized by engine true
CHECK locked target rejection text false
CHECK locked target excludes effect landing true
CHECK passing locked area stays legal true
CHECK fixture places origin true
CHECK real area_locked declaration loads true
CHECK fixture lock recognized by engine true
CHECK locked origin rejection text false
CHECK fixture places origin true
CHECK real area_locked declaration loads true
CHECK fixture lock recognized by engine true
CHECK lock does not forbid deployment true
```

### A07-restored-compare

- 原套件：`res://tests/refactor_area_golden_test.tscn`
- 命令：`E:\scratch\isolated-68b556faf22044668ffd2caae802b640\generated\Godot.exe --headless --fixed-fps 60 --path E:\scratch\isolated-68b556faf22044668ffd2caae802b640\generated\project --scene res://tests/refactor_area_golden_test.tscn`
- 结果：PASS；exit=0；CHECK=25；ERROR=0；Job ActiveProcesses=0；日志句柄已释放。
- RESULT：`RESULT checks=25 failures=[]`
- 原 stdout/stderr：`evidence/A07-restored-compare.stdout.log` / `evidence/A07-restored-compare.stderr.log`

```text
CHECK fixed seed seven seat match starts true
CHECK natural complete game reached true
CHECK step guard not exhausted true
CHECK 180 second wall budget respected true
CHECK legal deployments recorded true
CHECK battles recorded true
CHECK natural game_end recorded true
CHECK no game UI instantiated true
CHECK fixture places origin true
CHECK real area_locked declaration loads true
CHECK fixture lock recognized by engine true
CHECK locked target rejection text true
CHECK locked target excludes effect landing true
CHECK passing locked area stays legal true
CHECK fixture places origin true
CHECK real area_locked declaration loads true
CHECK fixture lock recognized by engine true
CHECK locked origin rejection text true
CHECK fixture places origin true
CHECK real area_locked declaration loads true
CHECK fixture lock recognized by engine true
CHECK lock does not forbid deployment true
CHECK captured golden exists true
CHECK golden parses as dictionary true
CHECK baseline equals actual queries:  true
```

## 差异逐项判定

| 情形 | 证据 | 判定 |
|---|---|---|
| A06 正常 compare | `golden matches exactly true`，11 CHECK，exit 0 | 无差异；没有批准差异/夹具漂移/产品缺陷需要归类 |
| A07 正常 compare | `baseline equals actual queries: true`，25 CHECK，exit 0 | 无差异；完整局 steps=272、round=11、game_end=1；548 样本、15344 查询行 |
| A07 负向：锁定目标拒绝文案 | 原 tests/refactor_area_golden_test.gd:99；`CHECK locked target rejection text false` | 副本中故意注入的产品规则缺陷，成功被原断言捕获；不是批准差异，不是夹具漂移，不表示未注入的生产存在缺陷 |
| A07 负向：锁定出发地拒绝文案 | 原 tests/refactor_area_golden_test.gd:105；`CHECK locked origin rejection text false` | 同上；自然终局及真实 area_locked 识别断言仍绿 |

负向运行在 locked_fixtures 后因两条原断言失败提前 finish，未走最终 golden 比较（22 而非 25 CHECK）。这是现有测试的失败关闭路径，并非删断言；负向不冒称产生了完整 GOLDEN_DIFF。stdout 未打印失败值，不推造实际文本值。恢复运行重新执行了完整 golden 比较。

## 注入与恢复字节证明

- 改动唯一位置：副本 `scripts/system/area_action_rules.gd` 的 `static func move_lock_reason(player_id: int, target_area: BaseMapArea) -> String` 函数体；签名、调用方、golden、断言均未改。现有 tactical_board_ui.gd:3151–3152 转发到此函数。
- 注入前 SHA：`409d569acaf4c4ba646ef44bb516878c3f70f4e74b5f7797e7d02a2235adce8a`
- 注入后 SHA：`445ae8d42ad0800083bce2d093420e8120d59870b7a91195c8a12e0b776ab91a`
- 立即 finally 恢复后 SHA：`409d569acaf4c4ba646ef44bb516878c3f70f4e74b5f7797e7d02a2235adce8a`
- 原字节比较：true；恢复副本全部原始输入 SHA 无漂移（project.godot 记录的编辑器设置转换除外）。仓库 area_action_rules.gd 注入前后 SHA 相同。
- 原始函数文件备份：`evidence/area_action_rules.original.gd`。

## golden 与关键源码 SHA256

| 文件 | 测试冻结 SHA256 |
|---|---|
| `tests/refactor_text_golden_test.gd` | `4a7dbdfd40f840c990d2df13b5de6b681c253dda57331f855d8a77c989fbc332` |
| `tests/refactor_text_golden_test.tscn` | `1e4506ffde52e71c214fefbd3fed1c5aacafe2ccde14b2e3b0c2c7b9b580fe6b` |
| `tests/refactor_area_golden_test.gd` | `84d553858a7780e9482552efc8cd2d0f362737f1eadb26d071ae50d68b9daf32` |
| `tests/refactor_area_golden_test.tscn` | `ac53cfb94af3bf1b52033745c34d5863c285ee19ff4e4688f3166c08c9215acb` |
| `docs/refactoring-golden/text.json` | `512b09b07f4f25240ce5f133c304532e16446bc5a589b33b92664f81cbd8953d` |
| `docs/refactoring-golden/areas.json` | `67d07ec5a7a6a2ae5682836cc0119214dfc11d18af1449c47b6977f75db030ac` |
| `scripts/game_scene/tactical_board_ui.gd` | `3063aca824df5c4561cf08588c4e77d14588a3777e48397d33823e5b6a15acda` |
| `scripts/system/area_action_rules.gd` | `409d569acaf4c4ba646ef44bb516878c3f70f4e74b5f7797e7d02a2235adce8a` |
| `scripts/match/match_driver.gd` | `8f76ea384e5ade542a4f3a8f39c8817423f043e305790f01d0596e50e1429307` |
| `scripts/system/global/effect_manager.gd` | `1755ff077e675105844d3d6ec33645bc3f701a48aa1cdf8dc2b11c8a6b5340c1` |
| `scripts/net/ui/v2_view_presenter.gd` | `daa158678c2d7542c65ba4b4390955193186127986e59203fa05c4b735a6f2ca` |
| `project.godot` | `986a066adc6f0d1346d19612538780abaf2ce4d3cdfef4342db653a0b53d8c8a` |

两份 golden 在原仓库和隔离副本的运行后 SHA 均等于运行前 SHA。

## 源码并行漂移

保留三轮独立快照，不拼接为同一冻结通过：snapshot1 首轮后 lobby_session.gd 漂移；snapshot2 重冻结后 effect_manager.gd 漂移；最后冻结含其更新，运行后 v2_view_presenter.gd 又发生并行写入。每轮四个运行的原日志、源码清单、manifest 均保留，全部实际 Job0。

| 路径 | 最后已测试 SHA | 报告生成时活体 SHA |
|---|---|---|
| `scripts/net/session/lobby_session.gd` | `468f9ca5dbaf8215aac0a74e62ed8490792c7737aee3b17687e1d81e09599ed0` | `7a192df75e82ca608c330f4a417b5d19b7e2203911b56d45c4a03994d1bc8cb1` |
| `scripts/net/ui/v2_view_presenter.gd` | `daa158678c2d7542c65ba4b4390955193186127986e59203fa05c4b735a6f2ca` | `81285a188f225449e7bdac8f3f955a8a3c196d83c79152e0888afd98d94d55f6` |

因此“两个指定测试在标明 SHA 的冻结上通过”已证实；“测试后的活体终态也通过”未证实。需要主代理停止相关生产写入后再冻结时，不能把本报告的旧 SHA 冒充该新终态。

## 实际遇到的问题

- 首轮干净冷导入 exit 0 但存在 CursorReplace 三张 PNG preload 的真实 SCRIPT ERROR（autoload 先于图像资源导入）；完整原 ERROR 在 snapshot1/import.stderr.log。此首轮不判干净导入通过。
- 原资源完成真实导入后，同一冻结第二次真实 import exit 0、无 ERROR；最后更新冻结的 import 亦 exit 0、无 ERROR。没有复制 .godot 缓存，没有忽略 ERROR，没有修改 autoload 或测试断言。
- 上述属于本次冷导入准备顺序问题，不是 golden 值差异；本任务的套件 compare / 负向 / 恢复阶段全部无 ERROR。不据暖导入宣称冷启动发行门通过。
- 并行源码漂移已经精确记录，未由本执行器修改、回滚或覆盖仓库文件。

## 完整证据与清理

- 当前：manifest.json、evidence/source-before.json、四次 stdout/stderr、import stdout/stderr、恢复原始函数文件。
- 旧冻结：snapshot1/、snapshot2/；真实主/派生 user:// 探针、首轮冷导入 ERROR 原样保留。
- 执行配方：executor/run.py、resume.py、refreeze.py、finalize.py。
- 所有自有 Job ActiveProcesses=0 后，按 owner run_id/generated/processes 回执与无 reparse-point 扫描删除本 UUID generated；正式仓库、正式存档、其他 scratch 与 protected PID 未作为清理目标。
