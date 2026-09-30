# 卡面 operation 全量审计：source_1（ID 1–580）

## 覆盖与口径

- 已逐条读取 `source_1.md` 的 580 条 OCR 转录，不按版本、`旧版`、`DIY` 或重复卡排除。
- 覆盖结果：`analyzed` 457 条、`non_rule` 115 条、`unclear` 8 条；逐条证据见 `coverage_1.json`。
- 本批只审阅 OCR 转录和仓库源码，**未查看或声称查看原图**。`unclear` 不据残缺文字推导 operation。
- 已核对 `assets/scripts/system/operations/*.gd`（195 个文件）、`assets/scripts/system/global/all_operations.gd`，并特别核对尚未提交也须纳入判断的 `CreateCard` / `BuildCard`：二者只负责创建独立对象，不负责入区、附件、换面、所有权重绑或临时效果生命周期。
- 下列是“候选原语/框架缺口”，不是要求按角色各写一个 operation。凡现有链可表达者均列入“可复用组合”，不新增。

## 新增候选

### 1. 全局牌堆/弃牌区的可查询与可转移原语

**精确卡面**：ID 1「阿塔兰忒」、3「撕裂天际的光辉之船」、8–10「派遣」卡背规则、48「耀眼的旅程」、128/129/134「白蔷薇姬－未唤醒」、131「白蔷薇的誓言」、132「星辰驰骋的终幕蔷薇」、138「陨铁之」、140「VR新阴流奥义 巴渊太阳剑」、190「展示王勇，遍历巡世的十二辉剑」、267「军神之剑·泪之星」、273「星之纹章」、352「桑丘·潘莎」、354–362「流浪骑士的大冒险」、564/568/570「梵天啊，覆盖大地」。

**为何现有原语不足**：玩家牌区已有 getter 与 `draw_card_by_card/index`，但事件牌堆、事件弃牌区、局势牌堆、局势弃牌区在 `MapData`，没有登记的 query operation。`add_event_from_deck` 只循环牌堆模板、克隆并入场，不能表达“洗进前 N 张”“展示/弃置牌堆底”“替换当前事件”“从任意位置取回”“移除本次将抽取的事件/局势”。`get_game_data_value` 读 `GameData`，不能替代 `MapData` 牌区。

**建议的单一职责候选**：

- `get_board_zone(zone_name)`：只返回一个明确白名单中的全局牌区数组。
- `move_board_card(card, from_zone, to_zone, to_index)`：只做全局牌区转移，并遵守事件/局势登记与注销不变量；不负责选择、洗牌或触发额外规则。

**可复用组合**：`random_int` + `add_to_array(index)` 可完成“前 N 张随机位置”；`shuffle_array` 可洗牌；`get_card_by_index_fr_arr` 可取顶/底；`draw_card_by_card/index` 可处理已取得的普通数组；`create_card/build_card` 仅在确实要创建新实例时使用。

### 2. 卡牌附件/叠放区原语与底层数据模型

**精确卡面**：ID 301/467/471「变容」（牌叠放在技能牌上）、563/567「三神之衣」与 ID 564/568/570「神力」（牌明置于从者牌上）。

**为何现有原语不足**：`add_to_array` 需要一个已存在且有生命周期语义的数组；当前卡对象没有通用附件区、明暗状态、归属、随宿主离场的处理。`set_property` 能写字段不等于对象模型、UI、效果登记和清理已支持。

**建议的单一职责候选**：`attach_card(host, card, concealed)` 与 `detach_card(host, card)`；先在基础对象模型中定义附件容器和离场规则，再登记 operation。

**可复用组合**：附件建立后，筛选/计数可复用 `get_property`、`array_length`、`get_cards_by_*_fr_arr`；移动实体仍复用 `draw_card_by_card`。

### 3. 卡牌换面/切换模板原语

**精确卡面**：ID 128/129/134「白蔷薇姬－未唤醒」、267「军神之剑·泪之星」、283/284「13号星期五」、530/533「女神的拥抱」。

**为何现有原语不足**：卡面“切换”同时涉及名称、图片、费用、威力、属性、效果注销/重登及状态保留。逐字段 `set_property` 会留下旧效果或破坏对象身份；`clone_object`、`create_card`、`build_card` 只创建另一对象，不能安全切换现有在场对象。

**建议的单一职责候选**：`switch_card_face(card, face_data)`，只切换声明过的双面模板并执行效果重绑；是否触发“展示/打出”由调用方决定。

**可复用组合**：`unregister_object_effects` / `register_object_effects` 是内部不变量；临时数值仍用 `edit_card_cost/power/attributes`。

### 4. 通用标记/计数模型

**精确卡面**：ID 86/90/91「煽动」、109/115「浪」、120「境界」、139「熬夜」、154/155「电荷」、249/251/253「王之印记」、305–313「音量」、341「远隔操作」、456–459「武练」、489/490「安贞」、599/600「响应」。

**为何现有原语不足**：这些标记可能属于玩家、牌、地点或关系，含公开/秘密、正负种类、过期时点和 token UI。`set_player_data` 只能覆盖玩家字段；`edit_data_number` 只处理既有 `BaseNumber`；`set_property` 不能建立通用持有者、可见性和清理协议。

**建议的单一职责候选**：底层 `MarkerCollection` 后提供 `get_marker_count(holder, marker_name)` 与 `edit_marker_count(holder, marker_name, delta, min, max)`。可见性、图标与过期策略属于框架声明，不写死角色名。

**可复用组合**：数值计算复用 `calculate_number/compare_number`；延时移除复用 `schedule_effect_on_time_point`；遍历对象复用 `foreach_func`。

### 5. 复制/替换既有卡的卡牌特征

**精确卡面**：ID 18/19「捕食日轮之角」、20–22「野性法则/福尔·韦瑟」、31「龙种改造」、62「无穷的武炼」、64「入阵曲」、98/99「试斩/刀剑审美」、124–127「予人以爱/花/星」、170/171「无形/诚之旗」、185「旭将军」、199/200「双神的神核/双神赞歌」、202「阎雀拔刀术其三」、275「妖精羽翼·泪之星」、301「变容」、381「尚未知晓的无垢湖光」、455「卢恩魔术」、488「颉颃胜负」、563「三神之衣」。

**为何现有原语不足**：`clone_object` 能生成副本，不能把来源牌的名称/费用/威力/属性/效果安全投影到目标牌；`set_property` 不会复制 `BaseNumber` 值语义、重绑效果、处理“至回合结束”回滚，也不能选择性排除“残留”等文本。

**建议的单一职责候选**：不要做万能“复制整张牌”。按需求拆成 `copy_card_characteristics(source, target, fields)` 与 `replace_card_effects(source, target, filter)`；字段白名单和效果过滤由数据参数声明，生命周期由 `schedule_effect_on_time_point` 回滚。

**可复用组合**：只复制整张独立对象时继续用 `clone_object`；临时复制入场用 `clone_object` → `add_attack/add_skill` → `register_object_effects`；从模板构建自定义临时牌用 `build_card`。

### 6. 卡牌控制权/所有权转移

**精确卡面**：ID 264「侥幸的拘捕网」、461「贯穿之朱枪」、488「颉颃胜负」。

**为何现有原语不足**：数组间移动不等于控制权转移。需要同步 `from`、所在玩家区、合计威力、效果触发玩家、回合结束归还。直接 `set_property("from")` 不会重绑已经登记的效果。

**建议的单一职责候选**：`transfer_card_control(card, player_id)`，只改变控制者并完成必要的注销/登记；临时归还用调度原语组合。

**可复用组合**：`find_player_array_containing` + `draw_card_by_card` 负责区域移动；`schedule_effect_on_time_point` 负责回合结束归还。

### 7. 原子交换位置

**精确卡面**：ID 141「VR新阴流」、316「海神，凶猛狂暴大海啸」、490「恋之追踪者」。

**为何现有原语不足**：两次 `set_location` 会受席位上限影响，第一步改变棋盘后第二步可能失败，无法保证交换原子性；`ignore_limit=true` 又会产生中间超员状态。

**建议的单一职责候选**：`swap_player_locations(player_a, player_b)`，只交换地点/地利占位并统一派发移动事实。

**可复用组合**：普通单向移动继续使用 `set_location/move/deploy`，不要为“任意地点移动”另加角色 operation。

### 8. 调用既有卡牌阶段能力

**精确卡面**：ID 34/36「阴阳螺旋」、64/70「入阵曲」、162「不容侵夺之拒绝王国」、214「隐藏不贞的头盔」、227「百合花开豪华绚烂」、502「伪·大神宣言」。

**为何现有原语不足**：当前 JSON 能注册效果，却没有“取得某张牌的指定阶段能力并在另一时点调用/重触发”的安全 operation。直接复制 funcs 会绕过每回合次数、可用性、付费和日志；`emit_time_point` 会广播，不是调用指定牌能力。

**建议的单一职责候选**：先补效果实例的稳定标识与使用计数，再提供 `invoke_card_effect(card, effect_name, context_override)`；operation 只调用一个已登记效果，不负责选择目标。

**可复用组合**：目标选择留在场景层；付费继续使用 `edit_magic`；时点迁移使用 `schedule_effect_on_time_point`。

## 不建议新增、可直接组合的高频机制

- “移出游戏”：`find_player_array_containing` → `draw_card_by_card` 到对应 `out_of_game`；ID 55/56/138/219/498 等无需角色专用 operation。
- “同战场对手全体减威力/败北”：`get_players_in_same_area` → `foreach_func` → `edit_power/defeat`；ID 40/49/51/59/61/88/92/94 等已有组合。
- “按属性筛选并改威力/属性”：`get_cards_by_attributes_fr_arr` → `foreach_func` → `edit_card_power/edit_card_attributes`；ID 145/170/289 等已有组合。
- “抽牌、打出、关闭、延后到下回合”：`draw_card_from_pl_deck_to_hand`、`play_attack/play_skill/add_attack/add_skill`、`close_card`、`schedule_effect_on_time_point` 已覆盖基本动作。
- “真名解放/隐藏”：优先 `release_true_name/hide_true_name`，不要再用裸 `set_player_data` 拼 UI 状态。
- “临时牌/复制牌”：`create_card` 或 `build_card` → `add_attack/add_skill/add_to_array` → 必要时 `register_object_effects`；创建与入区保持分离。

## 框架缺口（不应伪装成 `set_property` 已支持）

1. **选择与秘密信息 UI**：任意数量、至多 N、猜测、对手选择、同步支付、查看后复原等没有统一交互协议。
2. **效果影响策略**：ID 184「勇往直前」的改目标、194「新阴流·通透」的阻止整条效果及后续影响、216「守护的誓约」的区域保护、266/275/370 的不可关闭/不可减威力，都需要效果来源、目标与子调用传播模型；`counter` 只能反制当前效果/func，不能表达持续策略。
3. **战斗流程改写**：ID 33「立即结算战斗」、42/47/243/498 的直接获胜、166 的追加回合、372/382 的跨战场替代胜者，涉及 `BattleResolver/GameProgress`，不是普通数值 operation。
4. **移动路径历史**：经过所有地点、移动距离、方向变化等需确认日志是否完整记录每一步与路径；`query_log` 可查已有事实，但不能查询未记录的事实。
5. **永久规则改写与回滚**：获得/失去卡牌文字、限制出牌、改变手牌上限、下一回合禁止行动等需要声明式 modifier 层，不能靠临时字段散落。
6. **游戏胜利/淘汰替代/额外回合**：需统一的结算钩子和不可阻止优先级，不能把 `is_out`、回合数或胜者数组直接写掉。

## OCR 问题

以下 8 条无法从现有转录可靠判定完整规则，已标 `unclear`：

- ID 23「坏劫之天轮」：选项区域仅剩方框乱码。
- ID 101「剑胚」、108（大和武尊未知散列文件）、142（巴御前未知散列文件）、247「3.1更新 (3)」、416（布拉达曼特未知散列文件）、441（帕西瓦尔未知散列文件）：未识别到有效规则文字或仅单字符。
- ID 342「冥界佑护」：只有标题，无正文。

其余标为 `non_rule` 的条目是从者统计卡、卡背、标记/token 或 `Skill` 占位等未见可执行规则正文的素材；它们不是 OCR 成功的规则卡，不参与 operation 结论。
