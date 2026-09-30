# 第 1 批（read_01，U1–U465）逐条结论
格式：U编号 名称：实现形式 ｜ 需新增 op（N:）/ 框架改动（F:）。未写 N/F 的表示现有原语可组合。
代号见 catalog.md（写完全部批次后统一）。

1/2/7 阿塔兰忒/赫拉克勒斯/美狄亚(派遣)：派遣=切换此牌→get_map_data_value(event_deck)→random_int(0,9)→draw_card_by_card 插入；事件抽取时识别派遣面→切回→add_attack 给伊阿宋→add_event_from_deck 补事件；美狄亚+4 用 schedule(day_start 下回合)+edit_data_number(total_power_bonus) ｜ N:get_map_data_value, switch_card_face  F:事件抽取遇"非事件牌"替代抽取(F-事件抽取钩子)、card_drawn_from_event_deck 时点
3 撕裂天际的光辉之船：每局一次；select_cards 从 event_deck 里挑自己派遣的牌→play_attack(ignore min_magic)；其余 draw_card_by_card 回技能区→shuffle_array ｜ N:get_map_data_value；select_cards.source 需支持 MapData 数组(F-选牌来源可为任意数组表达式)
8 美狄亚-派遣(卡背面)：同 1 的派遣面数据 ｜ F:事件抽取钩子
11 妖精剑卡文汀：self_battle_phase_start；get_cards_by_name_fr_arr(played)+array_length→if→close_card
12 捕食日轮之角(新)：select_cards(played,name=狂战士,max3)→draw 至弃牌→for each：build_card(基础攻击，威力=印刷-5)+add_attack，临时=schedule day_end 移出
13 福尔·韦瑟(新)：cost 3；reveal 牌库顶3→移出；filter 基础/非基础计数→edit_magic、同战场对手 edit_score；out_of_game 取对应属性狂战士→draw 入 deck→shuffle ｜ N:reveal_cards
18 捕食日轮之角(3.2)：残留 X=9，day_end edit_card_power -3，≤0 close_card；圣者的数字：select 基础攻击→复制"印刷-1 的区特殊基础牌"名称与效果 ｜ N:add_card_effect；set_property(_name/_shown_name)
19 捕食日轮之角(旧)：同上，效果授予需条件判定 ｜ N:add_card_effect
20/22 野性法则：给非技能牌授予"强食"效果；狂化=day_end 按日志找因强食打出的牌→build 狂战士/基础牌替换(draw 原牌移出+新牌入场) ｜ N:add_card_effect
21 福尔·韦瑟(旧)：reveal 顶3→对每张 ask_player_option 二选一→替换并弃置/打出 ｜ N:reveal_cards
23 坏劫之天轮：OCR 选项缺失；前哨 options(未被选择过的项 max_uses=1)或 close_card；"不会因切换失效" ｜ F:切面保留效果声明
24 破灭之黎明：need_extra_play；log_exists 用过天轮→豁免 min_magic；edit_card_attributes 取已选龙心属性(log_field_values)
26 绿龙之心：remove_from_board→deploy(select_location forbidden 魔术工房) ｜ （remove_from_board 需能在行动阶段调用，核对）
27 蓝龙之心：战力结算时只计此牌 ｜ F:合计威力口径开关(player_data "power_only_cards")
28 黑龙之心：get_players_in_same_area→foreach played_cards 过滤本回合打出+非技能→close_card
29 青铜龙之心：log 查"以移动进入该战场"人数×2 → 个人地利 ｜ F:个人地利加成字段(location_benefit_bonus)
30 红龙之心：draw 1；select_cards(hand,max_power 3,max 3)→add_attack
31 龙种改造：首次使用天轮时移除此牌；ask 选4个龙心→授予天轮 ｜ N:add_card_effect
33/38 云耀：立即结算自己战斗→弃事件→参与者移出版图→地点禁入 ｜ N:resolve_battle_now  (之后 set_map_area_can_move_to、remove_from_board 复用)
34 阴阳螺旋：select 两张(一暗一明)→play；战斗阶段 set_card_concealed(阴,false)+close_card(阳)+支付阴费用+发动阴的行动阶段能力 ｜ N:invoke_card_effects
35 空之境界(新)：release 状态下 +3；reveal 交战对手牌库底→比较印刷威力→defeat 或 edit_power ｜ N:reveal_cards
37 空之境界(旧)：同上 + "一同打出的另一张 -3 费用" edit_card_cost
40 对魔力(3.6)：played_cards 取宝具最高费用 get_extreme_by_property→edit_score；zero_attribute_power(对手,[magic])
41–45 旅程事件(阿瓦隆/卡姆兰/卡美洛/廷塔杰尔)：使命判定 battle_end→切换至下阶段；阿瓦隆 V 立即胜利；卡美洛进入需条件(禁止进入除非付费) ｜ N:switch_card_face, finish_game  F:进入战场前置条件(move_requirements)、局势牌豁免宝具禁令字段
47 星与誓约之剑：log 统计真名解放从者数→min 12→edit_card_power；战力结算条件 total_power_bonus
48 耀眼的旅程：从任意位置把旅程事件放到战场 ｜ N:get_map_data_value；find 事件位置 F:全局牌区查询(find_card_zone)
51 对魔力(旧)：zero_attribute_power
52 契约胜利之剑：select 技能→移出游戏→edit_card_power/cost 永久
53 风王结界(旧)：禁止真名解放 ｜ F:player_data "true_name_release_locked"；zero_attribute_power(对手,[strength])
55 草那艺之大刀：battle_end 对每名败者 select_cards(owner target,played 基础)→移出游戏，标记为【鳞】(set_property tag 或 edit_card_attributes 添加 tag) ｜ 用 tag 标记即可
56 草那艺之大刀(初始)：battle_end 自身+弃牌堆至多3张移出为鳞；"作为鳞进弃牌堆后变为非技能牌并失去效果" ｜ N:switch_card_face(或 remove_card_effect)
58 鬼神之种：others_played_card 同战场+属性匹配鳞→draw 鳞至弃牌→close_card 对手牌
62 无穷的武练：select 手牌→play_attack→clone_object→add_attack 临时
63 过重湖光：前哨 edit_magic；battle_win edit_score
64/70 入阵曲：改写魔性之貌效果 ｜ N:remove_card_effect, add_card_effect
65/68/73 隐美假面：残留保持真名隐藏(禁止解放)；每回合一次关闭+release；打出时不受他人能力影响 ｜ F:真名解放锁定、他人能力免疫(ability_immunity)
66/69/74 魔性之貌：battle_resolve 对手 select_cards(owner 自选,非残留)→close_card；day_end edit_magic -2 / 不付则移出(ask) ｜ （对手自己选择：select_cards 需由目标玩家作答 F:选择答复者可指定为目标玩家）
71 入阵曲(旧)：foreach 统计威力低于/暗置/本回合被关闭→edit_card_power（本回合被关闭用 log）
75 魔性之貌(diy)：条件豁免 min_magic；战斗阶段威力=未用特殊牌玩家数×5 (log)
76 隐美假面(diy)：可追加打出；残留同威力判断 total_power_bonus；前哨关闭→打出指定技能；本回合禁再打出(play_requirements) ｜ F:play_requirements 新类型"本回合未被关闭过"
77 兰陵王入阵曲：前哨 同战场其他玩家 edit_data_number(play_limit,-1) + 到期恢复；魔性之貌威力翻倍 edit_card_power
79 病弱：合计威力变0 ｜ F:合计威力设为0(total_power_override)；"被移除游戏时改为弃置" F:离区替代钩子；手牌强制展示 N:reveal_cards
80/83 绝刀：交战时自动 reveal→add_attack→draw；战后弃置；替代规则同上 ｜ N:reveal_cards F:离区替代、手牌中效果监听(hand zone 效果登记)
82 无明三段突：build_card×2(4 迅捷)→add_attack 临时
84 誓言的羽织：公开手牌至回合结束 ｜ N:grant_card_visibility  (合计威力+3、battle_start draw 复用)
85 诚之旗：options max_uses 3 reset each round：select hand→play_attack(明置)→draw
86/91 黄之死：演说 others_battle_win 且持有煽动 buff→manage_buff+edit_magic 双方；-4X
89 我来我见我征服：need_extra_play；局势牌豁免 ｜ F:局势牌禁令豁免字段；对手 edit_power -=煽动层数
90 煽动：每层+1 合计威力(power_query 或 total_power_bonus)；day_start 全场层数≥12 切换 ｜ N:switch_card_face
95 日角之相：弃幸运；同战场对手本回合禁用战斗阶段能力 ｜ F:能力禁令(ability_ban 按阶段)
96 昆阳赤霄：+事件战果和；局势牌搬到战场视为事件 ｜ N:get_map_data_value F:局势牌作事件时力量修正作用域
97 无元剑制：本回合唯一出牌 ｜ F:play_requirements 类型"本回合唯一"；X=胚印刷威力和；day_end 关闭胚(不可阻止 F:不可反制标记)
98/106 试斩：reveal 顶3→非特殊基础 add_attack 其余弃→+3/张；被动：关胚→从手牌打出特殊基础 ｜ N:reveal_cards
99/103/104 刀剑审美：给胚/非特殊基础授予效果；失效时关闭所有胚 ｜ N:add_card_effect F:"此牌失效"时点(card_invalidated)
109/115 八岐怒涛：quantity_range 选 X；分配浪标记给多名玩家(总量≤X) ｜ F:分配式选择(select_players 带数量分配)；power 减益 by buff 层数
110/116 天丛云：常规出牌后授予其他常规出牌的属性(edit_card_attributes)；battle_end 移出战场被放置牌+事件 ｜ N:get_map_area_placed_cards
119 二天一流：按境界层数判断→total_power_bonus/edit_card_power 翻倍
120 俱利伽罗天象：battle_win 加境界，每回合≤3（log 计本回合已加）
124/125 予人以爱：唤醒后加入攻击回合结束入技能区；"因御主影响提升的合计威力翻倍" ｜ F:威力来源分项(modifier 来源标签)
126/127 予地以花/予天以星：事件牌/局势牌提升的威力翻倍 ｜ F:BoardPowerQuery 按来源倍率(player_data board_power_multiplier)
128 白蔷薇姬-未唤醒：展示时唤醒并切换，抽替代 ｜ N:switch_card_face F:事件/局势抽取钩子
130 月桂树之戒：ignore min_magic 对从者技能；授予"可追加打出" ｜ F:min_magic 豁免字段  N:add_card_effect(或 set_property _need_extra_play 允许)
131 白蔷薇的誓言：out_of_game 三张分别洗入局势牌堆/事件牌堆/自己牌库 ｜ N:get_map_data_value
132 终幕蔷薇：从任意处打出三张，回合结束回原位 ｜ F:find_card_zone(全局) N:get_map_data_value
136 皇帝特权：change_pl_order(set_order 1 或 末位) 复用
137 黄金剧场：残留 battle_win edit_score(生效后回合数=当前回合-日志记录回合)
138 陨铁之(尼禄)：draw2 select 不同威力→add_attack；剩余手牌移出
139 夏日午夜的侧面：熬夜 buff；局势包含魔力0→set_card_power 0 加入攻击 且豁免局势禁令 ｜ F:局势禁令豁免(card 级)
140 巴渊太阳剑：quantity X 0~3 付费；reveal 对手库底 X 张→弃→同属性数 -1 基础地利 ｜ N:reveal_cards F:个人地利加成字段
141 VR新阴流：查看双方库底 X+1 张→逐位交换 ｜ N:grant_card_visibility, swap_array_items
144 吞天食日：残留；进工房关闭；行动阶段开始抽2，仅可打这2 ｜ F:出牌白名单(play_whitelist)；弃特殊→打技能 -2 费
145/149/152 魔性束缚：区域间移动禁止 ｜ F:移动禁令(move_bans:{from,to})；对手"使用过行动/战斗阶段能力的攻击"威力设0 (log 查效果来源卡) N:set_card_power_zero? → 复用 edit_card_power(负自身威力)
146/148/151 捕食日轮之角(巴格斯特)：select hand max3 reveal→求和→edit_card_power ｜ N:reveal_cards
153 穿刺之雷刃：移动不可被阻止 F:move 阻止豁免；电荷放置给相邻地点玩家 ｜ N:get_adjacent_locations；能力禁用 F:能力禁令
154 夏日电疗：电荷=buff；强制移动至相邻 ｜ N:get_adjacent_locations
155 适度负载：收回 X 电荷 quantity → total_power_bonus
161 厄运：被动 败北时从手牌弃置→edit_score+同战场 defeat ｜ F:手牌区效果登记(zone 可监听)；打出时 draw、败时洗回
162 拒绝王国：others_move 进入你战场→play 一张并 invoke 其行动阶段能力(威力减半) ｜ N:invoke_card_effects；move 对手至相邻 N:get_adjacent_locations
166 终焉：本回合不会被淘汰 ｜ N:add_extra_round  F:淘汰豁免字段(elimination_immune)、局势指定
170 无形：条件 zero_attribute_power；付3 更换属性重复一次(ask)
171 诚之旗(斋藤)：draw2 reveal 手牌→免费打出基础力量/迅捷→关闭 ｜ N:reveal_cards
173/177/180 五德之鸟：随机获得每名其他玩家一张手牌，可打出，回合结束返回所有者弃牌堆 ｜ F:卡牌所有者字段(_owner_player)  N:get_card_owner  ；"不能同其他牌一起打出" F:play_requirements 唯一；飞影禁常规移动进入 F:移动禁令
175/176 倚天剑：对手 ask/select 手牌 reveal+弃→edit_card_power ｜ N:reveal_cards；答复者为对手 F:选择答复者
179 乱世之奸雄：battle_resolve 统计交战他人→total_power_bonus
181 超世之英杰：获胜后切换；day_end 统计未交战者 edit_score ｜ N:switch_card_face
184 勇往直前：威力即将被降低时改目标 ｜ F:数值变更替代事件(reaction/replacement)；付地利位置魔力使对手失去位置并重新部署 (set_location/deploy)
185 旭将军：授予"唯一可追加打出"；局势/事件修正三倍 ｜ N:add_card_effect F:board 倍率
189 吾转瞬即逝的荣光：X=14-2回合；局势/事件修正翻倍/高潮三倍 ｜ F:board 倍率
190 十二辉剑：胜利时事件洗回事件牌库；抽事件加入战场→属性授予 ｜ N:get_map_data_value
192/196 无刀取：选属性授予；破绽改为加入攻击→回合结束回原所有者弃牌堆 ｜ N:get_card_owner
193/195 新阴流·水月：quantity X 费 2X-1；reveal 任意玩家库底共 X 张→同属性作破绽弃置→按属性种类 -3 ｜ N:reveal_cards
194 新阴流·通透：他人效果即将弃置/移除/入区时付3 无效 ｜ F:效果替代/免疫询问；查看同地点玩家牌库 N:grant_card_visibility
198 凡性之赠：打出卡斯托耳攻击(tag)；授予基础攻击每局一次 N:add_card_effect；select deck/discard→hand
199 双神的神核：牌分属波鲁克斯/卡斯托耳(tag)；常规出牌组合约束 F:常规出牌组合规则(play_requirements 组)；力量修正两倍 F:board 倍率
200 双神赞歌：弃置→按 tag 批量 edit_card_power
202/207 十王判决：条件控制两牌→付7 加入攻击；居合=按控制牌授予对魔力效果 ｜ N:add_card_effect；日志统计以从者技能令他人获得魔力 sum_log_data
203/206 阎魔亭：游戏开始在牌堆顶(initial_zone)；放置于地点不视为攻击；该地点玩家获魔力时随机弃手牌+2 威力 ｜ N:get_map_area_placed_cards F:地图放置物(placed_cards) 与其效果登记
204/205 拔刀术一/二：打出时同战场 edit_magic；居合授予气息遮断/单独行动效果 ｜ N:add_card_effect
209/212 魔力放出：quantity X 付费→+2X；战败恢复一半(schedule battle_lose, 不可阻止)
214 隐藏不贞的头盔：hide_true_name；关闭本牌打出另一张并使用其行动阶段效果 ｜ N:invoke_card_effects
216 守护的誓约：弃1→+2；本回合多个区不受他人能力影响 ｜ F:他人能力免疫(按区)
219 银之臂：reshuffle 时点监听→-1 合计威力永久；牌堆≥2 移出→加入攻击 ｜ F:reshuffle 时点(deck_reshuffled)
220/223 圣人交叉拳：关闭礼物追加打出；关闭任意张自己攻击→按和关闭一张对手攻击
221/225 对魔力(圣诞)：out_of_game 礼物(无限库存)create_card 洗入同战场他人牌库
222/224 圣人连续拳：唯一出牌；礼物被拆开时+2(played_card source 礼物)；从手牌与牌库打出≤6 张迅捷基础
227 百合花开：格挡=弃1 关闭同威力对手本回合攻击+3；额外两次=max_uses
228 百合飞散：魔力<8 多付1 可打 F:min_magic 替代支付(pay_to_ignore)；无格挡则关闭(log)
229 自我暗示：性别视为 F:性别查询覆盖；select_cards(owner target, hand) 弃→+威力
231/232 三千大千世界(铃鹿旧)：抽3 事件选任意→战力结算视为受影响 ｜ N:get_map_data_value F:远程受事件影响(将事件效果/power_query 登记给玩家)
233 天鬼雨(旧)：魔力上限-1 F:个人魔力上限；clone 此牌 add 每局一次
234 才智的祝福(旧)：魔力超上限时 F:魔力溢出时点；宝具用后授属性；关闭攻击增加上限
236/240 三千大千世界(新)：永久 +1 费；reveal 顶3 弃→有4威力→+费用 ｜ N:reveal_cards
237 天鬼雨(新)：【才智】buff 花费；从弃牌堆打出 3+X 基础；战后洗回牌库
238 才智的祝福(新)：reshuffle 时 +1 才智 且保留 3 张 F:reshuffle 钩子(可指定保留)；无视败北(defeat 豁免 F:败北豁免字段)
243 誓约胜利之剑(阿尔托莉雅)：高潮 +4；赢第11回合战斗→获胜 ｜ N:finish_game（或 victory_override）
245 风王结界：真名隐藏时 -2 费；zero_attribute_power strength
246/254 花之旅途：4 次上限 options；draw→play 非幸运威力减半
249/251/253 必胜黄金之剑：王之印记 buff；+3X/费用+X
255/259 誓约胜利之剑(Alter)：局势豁免；连续打出回合数(log) ×3 ｜ F:局势禁令豁免(card)
256/260 黑化诅咒：用宝具时关闭；魔力<8 同战场对手禁宝具 ｜ F:能力/出牌禁令按属性与目标(可用 ForbidNoblePhantasm 扩展到按玩家)
262 偶像失控：询问他人付费否则只在战力结算视为原地 ｜ F:效果目标询问/位置视为；幸运移出→clone 本牌
263 威风凛凛的凯旋：移出手牌付费→选属性→全部攻击 edit_card_attributes
264 侥幸的拘捕网：单对手时选其攻击关闭或付费盗用至回合结束并发动行动效果 ｜ N:set_card_controller, invoke_card_effects
266/269 军神之剑：技能费用-事件最高战果(edit_card_cost)；攻击不可被关闭/减威力 F:保护标记(card_protection)；放置泪之星 ｜ N:get_map_area_placed_cards
267/271 泪之星：放置后下回合在此战斗时加入攻击并真名解放；战后移出、该地点改用文明废墟事件牌堆 ｜ F:战区专属事件牌堆(event_deck_override)
273/282 星之纹章：每回合一次事件改从文明废墟堆抽 F:事件抽取来源替换钩子；回合结束移至独立弃牌堆
275 妖精羽翼·泪之星：保护标记；技能牌 +X
277–279 文明废墟三张事件：power_query 按印刷威力≥5+属性 +4（现有 power_query 可表达）
283/284 13号星期五：降临者身份 F:玩家身份标签(roles)；残留攻击+3 费 edit_card_cost/attack_cost_discount；为前两位 build 领域外生命 add_attack
285 堕落的授职：劝诱标记 buff；下回合降临者身份
286 巡礼之旅：前置关闭；控制非幸运特殊攻击者 -5
289 圣者的数字(高文)：事件展示后弃同属性手牌→事件+3 战果(edit_map_area_score 或事件 score)；基础威力3 ×3
291 轮转胜利之剑：前哨+3魔+3；未打出则 day_end 失去所有魔力
293 幻想大剑：reveal 手牌→计数 ≥4→+2 (max6) ｜ N:reveal_cards
294 恶龙之血铠：对手移动进入时关闭(others_move + 同区判定)
295 隐身衣：失去 X 战果(log 次数)；隐藏真名至回合结束；不受同地点他人能力 F:能力免疫
298 坏劫之天轮(旧)：展示后每回合 -1 战果；授予基础牌效果 ｜ N:add_card_effect
299 破灭之黎明(旧)：battle_end +对手一张攻击费用(select owner target played)
300 里迪尔·赫萝蒂：need_extra_play；展示事件后获得属性(card_revealed 监听)
301/467/471 变容：叠放基础攻击；投影顶牌数值/效果；弃置叠放牌→属性授予 ｜ N:attach_card, get_attached_cards, detach_card F:附属牌数值/效果投影
302 天之锁(界)：束缚 buff；宝具威力0且只能打出 F:能力禁令
304 战斗续行：select_location forbidden 魔术工房 + set_location
305 怡赫季斯之夜：音量 buff×3 total_power_bonus(max15)；战败 -3
306/313 龙鸣雷声：交战人数加音量；未参战 -1
307/310 拷问技术：战果比较→费用-2 或 play_requirements(对手战果低) F:play_requirements 新类型(自定义查询)；battle_win 按战果最低败者扣分
311 拷问技术(旧)：敌方女性从者 F:性别查询；击败倒数名次 get_rank_by_data_number
312 鲜血魔女：本战场无地利(no_location_benefit 系统效果挂区域 buff)；音量×3
315 海神的偏爱：技能区时移动不受限制 F:移动禁令豁免；残留改名/性别 set_property；前哨关闭+3魔 本回合禁再打出
316 大海啸：与侦查玩家交换位置视为移动 ｜ N:swap_player_locations；-X by 地利
317 金色大翼：移动任意地点；+9 另一牌；+5 失去地利 F:个人地利字段
318/321 殿军的矜持：可暗置打出雄叫(set_property)；付三倍费激活暗置牌并使用其行动能力 ｜ N:invoke_card_effects；方阵+3 基础地利 F:个人地利字段
319 战士的雄叫：select 对手攻击→下回合 total_power_bonus
322 炎门守护者：同战场每人每回合只可打出1张明牌 F:play_requirements(按区域玩家生效的出牌限制)；移动时关闭
323/331 骑士的枪：以弃一张魔术基础牌为打出代价 F:额外打出代价(play_costs)；付 2 战果→授属性+威力，回合结束移出
324/327/329 变身戒指：battle_win release+score；打出时 hide；付费移动至相邻 ｜ N:get_adjacent_locations
325/328/330 狂暴少女狼：按对手数 draw→play；暗置打出时 edit_map_area_score -1；计数累积 buff
333 火尖枪：移动至战场；地利减至0 至下回合结束 edit_location_benefit+restore；燃烧 buff
334 如来的加护：三选一；攻击威力不会减少 F:保护标记；无视败北 F:败北豁免
335 道术：燃烧 buff 与 -2；battle_win 条件 +2；清除
336/339 花开冥界：放置冥界佑护于战场 ｜ N:get_map_area_placed_cards
337/344 冥界佑护/灵峰踏抱：本战场局势/事件修正 ×-1 F:board 倍率按战区；部署时 +1魔；回合结束回技能区
341/346 隐藏的大王冠：常规打出的特殊属性牌改名【远隔操作】并授予效果 N:add_card_effect；关闭+重新部署
347/350 献给公主之枪：战败永久 +3 费与威力(max+12)；独自在战场获得竞争战果(get_map_area_score+edit_score)
349 流浪骑士的大冒险：battle_win 按事件印刷战果调整
352 桑丘·潘莎：冒险=事件洗入事件牌库前2张 N:get_map_data_value；不能被关闭 F:保护标记；不受他人能力 F:能力免疫
354 流浪骑士的大冒险(事件)：出场再抽一张；进入弃牌/移除改为洗回事件牌堆 F:离区替代；战果+1
363 向心爱的公主献上：条件翻倍
366 此间凄然：对手宝具失去所有文字至战斗阶段结束 ｜ N:set_card_text_disabled
367 女神变生【天】：抽/魔/威/地利/打出/移动；下回合 cannot_play + 禁激活能力 F:个人地利字段、能力禁令
368 常夏日光：真名隐藏或性别不配 F:性别查询
370 盛夏咒术：授属性；魔术攻击保护 F:保护标记
371 佩里舞者(3.5)：进入侦查立即结算侦查战果 F:立即结算区域战果(或 resolve_battle_now 复用)；沿箭头移动至多3步 move 复用
372/373 光之地平线：切换；翱翔豁免局势事件禁令；选一处战场，战力结算若更高则取代胜者 ｜ N:switch_card_face, add_battle_winner_override  F:胜者改判；跨越：log 与所有人交战过→release→set magic 满
375 无人知晓的无垢搏动：经过所有地点(log move 路径 F:移动路径日志)；打出时 draw+play≤3；特殊+3
376/381 尚未知晓的无垢湖光：移动过→基础威力翻倍；clone 临时 / 变为此牌复制 ｜ N:switch_card_face(变为复制)
377 佩里舞者(diy)：无视限制移动 F:移动禁令豁免参数
378/379 光之地平线(diy)：切换两牌；未打出失去所有魔；临时复制；龙之心 +3 费威；仅打出特殊则追加一张(edit play_limit)
382 无垢搏动：同 372 胜者改判 ｜ N:add_battle_winner_override
383 佩里舞者(3.2)：move 过则 draw+play≤3
384 未能回归于星的龙：进入侦查加入攻击→+4魔+2分→移动→战后 -8
385/387/391/396/400 龙之心：赢且对手有同属性更高攻击→战后 -3/-4/-2
386/392/398 炎之灾厄：每回合首次移动后 +距离永久 (move 日志距离)
388/394/397 梅柳齐娜技能合集：光之地平线=战败展示→再次战败换从者阿尔比恩之骸 (换从者组合 unregister/set_player_data/register/deal_player_cards) ｜ N:reveal_cards；"不能复制或盗用" F:不可复制标记
403 先之先(3.6)：付2 立即部署；该战场禁止进出 F:移动禁令；顺位第一 get_phase_order→play
404/407/409 胧里月十一式：反制=对手出牌后打出同威力手牌(others_played_card)；初见杀=log 判首次同场→免费打出(cost 0)；画地为牢 F:移动禁令
408 先之先(旧)：同上
413 直至死亡拆散两人：爱人同场→属性替换+费/威翻倍 F:从者关系标签(lover) 用 set_player_data 自定义键即可
414 英雄的伴娘：付令咒；选从者为爱人(set_player_data)；爱人获胜时 +1/+3 (others_battle_win 过滤)
420 白羽骑士：属性互授；非追加打出时移动(log play extra=false)
421 闪光魔盾(3.0)：本回合被减少威力 > 一半→眩晕 buff F:威力变化日志(减少来源)、能力禁令(从者技能)；对手迅捷 -5 modify_attack_power_by_attribute
424 闪光魔盾(旧)：同属性攻击威力无法被局势/事件增加 F:board 修正豁免；付4 release+打出基础
425 秀美公主的戒指：对手使用技能时询问付2 否则不受影响 F:效果目标询问/免疫；关闭费用为 X 的魔术攻击
426/430 女王城塞：quantity X；残留其他攻击 +X 费/+X 威 ｜ N:add_card_effect(授"魔铠")；移动 X 步 move
428/432 贞淑的美德：幸运放置入场 +1 魔；特殊攻击同时名为幸运 F:多名称(card aliases)；无视败北 F:败北豁免
429/433 魔风呐喊：免费打出→回合结束关闭铠壳；威力低于费用的对手攻击设0
434/435 迦摩之灰：release 时 draw3；手牌上限+1(refill_hand limit 数据字段) F:个人手牌上限字段；淘汰预判 get_rank_by_data_number 与人数
437 知恋不为：select≤3 基础→若3张魔术则战斗阶段 defeat 一名交战对手
438 虚数环：打出 draw 可弃；弃牌堆 3 张基础洗回→属性判定→+4 或移动
439/444 无穷的教诲：对手打出基础攻击→教诲 buff；花 3 打出技能牌；battle_start release
440/445 炫目的选定之枪：release 后获宝具属性且费/威翻倍；使以移动进入者败北(log move)
446 二重拘束：激活枪的某效果至回合结束/至战败 F:效果启停(set_effect_enabled) → N:set_effect_enabled；X=回合差(log)
449 选定之枪(diy)：效果已激活判定(效果启停)；下回合开始你败北 schedule
450 穿刺死棘之枪：永久+2 费；单对手→defeat
451 刺穿死棘之枪：单对手 defeat
454 突穿死翔之枪：battle_end 交战人数 edit_score；胜则对手扣分
455/458 卢恩魔术：need_extra_play；reveal+弃手牌→复制威力/属性/能力 ｜ N:reveal_cards, add_card_effect
456/457/459 库林的猛犬：秘密标记 F:秘密状态可见性；武练 buff；每5层 +1 (max3)
461 贯穿之朱枪：交换双方各一张非残留攻击至回合结束 ｜ N:set_card_controller（配 draw_card_by_card 互换 played_cards）
464 护国鬼将：地利×2 F:个人地利字段；移动进入者 -4；赢则下回合部署于此 schedule+deploy
465 极刑王：play 1；有地利付2 再 play 1
