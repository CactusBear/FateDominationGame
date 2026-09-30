# source_4 卡面 Operation 审计（1741–2320）

## 范围与口径

- 已依次全文审阅 `source_4.md` 的 580 条转录（1741–2320），当前版、旧版、DIY、阶段卡、Token、素材图均未按版本排除。
- 结论仅基于转录与源码静态核对；**未查看或声称查看原图**。
- 已核对现有 195 个 operation 及 `all_operations.gd`，包括当前工作树中的 `create_card`、`build_card`。
- 能由多个单一职责原语组合的效果不列新增候选；需要底层状态模型、阶段机或多人选择协议的列为框架缺口。

## 结论摘要

本批的普通抽牌、弃牌、出牌、增减资源、真名、移动、属性/威力修改、延迟效果、创建临时牌、从游戏外取牌大多已有组合。高频硬缺口与 source_3 基本一致，并新增凸显了“运行时合牌”“跨形态从者替换”“按力量来源反转/免疫”“任务/好感度进度”和“每阶段触发”的底层需求。

## 新增候选（单一职责）

| 候选 | 精确卡面编号与卡名 | 为何现有原语不足 | 可复用组合 |
|---|---|---|---|
| `get_array_slice(arr, start, count)` | 1745/1748「百花缭乱·我爱你」；1818「天性的肉体」；2057「由一而生的百王子」；2176/2178「无边」；2299「虎啊，煌煌燎燃」 | 动态取牌堆顶 X 张并整体展示/选择时，单张 `get_card_by_index_fr_arr` 与只返回末次结果的循环无法产出窗口数组。 | 后续移动仍用 `draw_card_by_card/index`，排序用 `to_index`，洗牌用 `shuffle_array`。 |
| `sum_property(objects, property)` | 1861「至少，直至死亡的瞬间」（局势魔力总和）；1871「少女贞节」（全场费用总和）；1945「第五盛」（合并牌印刷费用/威力）；2121「五谷礼赞」相关动态牌组 | 现有遍历没有通用累加输出，不能对动态卡组的字段求和。 | `get_property` 取字段；求和结果交给 `calculate_number`、`edit_card_power`、`edit_score`。 |
| `count_distinct_values(values)` | 1802「一期一会」（失去属性种类）；1945「第五盛」（叠加两牌属性并去重）；2258「终末之火2」（基本威力互不相同） | 没有去重集合/不同值计数；用固定五属性分支会写死规则。 | 属性取值由 `get_card_attributes`，威力由 `get_attack_printed_power`。 |
| `round_number(value, mode)` | 1745/1748（初始牌库÷4向上取整）；1818（牌库÷3向上取整）；1884「伤兽的咆吼」（合计威力÷5向下取整）；2059/2062「战术躯体」（反应减半向上取整）；2273「燎原之火」（多处向上取整） | `calculate_number` 的除法不提供 floor/ceil。 | 先用 `array_length/get_data_number/calculate_number` 得原值，再单独取整。 |
| `set_object_effects_enabled(object, enabled)` | 1813「吞噬吾心吧，月光」（把需激活能力改写）；1969/1972「罗生门大怨起」相关保护；2195「幻世隔绝的理想乡」；2249「黄金之杯」；2267「剑士的傲慢」 | 注销已登记 effect 不等于禁止手牌、技能区、关键词和主动能力；清空 `_effects` 也无法恢复。 | 启停后继续复用 `register/unregister_object_effects`，但底层所有发动入口必须查询统一 enabled 状态。 |
| `switch_card_face(card, target_definition)` | 2087「他人格」；2102–2113「封印指定／逆光剑」；2200「梅莉伪装者」；2250「兽之权能」从者替换前后的技能面 | `set_property` 逐字段改写会漏掉图片、effects.from、数字登记、词条、打出限制与当前注册状态。 | 目标定义由 `create_card/build_card` 或现有模板提供；切换只负责同一实例的定义替换。 |
| `invoke_card_effect(card, effect_name)` | 1799「无穷的武炼」（复制攻击能力语义）；2145–2148「火箭飞拳」（每回合两次的反转能力）；2209–2214「女神的神核 I/II/III」（获得基础牌阶段能力） | 广播 `emit_time_point` 会触发其他牌；直接复制 `_funcs` 会绕过费用、次数、反转态、选择与日志。 | 定位后仍走 `BaseEffect` 的标准激活流程与 options。 |
| `get_adjacent_map_areas(area, direction)` | 1783/1786「复仇计划‘狂奔’」；1968/1969「罗生门大怨起」；2020「越过阿卡迪亚」；2093「太岁头上动土」；2315/2318「忘却补正」 | 当前 `move_location` 是带副作用的玩家移动，无法纯查询“相邻”“两者之间”“朝目标一步”或先判断可行性。 | 查询得到战区后，用 `get_move_target_location` + `set_location/move`；人数上限例外沿用 `ignore_limit`。 |
| `change_card_controller(card, player_id)` | 2079「宇宙新阴流·无刀取」；2166「屠戮的福音」；2198「于彼方招手的理想乡」 | 修改 `from` 不会迁移 `played_cards`、威力贡献、触发者与回合结束归还。 | 临时归还用 `schedule_effect_on_time_point`；候选仅做一次一致的控制权迁移。 |
| `replace_player_servant(player_id, servant)`（仅在组合模板难以稳定表达时考虑宏，不建议先加原语） | 2203–2217「埃列什基伽勒」三阶段；2250/2252「兽之权能」替换德拉科；2053「凶兆的产儿」不涉及替换 | 当前已有足够底层原语，但每次都必须按固定安全序列执行，漏一步会保留旧技能/旧牌堆。 | 首选组合：旧从者 `unregister_object_effects` → 摘其 buff → `set_player_data("servant", 新从者)` → `register_object_effects` → `deal_player_cards`。不要新增角色专用 operation。 |

## 优先复用现有组合（不新增）

| 卡面编号与卡名 | 可复用组合 |
|---|---|
| 1745/1748「百花缭乱·我爱你」 | 牌库数组 + `array_length/calculate_number/round_number` → 循环 `draw_card_by_index` 至 out-of-game；为空后 `defeat`。 |
| 1760–1773「黑龙胜利剑／刹那无影剑」 | 出牌次数用 `query_log/log_field_values/array_length`；从手牌/牌库/弃牌堆找牌后 `play_attack`；“移除改弃置”由卡的离场替代效果处理，不造角色操作。 |
| 1844–1848「不死兵」 | `build_card` 或 `create_card` → `for_func` → `add_attack`；临时清理用时点效果。`CreateCard/BuildCard` 已存在，不重复新增 CreateTemporaryAttack。 |
| 1852/1855「极意」 | 标记可放 `player_data` 的通用计数结构；资源增减用 `edit_data_number`，阈值判断用 `compare_number`。 |
| 1955「牛王招雷·天网恢恢」 | 出牌上限用 `edit_data_number("play_limit")`，一张免费牌通过指定 cost=0 的 `play_attack`；次数限制由 effect 自带字段。 |
| 1960「空想具现化」 | `compare_number(score)` + 同场判断 + `defeat/edit_score`。 |
| 1991–1996「十二试炼」 | 胜负日志 + `edit_score` + 将自身搬到 out-of-game；其他同名牌用 `get_cards_by_name_fr_arr` + `foreach_func(edit_card_power)`。 |
| 1998/2000「射杀百头」 | `play_attack` + `for_func`；每次额外使用的费用由 `edit_magic`，不用“射杀百头专用 operation”。 |
| 2005–2007「千里眼（超越）／至高神」 | `edit_card_attributes`；`clone_object` → `add_attack`；从技能区移除后 cost=0 打出。 |
| 2036/2040「万古不变的迷宫」 | 区域封锁若是全局，现有 `add_map_area_buff` + `map_area_has_effect`/`set_map_area_can_move_to` 可组合；按玩家收费的例外仍属框架缺口。 |
| 2054「恶之赌局」 | `random_int(1,6)` + `set_property`/效果值覆盖 + `compare_number`；不新增 RollDice。 |
| 2061–2063「霸王之武」 | 反应计数用 `player_data`，四个选项用 effect options；移动、牌堆顶出牌、免费手牌均有现成原语。 |
| 2078–2081「闪耀于原始宇宙的王冠」 | 各面若建成独立模板，切换候选 + `edit_card_attributes`；抽/打牌/关闭幸运均用现有原语。 |
| 2089/2090「无元剑制／试斩」 | 手/弃/移除区搬运与印刷威力汇总；反转面若是独立 effect，通过面切换统一处理。 |
| 2176/2177「无边／绝剑」 | `while_func` + 抽牌/属性判断/`add_attack`/`edit_magic`；需先用数组窗口或单张抽取保存结果，不新增角色循环。 |
| 2272「忘却补正」 | 监听 `score_add` 日志/时点，`play_attack` 指定两倍费用，随后抽牌。 |
| 2296–2299「岩窟王／心怀希望／虎啊」 | 技能区转移用 `draw_card_by_card`，延迟败北用 `schedule_effect_on_time_point`，按牌库展示循环用 `while_func`。 |

## 框架缺口（不应伪装成一个 Operation）

1. **运行时合牌/拆牌及定义合成**：1945「第五盛」要求两张牌合并成一张同时继承属性、文字、印刷威力、印刷费用并改变消耗。`build_card` 只能吃静态完整数据；`set_property` 无法安全重绑并合并 effects。需要先定义合成卡的数据所有权、effects.from、离场后原牌去向和克隆语义。
2. **卡下附着与放置物**：1779–1781「镌刻/作品」、1800/1805「驹之哀」复制置牌堆顶、2065–2070「红叶狩」、2167「货箱」、2301–2304「地狱之火」。卡下与地图上的非事件对象都缺通用 zone/lifecycle。
3. **按玩家生效的移动限制/收费**：1783/1786、1946「焰色接吻」、2024/2027「万古不变的迷宫」、2247「怀抱溶解的黄金剧场」。`SetLocation` 只认识区域全局 `_can_move_to`、席位上限和 `area_locked`，不能表达“某玩家可付费穿过、某玩家无视、下回合不部署”。
4. **来源可追踪的数值影响**：1889「人类无骨」多倍力量修正；1975–1988「纯粹」屏蔽局势/事件；2118「不死杀手」反转局势/事件修正；2204/2208/2211「太阳黑子」。当前总值/牌威力没有完整来源账本，不能只反转或屏蔽特定来源。
5. **持续免疫、反制和“不能被复制/盗用/无效”**：1841/1842「黄金冲击」、1892/1896「人类无骨」、2157–2164、2195。需要统一的 effect targeting/capability 协议；单写一个卡名判断的 operation 会破坏通用性。
6. **任务/好感度/多阶段进度系统**：2203–2229「兽-埃列什基伽勒」。通用计数可放 player_data，但随机抽任务、任务完成判定、未完成归还、阶段升级、濒淘汰替代需要结构化任务对象和 UI，不能用散落布尔字段拼装。
7. **玩家淘汰替代、继续游戏与胜利改写**：2212「兽之数字」、2257「终末之火」、1793「未亡人」。胜负/淘汰结算需要显式拦截点；`remove_defeat` 或写 `is_out` 不能回滚已执行的淘汰生命周期。
8. **从者/形态替换的完整生命周期**：2203–2217、2250/2252。虽然安全序列可组合，但数据层必须提供目标从者对象及其牌库规则；只 `set_property` 改名称/职阶不成立。
9. **每阶段开始触发**：1801/1804「茶之极致」按“每个阶段开始”询问。若 `TimePoints` 没有统一 phase-start 泛化时点，需要阶段机补齐，而不是为四个阶段复制四份卡效果。
10. **跨玩家临时借牌、归还原持有者弃牌堆**：2121「五谷礼赞」、2257/2258「终末之火」。现有卡的 `from` 同时承担来源/所有者语义，借出后归还需要明确 owner/controller 分离。

## OCR / 转录问题

- 明确无文字或无法识别：1814、1851、1862、2030–2035、2051、2060、2091、2154、2161、2171、2232、2234–2244。
- 仅有占位词/牌背/素材字样，按 `non_rule`：1949「NO」、1952「YeS」、2010「1」、2029「狂怒」、2082/2100/2135「Skill」、2137「Attack」、2229「☆」。
- 1905 仅识别为“R 米”，无法确定是否纯素材或规则，记为 `unclear`。
- 复杂版式或文本明显截断，机制可见但实现前需核原图：1779–1781（雕像少女括号反效果）、1945「第五盛」、2014「暗天蚀射」（末句截断）、2039/2042/2043/2046「迷宫的怪物」、2209–2214「女神的神核」、2230/2249「黄金之杯」（引号/末句缺失）。

## Coverage

逐条状态与机制标签见 `coverage_4.json`。所有 1741–2320 的编号各出现一次；状态仅为 `analyzed`、`unclear`、`non_rule`。
