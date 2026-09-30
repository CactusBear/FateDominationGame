# 卡面 operation 全量审计：source_2（ID 581–1160）

## 覆盖与口径

- 已逐条读取 `source_2.md` 的 580 条 OCR 转录，不按版本、`旧版`、`DIY` 或重复卡排除。
- 覆盖结果：`analyzed` 444 条、`non_rule` 126 条、`unclear` 10 条；逐条证据见 `coverage_2.json`。
- 本批只审阅 OCR 转录和仓库源码，**未查看或声称查看原图**。`unclear` 不据残缺文字推导 operation。
- 已核对 `assets/scripts/system/operations/*.gd`、`assets/scripts/system/global/all_operations.gd` 以及 `CreateCard` / `BuildCard` 的真实职责。`CreateCard` 只从已加载模板建独立对象；`BuildCard` 只从完整数据建对象。二者都不自动入区、登记效果、换面、附着或转移控制权。

## 新增候选

### 1. 全局事件/局势牌区查询与转移

**精确卡面**：ID 613「不夜的魅力」、683「终末剑·Enki」、859「圣夜之虹，军神之剑」、868「伟大的时间啊，于此回转」、869「光赫啊，显现狱死之海吧」、911/914「神威车轮」、913「王之军势」、1100「绅士之爱」。

**为何现有原语不足**：事件/局势牌堆与弃牌区位于 `MapData`，没有登记的 getter；`add_event_from_deck` 只从事件模板循环克隆入场，不能替换现有事件、操作局势弃牌、展示顶底、从弃牌区激活或把指定牌放回牌堆。`draw_card_by_card/index` 只有在调用方已拿到数组后才可复用。

**建议的单一职责候选**：

- `get_board_zone(zone_name)`：只读白名单全局牌区。
- `move_board_card(card, from_zone, to_zone, to_index)`：只转移指定全局卡并维护登记/注销。

**可复用组合**：顶/底选择用 `get_card_by_index_fr_arr`；洗牌用 `shuffle_array`；筛选用 `get_cards_by_*_fr_arr`；事件入场仍复用 `add_map_area_events`，新建临时事件可用 `create_card/build_card`。

### 2. 卡牌附件/叠放模型

**精确卡面**：ID 735「红宝石『喷洒模式』」、976「分割思考」、1005/1007/1009「分割思考」、1108/1109「咒层·丽日照」。

**为何现有原语不足**：卡面要求把手牌背面/正面放在技能牌上、之后按放置回合或名称筛选并打出；【咒】也需附着在牌上并可返回。现有卡对象没有通用附件容器与 UI/生命周期。`add_to_array` 不是底层支持，`set_property` 不能凭空建立受引擎追踪的牌区。

**建议的单一职责候选**：`attach_card(host, card, concealed)`、`detach_card(host, card)`；底层先定义附件容器、放置回合、原区域和宿主离场清理。

**可复用组合**：有附件数组后用 `filter_by_property`、`get_cards_by_name_fr_arr`、`foreach_func`；实体区域转移仍用 `draw_card_by_card`。

### 3. 卡牌换面/多状态模板

**精确卡面**：ID 747「机械弓术·毁灭之矢」、749「机械弓术·桩式锚定」、750/753「机械弓术·月轴检查」、754「机械弓术·桩式锚定」、755「机械弓术·毁灭之矢」。

**为何现有原语不足**：这些牌在三个状态间切换并保留对象身份及其他影响。`set_property` 逐字段修改会遗漏图片、效果注销/登记和印刷值；`clone_object/create_card/build_card` 会产生新对象，不能保留原牌上的影响。

**建议的单一职责候选**：`switch_card_face(card, face_data)`；只执行合法模板切换和效果重绑，不代替时点或支付。

**可复用组合**：回合结束选择和支付用现有控制流、`edit_magic`、`schedule_effect_on_time_point`；回到技能区继续用 `close_card`。

### 4. 通用标记/计数模型

**精确卡面**：ID 599/600/601「响应」、698「雷电之手」的超过上限次数语义、819「终局的犯罪」的【魔弹】、939/940「炎之吐息」、951「册封」、1150/1151「驯鹿」。

**为何现有原语不足**：这些状态属于玩家、地点、卡或关系，需计数、公开/秘密、过期、token UI；`edit_data_number` 只能改既有玩家 `BaseNumber`，`set_player_data` 不能覆盖地点和卡，`set_property` 没有通用标记协议。

**建议的单一职责候选**：底层 `MarkerCollection` 后提供 `get_marker_count(holder, marker_name)` 与 `edit_marker_count(holder, marker_name, delta, min, max)`。

**可复用组合**：阈值与公式复用 `compare_number/calculate_number`；跨回合移除复用 `schedule_effect_on_time_point`；地点玩家遍历复用 `get_players_in_map_area/foreach_func`。

### 5. 复制/替换卡牌特征与效果

**精确卡面**：ID 700/701「分身」、704/705「王之书库/月所不识的久远之光」、706/707「同睿智接触」、741/743「暮云春树」、742/744「枕草子·春曙抄」、745「星是昂星」、822「终极犯罪」、825「邪智的魅力」。

**为何现有原语不足**：`clone_object` 只复制现有对象，不能把来源卡的选择性字段应用到目标；`build_card` 可以新建完整数据，但不能安全修改一张已在技能区/攻击区的牌。名称、费用、威力、属性、阶段效果、是否攻击化与临时回滚涉及效果重新登记，裸 `set_property` 不成立。

**建议的单一职责候选**：

- `copy_card_characteristics(source, target, fields)`：复制明确白名单字段。
- `replace_card_effects(source, target, filter)`：仅替换筛选后的效果集合并重绑。

不要新增“复制某角色技能”之类专用 operation。

**可复用组合**：新建【分身】可用 `build_card`；完整临时副本用 `clone_object` → `add_attack/add_skill`；到期关闭/移除用 `schedule_effect_on_time_point` + 区域转移。

### 6. 卡牌控制权/借用/跨玩家区域转移

**精确卡面**：ID 691「神授智慧」、700/701「分身」、745「星是昂星」、961/963/964「终焉的大木马」、1112「愿百合王冠荣光永在」。

**为何现有原语不足**：把牌放到另一玩家手牌/攻击区或借出技能，不只是数组转移；需要改变控制者、效果触发玩家、合计威力来源并在指定时点归还。`draw_card_by_card` 不改控制权，`set_property("from")` 不重绑已登记效果。

**建议的单一职责候选**：`transfer_card_control(card, player_id)`；只改变控制者并维护效果登记。临时归还、区域移动和支付由其他 operation 组合。

**可复用组合**：`find_player_array_containing` + `draw_card_by_card` + `schedule_effect_on_time_point`。

### 7. 原子交换位置/强制成组移动

**精确卡面**：ID 586/589「天鹅湖」、630「月女神的爱箭恋矢」、897「加速过弯」、966「神体结界」、1103「坛之浦·八艘跳」。

**为何现有原语不足**：位置交换、两人同行、全员依序强制移动涉及席位占用和失败回滚。连续调用 `set_location` 会出现第一步成功、第二步因人数上限失败；临时 `ignore_limit` 会留下不合法中间状态。

**建议的单一职责候选**：`swap_player_locations(player_a, player_b)` 处理真正交换。全员强制移动仍用 `foreach_func` + `set_location`，但选择顺序/支付拒绝需场景层队列。

**可复用组合**：普通单人无视限制移动继续用 `set_location(..., ignore_limit=true)`；移出版图再部署用 `remove_from_board` → `deploy/set_location`。

### 8. 调用或重放指定卡牌能力

**精确卡面**：ID 605「圆桌骑士崔斯坦」、627「闪耀的大王冠」、745「星是昂星」、879/881/884「超越边界的存在」、998「尼莫护士」、999/1028「尼莫教授」、1102/1104/1105「喜见城·冰柱削」。

**为何现有原语不足**：卡面要求在非原时点使用行动阶段能力、重放某项攻击能力或触发“打出时”。`emit_time_point` 会广播时点，无法只调用指定牌；直接复制 funcs 会绕过每回合次数、费用、可用性和日志。

**建议的单一职责候选**：先补效果稳定标识和使用计数，再提供 `invoke_card_effect(card, effect_name, context_override)`，只调用一个已登记效果。选择能力与确认支付留在场景层。

**可复用组合**：支付用 `edit_magic`；到期清理用 `schedule_effect_on_time_point`；仅重新派发规则时点仍用 `emit_time_point`。

### 9. 批量回收并重新组牌的牌区事务

**精确卡面**：ID 649/653「无限剑制」、763/784「吾，以身殉魔天」、1014/1029「分割思考（尼莫牌库替换）」。

**为何现有原语不足**：理论上可以多次 `merge_arrays`、`foreach_func`、`draw_card_by_card`，但“从多个区任选组成手牌/整套替换牌库”需要玩家多选、剩余牌去向、效果注销/登记、手牌上限和失败回滚。单纯暴露数组会产生半完成状态。

**建议**：优先补“多选事务”框架，而不是新增角色 operation。若确需 operation，应拆为通用的 `collect_player_zones(zone_names)`（只查询）与 `replace_player_deck(cards, player_id)`（只原子替换牌库）；选择仍由 UI 产出参数。

## 不建议新增、可直接组合的高频机制

- 骑乘/单独行动/战斗续行等重复卡：现有 `draw_card_from_pl_deck_to_hand`、`play_attack/play_skill`、`move/set_location`、`edit_score` 足够，重复版本不是新增 operation 证据。
- 按属性筛选、改威力/费用/属性：`get_cards_by_attributes_fr_arr` → `foreach_func` → `edit_card_power/edit_card_cost/edit_card_attributes`。
- 从游戏外或模板创建临时攻击：`create_card`/`build_card` → `add_attack/add_skill/add_to_array` → 必要时 `register_object_effects`。ID 907/910「王之军势」无需再加“创造基础攻击”专用 operation。
- 关闭、败北、抽牌、改魔力/战果、地利倍率：现有 `close_card/defeat/draw_card_from_pl_deck_to_hand/edit_magic/edit_score/edit_location_benefit` 可直接组合。
- 每局一次/每回合次数：优先已有日志 `query_log/log_exists` 或 `used_once_effects` 组合；但前提是相应动作确实记日志，不用资源数倒推。

## 框架缺口（不应伪装成 `set_property` 已支持）

1. **选择/协商/秘密信息 UI**：ID 660 的多人二选一、664/665 的 X 支付、700/701 的分身选择、929 的宣言、1034 的多人支付会谈、1112 的依次询问，都需要可暂停、可恢复、带隐私边界的交互队列。
2. **战斗胜者与游戏流程改写**：ID 625 的跨战场替代胜者、716/720/722 的“与其他胜者共同获胜”、683 的下回合不抽事件、879/881 的规则冲突无效化、1112 的双人共同游戏胜利，不是普通 operation；需 `BattleResolver/GameProgress` 的声明式钩子。
3. **持续保护/免疫/来源过滤**：ID 646 的效果反射、661 的不可关闭/不可减威力、805/806 的隐藏与中毒、1137–1147 的双方隔离和来源白名单，需要效果调用链携带来源、目标、父子调用和保护策略。`counter` 只能反制当前效果/func。
4. **移动路径与历史快照**：ID 737/738 的“上次使用回合”、741–745 的上回合基础攻击属性/阶段能力、1053 的移动距离与经过战场，需要日志记录对应字段快照；`query_log` 本身不会补录事实。
5. **部署/战斗/淘汰替代**：ID 927 的淘汰替代、1085 的下回合跟随部署、1088 的跨回合窃取所得战果、1118 的强制部署，都需要结算钩子和优先级。
6. **永久 modifier 层**：费用/威力下限、技能禁用、改变常规出牌时点、获得他牌文本、区域规则覆盖等不应散落为直接字段写入；需要可追踪来源、叠加和到期的 modifier。

## OCR 问题

以下 10 条无法从现有转录可靠判定完整规则，已标 `unclear`：

- ID 587（迷之 Alterego·Λ 散列文件）：正文几乎全为数字乱码。
- ID 708「str 7」：仅能辨认职阶技能数值，缺少可确认的规则正文。
- ID 758「弓沉月」、759「机械弓术」、760/761「源为朝」、762「迅捷射击」：英文版素材只识别到标题/数值或从者统计，无法确认是否遗漏规则。
- ID 892（乔尔乔斯散列文件）：未识别到文字且素材类型不明。
- ID 1083/1084（梅芙散列文件）：仅识别到“目”/“3”。

其余 `non_rule` 为从者统计卡、卡背、token/标记、目录占位图或仅标题数值且明确无规则正文的素材；不据此提出 operation。
