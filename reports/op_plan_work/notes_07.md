# 第 7 批（read_07，U2508–U2857）逐条结论
代号：N=需新增 operation；F=框架改动；未标注=现有原语组合。

2508 长恨歌：灼伤 buff；回合开始抽牌前从游戏外加入【领域外生命】 N:create_card_from_pool(游戏外按名创建)；回合结束检查本回合是否打出过该名牌 N:get_turn_played_cards(本回合打出记录)；否则移除牌库顶X F:buff持续回合计数(get_buff_duration) N:get_buff_elapsed；不足转失去战果（remove后比较数量）
2509 妖星的火轮：连续打出费用+2 N:get_card_consecutive_play_count；灼烧=给同地点未灼伤者下回合开始挂 buff（schedule）；紫玉之笛吸取魔力（现有 steal/transfer 组合）
2510/2556/2568/2585/2602/2610/2615/2631/2637/2645/2650/2656/2663/2665/2670/2675/2676/2692/2707/2725/2727/2736/2738/2748/2753/2844/2847 从者/礼装本体卡（属性-威力表）：数据
2511/2515 星月夜：真名隐藏判定（现有 true_name 状态）；战场+侦查玩家加入领域外生命 N:create_card_from_pool；全场领域外生命+3 N:select_cards_global(跨玩家按名选牌)+add_power
2512/2514 水之宁芙/克吕提厄：每张领域外生命抽展示一张，获得其全部属性 N:add_card_attributes(复制属性,已有 add 属性则复用) N:reveal_cards
2513/2538/2540/2544等 领域外生命：你和指定从者名各+6合计威力（自身即为该从者时不叠加）N:get_players_by_servant_name；战斗阶段结束后加入该从者弃牌堆 N:move_card_to_player_zone(跨玩家移动)
2518 零标之魂(向日葵)：真名解放时触发 F:时点 self_true_name_release；展示弃牌堆计数失战果（上限6）；领域外生命加入你手牌（跨玩家移动）；此牌移除
2519 星月夜X：打出时自由选择X F:数值选择(choose_number)→N:choose_number；残留：准备阶段弃领域外生命否则关闭
2520 虚数美术(临摹)：选择同属性同威力他人明置技能牌，获得其需激活能力文字 N:copy_card_effects(复制效果到目标)；献身：重新分配攻击属性与威力（总和不变）N:redistribute_attack_stats(交互分配)
2521 零标之魂X：记录忽略局势/事件影响的合计威力 N:get_player_power_filtered(按来源过滤威力) N:set_player_total_power
2523 星月夜：费用-本局使用次数 N:get_usage_count；弃领域外生命移除临摹，复制临摹文字至回合结束（copy_card_effects+schedule remove）；为临摹拥有者创造临时领域外生命 N:create_temp_card_for_player
2524 虚数美术：同地点他人与你攻击同属性同基础威力技能牌叠放为临摹 N:attach_card；临摹不能常规打出 F:附属牌不可打出（属性标记）；令临摹失去文字+每局一次打出 N:clear_card_effects N:play_card_from_zone
2525 黄房子：X=玩家数-回合数（现有 get 组合）；放置入场时交换属性/威力（redistribute_attack_stats）；记录攻击带来威力后设0，下回合基础威力增加 N:set_player_total_power；不能连续两回合 F:使用间隔约束(last_used_turn) N:get_card_last_used_turn
2527/2536 森罗万象：颜色标记（每种唯一）放置到明置牌上，印刷属性改为标记属性 N:set_card_attributes(覆盖属性,至回合结束) F:标记物(token)系统 N:add_token/remove_token/get_tokens（通用标记：颜色/恶/检/羽/符文/迷彩/代币）
2534 富岳三十六景：残留至下回合结束且下回合威力-3（schedule+add_power）；同战场对手非×魔术攻击-2（select_cards 属性过滤）
2539 色彩的彼界：领域外生命拥有所有属性（被动光环 set_card_attributes）；支付激活攻击费用并移除至回合结束，放置手牌领域外生命 N:remove_card_until(暂时移出游戏并定时返回)
2543/2554 无限溯行歌词：随机两属性为 Combo F:随机选属性 N:random_choice(从列表随机)；打出/加入同属性攻击计数 F:时点 self_card_enter_attack；结算分支：关闭/令他人成为粉丝(全局标记 N:add_token 作玩家标记)/创造临时领域外生命(create_temp_card_for_player)
2545/2550/2552 煌彩幻奏霸道剑：粉丝同属性交战各+1魔力；从手牌/牌库打出可触发 Combo 的牌 N:play_card_from_zone；可付2改从弃牌堆
2548/2551 CABER/RRAOIME：OCR 残片，无效果
2553 王之歌声：高潮+7 或 +2X（X=淘汰粉丝数 N:get_players_by_token）；获胜令败者成为粉丝（战斗败者列表 N:get_battle_losers）；为所有粉丝创造临时领域外生命
2557/2559 乘镀：真名隐藏时幸运+3；付2隐藏真名 N:hide_true_name(若无)；从牌库/弃牌堆加入幸运（现有 search）；打出两张同属性攻击后可追加打出幸运 F:追加打出许可条件
2558 无铭星云剑：对手控制特殊攻击时视为所有属性且威力不能被减少 N:set_power_floor/F:威力不可降低标记；每张其他特殊攻击+3
2561/2562 止境的正义：获胜时改败者职阶为降临者且特殊基础攻击同名领域外生命至其获胜 N:set_player_class N:add_card_alias(别名)；令控制领域外生命的玩家败北（现有 defeat）
2564 伦戈米尼亚德：移除战斗中代币获得+3X；累计≥5 游戏胜利 N:win_game（若无）；累计计数用变量
2566 圣枪甲胄：X=7-代币数；打出手牌，基础威力低于X则设0 N:set_card_base_power
2567 宇宙反应器：所有玩家从游戏外洗入领域外生命 N:create_card_from_pool(to=deck,shuffle)；对手获得 Saber 代币直至打出领域外生命或被你战胜（token + 条件移除监听）
2569/2574 魔女审判：隐藏真名；交战对手随机弃一张后展示弃牌堆，计数最多者败北；领域外生命加入你弃牌堆（跨玩家移动）
2570/2573 于深渊化作光/理智丧失：X=本局分发数（变量累计）；X=12 胜利 N:win_game；同地点对手加入游戏外领域外生命
2571 领域外生命(阿比盖尔)：同 2513
2572 光壳流溢的虚树：移除手牌领域外生命+2魔力；从弃牌堆打出任意张（play_card_from_zone）；战斗结束洗回牌库
2576/2580/2582 蔷薇的沉睡：领域外生命进入弃牌堆时 F:时点 self_card_to_discard；选择移除+1魔力或放置他人牌库底（跨玩家移动）；甜美沉沦：同地点对手牌库不能被他人能力变动 F:牌库保护 buff（效果类 DeckLockEffect，参考 CannotPlayCardsEffect）
2577/2578/2581/2583 诺修&鲁撒：按本回合打出攻击共有属性分支（get_turn_played_cards+属性计数）；游戏外领域外生命加入牌库底/他人牌库底/攻击（create_card_from_pool 参数 to_zone,position）
2579/2584 遥远的幻梦境：隐藏全战场真名 N:hide_true_name；按基础威力排序选两张攻击暂时移除（remove_card_until）；打出/加入牌库底两张，不足洗弃牌堆（现有 reshuffle）
2587 深海电脑乐土：替换事件牌堆来源 F:地点事件牌堆可配置 N:set_location_event_deck；额外激活局势牌 N:activate_situation_card；移动保留地利 F:地利跟随；未胜失3魔力不足转战果 N:lose_resource_with_overflow(溢出转换，通用)
2588 十之王冠：按顺序每局限一次分支（变量记录）；永久改印刷威力 N:set_card_base_power(永久)；X=魔力≤7 加合计威力；移动任意地点并本回合免疫同地他人能力 F:免疫 buff(ImmuneEffect)
2589 樱之迷宫：费用-明置打出次数（统计变量）；其他特殊攻击改名幸运 add_card_alias 并授予无视败北 N:add_card_effect；常规出牌费用减半向上取整 F:费用修正支持乘法 N:add_cost_modifier(mode=mul)；打乱地点顺序 N:shuffle_locations(保留箭头)
2590/2597 蓝色/无色权能 Cursed：同地点玩家失1战果（现有）
2591/2592/2596 权能 Cupid：沿箭头移动至多一步（现有 move）
2595/2598 Cleanser：+1魔力
2604–2608 地点名：数据
2609 太阳的数字：事件牌展示后 F:时点 any_event_revealed；弃对应属性手牌抽一张，事件牌+3战果 N:add_event_reward；基础威力3的攻击三倍 N:multiply_card_power(通用乘法，可复用于翻倍)
2611 轮转胜利之剑：回合数%3（现有取余/条件表达）；技能区牌加入攻击（现有）
2612 骑士的夙愿：连胜次数 F:战绩统计 N:get_win_streak；授予对魔力文字 copy_card_effects；打出基础威力3攻击
2613 无二打：暗置攻击同属性移除后令对手败北
2614 无极：任意阶段开始付1选阶段效果；隐藏区域 F:隐藏区域状态；打出暗置手牌（现有 play 暗置）；战斗阶段可用行动阶段能力 F:能力阶段映射覆盖 N:add_phase_override；激活攻击改暗置 N:set_card_face
2616 阴阳交错：同礼装其他技能费用与威力翻倍并失去文字 multiply_card_power/add_cost_modifier(mul)/clear_card_effects
2617 遥远的理想乡：即将淘汰时替代 F:时点 self_before_eliminate + 可取消 N:cancel_event；回复令咒=高潮回合数
2618/2623 誓约胜利之剑：高潮回合赢得第11回合战斗胜利 N:win_game；手牌与技能区攻击费用-1（光环 cost modifier）
2619/2622 风王结界：真名隐藏费用-2；选择属性 N:choose_attribute；对手该属性攻击威力设0 N:set_card_power；首次真名解放回合对手不能用能力 F:能力封锁（参考 ForbidNoblePhantasmEffect 泛化 CannotUseAbilityEffect）
2620 骑士之王：本体
2625 干将·莫邪：魔力需≥8打出（默认规则）；投影需追加打出 F:追加打出限制标记（出牌规则数据字段）
2626 回路连接：移除技能区投影，游戏外四张宝具加入技能区并获得每局一次 create_card_from_pool+N:add_card_keyword(已有 ApplyCardKeywords 则复用)
2628 无限剑制：从打出/手牌/牌堆/弃牌堆组成12张手牌 F:多区选择；每回合打0–4张、不能抽牌 F:出牌数量上下限修正 N:set_play_count_limit；F:禁抽 buff；无手牌关闭；返回手牌
2629/2604 等名称残片：数据
2632/2634/2093 天之锁：持续至下回合战斗阶段结束 schedule；禁宝具(ForbidNoblePhantasmEffect)；不能离开战场 F:禁移动 buff；加入对手攻击并定时返回 N:move_card_to_player_zone
2633/2636 天地乖离开辟之星：不可复制/盗用/无效/同打出 F:卡牌保护标记（数据标记 + 各相关 op 检查）；战力结算外计算不计入 F:power_query 上下文过滤
2635/2638 王律之键：自由选X个非β特殊属性 choose_number+choose_attribute(多选)；地利位置或侦查+1/+2战果；地利翻倍 multiply_player_value
2640 童女讴歌：+X(移除计数)；抽2打出不同基础威力攻击，剩余手牌移除
2641/2644 纵使三度迎来落日：使用次数到3关闭；创造临时幸运/疾行/远隔操作或特殊基础攻击 N:create_temp_card
2642/2643 不夜特权：调整本轮顺位首/末/任意 N:set_turn_order_position；属性循环附加（光环 add_card_attributes）；顺位在后玩家数加战果
2646 Sonnet 155：从者名判定解锁升华技 unlock_upgrade_skill；可追加打出升华技 F:追加打出许可
2647 国王剧团：X=16-回合×2；部署魔术工房+1魔力+2战果（现有部署时点）；本回合打出基础攻击的临时复制 create_temp_card(copy_of)
2648 开演之时已至：本回合未用令咒的交战者败北 F:令咒使用记录 N:get_turn_command_spell_used
2651 一之太刀：弃置力量基础攻击关闭对手基础攻击
2652 三之太刀：打出两张迅捷攻击时可追加 F:追加许可条件；同时控制一/二之太刀→真名解放 N:true_name_release(若无)
2653/2655 二之太刀：同地点他人不能用行动/战斗阶段能力（CannotUseAbilityEffect 参数 phases）
2657/2661 千年京：此牌设置于/移动至地点 F:地点放置卡 N:place_card_at_location；回合结束让拥有者选择成为咒相放置或失1魔力
2658/2662 水天日光：打出X张咒相（地点上牌打出 play_card_from_zone zone=location）；结算后选择返回千年京或移除/弃
2659/2660 狐之婚嫁：魔术攻击不受他人能力影响 F:免疫 buff；属性改为魔术 set_card_attributes；攻击不被无效/减威 F:威力不可降低
2664 卢恩魔术：打出时选择一项作为效果直至关闭 F:效果选项启用 N:set_effect_enabled；移动除工房外；打出手牌+3
2666 穿刺死棘之枪：仅一名对手同战场则败北
2667 突穿死翔之枪：X=交战对手数至少3（max）；失去/获得战果
2668 乱世枭雄：获胜时不获事件战果，竞争/令咒战果翻倍 F:战果来源分类与修正 N:add_reward_modifier(source,mode)
2669 房火浮屠：回合结束打出基础攻击；若未战斗或付X魔力：失X战果、X张攻击持续激活至下回合结束 N:set_card_persist(残留延长)
2671 神鬼无前：付激活攻击费用令基础威力翻倍并获每局一次 multiply_card_power+add_card_keyword
2672 游星之纹章：持续至第二回合结束；为某战场使用文明废墟牌堆 set_location_event_deck
2673 巨神之剑：费用-最高事件牌战果 N:get_location_event_cards；攻击不被无效/减威
2674 女神变生：费用-胜场数（统计）；可追加；基础攻击获得残留至回合结束 N:add_card_keyword
2677 创造物工厂：创造物获得"打出时复制洗入牌库"(add_card_effect)；弃牌堆洗回牌库时淘汰 F:时点 self_deck_reshuffled N:eliminate_player；随机游戏外创造物加入牌库（create_card_from_pool random）
2678 转动的命运：每局限三次（使用计数上限，数据）；任意位置选创造物创建临时复制；已放置则连同同名加入攻击（全区搜索 N:select_cards_global）
2679 绝高无上·谦恭：创造物使用后不进弃牌堆而放置此牌上 F:弃牌去向重定向 N:add_zone_redirect；X=种类数（attached 去重计数）；抽一弃一
2680–2691 各创造物：同名每局限两次 F:同名共享使用次数；X>5 加入加农炮；关闭后下回合+3；追加打出；+1魔力抽1；打出+2魔力；+4/无视直接败北(F:无视败北 buff)；付3费用与威力+3；本回合移动过则加入攻击 N:get_turn_moved；移动两步；守御：打出/手牌/技能区免疫他人能力；重新部署 N:redeploy；唯一复制 create_temp_card
2693 次元超越：将自身从桌面移除 F:玩家离场状态；上回合合计威力比较取代胜者 N:get_player_last_turn_power N:set_battle_winner
2694 命运的指引：局势牌属性视为魔术 F:局势影响属性映射；回合结束加入技能区；合计威力设0，下回合加回 set_player_total_power+schedule
2695 无尽巫师：每回合仅一项（选项互斥 set_effect_enabled/变量）；上回合合计威力为0 get_player_last_turn_power；暗置手牌下回合加入攻击 schedule；魔术攻击与合计威力不被减少
2697 溶烛化紫：查看事件牌堆秘密标记 N:peek_event_deck + add_token(卡标记)；战斗阶段开始转化为虚空事件 N:transform_card
2698 万载豪笼：存在虚空事件获胜返回技能区；移除败者未激活从者技能，按威力/6向上取整创造领域外生命
2699 虚空激流：每回合限一次；移除牌库顶后改洗入牌库（zone redirect 条件）；每回合限四次从未被选择位置打出（位置去重变量）
2700–2704 龙辉巧：残留两回合（persist）；每回合限一张同名族 F:按名称族限打出；打出需弃一张 F:出牌附加费用(弃牌) N:add_play_extra_cost；+2合计；抽1/选龙辉巧加入手牌/关闭并加入攻击/移动下一地点/+1魔力
2705 龙仪巧-QUA：回合结束关闭不可阻止 F:不可取消标记；获得两张本回合关闭龙辉巧属性 F:本回合关闭记录 N:get_turn_closed_cards；对手同属性攻击不能用战斗阶段能力
2706 龙仪巧-DR：关闭对手因效果打出的牌 F:打出来源记录(play_source) N:get_card_play_source
2708 法芙娜：X=玩家数-回合数；前哨弃1将龙辉巧加入攻击
2709 流星辉巧群：关闭2X张打出游戏外X张龙仪巧 create_card_from_pool+play；每局一次加入两张
2710 来自天龙座的降诞：关闭，抽二或加入龙辉巧
2711 时代观察：特殊基础牌同名复仇者 add_card_alias；残留至战胜一名对手；移除幸运解锁升华技
2712 焦骨牡丹：检标记 add_token/remove_token；回合结束每标记选择花战果移除或洗入随机瓯（create_card_from_pool random）
2714 告密罗织经：瓯被移除时武则天创造酷吏 F:时点 any_card_removed；展示牌库顶五张不足先洗；对每张瓯选择支付战果或触发加入手牌时效果 N:trigger_card_effect(按时点触发指定牌效果)；无法展示五张则败北
2715 酷吏：战败时关闭一半；威力不因效果变动 F:威力锁定
2717–2720 各瓯：加入手牌时触发 F:时点 self_card_to_hand；展示移除；复制洗入/随机弃/本回合不受事件影响(F:事件免疫 buff)/合计-3 武则天+3（get_players_by_servant_name）
2722 潮满珠·潮干珠：每回合至多一项，反转改任意项；查看牌库顶3弃任意得等量合计；弃牌堆至多3洗入
2723 开辟海境：牌库与弃牌堆差值≤1 真名解放；创造引导之星；选匙，免费打出牌堆顶三张，战力结算时关闭与匙不同属性的
2724 引导之星：魔力<8可用技能（出牌规则修正 buff）；准备阶段付差值魔力否则关闭；他人格即将关闭时改为牌库顶置弃 F:时点 before_card_close+cancel_event
2729/2731 零落泛滥：回合结束令战胜战果更高对手的玩家选择给1战果或获恶标记（选择交由他人 F:他人选择 N:ask_player_choice）；宣言属性，展示牌库顶(1+恶数)弃置，按属性减合计威力；反转并败北 F:反转效果标记
2730/2732 恶念祝祭：令他人反转，拉斯普京选择一/两项；半威力打出 multiply_card_power
2733 鲜花战争：首次真名解放令其他玩家把非特殊基础手牌替换为游戏外狂战士 N:replace_card；职阶与从者名永久更改 N:set_player_class N:set_servant_name；狂战士-2费；展示对手手牌加入攻击；置入弃牌堆令原所有者获魔力战果
2734 第三太阳：令其他玩家立即使用或失去令咒 N:use_command_spell/lose_command_spell；首次用令咒获得裁决者令咒 F:时点 any_command_spell_used N:add_command_spell(type)
2735 重启动心脏都市：游戏开始时置牌库顶 F:时点 game_start；X=伪装者回合数；首次真名解放从手牌加入攻击获X战果，回合结束移除；展示手牌中此牌真名隐藏+2
2737 月之湖：放置于战场直至关闭 place_card_at_location；抽事件牌置于此牌上作为星 attach_card；受星影响（F:额外事件牌影响来源）；支付战果额外受影响
2739 伪装者(圣诞)：首次真名解放加入攻击获X战果；X张礼物洗入他人牌库；X永久设置 N:set_card_var
2740–2745 糖果：每局一次；激活时+1基础地利 N:add_base_advantage；洗入游戏外幸运/复仇者；移除手牌+2魔力；下回合复制后置位玩家已展示技能 create_temp_card(copy_of)；领域外生命同 2513
2746 糖果仙子的舞蹈：属性依御主性别 F:御主性别字段 N:get_master_attr；因御主能力失去资源后回补（时点 self_resource_lost + 来源过滤）；御主获得能力直至游戏结束 N:add_card_effect(to master card)；都获得则翻倍
2747 渴盼中隐约得见的梦：拆礼物时 F:时点 any_gift_opened（礼物牌自身效果触发，可用 self_card_to_hand 代替）；展示牌库顶三张替换激活攻击 N:swap_cards
2749 为圆环十字：受他人行动阶段能力影响前先行动 F:阶段插队(重大框架改动，建议简化为"被动响应"时点)；咆吼叠放 attach_card；重复使用按次数付魔力（循环+变量）；Y=叠放威力和
2751 永久遥远的胜利之剑：展示手牌基础攻击授予誓约效果（add_card_effect，至回合结束）
2752 斩断死辉之刃：局势牌无法阻止打出 F:局势限制豁免；X=本局打出次数 get_card_play_count；移除此牌改从者名 set_servant_name；游戏外同印刷威力凯尔特宝具加入攻击
2756 赤枝的骑士：X=6-属性数；获得未有属性至游戏结束 add_card_attributes；打出属性各不同攻击（选择过滤：属性互斥）F:select 约束 distinct_attr
2759 灼烧殆尽的炎笼：交战对手失去令咒且不能移动离开（禁移动 buff）
2764 唤来希望的号角：打出时移除；被移除时 F:时点 self_card_removed；花X战果失X魔力创造随机十二勇士技能攻击 create_temp_card(random pool)
2765 不毁的极圣：X=无牌区域数×2 N:count_empty_zones；文字不可失效 F:效果保护标记；移除至多4张跨区
2766 金刚之体：按无牌区域数分级光环（add_card_effect/条件 buff）；失去非宝具属性 N:remove_card_attributes；失去文字 clear_card_effects；不受事件与非高潮局势影响；常规出牌仅1张 set_play_count_limit；无法获得战果 add_reward_modifier(mul=0)；移除从者牌并视为空区
2780 破却宣言：付其费用关闭技能牌；自愿玩家协助付魔力（ask_player_choice）并获1战果
2783 雅号·龙纹：五种属性判定；他人使用技能攻击需弃同属性手牌 add_play_extra_cost(target=others)
2784 神通力（墨）：打出手牌作为引；交战对手各选择失去属性 remove_card_attributes+ask_player_choice；获得色彩标记放置于明置牌增加属性 add_token+add_card_attributes
2785 诸国瀑布揽胜：X=属性数；获得属性改为永久（修饰持续时间覆盖 F）；无对手具有此牌未有属性攻击则获得战果
2788 高梨的宝刀：本体
2789 黑姬物语：特定回合为宝刀选择追加效果直至游戏结束（add_card_effect 选项表）；数字翻倍 F:效果参数倍率(需效果参数可被修饰，框架改动)
2791–2793 进度如何/五彩缤纷/稿件：原稿状态=威力视为0且失去文字（set_card_power+clear_card_effects+关闭时返回原所有者 F:ownership 跟踪）；催稿=双方秘密选择 N:secret_choice_compare；查看手牌选取加入你攻击（跨玩家移动）；属性差异计数加威力；本回合关闭原稿计数
2796 迷彩狙击：秘密放置迷彩标记（token 可见性 hidden）；移除获得基础地利
2797 以二弹击之：抽2加一弃一重复；同基础威力令对手战斗阶段开始败北（schedule defeat）
2798 重整旗鼓：上回合战败 F:get_last_turn_result；移出版图不部署；查看顶3任意排到顶/底 F:排序选择 N:arrange_cards；常规出牌可少打 set_play_count_limit
2800 第一太阳：未用令咒者败北；在败北者中计算胜者 F:战斗结算规则覆盖 N:set_battle_resolution_mode
2801 战士之司：秘密选择花费战果 secret_choice；牌库顶X加入攻击；唯一胜者得回战果并移除，其他洗回
2802 山之心脏：移除手牌从游戏外加入同属性狂战士（replace_card），本回合免费打出 add_cost_modifier(set=0)
2804–2808 迦勒底礼装：花羽缝制并切换礼装牌 N:swap_master_card(切换此牌)；每项每局限一次选项；相邻移动；威力翻倍；免疫；三回合结束+2魔力(schedule 重复)；魔力设8 N:set_player_resource；重新分配顺位 set_turn_order_position；Gandr 选择阶段封锁 CannotUseAbilityEffect；抽未用从者选技能加入技能区 N:draw_servant_pool
2809/2813 鹤恩惜别歌：获得羽时+等量魔力（token 变化时点）；解锁升华技并替换从者名文本；抽新从者选技能
2810/2812 阵地建造〔衣〕：部署工房获羽；切换已缝制礼装（swap_master_card，列表来自变量）
2816 原初之卢恩：展示弃置事件牌顶，按文字关键字选择符文 F:事件牌文字标签字段（数据声明 rune_tags，不从文本推断）；花符文获得效果
2819/2821 九头龙杀/酒壶：放入酒壶 attach_card；加入对手攻击并反转威力 F:威力取反修饰 N:add_power_modifier(mode=negate)；首次进入战场付战果加入攻击（时点 any_enter_location）；移除
2820 护法之鬼：打出时选择属性与效果（choose_attribute+set_effect_enabled）；对手牌库顶加入你攻击；本回合入场攻击+2（入场回合标记 F:card entered_turn）
2823–2829 法宝：不受他人影响（免疫）；临时复制失去敏捷得魔术；攻击获得力量或+1；乾坤圈令地利位置对手失去地利 set_player_advantage；聚灵牌名去重计数（同属性特殊基础视同名 F:名称归一化规则由数据声明）；无视事件移动；混天绫减少费用与威力共计≤5（交互分配）并借用、回合结束返还
2830 化生：秘密计数莲体（隐藏变量）；即将淘汰时花莲体虚增战果判定 F:淘汰判定钩子；花莲体打出法宝并真名解放
2831/2832 灵珠子：抽X，按合成规则（弃牌组合→法宝，规则表写在数据）弃牌后加入临时法宝 create_temp_card
2834 诚之旗：展示顶牌，从弃牌堆打出同基础威力至多三张，狂战士-1费
2835 龙飞剑：展示两张手牌各选弃置或置顶
2836 我武新：获胜/打出狂战士后替换基础牌为同属性印刷威力+1（replace_card）
2838 夏天：需与更低基础威力攻击一同打出 F:打出组合约束；关闭本回合入场低威力攻击，按归属计数给战果与合计威力
2839/2840 色彩涂鸦/夏日街头：展示手牌属性数分级；放置复制到战场 place_card_at_location；他人进入可加入技能区；失去文字+2加入攻击后移除；作为常规出牌唯一一张打出抽2
2845 坐■不明：失去所有魔力，失去<6则下回合开始淘汰；战力结算单卡威力≥你总攻击威力则其所有者败北
2846 宗和的心得：真名隐藏+3；解放后力量/敏捷互加属性并授予坐杀效果
2848 百骨万世千塔修验：本回合常规出牌与上回合属性和基础威力完全相同 F:按回合历史出牌记录 get_turn_played_cards(turn_offset)；额外一次力量修正 F:力量修正可重复应用 N:apply_strength_modifier
2849/2850/2853 夺萃/裂舍/创始闪光：同时打出判定；移除两张加入游戏外创始闪光；偷魔力/合计威力；本局移除非技能牌计数
2851 领域外生命(XX Alter)：同 2513
2854 量子甲胄：X=12-魔力；即将移除基础手牌改为打出并回合结束移除（before_card_remove+cancel）；获胜需付3否则关闭；控制特殊攻击的对手失去地利
2855 武恶之极限：需与两张同基础威力攻击一同追加打出（组合约束）；选他人非特殊基础攻击加入手牌，可移除并为原拥有者创造领域外生命
2857 新天地探索航行：获胜时征服事件牌放置此牌上（attach_card）；抽或选征服事件牌；放置到地点并弃该地点一张事件牌后移动 N:place_event_card_at_location；移除获一半战果向上取整
