# source_5 Operation 全量审计（2321—2900）

## 范围与结论

- 已按编号逐条阅读 `source_5.md` 的 580 条转写（2321—2900），未按版本、新旧目录或“待加入/待更新”排除。
- 本批只审计现有转写与源码，**未查看或声称查看原图**。19 条转写不足以判断规则，单列为 `unclear`；其余条目均保留逐条语义记录于 `coverage_5.json`。
- 已核对 `assets/scripts/system/operations/` 的现有实现与 `assets/scripts/system/global/all_operations.gd`。`CreateCard.gd`、`BuildCard.gd` 虽为未提交能力，也纳入现有能力：前者按内部名从已加载卡库建牌，后者按完整卡牌数据建牌；二者都只负责构造，不负责放入区域或登记效果。
- 结论不是“每张特殊卡各做一个 operation”。大部分数值、抽牌、移牌、出牌、真名、属性、胜负、时点效果可由现有原语组合。真正缺口集中在：通用选取交互、任意区域/牌堆位置转移、持续标记、规则文本变换、地图拓扑、跨回合任务与替代胜利。

## 已核对的现有原语与边界

| 能力 | 真实源码结论 |
|---|---|
| 数值/比较 | `get_data_number`、`edit_data_number`、`calculate_number`、`compare_number`、`if_func`、`foreach_func` 足以表达多数魔力/战果/威力公式。 |
| 卡牌筛选/移动 | `merge_arrays` + `get_cards_by_*_fr_arr` + `draw_card_by_card` 可处理已知数组之间的卡牌移动；`find_player_array_containing` 可找玩家区域。缺少“牌堆顶/底/任意位置”和“记住原区域后定时归还”的一等语义。 |
| 构造 | `create_card` / `build_card` + `add_to_array` + `register_object_effects` 可覆盖固定牌、临时牌、复制牌的创建流程，故“创造【领域外生命】/【幸运】/临摹”等本身不是新增理由。 |
| 属性/威力/费用 | `edit_card_attributes`、`edit_card_power`、`edit_card_cost`、`zero_attribute_power` 可组合。`set_property` 只在属性真实存在时写值；写成功也不代表战斗结算、UI、回滚、日志会理解该规则。 |
| 时点/延迟 | `schedule_effect_on_time_point` 会克隆 funcs 并一次性登记，可覆盖“下回合获得/归还/失去”等固定时点；复杂的持续任务、次数和暂停恢复仍需状态模型。 |
| 日志 | `query_log`、`sum_log_data`、`log_field_values`、`log_exists` 可查已记录历史事实；若底层未记录“曾到过地点、弃置原因、临时控制者、同一能力连续使用”等事实，单有查询原语无效。 |
| 地图 | 现有 `set_location`、`edit_map_area_*`、`set_map_area_can_move_to`、`set_location_pl_num_limit` 只能改现有对象；无法安全创建/删除区域、边、合并地点或打乱地点顺序。 |
| 真名/换角色 | 真名用 `release_true_name` / `hide_true_name`。换从者/御主应组合卸载旧效果、写字段、登记新效果；换从者还必须 `deal_player_cards`，不是新增角色专用 operation。 |

## 可复用组合（不新增）

1. **移出游戏**：`find_player_array_containing` → `draw_card_by_card` 到对应 `out_of_game` 数组。适用 2431「零次集束」、2518「澪标之魂」、2640「童女讴歌的繁华帝政」、2765「不毁的极圣」等固定来源移除。
2. **同场对手败北**：`get_players_in_same_area` / `get_area_round_participants` → 条件筛选 → `foreach_func(defeat)`。适用 2322「咆哮吧，吾之愤怒」、2478「红莲圣女」、2666「穿刺死棘之枪」、2760「死亡满溢的魔境之门」。
3. **费用/威力公式**：`get_current_round`、印刷值查询、`array_length`、`calculate_number` → `edit_card_cost/power`。适用 2355「阵地建造」、2414「机动圣都」、2527「森罗万象」、2673「巨神之剑」。
4. **创建临时牌**：`create_card`（固定库内牌）或 `build_card`（完整临时数据）→ `add_to_array` → 必要时 `register_object_effects`；结束时 `draw_card_by_card`/移出。适用 2385「空想具现化」、2544「王之歌声」、2641「纵使三度迎来落日」、2690「增殖的创造物」。
5. **条件执行与一次性**：`if_func`/`compare_number` 的 bool 作为后续 `condition`；每局限次用 `used_once_effects` + `is_in_array` + `add_to_array`，不要为每张牌建专用 operation。
6. **换从者/御主**：`unregister_object_effects(旧对象)` → 清理其 buff → `set_player_data` → `register_object_effects(新对象)`；换从者再 `deal_player_cards`。适用 2352「女神的神核」、2733—2737 伪装者形态变化。

## 新增候选（单一职责）

以下是通用原语候选，不是最终实现清单；相同缺口只提一次。

| 候选 operation | 精确卡面编号与卡名 | 现有原语为何不足 | 可与哪些现有原语组合 |
|---|---|---|---|
| `request_choice(options, min, max, visibility)` | 2328「B.B.老虎机」；2406「光之神谕」；2468「阴谋构造」；2733「鲜花战争」；2791「进度如何」；2801「战士之司」 | JSON 控制流能执行已知分支，但没有把合法选项交给指定玩家、支持秘密/同时选择并把结果返回的交互协议。 | 结果交给 `if_func`/`match_func`，再组合数值、出牌、移动原语。 |
| `transfer_card_at_position(source, target, position)` | 2374「决胜截击者」（牌堆顶展示后去向）；2576「蔷薇的沉睡」（置于他人牌库底）；2579「遥远的幻梦境」（牌堆底打出）；2798「重整旗鼓」（牌堆顶三张重排） | `draw_card_by_card/index` 只在数组间移动，未定义顶/底/保持次序/插入位置；`add_to_array` 的索引写法不足以承载跨玩家归属、可见性和日志。 | `get_player_deck/discard/hand`、`shuffle_array`、`get_card_by_index_fr_arr`。 |
| `return_card_to_origin(card)` | 2397「守护」；2462「水边圣女」；2539「色彩的彼界」；2584「遥远的幻梦境」；2773「轻率的偶像失控」 | 暂时移走后必须记住原拥有者、原区域、原索引和状态；当前原语没有统一来源快照，逐卡字段会产生冗余且易错。 | 首次移动仍用 `draw_card_by_card`，结束时由 `schedule_effect_on_time_point` 调用本原语。 |
| `manage_marker(target, marker, delta, visibility)` | 2387「人鱼之肉」【滋养】；2508—2509【灼伤】；2527「森罗万象」【颜色】；2543—2555【Combo/粉丝】；2567【Saber】；2712—2721【检/酷吏】；2830【莲体】 | `set_player_data/edit_data_number` 可硬塞玩家数字，但不能覆盖牌上标记、地点秘密标记、所有者/可见性、随对象离场清理及日志。 | `get_property`/`query_log`/`schedule_effect_on_time_point`；标记产生的具体效果继续用现有编辑原语。 |
| `copy_or_replace_effects(source, target, mode, duration)` | 2351「双重神性」；2482「万能之人（夏）」；2483「于黄昏闪耀」；2524「虚数美术」；2782「炫目的闪光魔盾」；2793「您的稿件已收到！」 | `clone_object` 复制整对象，`set_property` 不能安全迁移 BaseEffect 的来源、触发者、登记状态、持续期及“仅某一阶段能力”。 | `unregister/register_object_effects`、`schedule_effect_on_time_point`、`create_func`。 |
| `set_rule_lock(target, capability, allowed, duration)` | 2340「毗那夜迦」；2368「天之锁」；2395「幽世幻都」；2653「二之太刀」；2688「守御的创造物」；2778「秀美公主的戒指」 | “不能移动/抽牌/用阶段能力/受某来源影响”是结算入口级约束。对对象写布尔字段不会自动让移动、出牌、结算入口遵守，也无法正确叠加多个来源。 | 具体目标由玩家/卡牌查询原语提供；持续期用 buff + schedule。 |
| `edit_map_topology(change)` | 2329「C.C.C.」（两地点合并）；2589「樱之迷宫」（地点顺序随机）；2884「止境的加护（宇宙）」（追加【深空】及箭头） | 现有地图 operation 只能改区域数值、席位和进入开关，不能新增/合并区域、建立有向边、重排版图并保持移动成本。 | `location` 构造地点；现有 `edit_map_area_move_cost` / `set_location_pl_num_limit` 补参数。 |
| `track_objective(key, event, amount, pause_policy)` | 2449「业已无法抵达的理想乡」（移除七张宝具获胜）；2521「零标之魂」（跨回合记录且不可连续）；2564「伦戈米尼亚德LR」（累计移除代币）；2881—2887「星之航海家」（多航线、暂停不重置） | `query_log` 只能查已记录事实，无法统一表达多步骤进度、暂停/恢复、一次完成触发和进度 UI；在每张牌上临时加字段不可维护。 | 日志事件提供增量，`edit_data_number` 存数，达成后 `emit_time_point`。 |
| `resolve_alternate_victory(player, reason)` | 2434「始皇帝」（诏令/持续状态）；2449「业已无法抵达的理想乡」；2564「伦戈米尼亚德LR」；2570「于深渊化作光」；2693「次元超越」 | 现有 `defeat` 只标记败北；没有明确的“直接获胜/替换历史胜者/继续游戏”的胜负结算入口。直接写玩家字段无法更新游戏结束流程。 | 进度判断用日志/计数原语，最终只由该 operation 提交胜负。 |
| `manage_overlay(host, card, action)` | 2387「人鱼之肉」（牌上标记/附属）；2679「绝高无上·谦恭」（创造物叠放）；2737「月之湖」（事件牌作为【星】）；2791—2793【原稿】；2860—2863【盘/概念】 | 数组移动可把牌塞进任意数组，但卡牌对象没有统一附属区、离场级联和归属处理。`set_property` 只有字段存在才写。 | `draw_card_by_card`、`get_cards_by_*`、`register/unregister_object_effects`。 |

## 框架缺口（不应伪装成 operation）

1. **选择 UI 与联网/回放协议**：秘密选择、同时选择、让对手选择、支付后确认，必须在场景/网络层形成可重放输入；operation 只消费结果。
2. **底层规则入口的可拦截性**：移动、抽牌、出牌、使用阶段能力、获得战果/魔力、败北免疫都需统一询问规则锁。仅靠 `set_property` 或 buff 上有一句文字不会自动生效。
3. **日志覆盖面**：候选能力依赖日志记录卡牌从哪个区域移动、移动距离、临时控制权、弃置/移除原因、能力使用、属性变化、进入地点等。`query_log` 不能查询从未写入的事件。
4. **地图模型**：地点合并、版图重排、动态边和新增地点需要地图控制器维护相邻关系、部署位、战斗归属和 UI；不是单次改字段。
5. **胜负状态机**：替代获胜者、直接游戏胜利、阻止淘汰、从桌面移除后回归必须由统一状态机裁决。
6. **附属牌/独立牌堆**：牌上叠放区、专属牌堆、卡牌原位快照和级联清理应成为模型能力。

## OCR / 转写问题

以下仅按现有转写判为 `unclear`，未据此猜测规则或提出候选：

- 2343（吉娜可 URL 图）、2402、2403（卑弥呼 beta 两图）、2498「谴责」、2506（杨贵妃 URL 图）、2522「临摹token」。
- 2529—2533（葛饰北斋五张 URL 图）、2763（罗兰 URL 图）、2811（克莱恩小姐 URL 图）。
- 2890「小王子攻击」、2891「小王子移动」、2892「小王子魔力」、2894「旅行者从者立牌」、2898「背面」。

另有卡背、场地名、身份/牌组构成与 token 等静态素材标为 `non_rule`；其余即使存在符号 OCR 噪声，也在 coverage 中保留原转写，未擅自修正数字或属性。
