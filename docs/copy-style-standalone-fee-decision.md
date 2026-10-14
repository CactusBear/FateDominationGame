# 单独资源名「费用」修改与保留清单

## 结论与范围

按用户「只改游戏内可见文案中单独作为资源名的『费用』，复合词一律不动」执行。剩余 16 处已逐项判定：a 类 1 处修改；b 类 5 处保留；c 类 10 处保留。c 类按非玩家界面优先分类，其中复合词也单列备查。

本轮生产源码只改 `scripts/match/view_builder.gd:407` 一个字面量。既有前缀修改与 `battle_board_v2.tscn:1490` 的资源标签修改未再改动。不改规则、字段、数值、时点键或 golden。未运行 Godot，也未操作任何进程；本次验收为用户指定静态扫描与字节核对，不宣称窗口验收。

## 16 处逐项判定（原文依据）

|类|文件:行|完整原文字符串|判定依据 / 处理|
|---|---|---|---|
|a|`scripts/match/view_builder.gd:407`|`费用`|`public_description` 把单独资源名格式化为 `费用：数值`；同文件 355、379 行写入 `description`，`scripts/game_scene/battle_board_v2.gd:3025,4692` 消费为放大说明。改为 `魔力消耗`。|
|b|`assets/scenes/game_scene/battle_board_v2.tscn:1511`|`悬浮右侧竖条切换主图 · 令咒可代替移动费用`|正式场景 text 属性；「移动费用」是复合词，保留。|
|b|`data/servants/00005_medea/00005_medea.json:31`|`此牌费用为X，X为16-（当前回合数×2）`|`$.specials.SKILLS[0].effects[0].shown_effect_name`；「费用为X」属于用户明确保留的复合表述，公式原样保留。|
|b|`scripts/system/time_points.gd:450`|`卡牌费用计算完成时`|`shown_time_points` 的价格类时点显示名；`scripts/ui/text/game_log_text.gd:78` 有游戏日志消费入口。复合时点名，保留。|
|b|`scripts/system/time_points.gd:451`|`自己卡牌费用计算完成时`|同上；复合时点名，保留。|
|b|`scripts/system/time_points.gd:452`|`他人卡牌费用计算完成时`|同上；复合时点名，保留。|
|c|`assets/scenes/debug/debug_console.tscn:353`|`改卡牌费用`|调试控制台按钮；不属于普通对局玩家文案，保留。亦含「卡牌费用」复合词。|
|c|`scripts/debug/debug_action_panel.gd:171`|`改卡牌费用`|debug 命令 `card.cost` 的 label，保留。亦含「卡牌费用」复合词。|
|c|`scripts/system/global/all_operations.gd:95`|`攻击印刷费用`|operation 注册表 `get_attack_printed_cost` 的 summary；编辑器摘要，保留。亦含「印刷费用」复合词。|
|c|`scripts/system/global/all_operations.gd:97`|`技能印刷费用`|operation 注册表 `get_skill_printed_cost` 的 summary；编辑器摘要，保留。亦含「印刷费用」复合词。|
|c|`scripts/system/global/all_operations.gd:127`|`区域移动费用`|operation 注册表 `get_move_cost` 的 summary；编辑器摘要，保留。亦含「区域移动费用」复合词。|
|c|`scripts/system/global/all_operations.gd:190`|`改卡费用`|operation 注册表 `edit_card_cost` 的 summary；编辑器摘要，保留。亦含「卡费用」复合表述。|
|c|`scripts/system/global/all_operations.gd:200`|`改区域移动费用`|operation 注册表 `edit_map_area_move_cost` 的 summary；编辑器摘要，保留。亦含「区域移动费用」复合词。|
|c|`scripts/system/global/all_operations.gd:224`|`把攻击加入场上(不计费用上限)`|operation 注册表 `add_attack` 的 summary；编辑器摘要，保留。亦含「费用上限」复合词。|
|c|`scripts/system/global/all_operations.gd:228`|`只改位置并返回费用`|operation 注册表 `move_location` 的 summary；非玩家界面，保留。不从技术摘要拆取「费用」改写。|
|c|`json_maker/json_maker_ui.gd:3050`|`固定数字不能再被任何效果更改（例如「费用减一」「威力加倍」都会对它无效）。\n卡面上的数字一般都应当能被更改，除非这张牌写明了这个数字不变。\n\n确定要改成固定数字吗？`|JSON 编辑器 `_confirm_fixed_number` 确认弹窗，保留。亦含用户明确保留的「费用减一」。|

注册表摘要的实际编辑器消费依据：`json_maker/json_maker.gd:1399,1424,1427,1432` 从 `AllOperations.TABLE` 读取 summary，作为编辑器 shown/help。扫描器的「visible」仅为词法展示证据，不能把 debug、编辑器、注册表摘要等同于游戏内玩家可见文案。

## 本轮实际改动与 SHA256

文件与行：`scripts/match/view_builder.gd:407`。

前原文：
```gdscript
			lines.append("%s：%s" % ["费用" if field == "_cost" else "威力", BaseNumber.display_text(value.number)])
```

后原文：
```gdscript
			lines.append("%s：%s" % ["魔力消耗" if field == "_cost" else "威力", BaseNumber.display_text(value.number)])
```

SHA256 是整文件原始字节哈希：
- 修改前：`9a7ed25688ded565bce41b0a8b7473f8067553b55629fbb7d7ce88a276ec831e`
- 修改后：`78607bec727a0698e81370e33e988caa0b41def226a04f5e13bd4b8e6567ca8e`

核对结果：后文件中完整新行恰好出现一次，将该行替回原行后 SHA256 与修改前一致，证明本轮只发生这一处字节替换，既有改动和换行格式未变。`git diff --check -- scripts/match/view_builder.gd` exit 0。相对 HEAD 的 diff 仍含任务开始前的既有改动，不将它们计为本轮改动。

## b 类复合词逐一保留清单

|文件:行|仍保留的含「费用」复合词 / 时点名|原文|
|---|---|---|
|`assets/scenes/game_scene/battle_board_v2.tscn:1511`|`移动费用`|`悬浮右侧竖条切换主图 · 令咒可代替移动费用`|
|`data/servants/00005_medea/00005_medea.json:31`|`费用为X`|`此牌费用为X，X为16-（当前回合数×2）`|
|`scripts/system/time_points.gd:450`|`卡牌费用计算完成时`|`卡牌费用计算完成时`|
|`scripts/system/time_points.gd:451`|`自己卡牌费用计算完成时`|`自己卡牌费用计算完成时`|
|`scripts/system/time_points.gd:452`|`他人卡牌费用计算完成时`|`他人卡牌费用计算完成时`|

以下属于 c 类，不计入上述 b 类 5 处；为避免复合词被遗漏，另列供用户日后决定：

|文件:行|仍保留的含「费用」词形 / 表述|
|---|---|
|`assets/scenes/debug/debug_console.tscn:353`|`改卡牌费用`|
|`scripts/debug/debug_action_panel.gd:171`|`改卡牌费用`|
|`scripts/system/global/all_operations.gd:95`|`攻击印刷费用`|
|`scripts/system/global/all_operations.gd:97`|`技能印刷费用`|
|`scripts/system/global/all_operations.gd:127`|`区域移动费用`|
|`scripts/system/global/all_operations.gd:190`|`改卡费用`|
|`scripts/system/global/all_operations.gd:200`|`改区域移动费用`|
|`scripts/system/global/all_operations.gd:224`|`费用上限`（完整原文见分类表）|
|`scripts/system/global/all_operations.gd:228`|`返回费用`（完整原文见分类表）|
|`json_maker/json_maker_ui.gd:3050`|`费用减一`（完整原文见分类表）|

## 真实扫描命令、退出码与计数

仓库工作目录：`E:/Projects/Godot/FateDominationGame-master`。执行环境 TMPDIR/TEMP/TMP 均指向 `E:/Projects/Godot/FateDominationGame-master/scratch/copy-style-standalone-fee`；工具看门狗 600 秒。

```bash
python -B tools/scan_visible_copy_style.py --root . --output docs/copy-style-static-scan.json --report docs/copy-style-static-scan.md --top 5 --overwrite
```

真实 exit：**0**。生成 JSON 已读回核对。

|指标|改前|改后|
|---|---:|---:|
|扫描文件|521|521|
|中文条目|4624|4624|
|确认词法违例|0|0|
|人工复核规则命中|17|16|
|人工复核 R1|1|1|
|人工复核 R4|16|15|
|费用/降费字符串条目|16|15|
|扫描器 visible_fee_mentions|16|15|
|不在本口径处理的命中|124|124|
|R2 括号 / R3 量词|61 / 63|61 / 63|
|读取/解析错误|0|0|

扫描器源码未修改。它仍把 debug/编辑器摘要计为词法可见，且生成报告仍包含旧的复合词候选建议和固定 APPLIED_CHANGES；这些不是本次执行授权，也不是本次完整改动清单。本文件的逐项分类与字节哈希是本次实际执行凭据。不为减少扫描计数修改复合词或非玩家文本。

## 保留项核验

基线：`scratch/copy-style-standalone-fee/baseline.json`。已程序核对：改后 15 个含「费用」条目的文件、行号、完整原文与基线完全一致；除本次改动所在文件外，其余 7 个命中文件整文件 SHA256 保持一致。

|未改文件|SHA256|
|---|---|
|`assets/scenes/debug/debug_console.tscn`|`552e4d3cc0b539f5fbc7437593c1be0c7d9af0c6e6223caa326172c450997339`|
|`assets/scenes/game_scene/battle_board_v2.tscn`|`819c08a3db6a88c943849d328dbd0e2bfca0c51bdac9c71f910c89e2451bf512`|
|`data/servants/00005_medea/00005_medea.json`|`8a5faf63375d904ed2ff717854364930687ac4e8dacef54a38be96706e6eecbf`|
|`json_maker/json_maker_ui.gd`|`78b55d217cdced1c95d79f55cad7b2ce55e07b9532053b2bef7035afd2d1d849`|
|`scripts/debug/debug_action_panel.gd`|`881c7be32fea6c24f429812e2bbaca38f53ee80c90bf80bd8f14067970a67c65`|
|`scripts/system/global/all_operations.gd`|`8f39c2dfa98a2989a79040fba436d69bc93c8e6c93a86e7f3664e0f44fbd775a`|
|`scripts/system/time_points.gd`|`4d0efceb07141424d3288f8fc4c643c38cf1814e76f205603e15786d6a26c406`|

扫描产物 SHA256：
- `docs/copy-style-static-scan.json`：`85642cd83ff1e7e83d088479ebc0a26338dd1ebe74b44325d02d7c94c3d610f9`
- `docs/copy-style-static-scan.md`：`b4ae0e6bd667bf001bd8713bf380384ed0654c8deff671982e5ad7542f253b5e`
- 未改扫描器 `tools/scan_visible_copy_style.py`：`bf704c5e02aee582b73d620361c970bbf719621ce5e97f4324f6b50c2e61e4e1`

本轮新建分类交付文档与 E 盘 scratch 基线，覆盖重生成指定两份扫描报告；未提交、未回滚其他工作树改动。
