# 用户可见文案静态扫描报告

## 交付与运行

- 脚本：`tools/scan_visible_copy_style.py`
- SHA256：`bf704c5e02aee582b73d620361c970bbf719621ce5e97f4324f6b50c2e61e4e1`
- 命令：`python -B tools/scan_visible_copy_style.py --root . --output docs/copy-style-static-scan.json --report docs/copy-style-static-scan.md --top 5 --overwrite`
- 扫描退出码：`0`
- 源文件清单 SHA256：`32fee4a665029f9e14e66ddf6e0f47efba7a3701b39956093110063daea1dd82`
- 详细数据：与本报告同次生成的 JSON，含每项原文、源码字面量、行/列/键路径、匹配证据与源文件 SHA256。

## 实际统计

- 扫描文本文件 521；中文文本条目 4624。
- 确认词法违例 0 项规则命中，涉及 0 个文本条目 / 0 个文件。
- “本口径不处理” 124 项规则命中（R2 括号 61、R3 量词 63），不计违例、不影响退出码。
- 需人工确认 16 项；读取/解析错误 0。

|规则|判定口径|确认违例|需人工确认|本口径不处理|
|---|---|---:|---:|---:|
|R1|描述行带效果前缀|0|1|0|
|R2|括号补充文字（本口径不处理）|0|0|61|
|R3|数值或数量词后带点/层/画/枚/个（本口径不处理）|0|0|63|
|R4|资源标签费用未使用魔力消耗|0|15|0|

同一文本命中多条规则分别计数；同一文本同一规则重复命中只计一次。扫描所有版本和旧界面，不按运行入口删减。

## 本轮实际修正

|文件:行 / 键路径|前原文|后原文|
|---|---|---|
|`assets/scenes/game_scene/tactical_board_ui.tscn:1644` / `metadata/event_desc`|"深山町明置事件牌\\n\\n效果：本战场所有英灵进行光荣的正面对决，力量属性攻击的威力 +2。"|"深山町明置事件牌\\n\\n本战场所有英灵进行光荣的正面对决，力量属性攻击的威力 +2。"|
|`assets/scenes/game_scene/battle_board_v2.tscn:1490` / `text`|"移动路线 · 费用"|"移动路线 · 魔力消耗"|

## 用户可见费用/降费位置

- 扫描器按显式展示证据确认 15 项；扫描范围内共提取含“费用/降费”的字符串条目 15 项。
- 下表逐一列出扫描器确认可见的位置；后表列出同词但当前词法规则未能确认可见的候选，避免把间接 UI 数据流误报为已确认可见。

|文件:行:列 / 键路径|原文|可见性依据|
|---|---|---|
|`assets/scenes/debug/debug_console.tscn:353:8` / `text`|"改卡牌费用"|场景展示属性:text|
|`assets/scenes/game_scene/battle_board_v2.tscn:1511:8` / `text`|"悬浮右侧竖条切换主图 · 令咒可代替移动费用"|场景展示属性:text|
|`data/servants/00005_medea/00005_medea.json:31:34` / `$.specials.SKILLS[0].effects[0].shown_effect_name`|"此牌费用为X，X为16-（当前回合数×2）"|JSON展示字段:shown_effect_name|
|`json_maker/json_maker_ui.gd:3050:3` / `_confirm_fixed_number`|"固定数字不能再被任何效果更改（例如「费用减一」「威力加倍」都会对它无效）。\n卡面上的数字一般都应当能被更改，除非这张牌写明了这个数字不变。\n\n确定要改成固定数字吗？"|UI间接输出证据:_confirm_fixed_number|
|`scripts/debug/debug_action_panel.gd:171:32` / `<top-level>`|"改卡牌费用"|UI间接输出证据:<top-level>|
|`scripts/system/global/all_operations.gd:95:100` / `<top-level>`|"攻击印刷费用"|UI间接输出证据:<top-level>|
|`scripts/system/global/all_operations.gd:97:98` / `<top-level>`|"技能印刷费用"|UI间接输出证据:<top-level>|
|`scripts/system/global/all_operations.gd:127:80` / `<top-level>`|"区域移动费用"|UI间接输出证据:<top-level>|
|`scripts/system/global/all_operations.gd:190:82` / `<top-level>`|"改卡费用"|UI间接输出证据:<top-level>|
|`scripts/system/global/all_operations.gd:200:97` / `<top-level>`|"改区域移动费用"|UI间接输出证据:<top-level>|
|`scripts/system/global/all_operations.gd:224:72` / `<top-level>`|"把攻击加入场上(不计费用上限)"|UI间接输出证据:<top-level>|
|`scripts/system/global/all_operations.gd:228:78` / `<top-level>`|"只改位置并返回费用"|UI间接输出证据:<top-level>|
|`scripts/system/time_points.gd:450:25` / `<top-level>`|"卡牌费用计算完成时"|UI间接输出证据:<top-level>|
|`scripts/system/time_points.gd:451:30` / `<top-level>`|"自己卡牌费用计算完成时"|UI间接输出证据:<top-level>|
|`scripts/system/time_points.gd:452:32` / `<top-level>`|"他人卡牌费用计算完成时"|UI间接输出证据:<top-level>|

### 同词但未由词法证实可见

|文件:行:列 / 键路径|原文|当前证据|
|---|---|---|
|无|—|—|

### 复合词候选（仅交 main 定，不自动修改）

|现有词形|最小一致候选|理由|
|---|---|---|
|费用|魔力消耗|Q06 已确认的统一词；不改变数值。|
|卡牌费用|卡牌魔力消耗|仅替换“费用”子串，保留“卡牌”修饰与原语义。|
|移动费用|移动魔力消耗|仅替换“费用”子串，保留移动语义；是否改成“移动所需魔力”交 main。|
|费用为X|魔力消耗为X|仅替换资源名，保留 X 与公式结构。|
|费用减一|魔力消耗减一|仅替换资源名，保留减一数值；是否采用更自然的“魔力消耗减少1点”交 main。|
|印刷费用|印刷魔力消耗|仅替换“费用”子串，保留印刷值语义。|
|区域移动费用|区域移动魔力消耗|仅替换“费用”子串，保留区域移动限定。|
|费用上限|魔力消耗上限|仅替换资源名，保留上限语义。|
|返回费用|返回魔力消耗|仅替换资源名，保留返回值语义。|
|费用计算完成时|魔力消耗计算完成时|仅替换资源名，保留时点语义。|
|降费|减少魔力消耗|源码当前无“降费”字面；这是待 main 选择的复合词候选，不自动套用。|

## Top 样本

Top 是按文件/行/规则排序每条规则取前 5 项，不是风险评级。

### R1

|文件:行:列 / 键路径|原文|命中片段|
|---|---|---|
|无|—|—|

### R2

|文件:行:列 / 键路径|原文|命中片段|
|---|---|---|
|无|—|—|

### R3

|文件:行:列 / 键路径|原文|命中片段|
|---|---|---|
|无|—|—|

### R4

|文件:行:列 / 键路径|原文|命中片段|
|---|---|---|
|无|—|—|

## 待澄清与覆盖边界

- 规则①仅判断行首“效果：/效果:”。是否要求“附加效果：”“残留效果：”等也禁止，需要明确；不从分号、句号猜多个效果或强制分行。
- 规则②括号按 Q06 标为“本口径不处理”：仍记录命中位置，但不计违例、不修改、不影响退出码。
- 规则③量词按 Q06 标为“本口径不处理”：仍记录命中位置，但不计违例、不修改、不影响退出码。
- 规则④资源标签以及正文费用统一词待按 Q06 执行；本轮只自动确认并修正明确命中的资源标签，其余“费用/降费”位置与复合词候选单列交 main。
- 规则⑤按本次要求不验收。没有卡图OCR、逐项卡面比对或Godot执行，因此不证明卡面信息与UI描述对应完备。
- JSON展示字段采用显式字段名单与shown_前缀；名称/真名仅人工确认。未知字段若命中规则仍列人工确认，不静默丢弃。
- GDScript使用词法字符串提取、明确展示赋值/调用、已验证的event_desc/zoom_desc/zoom_hint说明元数据及scripts/ui/text返回/输出映射；其他命中列人工确认。不做跨函数数据流、运行时字符串拼接/翻译与动态数值求值；多行输出调用和间接变量绑定可能留在人工确认。
- 扫描data/assets全部JSON、场景、资源、文本及scripts/json_maker所有GDScript；图片、字体、音视频、配置、导入产物等不解析，跳过统计在JSON。普通文件按UTF-8读取，不跟随文件符号链接。
- 扫描只读取生产文件；仅按显式参数新建docs报告，不修改任何原文，不调用Godot、不操作进程。工作树原有改动不回滚。

## 完整命中清单

|类别|规则|文件:行:列 / 键路径|原文|判定依据|
|---|---|---|---|---|
|需人工确认|R4|`assets/scenes/debug/debug_console.tscn:353:8` / `text`|"改卡牌费用"|正文/操作文字/非魔力资源费用，非明确魔力标签；需确认替换口径；场景展示属性:text|
|需人工确认|R4|`assets/scenes/game_scene/battle_board_v2.tscn:1511:8` / `text`|"悬浮右侧竖条切换主图 · 令咒可代替移动费用"|正文/操作文字/非魔力资源费用，非明确魔力标签；需确认替换口径；场景展示属性:text|
|本口径不处理|R2|`assets/scenes/game_scene/tactical_board_ui.tscn:440:8` / `text`|"顺位流转 (首家 ➔ 末家)"|本口径不处理；场景展示属性:text|
|本口径不处理|R2|`assets/scenes/game_scene/tactical_board_ui.tscn:873:8` / `text`|"🥉 士郎 (你)"|本口径不处理；场景展示属性:text|
|本口径不处理|R2|`assets/scenes/game_scene/tactical_board_ui.tscn:1193:8` / `text`|"⚔️ 深山町已打出牌 (威力: 8)"|本口径不处理；场景展示属性:text|
|本口径不处理|R2|`assets/scenes/game_scene/tactical_board_ui.tscn:2091:8` / `text`|"御主卡 (士郎)"|本口径不处理；场景展示属性:text|
|本口径不处理|R2|`assets/scenes/game_scene/tactical_board_ui.tscn:2157:8` / `text`|"⚔️ 出牌区 (深山町)"|本口径不处理；场景展示属性:text|
|本口径不处理|R2|`assets/scenes/game_scene/tactical_board_ui.tscn:2201:8` / `text`|"力量3 (常规)"|本口径不处理；场景展示属性:text|
|本口径不处理|R2|`assets/scenes/game_scene/tactical_board_ui.tscn:2219:8` / `text`|"敏捷3 (常规)"|本口径不处理；场景展示属性:text|
|本口径不处理|R2|`assets/scenes/game_scene/tactical_board_ui.tscn:2237:8` / `text`|"幸运4 (追加)"|本口径不处理；场景展示属性:text|
|本口径不处理|R2|`assets/scenes/game_scene/tactical_board_ui.tscn:2244:8` / `text`|"常规2张 + 幸运追加 (已计入深山町地利+3)"|本口径不处理；场景展示属性:text|
|本口径不处理|R2|`assets/scenes/game_scene/tactical_board_ui.tscn:2407:8` / `text`|"牌库 (7)"|本口径不处理；场景展示属性:text|
|本口径不处理|R2|`assets/scenes/game_scene/tactical_board_ui.tscn:2425:8` / `text`|"弃牌 (2)"|本口径不处理；场景展示属性:text|
|本口径不处理|R3|`assets/scenes/main_menu/multiplayer_lobby.tscn:268:20` / `placeholder_text`|"辅助连接地址，多个地址用逗号分隔"|本口径不处理；场景展示属性:placeholder_text|
|本口径不处理|R3|`data/attacks/basic/preparation/preparation.json:81:25` / `$.effects[1].shown_effect_name`|"战斗阶段：若你赢得战斗，获得2点战果。"|本口径不处理；JSON展示字段:shown_effect_name|
|本口径不处理|R3|`data/events/origin/contain_third_party/contain_third_party.json:87:25` / `$.effects[1].shown_effect_name`|"此战场胜者可恢复1枚令咒"|本口径不处理；JSON展示字段:shown_effect_name|
|本口径不处理|R3|`data/events/origin/contain_third_party/contain_third_party.json:133:7` / `$.effects[1].funcs[3].parameters[2]`|"恢复1枚令咒"|本口径不处理；JSON未声明展示用途:parameters|
|本口径不处理|R3|`data/events/origin/ley_line/ley_line.json:13:25` / `$.effects[0].shown_effect_name`|"位于此战场的玩家在此战场发生战斗后获得2点魔力"|本口径不处理；JSON展示字段:shown_effect_name|
|本口径不处理|R3|`data/masters/00001_emiya_shirou/00001_emiya_shirou.json:122:6` / `$.specials.SKILLS[0].shown_notes[0]`|"你的魔力需要达到8点才能打出此牌"|本口径不处理；JSON展示字段:shown_notes|
|本口径不处理|R3|`data/masters/00002_tohsaka_rin/00002_tohsaka_rin.json:10:25` / `$.effects[0].shown_effect_name`|"宝石魔术·聚宝 - 游戏开始时，你获得10枚【宝石】"|本口径不处理；JSON展示字段:shown_effect_name|
|本口径不处理|R3|`data/masters/00002_tohsaka_rin/00002_tohsaka_rin.json:96:25` / `$.effects[1].shown_effect_name`|"绝对服从的命令 - 你必须于第一回合使用一枚令咒。否则于该回合结束失去一枚令咒。"|本口径不处理；JSON展示字段:shown_effect_name|
|本口径不处理|R3|`data/masters/00002_tohsaka_rin/00002_tohsaka_rin.json:245:25` / `$.effects[2].shown_effect_name`|"绝对服从的命令 - 若你以该令咒获得了魔力，战斗阶段结束后，你失去4点魔力"|本口径不处理；JSON展示字段:shown_effect_name|
|本口径不处理|R3|`data/masters/00002_tohsaka_rin/00002_tohsaka_rin.json:437:26` / `$.specials.BUFFS[0].effects[0].options[0].shown_option_name`|"获得1点魔力"|本口径不处理；JSON展示字段:shown_option_name|
|本口径不处理|R3|`data/masters/00002_tohsaka_rin/00002_tohsaka_rin.json:799:25` / `$.specials.BUFFS[0].effects[1].shown_effect_name`|"高潮回合的行动阶段：可以选择相同的选项，每个选项至多3次，共计9次"|本口径不处理；JSON展示字段:shown_effect_name|
|本口径不处理|R3|`data/masters/00002_tohsaka_rin/00002_tohsaka_rin.json:814:26` / `$.specials.BUFFS[0].effects[1].options[0].shown_option_name`|"获得1点魔力"|本口径不处理；JSON展示字段:shown_option_name|
|本口径不处理|R3|`data/masters/00003_matou_shinji/00003_matou_shinji.json:10:28` / `$.effects[0].shown_effect_name`|"吸魔命令 - 进入深山町时，获得1点魔力"|本口径不处理；JSON展示字段:shown_effect_name|
|本口径不处理|R3|`data/masters/00003_matou_shinji/00003_matou_shinji.json:135:28` / `$.effects[2].shown_effect_name`|"小丑 - 当你战败时，失去一枚令咒"|本口径不处理；JSON展示字段:shown_effect_name|
|本口径不处理|R3|`data/masters/00003_matou_shinji/00003_matou_shinji.json:481:34` / `$.specials.BUFFS[0].effects[1].shown_effect_name`|"契约再续 - 间桐樱在场时，当你第一次失去所有令咒，该回合结束时将从者替换为一个随机的、未被使用的从者，重新获得3令咒"|本口径不处理；JSON展示字段:shown_effect_name|
|本口径不处理|R3|`data/masters/00003_matou_shinji/00003_matou_shinji.json:1226:32` / `$.upgrade_skill[0].effects[2].shown_effect_name`|"若莎士比亚并非你的第一名从者，你获得8点战果"|本口径不处理；JSON展示字段:shown_effect_name|
|本口径不处理|R3|`data/masters/00004_matou_sakura/00004_matou_sakura.json:514:25` / `$.specials.BUFFS[0].effects[0].shown_effect_name`|"黑泥 - 准备阶段：花费2点魔力，若你未激活【被污染的圣杯】，获得2点战果"|本口径不处理；JSON展示字段:shown_effect_name|
|本口径不处理|R2|`data/masters/00004_matou_sakura/00004_matou_sakura.json:615:25` / `$.specials.BUFFS[1].effects[0].shown_effect_name`|"你拥有无限魔力（此状态下无法获得或失去魔力）"|本口径不处理；JSON展示字段:shown_effect_name|
|本口径不处理|R3|`data/masters/00005_illyasviel_von_einzbern/00005_illyasviel_von_einzbern.json:249:25` / `$.effects[3].shown_effect_name`|"小圣杯 - 回合结束时，若你本回合打出的攻击均为暗置，获得1点魔力"|本口径不处理；JSON展示字段:shown_effect_name|
|本口径不处理|R3|`data/masters/00005_illyasviel_von_einzbern/00005_illyasviel_von_einzbern.json:343:25` / `$.specials.BUFFS[0].effects[0].shown_effect_name`|"归于虚无 - 回合开始时，若你上回合在战斗阶段时与至少一名被淘汰的玩家位于同一战场，获得2点战果"|本口径不处理；JSON展示字段:shown_effect_name|
|本口径不处理|R2|`data/masters/00006_kotomine_kirei/00006_kotomine_kirei.json:10:25` / `$.effects[0].shown_effect_name`|"两幅面孔 - 当从者真名隐藏时，你是【监督者】；其他情况下，你是【执行者】（包括且不限于你没有从者）"|本口径不处理；JSON展示字段:shown_effect_name|
|本口径不处理|R3|`data/masters/00007_kuzuki_souichirou/00007_kuzuki_souichirou.json:208:25` / `$.effects[3].shown_effect_name`|"局外人 - 每回合战斗阶段结束后，若你于该回合未获得战果，获得1点战果，若你同时是位于魔术工房的唯一玩家，改为获得2点战果"|本口径不处理；JSON展示字段:shown_effect_name|
|本口径不处理|R3|`data/masters/00007_kuzuki_souichirou/00007_kuzuki_souichirou.json:549:26` / `$.upgrade_skill[0].effects[2].shown_effect_name`|"你的【蛇】获得以下效果 - 被动/战斗阶段：花费6点魔力，将此牌加入你的攻击中"|本口径不处理；JSON展示字段:shown_effect_name|
|本口径不处理|R3|`data/masters/00007_kuzuki_souichirou/00007_kuzuki_souichirou.json:648:28` / `$.upgrade_skill[0].effects[2].funcs[6].parameters[0][3].parameters[0].shown_effect_name`|"被动/战斗阶段：花费6点魔力，将此牌加入你的攻击中"|本口径不处理；JSON展示字段:shown_effect_name|
|本口径不处理|R3|`data/servants/00001_artoria_pendragon/00001_artoria_pendragon.json:31:28` / `$.specials.SKILLS[0].effects[0].shown_effect_name`|"宝具绽放 - 被动/战斗阶段：若你于本回合打出了你战斗中魔力消耗最高的宝具攻击，获得1点战果。若其消耗≥4，你额外获得1点战果"|本口径不处理；JSON展示字段:shown_effect_name|
|本口径不处理|R3|`data/servants/00001_artoria_pendragon/00001_artoria_pendragon.json:58:30` / `$.specials.SKILLS[0].effects[0].options[0].shown_option_name`|"宝具绽放 - 被动/战斗阶段：若你于本回合打出了你战斗中魔力消耗最高的宝具攻击，获得1点战果。若其消耗≥4，你额外获得1点战果"|本口径不处理；JSON展示字段:shown_option_name|
|本口径不处理|R2|`data/servants/00003_cu_chulainn/00003_cu_chulainn.json:46:26` / `$.specials.SKILLS[0].effects[0].options[0].shown_option_name`|"移动至任意地点（魔术工房除外）"|本口径不处理；JSON展示字段:shown_option_name|
|本口径不处理|R3|`data/servants/00003_cu_chulainn/00003_cu_chulainn.json:111:25` / `$.specials.SKILLS[1].effects[0].shown_effect_name`|"【真名解放】战斗阶段：战斗阶段结束后，每与一名对手进行了战斗便获得1点战果。若你获得胜利，每名交战对手失去该数量的战果"|本口径不处理；JSON展示字段:shown_effect_name|
|本口径不处理|R2|`data/servants/00003_cu_chulainn/00003_cu_chulainn.json:319:25` / `$.specials.SKILLS[2].effects[0].shown_effect_name`|"【真名解放】打出时：此牌+2魔力消耗（可叠加）直至游戏结束"|本口径不处理；JSON展示字段:shown_effect_name|
|本口径不处理|R3|`data/servants/00004_medusa/00004_medusa.json:211:34` / `$.specials.SKILLS[1].effects[0].shown_effect_name`|"【真名解放】行动阶段：移动到任一地点，若为战场，重新部署于该地点的2个地利，原地利的占领者失去该地利"|本口径不处理；JSON展示字段:shown_effect_name|
|本口径不处理|R2|`data/servants/00005_medea/00005_medea.json:31:34` / `$.specials.SKILLS[0].effects[0].shown_effect_name`|"此牌费用为X，X为16-（当前回合数×2）"|本口径不处理；JSON展示字段:shown_effect_name|
|需人工确认|R4|`data/servants/00005_medea/00005_medea.json:31:34` / `$.specials.SKILLS[0].effects[0].shown_effect_name`|"此牌费用为X，X为16-（当前回合数×2）"|正文/操作文字/非魔力资源费用，非明确魔力标签；需确认替换口径；JSON展示字段:shown_effect_name|
|本口径不处理|R3|`data/servants/00005_medea/00005_medea.json:105:34` / `$.specials.SKILLS[0].effects[1].shown_effect_name`|"残留：当你部署于魔术工房时，获得1点魔力和2点战果"|本口径不处理；JSON展示字段:shown_effect_name|
|本口径不处理|R3|`data/servants/00005_medea/00005_medea.json:207:34` / `$.specials.SKILLS[1].effects[0].shown_effect_name`|"【真名解放】<每局游戏限一次>行动阶段：你所在战场的一名玩家失去一枚令咒，若其原本只有一枚或更少的令咒，令其【败北】。若其原本没有令咒，你总威力+10"|本口径不处理；JSON展示字段:shown_effect_name|
|本口径不处理|R3|`data/servants/00005_medea/00005_medea.json:238:38` / `$.specials.SKILLS[1].effects[0].options[0].shown_option_name`|"【真名解放】，令一名同战场玩家失去一枚令咒"|本口径不处理；JSON展示字段:shown_option_name|
|本口径不处理|R3|`data/servants/00006_sasaki_kojirou/00006_sasaki_kojirou.json:31:28` / `$.specials.SKILLS[0].effects[0].shown_effect_name`|"你拥有的魔力少于8点也可打出此牌"|本口径不处理；JSON展示字段:shown_effect_name|
|本口径不处理|R3|`data/servants/00006_sasaki_kojirou/00006_sasaki_kojirou.json:155:28` / `$.specials.SKILLS[0].effects[2].shown_effect_name`|"若如此，获得2点魔力且关闭一名交战玩家至多一张基础攻击。"|本口径不处理；JSON展示字段:shown_effect_name|
|本口径不处理|R2|`data/servants/00006_sasaki_kojirou/00006_sasaki_kojirou.json:347:28` / `$.specials.SKILLS[1].effects[0].shown_effect_name`|"行动阶段：与你位于同一战场的对手无法使用【行动阶段】和【战斗阶段】能力（令咒为行动阶段能力）"|本口径不处理；JSON展示字段:shown_effect_name|
|本口径不处理|R2|`data/servants/00006_sasaki_kojirou/00006_sasaki_kojirou.json:362:30` / `$.specials.SKILLS[1].effects[0].options[0].shown_option_name`|"行动阶段：与你位于同一战场的对手无法使用【行动阶段】和【战斗阶段】能力（令咒为行动阶段能力）"|本口径不处理；JSON展示字段:shown_option_name|
|本口径不处理|R3|`data/servants/00007_heracles/00007_heracles.json:32:34` / `$.specials.SKILLS[0].effects[0].shown_effect_name`|"【真名解放】若你战败，获得3点战果并令此战斗的所有胜者分别失去3点战果，然后将此牌移除游戏并令你的其他【十二试炼】获得+3威力直至游戏结束"|本口径不处理；JSON展示字段:shown_effect_name|
|本口径不处理|R3|`data/servants/00007_heracles/00007_heracles.json:330:34` / `$.specials.SKILLS[1].effects[0].shown_effect_name`|"【真名解放】若你战败，获得3点战果并令此战斗的所有胜者分别失去3点战果，然后将此牌移除游戏并令你的其他【十二试炼】获得+3威力直至游戏结束"|本口径不处理；JSON展示字段:shown_effect_name|
|本口径不处理|R3|`data/servants/00007_heracles/00007_heracles.json:628:34` / `$.specials.SKILLS[2].effects[0].shown_effect_name`|"【真名解放】若你战败，获得3点战果并令此战斗的所有胜者分别失去3点战果，然后将此牌移除游戏并令你的其他【十二试炼】获得+3威力直至游戏结束"|本口径不处理；JSON展示字段:shown_effect_name|
|本口径不处理|R3|`data/servants/00008_angra_mainyu/00008_angra_mainyu.json:47:34` / `$.specials.SKILLS[0].effects[0].shown_effect_name`|"你拥有的魔力少于8点也可使用此牌。\n行动阶段：若你位于的战场存在对手，抽2张牌。若你独自位于一处战场，获得4点魔力。"|本口径不处理；JSON展示字段:shown_effect_name|
|本口径不处理|R2|`data/servants/00008_angra_mainyu/00008_angra_mainyu.json:547:34` / `$.specials.SKILLS[2].effects[0].shown_effect_name`|"【真名解放】\n行动阶段：战斗阶段结束后弃置自己4张牌（若不足4张，则手牌全部弃置）。若你战败，每弃置一张【复仇者】，你便可偷取一名击败你的胜利者2点战果。"|本口径不处理；JSON展示字段:shown_effect_name|
|本口径不处理|R3|`data/servants/00008_angra_mainyu/00008_angra_mainyu.json:547:34` / `$.specials.SKILLS[2].effects[0].shown_effect_name`|"【真名解放】\n行动阶段：战斗阶段结束后弃置自己4张牌（若不足4张，则手牌全部弃置）。若你战败，每弃置一张【复仇者】，你便可偷取一名击败你的胜利者2点战果。"|本口径不处理；JSON展示字段:shown_effect_name|
|本口径不处理|R3|`json_maker/json_maker_ui.gd:246:73` / `_set_palette_section`|"取值：算出一个值，供其他积木引用。"|本口径不处理；UI输出入口:_set_palette_section|
|本口径不处理|R3|`json_maker/json_maker_ui.gd:410:11` / `_palette_text`|"当前这一项 循环 每一个"|本口径不处理；脚本字面量，未证明可见:_palette_text|
|本口径不处理|R2|`json_maker/json_maker_ui.gd:849:18` / `_paint_card`|"恢复教程前原稿（包括未保存修改）"|本口径不处理；UI输出入口:_paint_card|
|本口径不处理|R2|`json_maker/json_maker_ui.gd:949:16` / `_field_row`|"（跟随自动发动）"|本口径不处理；UI输出入口:_field_row|
|本口径不处理|R3|`json_maker/json_maker_ui.gd:1073:36` / `_time_points_editor`|"＋ 加一个时机"|本口径不处理；脚本字面量，未证明可见:_time_points_editor|
|本口径不处理|R3|`json_maker/json_maker_ui.gd:1371:14` / `_paint_sub_list`|"删掉这一个"|本口径不处理；UI输出入口:_paint_sub_list|
|本口径不处理|R3|`json_maker/json_maker_ui.gd:1379:13` / `_paint_sub_list`|"＋ 加一个"|本口径不处理；UI输出入口:_paint_sub_list|
|本口径不处理|R2|`json_maker/json_maker_ui.gd:1460:45` / `_redraw_deck_picker`|" 张（可重复）。旧引用保持原样；新选牌按内部名精确引用。"|本口径不处理；UI输出入口:_redraw_deck_picker|
|本口径不处理|R2|`json_maker/json_maker_ui.gd:1515:30` / `_paint_scripts`|"这张牌还没有效果。点上面的按钮加一条，然后从左边拖积木进来。子牌（技能牌、状态、附带物……）的效果在左边「子牌」里点那张牌再编辑。"|本口径不处理；UI输出入口:_paint_scripts|
|本口径不处理|R2|`json_maker/json_maker_ui.gd:1670:30` / `_hat_block`|"（还没选时机）"|本口径不处理；脚本字面量，未证明可见:_hat_block|
|本口径不处理|R3|`json_maker/json_maker_ui.gd:1673:23` / `_hat_block`|"效果从这里开始。选一个或多个时机，时机到了就往下做积木。\n\n• 默认满足任意一个时机就触发；在「发动方式与限制」里勾「时机要全部同时成立」就变成都要满足。\n• 「自己……」是轮到自己时，「他人……」是轮到别人时。"|本口径不处理；UI输出入口:_hat_block|
|本口径不处理|R3|`json_maker/json_maker_ui.gd:1927:13` / `_options_view`|"＋ 再加一个选项"|本口径不处理；UI输出入口:_options_view|
|本口径不处理|R3|`json_maker/json_maker_ui.gd:2213:13` / `_option_mouths`|"＋ 再加一个选项"|本口径不处理；UI输出入口:_option_mouths|
|本口径不处理|R2|`json_maker/json_maker_ui.gd:2288:29` / `_render_raw`|"看不懂的一步（原样保留）"|本口径不处理；脚本字面量，未证明可见:_render_raw|
|本口径不处理|R2|`json_maker/json_maker_ui.gd:2495:27` / `_slot_widget`|"（一串积木）"|本口径不处理；脚本字面量，未证明可见:_slot_widget|
|本口径不处理|R3|`json_maker/json_maker_ui.gd:2604:23` / `_literal_editor`|"填一个数字。它会记成这条效果的数字，别的效果可以改它；也可以把算数字的积木拖进来，或点 ▾ 选。"|本口径不处理；UI输出入口:_literal_editor|
|本口径不处理|R3|`json_maker/json_maker_ui.gd:2614:22` / `_literal_editor`|"空着就用默认值。点一下填一个数字。"|本口径不处理；UI输出入口:_literal_editor|
|本口径不处理|R3|`json_maker/json_maker_ui.gd:2730:83` / `_slot_groups`|"记成这条效果的一个数字，别的效果可以改它"|本口径不处理；脚本字面量，未证明可见:_slot_groups|
|本口径不处理|R2|`json_maker/json_maker_ui.gd:3050:3` / `_confirm_fixed_number`|"固定数字不能再被任何效果更改（例如「费用减一」「威力加倍」都会对它无效）。\n卡面上的数字一般都应当能被更改，除非这张牌写明了这个数字不变。\n\n确定要改成固定数字吗？"|本口径不处理；UI间接输出证据:_confirm_fixed_number|
|需人工确认|R4|`json_maker/json_maker_ui.gd:3050:3` / `_confirm_fixed_number`|"固定数字不能再被任何效果更改（例如「费用减一」「威力加倍」都会对它无效）。\n卡面上的数字一般都应当能被更改，除非这张牌写明了这个数字不变。\n\n确定要改成固定数字吗？"|无明确展示字段或UI输出证据；需确认是否用户可见；UI间接输出证据:_confirm_fixed_number|
|本口径不处理|R3|`json_maker/json_maker_ui.gd:3279:26` / `_open_context`|"加一个「仅当」条件"|本口径不处理；UI输出入口:_open_context|
|本口径不处理|R2|`json_maker/json_maker_ui.gd:3338:24` / `_open_slot_menu`|"改成「↻ 当前这一项」（循环里用）"|本口径不处理；UI输出入口:_open_slot_menu|
|本口径不处理|R2|`json_maker/json_maker_ui.gd:3363:20` / `_show_welcome`|"[color=#c9a45c]像搭积木一样写卡牌效果[/color]\n\n1. 上面选卡牌种类，在左中「选一张卡」里双击打开，或点「新建一张」。\n2. 在「卡面信息」里填牌名、选图。\n3. 在「效果积木」里，每条效果先选[color=#c9a45c]当……时[/color]，再从最左边的积木区把积木拖到下面。\n4. 深色的圆角格子是[color=#c9a45c]空位[/color]：可以直接填，也可以把圆角积木（算出一个值的积木）拖进去。\n5. 橙色「如果……那么」把要做的事包起来，就只在条件成立时做。\n6. 点任意积木，这里会告诉你它是干什么的。点积木右边的 ✕ 删除它，右键可以复制。\n7. 想插在两块积木中间，就拖到下面那块的上半截或上面那块的下半截，会出现一条蓝线标出位置。\n8. 右下「还要修的地方」清空后就能保存。\n9. 效果下面的「生成牌」按内部名新建一张牌放进某一区。\n\n"|本口径不处理；UI输出入口:_show_welcome|
|本口径不处理|R3|`json_maker/json_maker_ui.gd:3363:20` / `_show_welcome`|"[color=#c9a45c]像搭积木一样写卡牌效果[/color]\n\n1. 上面选卡牌种类，在左中「选一张卡」里双击打开，或点「新建一张」。\n2. 在「卡面信息」里填牌名、选图。\n3. 在「效果积木」里，每条效果先选[color=#c9a45c]当……时[/color]，再从最左边的积木区把积木拖到下面。\n4. 深色的圆角格子是[color=#c9a45c]空位[/color]：可以直接填，也可以把圆角积木（算出一个值的积木）拖进去。\n5. 橙色「如果……那么」把要做的事包起来，就只在条件成立时做。\n6. 点任意积木，这里会告诉你它是干什么的。点积木右边的 ✕ 删除它，右键可以复制。\n7. 想插在两块积木中间，就拖到下面那块的上半截或上面那块的下半截，会出现一条蓝线标出位置。\n8. 右下「还要修的地方」清空后就能保存。\n9. 效果下面的「生成牌」按内部名新建一张牌放进某一区。\n\n"|本口径不处理；UI输出入口:_show_welcome|
|本口径不处理|R3|`json_maker/json_maker_ui.gd:3416:27` / `_show_help_for`|"放在「对……里的每一个」的嘴里。每一轮，它代表正在处理的那一个。\n\n注意：程序是按「填入位置」把当前这一个填进嘴里每一步的某个空位的，只填空着的那一格。"|本口径不处理；UI输出入口:_show_help_for|
|本口径不处理|R3|`json_maker/json_maker_ui.gd:3675:32` / `_pick_image`|"在现在这一层里按名字筛"|本口径不处理；UI输出入口:_pick_image|
|本口径不处理|R3|`json_maker/json_maker_ui.gd:3788:24` / `_fill_image_picker`|"这一层没有图片也没有文件夹。"|本口径不处理；UI输出入口:_fill_image_picker|
|本口径不处理|R2|`json_maker/json_maker_ui.gd:4353:39` / `_collect_key_names`|"相对项目根目录（data/masters/00002_x/…）"|本口径不处理；脚本字面量，未证明可见:_collect_key_names|
|本口径不处理|R2|`json_maker/json_maker_ui.gd:4353:82` / `_collect_key_names`|"相对这种卡的根目录（00002_x/…）"|本口径不处理；脚本字面量，未证明可见:_collect_key_names|
|本口径不处理|R2|`json_maker/json_maker_ui.gd:4353:116` / `_collect_key_names`|"只放卡文件夹（00002_x/…，不含上层）"|本口径不处理；脚本字面量，未证明可见:_collect_key_names|
|本口径不处理|R2|`json_maker/json_maker_ui.gd:4428:32` / `_paint_export_form`|"图片命名（不含扩展名）"|本口径不处理；UI输出入口:_paint_export_form|
|本口径不处理|R2|`json_maker/json_maker_ui.gd:4504:93` / `_paint_export_preview`|"（原名）"|本口径不处理；脚本字面量，未证明可见:_paint_export_preview|
|本口径不处理|R2|`json_maker/json_maker_ui.gd:4537:28` / `restore_tutorial_previous`|"（仍未保存）"|本口径不处理；脚本字面量，未证明可见:restore_tutorial_previous|
|需人工确认|R4|`scripts/debug/debug_action_panel.gd:171:32` / `<top-level>`|"改卡牌费用"|无明确展示字段或UI输出证据；需确认是否用户可见；UI间接输出证据:<top-level>|
|本口径不处理|R2|`scripts/debug/debug_action_panel.gd:299:13` / `_fill_player_picker`|"（本地）"|本口径不处理；脚本字面量，未证明可见:_fill_player_picker|
|本口径不处理|R2|`scripts/debug/debug_action_panel.gd:301:13` / `_fill_player_picker`|"（已淘汰）"|本口径不处理；脚本字面量，未证明可见:_fill_player_picker|
|本口径不处理|R2|`scripts/debug/debug_action_panel.gd:540:15` / `_entries_for`|"（本地）"|本口径不处理；脚本字面量，未证明可见:_entries_for|
|本口径不处理|R2|`scripts/debug/debug_action_panel.gd:838:10` / `_empty_reason`|"没有可选对象：%s（当前没有符合条件的对象）"|本口径不处理；脚本字面量，未证明可见:_empty_reason|
|本口径不处理|R2|`scripts/debug/debug_action_panel.gd:840:10` / `_empty_reason`|"没有可选对象：%s（当前没有符合条件的对象）"|本口径不处理；脚本字面量，未证明可见:_empty_reason|
|本口径不处理|R3|`scripts/debug/debug_adapters/debug_card_adapter.gd:93:16` / `swap_zones`|"不能交换同一个牌区"|本口径不处理；脚本字面量，未证明可见:swap_zones|
|本口径不处理|R2|`scripts/debug/debug_adapters/debug_map_adapter.gd:125:25` / `extra_play`|"出牌原语拒绝了这次追加打出（阶段、行动者或卡面条件不满足）"|本口径不处理；脚本字面量，未证明可见:extra_play|
|本口径不处理|R2|`scripts/debug/debug_adapters/debug_map_adapter.gd:131:25` / `release_name`|"原语未执行（已处于真名解放状态或缺卡）"|本口径不处理；脚本字面量，未证明可见:release_name|
|本口径不处理|R2|`scripts/debug/debug_adapters/debug_map_adapter.gd:137:25` / `hide_name`|"原语未执行（当前不处于可隐藏的状态）"|本口径不处理；脚本字面量，未证明可见:hide_name|
|本口径不处理|R3|`scripts/debug/debug_adapters/debug_player_adapter.gd:42:16` / `set_resource`|"set 与 vary 至少提供一个"|本口径不处理；脚本字面量，未证明可见:set_resource|
|本口径不处理|R3|`scripts/debug/debug_adapters/debug_player_adapter.gd:73:16` / `edit_number`|"set 与 vary 至少提供一个"|本口径不处理；脚本字面量，未证明可见:edit_number|
|本口径不处理|R2|`scripts/debug/debug_console_ui.gd:79:18` / `open_panel`|"[错误] 控制台尚未 initialize(host)"|本口径不处理；脚本字面量，未证明可见:open_panel|
|本口径不处理|R2|`scripts/game_scene/battle_board_v2.gd:4327:13` / `_refresh_broadcast_continue`|"继续（已确认 %d/%d）"|本口径不处理；UI输出入口:_refresh_broadcast_continue|
|本口径不处理|R2|`scripts/game_scene/tactical_board_ui.gd:3809:46` / `_show_effect_modal`|"请选择要发动的效果（可多选）"|本口径不处理；UI输出入口:_show_effect_modal|
|本口径不处理|R2|`scripts/game_scene/tactical_board_ui.gd:3821:18` / `_show_effect_modal`|"（已用完）"|本口径不处理；脚本字面量，未证明可见:_show_effect_modal|
|本口径不处理|R2|`scripts/game_scene/tactical_board_ui.gd:3821:48` / `_show_effect_modal`|"（不可选）"|本口径不处理；脚本字面量，未证明可见:_show_effect_modal|
|本口径不处理|R3|`scripts/net/p2p/p2p_signal_client.gd:154:10` / `poll`|"一个客机的直连握手超时"|本口径不处理；脚本字面量，未证明可见:poll|
|本口径不处理|R3|`scripts/net/session/lobby_session.gd:429:82` / `_join_identity`|"认证身份匹配多个成员，请使用原成员恢复凭据"|本口径不处理；脚本字面量，未证明可见:_join_identity|
|本口径不处理|R2|`scripts/net/session/lobby_session.gd:1987:10` / `_fail_closed_restore`|"恢复失败并关闭会话（未回滚原对局）；请丢弃此会话并重启权威："|本口径不处理；脚本字面量，未证明可见:_fail_closed_restore|
|本口径不处理|R2|`scripts/net/session/lobby_session.gd:2268:11` / `_begin_selected_match`|"录制开局失败并关闭会话（未回滚规则状态）；请重启权威："|本口径不处理；脚本字面量，未证明可见:_begin_selected_match|
|本口径不处理|R3|`scripts/net/ui/lobby_screen.gd:183:34` / `_network_mode_changed`|"双方填写同一个连接服务地址。房主创建后把房间码发给其他玩家，对局由玩家电脑直接连接。"|本口径不处理；UI输出入口:_network_mode_changed|
|需人工确认|R1|`scripts/net/ui/v2_view_presenter.gd:384:13` / `_refresh_guard`|"结算未完成，疑似异常\n玩家：%s\n卡牌：%s\n效果：%s\n跳过会撤销整个效果，重开会重新开始本局。"|无明确展示字段或UI输出证据；需确认是否用户可见；脚本字面量，未证明可见:_refresh_guard|
|本口径不处理|R3|`scripts/system/action_rules.gd:19:22` / `<top-level>`|"本回合必须使用一枚令咒"|本口径不处理；脚本字面量，未证明可见:<top-level>|
|需人工确认|R4|`scripts/system/global/all_operations.gd:95:100` / `<top-level>`|"攻击印刷费用"|无明确展示字段或UI输出证据；需确认是否用户可见；UI间接输出证据:<top-level>|
|需人工确认|R4|`scripts/system/global/all_operations.gd:97:98` / `<top-level>`|"技能印刷费用"|无明确展示字段或UI输出证据；需确认是否用户可见；UI间接输出证据:<top-level>|
|本口径不处理|R2|`scripts/system/global/all_operations.gd:119:113` / `<top-level>`|"当前实际享有的地利(部署才算)"|本口径不处理；UI间接输出证据:<top-level>|
|本口径不处理|R2|`scripts/system/global/all_operations.gd:121:75` / `<top-level>`|"是否处于交战状态(与对手同处会发生战斗的战场)"|本口径不处理；UI间接输出证据:<top-level>|
|需人工确认|R4|`scripts/system/global/all_operations.gd:127:80` / `<top-level>`|"区域移动费用"|无明确展示字段或UI输出证据；需确认是否用户可见；UI间接输出证据:<top-level>|
|本口径不处理|R2|`scripts/system/global/all_operations.gd:128:101` / `<top-level>`|"常规移动落点(满了返回null)"|本口径不处理；UI间接输出证据:<top-level>|
|本口径不处理|R2|`scripts/system/global/all_operations.gd:134:100` / `<top-level>`|"区域人数(读location._players)"|本口径不处理；UI间接输出证据:<top-level>|
|本口径不处理|R2|`scripts/system/global/all_operations.gd:137:89` / `<top-level>`|"MapData任意字段(事件牌堆、局势牌堆等)"|本口径不处理；UI间接输出证据:<top-level>|
|本口径不处理|R2|`scripts/system/global/all_operations.gd:144:89` / `<top-level>`|"全局面(局势+事件+区域buff)是否含效果名"|本口径不处理；UI间接输出证据:<top-level>|
|本口径不处理|R2|`scripts/system/global/all_operations.gd:148:73` / `<top-level>`|"查游戏日志（历史事实）"|本口径不处理；UI间接输出证据:<top-level>|
|本口径不处理|R3|`scripts/system/global/all_operations.gd:163:86` / `<top-level>`|"合并最多四个数组"|本口径不处理；UI间接输出证据:<top-level>|
|本口径不处理|R3|`scripts/system/global/all_operations.gd:165:95` / `<top-level>`|"删除一个匹配元素"|本口径不处理；UI间接输出证据:<top-level>|
|需人工确认|R4|`scripts/system/global/all_operations.gd:190:82` / `<top-level>`|"改卡费用"|无明确展示字段或UI输出证据；需确认是否用户可见；UI间接输出证据:<top-level>|
|需人工确认|R4|`scripts/system/global/all_operations.gd:200:97` / `<top-level>`|"改区域移动费用"|无明确展示字段或UI输出证据；需确认是否用户可见；UI间接输出证据:<top-level>|
|本口径不处理|R2|`scripts/system/global/all_operations.gd:206:87` / `<top-level>`|"把御主移出版图(回合结束)"|本口径不处理；UI间接输出证据:<top-level>|
|本口径不处理|R2|`scripts/system/global/all_operations.gd:224:72` / `<top-level>`|"把攻击加入场上(不计费用上限)"|本口径不处理；UI间接输出证据:<top-level>|
|需人工确认|R4|`scripts/system/global/all_operations.gd:224:72` / `<top-level>`|"把攻击加入场上(不计费用上限)"|无明确展示字段或UI输出证据；需确认是否用户可见；UI间接输出证据:<top-level>|
|本口径不处理|R2|`scripts/system/global/all_operations.gd:225:70` / `<top-level>`|"把技能加入场上(不计常规出牌上限)"|本口径不处理；UI间接输出证据:<top-level>|
|需人工确认|R4|`scripts/system/global/all_operations.gd:228:78` / `<top-level>`|"只改位置并返回费用"|无明确展示字段或UI输出证据；需确认是否用户可见；UI间接输出证据:<top-level>|
|本口径不处理|R2|`scripts/system/global/all_operations.gd:229:85` / `<top-level>`|"给某玩家(重)发从者牌"|本口径不处理；UI间接输出证据:<top-level>|
|本口径不处理|R3|`scripts/system/global/all_operations.gd:242:67` / `<top-level>`|"反制效果或其中一个func"|本口径不处理；UI间接输出证据:<top-level>|
|本口径不处理|R3|`scripts/system/global/all_operations.gd:253:86` / `<top-level>`|"执行到这一步时让玩家在区间内选一个数"|本口径不处理；UI间接输出证据:<top-level>|
|需人工确认|R4|`scripts/system/time_points.gd:450:25` / `<top-level>`|"卡牌费用计算完成时"|无明确展示字段或UI输出证据；需确认是否用户可见；UI间接输出证据:<top-level>|
|需人工确认|R4|`scripts/system/time_points.gd:451:30` / `<top-level>`|"自己卡牌费用计算完成时"|无明确展示字段或UI输出证据；需确认是否用户可见；UI间接输出证据:<top-level>|
|需人工确认|R4|`scripts/system/time_points.gd:452:32` / `<top-level>`|"他人卡牌费用计算完成时"|无明确展示字段或UI输出证据；需确认是否用户可见；UI间接输出证据:<top-level>|
