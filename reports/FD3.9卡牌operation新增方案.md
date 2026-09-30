# FD3.9 从者/御主卡面 → 新增 operation 方案

数据源：`reports/FD3.9从者御主卡面数据.md`（4633 条记录）。
分析口径：不区分新旧版本，同一张卡的多个版本各自分析，取能覆盖所有版本的原语集合。
逐卡结论：`reports/FD3.9逐卡实现明细.md`（10 批合并，每张卡写明实现形式；`N:` 表示卡面级建议原语，`F:` 表示需要框架支持的点）。本文件是去重、对照现有 196 个 operation 之后的**最终方案**。

## 0. 覆盖统计

| 项 | 数量 |
|---|---|
| 原始记录 | 4633 |
| 未识别到文字 | 345 |
| 原文完全相同合并后 | 3585 |
| 近似版本合并后的代表条目 | 3310 |
| 逐条写入结论的条目 | 3045（含同类合并） |
| 纯从者属性表/名称残片，无效果文字 | 265 + 若干残片（已核对，均不含"阶段/打出/获得/失去/令咒/魔力/威力"等效果词） |

覆盖率由脚本核对：所有代表条目的编号都出现在明细中，或属于无效果文字的残片/属性表。

## 1. 原则

1. **先组合、后新增**：卡面阶段写出的约 210 个建议原语，逐个和现有 operation 对照，能组合的全部改走现有原语（见 §2），最后只剩 §3 的 20 个真正缺的。
2. **不改、不删现有 operation**：新增 op 都是新文件；框架扩展（§4）只加字段、时点和效果类，默认值与现有行为一致，不改现有 exec 签名的语义。
3. **单一职责**：每个新增 op 只做一件事，规则数字、属性、次数、映射表都作为参数传入或写在卡牌 JSON 里，不在代码里写死。
4. **数据显式声明**：卡片分类、事件牌组、恐惧属性、战型切换表、容器区间等全部由 JSON 声明，程序不从文本或尺寸推断。

## 2. 卡面建议原语 → 现有 operation 的对照（不需要新增）

| 卡面阶段的写法 | 用现有原语组合 | 典型卡 |
|---|---|---|
| set/add/remove_card_attributes（属性增删、改为、获得所有属性） | `edit_card_attributes` | 水之宁芙、森罗万象、狐之婚嫁、无名之森 |
| set_card_power / set_card_base_power / multiply_card_power（设 0、翻倍、×3、减半） | `calculate_number` + `edit_card_power(set_num)` | 风王结界、神鬼无前、太阳的数字、八极崩 |
| add_cost_modifier（±费用、减半向上取整、免费） | `edit_card_cost` / `edit_data_number("attack_cost_discount")`，在 `card_cost_calculated` 时点里算 | 樱之迷宫、誓约胜利之剑、魅惑的美声 |
| set_play_count_limit（多打/少打一张、仅一张） | `edit_data_number("play_limit" / "regular_play_min")` | 阴阳鱼、被污染的圣杯、魔兽、金刚之体 |
| set_turn_order_position（首位/末位/任意位） | `change_pl_order` | 不夜特权、终局、OrderChange |
| hide_true_name / true_name_release | `hide_true_name` / `release_true_name` | 乘镀、遥远的幻梦境、三之太刀 |
| eliminate_player | `edit_lives(set_num=0)` | 创造物工厂、U-奥尔加玛丽、指证 |
| win_game（判定获胜） | `set_player_data("victory_override", true)`；需要立刻结束时加 §3 的 `end_game` | 伦戈米尼亚德、誓约胜利之剑、第三法 |
| defeat / 无视败北 | `defeat` / `remove_defeat` | 冠位·杀、幸运、月灵髓液 |
| create_card_from_pool / create_temp_card（从游戏外加入、创造临时牌） | `create_card` 或 `build_card` + `add_to_array` / `add_attack` / `add_skill_to_skill_zone`；"临时"用 `schedule_effect_on_time_point` 到期移除 | 领域外生命、法宝、龙仪巧、糖果 |
| replace_card / replace_deck（替换为另一张牌、重组牌库） | `remove_from_array` + `create_card` + `draw_card_by_card(to_index)` | 起源弹、狱炎、我武新、最后的叙述者 |
| insert_into_deck（放入牌库第 X 张、前 5 张） | `draw_card_by_card(card, from, to, to_index)` + `random_int` | 蓄势、梦游仙境 |
| move_card_to_player_zone / set_card_controller（加入他人攻击、借用、回合结束返还） | `remove_from_array` + `add_attack(card, 对方id)`；原主人留在 `from`，返还用 `schedule_effect_on_time_point` | 天之锁、援护射击、混天绫、酒壶 |
| play_card_from_zone（从手牌/牌库/弃牌堆/他人区域打出） | `find_player_array_containing` + `play_attack(ignore_limit)` / `add_attack` | 光壳流溢的虚树、复仇者EX、女神的视线 |
| attach/detach/get_attached（叠放、盘、临摹、征服、酒壶） | `draw_card_by_card` 在宿主卡的附属数组之间搬运（附属数组见 §4.3） | 虚数美术、咆吼、新天地探索航行 |
| random_choice / 随机 Combo / 随机弃置 | `random_int` + `get_card_by_index_fr_arr` / `shuffle_array` | 无限溯行歌词、招谏、怪兽王女 |
| choose_attribute / 多选一效果 / 选项每局限一次 | `ask_player_option`（选项带 `max_uses`、`activation_requirements`） | 卢恩魔术、迦勒底礼装、宝石、原初之卢恩 |
| ask_player_choice（让其他玩家选择） | `ask_player_option(player_id=对方)` / `queue_optional_effect_for_players` | 李书文、零落泛滥、老相识 |
| get_turn_played_cards / 本回合是否移动 / 是否用过令咒 / 连胜 / 上回合胜负 / 使用次数 / 打出次数 | `query_log` / `log_field_values` / `sum_log_data`（按 `round_offset` 查） | 妖精骑士、参孙、开演之时已至、骑士的夙愿 |
| get_player_stat（本回合花费/获得的魔力、战果） | `sum_log_data`（`record_resource_change` 已记录 delta） | 宝石剑、类食尸鬼、加尔瓦略之星 |
| get_player_rank / 唯一最高 | `get_rank_by_data_number` / `get_extreme_by_property` | 间桐樱、原罪、娜塔莉亚 |
| get_battle_losers | `get_area_round_participants` − `get_area_round_winners`（`array_difference`） | 王之歌声、止境的正义 |
| 玩家状态：粉丝/神仆/新郎/枯萎/灼伤/猎物/恶/检/燃烧/境界/老虎标记 | `create_buff` + `manage_buff`；叠层用同名 buff 计数 `get_buff_by_name_fr_arr` + `array_length` | 长恨歌、赛蕾妮可、火炎弹 |
| transfer/add/lose/restore_command_spell | `get_pl_command_spell_side` + `draw_card_by_card` / `create_card(card_type="command_spell")` / `edit_data_number("command_spell_count")` | 漫长旅途、第三太阳、觉醒 |
| set_player_resource / 魔力设为 N | `edit_magic(set_num)` | 前线回复、连通根源、万华镜 |
| 地利翻倍/失去地利/基础地利 | `edit_location_benefit`；玩家级加成见 §4.1 | 远隔操作、铁山靠、乾坤圈 |
| deploy_to / redeploy / 移动至任意地点 | `deploy` / `remove_from_board` + `deploy` / `set_location` | 绚烂的创造物、魔力计、予星以梦 |
| 禁止进入/离开、人数上限、移动费用 | `set_map_area_can_move_to` / `set_location_pl_num_limit` / `edit_map_area_move_cost` | 异闻带扩张、懊悔、塔塔利 |
| 事件牌放置/加牌/移除/替换/交换/重抽 | `add_event_from_deck` / `add_map_area_events` / `get_events` + `remove_from_array` | 泛人类史、规则操作、胎藏界 |
| activate/replace_situation_card | `add_situations` + `remove_from_array` | 心像世界、异星神扩张、拉尼VII |
| replace_master / replace_servant / swap_servant | `set_player_data("master"/"servant")` + `register_object_effects` / `unregister_object_effects` + `deal_player_cards` | 伪臣之书、CETRRL爆了、诀别之时已至 |
| 残留延长 / 持续至下回合结束 | `set_property(effect, "_is_residue")` + `schedule_effect_on_time_point` | 房火浮屠、生命赋予、回响 |
| 反制/阻止某项效果 | `counter` | 规则层面的"无效" |
| draw_until / 重复 N 次 / 按次数付费重复 | `while_func` / `for_func` + `draw_card_from_pl_deck_to_hand` | 空想具现化、咆吼 |
| arrange_cards（任意顺序放回） | 选牌结果按选择顺序 `add_to_array` | 捕捉、最优解、重整旗鼓 |
| 暗置/明置、改为暗置 | `set_card_concealed` | 无极、奥尔科特上校 |
| count_empty_zones / zone 张数 | `array_length` 对各区求和 | 不毁的极圣、金刚之体 |
| 双御主/双从者切换（牌库、弃牌堆、技能区各自独立） | `set_player_data("master"/"servant")` + `unregister_object_effects` / `register_object_effects`；整组区用 `set_player_data("deck"/"discard"/…)` 换引用，换下的一套 `set_dictionary_value` 存进 `extra_zones` | Tiger/Zero、太平之愿、扭蛋女皇 |
| 宣称打出（暗置后声明牌名，行动阶段结束展示校验） | 暗置打出 + `edit_magic`（值取 `get_attack_printed_cost`）+ `tag` 记宣称名 + 行动阶段结束 `show_cards` 并比对 `_name`；暗置仍计威力用 `build_effect` 挂 CountsPowerWhileConcealed | 回路增幅 |
| 卡面数字整体倍率（"阿拉伯数字均翻倍"） | 按数据声明的效果名 `for_func` + `get_effect_number` + `edit_num_and_return(times=2)`（效果数字是共享的数字对象，就地改值） | 姬发流 |
| 受某状态效果双倍影响 | 本卡自带一条效果：持有该状态时再执行一次同样的 `edit_card_cost` / `edit_card_power` | 千年城（血之渴望） |

## 3. 新增 operation（20 个）

### 3.1 查询

| op | 参数 | 返回 | 职责 | 涉及卡（举例） |
|---|---|---|---|---|
| `get_map_data_value` | `key:String` | 任意 | 读取 MapData 字段（事件牌堆、事件弃牌堆、局势牌堆等），与 `get_game_data_value` 对称 | 派遣、溶烛化紫、鉴识眼、迦勒底亚斯、异闻带扩张、梦游仙境（19 处） |
| `get_adjacent_map_areas` | `area, direction:String("forward"/"backward"/"both")` | `Array[BaseMapArea]` | 按地图箭头返回相邻战区 | 紧急回避、相邻移动、俯瞰风景、嗅迹追踪、水之型（9 处） |
| `get_object_counter` | `object, key:String` | `BaseNumber` | 读取任意对象（卡/地点/效果）上的命名计数 | 灵力、经验、羽、code、莲体、X 永久值、宝具使用次数 |
| `get_player_power_breakdown` | `player_id, include_sources:Array, exclude_sources:Array` | `BaseNumber` | 按来源（局势/事件/他人能力/令咒/攻击）统计合计威力，依赖 §4.4 的来源标记 | 直死之魔眼、零标之魂、人智统合真国、兵器的成长、对魔力EX |

### 3.2 交互

| op | 参数 | 返回 | 职责 | 涉及卡 |
|---|---|---|---|---|
| `ask_player_number` | `min, max, player_id, shown_name` | `BaseNumber` | 让玩家在区间内选一个数（上下限可以是变量） | 星月夜X、王律之键、月灵收束、天灾、破浪、补血剂、调律、抹大拉的圣骸布 |
| `ask_players_secret_option` | `players:Array, options:Array, reveal:bool` | `Dictionary{pid:选择}` | 多名玩家同时秘密选择，结算后可选择公开；比较结果交给 `match_func` / `compare_number` | 催稿、斗争的魅力、猜拳（月之胜利者/岸波白野）、事件簿预测、代价魔术宣言、闪鞘猜牌、天体学记录回合 |
| `show_cards` | `cards:Array, viewer_ids:Array(空=所有人), shown_name` | 无 | 展示牌（不改变明/暗置状态），并派发 `card_revealed` | 展示手牌/牌库顶/弃牌堆（41 处：魔女审判、零落泛滥、女神的视线、黑键…） |

### 3.3 效果与卡牌

| op | 参数 | 返回 | 职责 | 涉及卡 |
|---|---|---|---|---|
| `build_effect` | `effect_data:Dictionary, owner` | `BaseEffect` | 按卡牌 JSON 里的 effect 格式建效果对象，不登记也不挂载；挂到哪张牌由 `add_to_array` + `register_object_effects` 组合 | 授予文字：爱之炎、誓约、坐杀、粉碎灵魂、概念、理解、灵、菩提之叶给对手的能力（56 处） |
| `activate_effect` | `effect, player_id` | 无 | 让一项已存在的效果作为当前玩家的一次使用进入结算（遵守该效果自身的次数与前提） | 魔女咒术、超载、魔神柱佛钮司、兽王之巢再用一次、机械翡翠、鸦之友、组合使用（26 处） |
| `flip_card_face` | `card` | `card` | 双面卡切换到另一面：换卡面数据、注销旧效果、登记新效果；另一面数据由 JSON 声明（§4.3） | 迦勒底礼装、战型、第X天、敏锐嗅觉/自我欺骗、容器、原罪↔美德、彼界之门、菲奥蕾超越、秋之森/威尔士（24 处） |
| `edit_object_counter` | `object, key, set_num, vary_num, min_value, max_value` | `BaseNumber` | 改写对象上的命名计数（与 `edit_data_number` 同一用法，只是作用于任意对象） | 同 `get_object_counter` |

### 3.4 预处理与替代（依赖 §4.2 的"即将发生"时点）

| op | 参数 | 返回 | 职责 | 涉及卡 |
|---|---|---|---|---|
| `cancel_pending_action` | 无 | `bool` | 在 `before_*` 时点里取消这次即将发生的动作（淘汰、败北、关闭、移除、弃置、获得令咒…） | 遥远的理想乡、阿瓦隆、救世主、橄榄枝、守护、量子甲胄、引导之星、苍天之力 |
| `get_pending_action_value` | `key:String` | 任意 | 读取即将发生动作携带的值（`effect`/`card`/`amount`…），只读不改 | 信仰的加护（取被延后的效果）、按即将关闭/移出的牌做判断 |
| `edit_pending_action` | `key:String, set_num, vary_num` | `BaseNumber` | 改写即将发生动作的数值或去向（战果减半、令咒改为 4 魔力、弃牌改为放置、魔力来源倍率、每回合获得上限） | 被虐灵媒体质、冬之圣女、创造者、巴巴妥司、绝高无上·谦恭、蔷薇的沉睡、土御门泰广、回路不良、红赤朱 |

### 3.5 战斗与对局

| op | 参数 | 返回 | 职责 | 涉及卡 |
|---|---|---|---|---|
| `set_battle_result` | `map_area, winner_ids:Array, mode:String("replace"/"add"/"losers_only")` | 无 | 在 `battle_resolve` 时点改写该战场胜负：直接指定胜者、追加胜者、只在败北者中计胜者 | 诀别之时已至、次元超越、第一太阳·黑色太阳、直到地狱的尽头、妖精骑士共享胜利 |
| `end_game` | `winner_ids:Array` | 无 | 立刻结束对局并按给定胜者结算（`victory_override` 只在终局判定时生效，这里补"立即"） | 伦戈米尼亚德、于深渊化作光、誓约胜利之木剑、空想树、奥伯龙 |

### 3.6 地图与棋子

| op | 参数 | 返回 | 职责 | 涉及卡 |
|---|---|---|---|---|
| `add_map_area` | `area_data:Dictionary, link_from, link_to` | `BaseMapArea` | 按数据新增战区并接入地图 | 深空、阿里芒戈岛、宅邸 |
| `set_map_area_link` | `from_area, to_area, cost:BaseNumber, enabled:bool` | 无 | 增加、修改或断开一条移动箭头 | 翘曲空间、阿里芒戈岛（侦查→岛 费用 2） |
| `set_map_area_enabled` | `map_area, enabled:bool` | 无 | 关闭或开启整个地点（与 `set_map_area_can_move_to` 不同：关闭后不部署、不结算、不放事件） | 懊悔、月之圣杯开启/重启、月之可能性 |
| `add_player` | `controller_id:int, shared_keys:Array, overrides:Dictionary` | `int`（新条目玩家 id） | 新建玩家条目：`controller_id>=0` 为分身棋子（胜利归控制者），`-2` 为 NPC，`-1` 为普通玩家；`shared_keys` 列出与控制者共用同一对象的字段（`played_cards`/`score`/`magic`…），不共用的字段（`location`/`power`）各自独立。放置、设威力、移除都用现有 op 组合（`deploy` / `edit_power` / `remove_from_board` + `set_player_data("is_out", true)`） | 幻影爱丽丝、达芬奇投影、泽尔里奇分身、始皇帝、摩根、妖精骑士、奥伯龙、星之锚 |

共 20 个：查询 4、交互 3、效果与卡牌 4、预处理 3、战斗与对局 2、地图与棋子 4（原 `spawn_board_entity` / `remove_board_entity` 两个合并为 `add_player`）。

## 4. 框架扩展（不新增 op，但卡要实现必须有）

### 4.1 player_data 新字段（默认值与现状一致，用 `edit_data_number` / `set_player_data` 改）
- `hand_limit`（现为全局 `GameData.hand_limit`；增加玩家级覆盖，缺省时取全局）：火焰之花、女仆扫除计划、矿石的极致、探寻未知。
- `magic_limit` / `magic_min`（同上）：间桐脏砚上限 16、贫血症下限、被污染的圣杯无限魔力（上限设为无限值）。
- `score_can_go_negative`：地右卫门、赛蕾妮可、光之剑。
- `move_cost_discount`（每步）：库·丘林、水之型、老虎道场；`move_cost_multiplier_rules` 不需要，翻倍用区域移动费修改。
- `location_benefit_bonus`（玩家级基础地利）：阿周那、糖果、冠位·术、迷彩狙击。
- `roles:Array`（异星神/隐匿者/新郎/红队/监督者…）：异闻带、圣杯大战、恶的庇护者，按身份判定用 `is_in_array`。
- `gender`、`fear_attribute` 等御主数据字段：糖果仙子、原罪、猎物、恐惧；数值由 JSON 或开局规则写入，不在代码推断。
- `extra_zones:Dictionary`（按名称的独立牌库/手牌/弃牌堆）：月灵髓液、艺术品、记忆、代码、兽、精品、创伤、异闻带事件堆。区域名由卡牌数据声明，搬运全部用 `draw_card_by_card`。
- `command_spell_limit` 已存在：漫长旅途"无上限"改为设大值即可。
- `controller`（缺省 -1）：由 `add_player` 写入。受控条目不进顺位（`get_player_order_ids`）、不进 `get_active_player_ids`（因此不单独行动、不参与终局与高潮淘汰）；战斗与交战判定改用 `GameDataManager.get_board_player_ids()`，胜负按 `represented_id` 落到控制者。
- `phase_as`（缺省 `{}`）：`{实际阶段: [视为的阶段...]}`，由 `GameProgress.effective_phase_names/is_phase_for/effective_phase_mids` 读取；阶段窗口派发、手动能力窗口、常规出牌、部署/移动界面、AI 与"结束行动"义务检查都按它判定。天堂之孔、无极、老虎道场绿 3+。
- `regular_play_zones`（缺省 `["hand_cards"]`）：常规出牌"视为手牌"的区路径列表，`RegularPlay` 的候选、暗置打出与技能区魔力门槛都按它判定。螺湮城（`["discard"]`）。

### 4.2 新时点（只加发射点，不改现有时点）
- 牌区变化：`card_to_hand`、`card_to_discard`、`card_to_deck`、`card_removed`、`card_to_skill_zone`、`card_leave_deck`（含 self_/others_ 前缀）。在 `DrawCardByCard` 等搬运入口统一发射；覆盖瓯、变节、蔷薇的沉睡、瓦伦丁的圣骸布、号角、蓄势。
- 即将发生（可被 `cancel_pending_action` / `edit_pending_action` 处理）：`before_eliminate`、`before_defeat`、`before_card_close`、`before_card_remove`、`before_score_add`、`before_magic_add`、`before_command_spell_add/spend`、`before_situation_activate`。
- 地点：`enter_location`、`leave_location`（现有 `move` 只覆盖常规移动）；覆盖冻土、潜影、周旋、神之遗产、塔塔利、吉娜可。
- 其他：`deck_reshuffled`（创造物工厂、卫宫家今天的饭）、`card_drawn`（变节、流体力学）、`situation_activated`（月光下的华尔兹）、`location_closed`（夏蕾死徒化）、`card_face_flipped`（战型"切换至此战型时"）、`any_survive_elimination`（天从人愿）。
- `effect_start` / `effect_end`：原先只有常量没有派发，现已接入 `EffectManager.activate_effect`。`effect_start` 是"即将发生"时点（`values.effect` 为该效果），监听者可 `cancel_pending_action` 让它不结算（不记为已触发）；`effect_end` 在效果结算完派发，来源对象即该效果。为 effect_start 同步结算时不再嵌套派发。
- 已有且直接可用：`true_name_release`、`command_spell_used`、`card_closed`、`card_revealed`、`battle_win/lose`、`eliminated`、`played_card`、`magic_add/decrease`、`score_add/decrease`、`card_cost_calculated`。

### 4.3 卡牌/地点对象字段
- `_attached_cards:Array`（附属牌，随宿主离场处理方式由数据声明）：临摹、盘、酒壶、征服、叠放、五朔节骑士、宝石魔术。
- `_other_face:Dictionary`（双面卡另一面数据）：供 `flip_card_face`。
- `_alias_names:Array`（"同时名为/视为"）：女神的神核、止境的正义、时代观察、樱之迷宫、游身步；按名称查询的 op 需要同时匹配别名。
- `_text_disabled:bool`（失去文字/封印/覆盖，恢复时清除即可，不删效果）：原稿、死点、苍银之殇、紫苑覆盖、兽性赋予。在 `EffectManager.card_state_allows` 增加一处判断。
- `_counters:Dictionary`：供 `get/edit_object_counter`。
- `_placed_cards:Array`（地点上的放置物）：千年京、星之锚、过负荷、色彩涂鸦、线索、月之湖、螺湮城。
- `_play_source`（本次打出来源：常规/效果/手牌/弃牌堆/牌库）：龙仪巧-DR、创世灭亡轮回、怯懦、诅咒、地狱的单独行动、誓约胜利之木剑。写入 GameLog 的 play 记录即可，用 `query_log` 查询。
- 效果对象 `_disabled:bool`：卢恩魔术选项、他人格反转、回路增强"不能再过载"，用 `set_property` 打开/关闭。

### 4.4 新系统效果类（同 `CannotPlayCardsEffect` 的做法：由入口按效果名查询）
- `CannotUseAbilityEffect`（参数：阶段、属性、明/暗置、名称排除）：二之太刀、金星神、绞首刑之雷、Gandr、冠位·剑。
- `ImmuneToOthersEffect`（参数：来源过滤：他人/非局势/非御主）：守御的创造物、御佐姬、求道者、诅咒、二重存在。
- `PowerRuleEffect`（上限、下限、锁定、取反、"不能被增加/减少"，带来源过滤）：迁延之魔眼、无铭星云剑、酷吏、魔神柱、醉酊、魔力猛攻、左右腕、幡然悔悟。需要在 `EditCardPower` / `EditPower` 内加一次查询（新增可选参数 `source`，缺省时行为不变）。
- `CannotMoveEffect`、`CannotLeaveLocationEffect`、`EnterCostEffect`：天之锁、抹大拉、宿敌、塔塔利、神仆、黑暗。
- `ForbidDrawEffect`（带白名单）：无限剑制、钻石领域。
- 威力来源标记：合计威力增减时附带 source 标签（在 `EditPower` 增加可选参数，缺省为 "effect"），供 `get_player_power_breakdown` 使用。

### 4.5 出牌规则数据
追加打出条件、组合打出（需与某牌一同打出/同名一同打出免费）、额外代价（弃牌/付战果/付令咒/移除宝具/弃标记）、只能以某方式打出、宣言后才能打出，全部写入卡牌 JSON 的打出条件字段，由现有"卡面声明的打出条件"入口判断；支付动作在该卡打出时的效果里用现有原语执行。涉及龙辉巧、雅号·龙纹、幻想崩坏、侵蚀、守护EX、绞首刑之雷、兽、天狼星、生·切断、菩提之叶。

## 5. 重型机制

原列的 10 类机制按"能否用现有 op 组合"重新归类：4 类已挪入 §2，3 类由一个新增 op 加引擎小改动覆盖（已实现），2 类加引擎钩子后可组合（已实现），2 类仍需单独立项。

| 机制 | 涉及卡 | 结论 |
|---|---|---|
| 一名玩家多枚棋子 / 同时在多个战场 | 幻影爱丽丝、达芬奇投影、泽尔里奇第二法 | **已实现**：`add_player(本体id, ["played_cards","score","magic","total_power_bonus"])` + `deploy`。两处威力、地利分别计算，分身胜利的战果与 `battle_win` 归本体；分身不登记效果，能力不会触发两次；"由哪一处发动地点效果"用 `ask_player_option` |
| NPC 参战 | 始皇帝、摩根、妖精骑士、奥伯龙 | **已实现**：`add_player(-2, [], {"power": 14})` + `deploy`；按独立参战者比威力，不进顺位与终局判定 |
| 双御主/双从者切换 | Tiger/Zero、太平之愿、扭蛋女皇 | 挪入 §2（现有 op 组合） |
| 阶段顺序覆盖 | 天堂之孔、老虎道场绿 3+、无极 | **已实现**：玩家字段 `phase_as` 由 `set_player_data` 写入；需在"先出牌后移动"的卡另行组合移动限制 |
| 效果延后到下回合重放 | 信仰的加护 | **已接钩子**：`others_effect_start` 监听 + 条件判断（来源玩家合计威力等） + `cancel_pending_action` + `schedule_effect_on_time_point` 到下回合同一阶段 + `activate_effect(原效果, 原主人)`。被延后的效果对象用 `get_pending_action_value("effect")` 取。"是否影响到你"的目标判定仍需卡牌数据声明 |
| 条件通配（自由决定是否符合条件） | 幻术 | 单独立项：条件筛选分布在各查询 op 内，没有统一插入点 |
| 宣称打出 | 回路增幅 | 挪入 §2 |
| 区域视同（弃牌堆视为手牌） | 螺湮城 | **已实现**：玩家字段 `regular_play_zones`；"关闭时改为洗回牌库"用 `before_card_close` + `cancel_pending_action` + `draw_card_by_card` |
| 效果数值整体倍率 | 姬发流、千年城/血之渴望 | 挪入 §2 |
| 随从玩家 | 特里姆玛乌 | 单独立项：独立区域与代付可用 `extra_zones` + `add_attack` + `edit_magic`，但"其攻击对他人视为对手攻击"需要牌级归属，与 `add_player` 的共享模型不吻合 |

## 6. 结论

- 3310 条代表卡面都给出了实现路径：能用现有 196 个 operation 组合的走 §2，其余依赖 §3 的 20 个新增 op 与 §4 的框架扩展（逐卡归属见明细，没有做精确的比例统计）。
- 现有 operation 一个都不删；§4 的改动只加可选参数、字段和时点发射，默认行为不变。
- §5 的 10 类机制中：4 类改走现有组合，多棋子/NPC/阶段覆盖/区域视同已由 `add_player` 与三个玩家字段实现，效果延后已接 `effect_start/effect_end` 钩子；剩条件通配（幻术）与随从玩家（特里姆玛乌）需单独立项。
