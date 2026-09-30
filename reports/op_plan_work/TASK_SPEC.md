# 分片任务说明（每个子代理只处理自己的 chunk）

## 输入
- 卡面分片：`E:/Projects/Godot/FateDominationGame-master/reports/op_plan_work/chunk_<N>.md`
  每条形如 `### U<首编号> ids=[...]`，下接 `path:` 与卡面 OCR 原文。ids 是原文完全相同的重复卡，合并成一条分析即可。
- 引擎上下文与现有 operation 全表：同目录 `engine_context.md`（必须先完整读完）。
- 需要核实某个 operation 的具体语义时，可以读源码 `E:/Projects/Godot/FateDominationGame-master/assets/scripts/system/operations/<PascalCase>.gd`，或同目录上一级的 `global/*.gd`。只读，不许修改任何文件，只写下面的输出文件。

## 要做什么
chunk 里的每一条 U 都要分析，不许跳过、不许抽样；不区分新旧版本和 DIY。对每条：
1. 把卡面拆成原子机制（触发时点、条件、选择、动作、持续期、清理）。
2. 先尝试用**现有 operation + 效果 JSON 字段（options/select_*/schedule_effect_on_time_point/buff 等）组合**实现。能组合就写组合，不许为了省事新增。
3. 确实无法组合的，才提出新增 operation。要求：
   - 单一职责，一个 operation 只做一件事（例如「获取事件牌堆」与「插入牌堆」必须分开）；
   - 参数由调用方传入，不写死职阶名/牌名/数字/区域名；
   - 尽量不改、不删现有 operation；如果必须改现有系统（加字段、加时点、改结算器），单独标成「框架改动」，不要伪装成 operation；
   - 优先复用下方「候选名单」里的名字与签名；名单里没有合适的才起新名字（snake_case），并给出签名。
4. OCR 残缺/看不懂的，写清哪部分无法判断，仍然分析能看懂的部分。纯头像/职阶卡（只有数值行，如 `Saber 伊阿宋 米 2,3,3 ...`）标 `form=从者/御主本体数据`，new 为空。

## 候选名单（优先复用，签名可以补充参数，但要说明理由）
- get_event_deck() / get_event_discard() / get_situation_deck() / get_situation_discard()：返回 MapData 对应数组（只读取，不移动）
- get_map_areas()：全部战区
- swap_array_items(arr_a, index_a, arr_b, index_b)：两个数组指定位置互换
- switch_card_face(card, face_data)：同一实体切换正反面/另一形态
- attach_card(host_card, card) / get_attached_cards(host_card) / detach_card(host_card, card, to_arr)：叠放在牌上的附属牌
- add_card_effect(card, effect_data) / remove_card_effect(card, effect_name)：给牌附加/移除一条效果
- invoke_card_effect(card, effect_name, ignore_cost, ignore_phase)：让指定牌的指定效果再发动一次
- set_card_controller(card, player_id)：控制权转移（盗用）
- swap_player_locations(a, b, is_move)：两名玩家同时交换位置
- set_battle_winner(map_area, player_ids) / resolve_battle_now(map_area)：改判胜者 / 立即结算指定战场
- finish_game(winner_ids)：立即结束游戏并指定胜者
- eliminate_player(player_id) / restore_player(player_id)
- grant_visibility(cards, viewer_id, until_time_point)：让某玩家能看到一批牌
- reveal_cards(cards)：展示（全员可见）并派发 card_revealed
- set_player_order(player_id, position)：把某玩家顺位设到指定位置
- add_extra_turn / skip_phase(player_id, phase)
- add_map_area / set_map_edge 等地图拓扑改动

## 输出（两份文件，写完才算完成）
1. `E:/Projects/Godot/FateDominationGame-master/reports/op_plan_work/result_<N>.jsonl`
   每条 U 一行 JSON：
   `{"u":首编号,"name":"卡名","form":"实现形式一句话（触发时点+效果骨架）","reuse":["现有op",...],"new":["新增op名",...],"framework":["框架改动简述",...],"note":"OCR 问题或规则疑点，可空"}`
   行数必须等于 chunk 里 `### U` 的条数。写完用程序数一遍再结束。
2. `E:/Projects/Godot/FateDominationGame-master/reports/op_plan_work/summary_<N>.md`
   - 本分片所有新增 operation 的去重清单：名称、签名、单一职责说明、为什么现有组合做不到、引用它的 U 编号（全部列出）；
   - 本分片所有框架改动的去重清单，同样列出 U 编号；
   - 3~6 张最复杂的卡的详细拆解示例（JSON 骨架级别即可）。

全部用中文。最终回复只报告：条数核对结果、两份文件路径、新增 op 名列表。
