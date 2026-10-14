extends "res://tests/ichi_no_tachi_test.gd"

func setup() -> void:
	ctx = _reset_ctx()
	GameLog.reset()
	GameLog.set_context(1, "action")
	GameData.player_data_library.clear()
	for id in range(2):
		var d:Dictionary = GameData.new_player_data()
		d.is_out = false
		d.order.number = id
		d.magic.number = 4
		GameData.player_data_library[id] = d
	GameProgress.is_game_over = false
	GameProgress.current_round = 1
	GameProgress.current_phase_index = 2
	GameProgress.current_player_id = 0
	LoadSituation.climax_situations = {}
	for area in MapData.areas:
		for loc in area._locations:
			loc._players.clear()
	SetLocation.new().exec(MapData.miyama._locations[0], 0, false, true, true, ctx)
	SetLocation.new().exec(MapData.miyama._locations[1], 1, false, true, true, ctx)
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.ACTION_PHASE, TimePoints.NON_CLIMAX], ctx)

func master():
	var m = FixtureClone.clone_template(named(GameData.loaded_masters, "tohsaka_rin"), ctx)
	check(m != null, "远坂凛使用正式本局御主工厂")
	if m == null:
		return null
	GameData.player_data_library[0].master = m
	check(EffectManager.register_effects(m._effects, 0), "远坂凛御主效果登记")
	check(MasterManager.deal_initial_master_cards(0, ctx), "远坂凛正式开局分发三张游戏外阴炁弹")
	return m

func start() -> void:
	TimePointChecker.global_time_point([TimePoints.GAME_START], null, ctx)

func day_end(round_num:int = 1) -> void:
	GameProgress.current_round = round_num
	GameLog.set_context(round_num, "end")
	TimePointChecker.set_phase_time_points([], ctx)
	TimePointChecker.global_time_point([TimePoints.DAY_END], null, ctx)

func awaken(m) -> bool:
	var session = DebugSession.new(null, ctx)
	var result:Dictionary = session.execute_action("skill.awaken", {"player": 0, "card_id": m._upgrade_skill[0].get_instance_id()})
	var duplicate:Dictionary = session.execute_action("skill.awaken", {"player": 0, "card_id": m._upgrade_skill[0].get_instance_id()})
	check(not duplicate.get("ok", false), "宝石剑重复觉醒不重复入技能区")
	session.shutdown()
	check(GameData.player_data_library[0].side.skills.has(m._upgrade_skill[0]), "调试觉醒实际派发入技能区效果")
	GameData.player_data_library[0].magic.number = 12
	return result.get("ok", false)

func active_option(effect:BaseEffect, option:int) -> bool:
	if effect == null or not EffectManager.request_manual_activation(effect, 0):
		return false
	return EffectManager.submit_option_choice(effect, [option])

func command_spell(m, option:int = 0):
	var d:Dictionary = GameData.player_data_library[0]
	var card = FixtureClone.clone_template(LoadCommandSpell.command_spells.values()[0], ctx)
	d.out_of_game.command_spell = [card]
	RegisterObjectEffects.new().exec(card, 0, ctx)
	d.command_spell_count.number = 3
	var effect:BaseEffect = card._effects[0]
	if not EffectManager.request_manual_activation(effect, 0):
		return false
	return EffectManager.submit_option_choice(effect, [option])

func jewel_effect(m, effect_name:String) -> BaseEffect:
	var buff = named(m._specials.BUFFS, "jewels")
	return effect_named(buff._effects, effect_name)

func extra_attack(card:BaseAttack) -> bool:
	var op:Dictionary = GameProgress.start_progress_operation("add_attack", [card, 0], ctx)
	var receipt:Dictionary = await GameProgress.wait_progress_operation(op)
	print("OBS 追加攻击回执=", receipt)
	return receipt.get("ok", false) and receipt.get("value", false) == true

func run() -> void:
	# 御主牌开局能力：10枚宝石与第一回合令咒义务。
	setup()
	var m = master()
	var d:Dictionary = GameData.player_data_library[0]
	check(named(d.buffs, "jewels") == null, "宝石魔术游戏开始前尚未获得宝石buff")
	start()
	var jewel = named(d.buffs, "jewels")
	check(jewel != null, "宝石魔术开局获得宝石附带牌")
	check(jewel != null and jewel._buff_level.number == 10, "宝石魔术开局精确获得10枚宝石")
	check(d.action_requirements.has("command_spell_used"), "绝对服从的命令第一回合加入令咒行动义务")
	day_end(1)
	check(d.command_spell_count.number == 2, "第一回合未用令咒回合结束失去1枚令咒")

	# 使用令咒满足第一回合义务，并验证以令咒获得魔力的战斗结束惩罚。
	setup()
	m = master()
	d = GameData.player_data_library[0]
	start()
	check(command_spell(m, 0), "真实令咒入口选择获得魔力")
	check(GameLog.query({"type": "command_spell_used", "actor": 0}, 0).size() == 1, "令咒使用留下结构化使用事实")
	check(not d.action_requirements.has("command_spell_used") or not ActionRules.unmet("command_spell_used", 0), "令咒使用满足第一回合行动义务")
	var magic_before:int = d.magic.number
	GameLog.set_context(1, "battle")
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.BATTLE_PHASE], ctx)
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_PHASE_END], 0, null, ctx)
	check(d.magic.number == magic_before - 4, "令咒获得魔力后战斗结束失去4点魔力")
	day_end(1)
	check(d.command_spell_count.number == 2, "第一回合已使用令咒不再额外失去令咒")
	day_end(2)
	check(d.command_spell_count.number == 2, "第二回合未使用令咒没有第一回合罚扣")

	# 令咒使用了其他选项时不触发4点惩罚；上一回合的事实也不触发。
	setup()
	m = master()
	d = GameData.player_data_library[0]
	start()
	check(command_spell(m, 1), "真实令咒入口选择非获得魔力选项")
	magic_before = d.magic.number
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_PHASE_END], 0, null, ctx)
	check(d.magic.number == magic_before, "非获得魔力令咒不触发4点惩罚")
	setup()
	m = master()
	d = GameData.player_data_library[0]
	start()
	check(command_spell(m, 0), "上一回合真实使用获得魔力令咒")
	GameProgress.current_round = 2
	GameLog.set_context(2, "battle")
	magic_before = d.magic.number
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_PHASE_END], 0, null, ctx)
	check(d.magic.number == magic_before, "上一回合令咒获得魔力不触发本回合惩罚")

	# 宝石：非高潮回合三个选项分别走真实选择/资源入口。
	setup()
	m = master()
	d = GameData.player_data_library[0]
	start()
	var action_effect:BaseEffect = jewel_effect(m, "jewel_sorcery_action")
	magic_before = d.magic.number
	check(active_option(action_effect, 0), "宝石行动阶段获得1点魔力")
	check(d.magic.number == magic_before + 1, "宝石获得魔力精确为1")
	active_option(action_effect, 0)
	check(d.magic.number == magic_before + 1 and EffectManager.get_option_use_count(action_effect, 0) == 1, "宝石同回合相同选项不能第二次选择")
	check(m._other_things.size() == 9 and d.out_of_game.others.size() == 1, "宝石使用后每局限一次移出一张宝石")
	GameProgress.current_phase_index = 3
	check(not EffectManager.request_manual_activation(action_effect, 0), "宝石非行动阶段不能使用")
	GameProgress.current_phase_index = 2
	GameProgress.current_round = 2
	GameLog.set_context(2, "action")
	EffectManager.reset_round_option_counts()
	check(active_option(action_effect, 0) and d.magic.number == magic_before + 2, "宝石下一回合相同选项可再次选且精确加1")

	setup()
	m = master()
	d = GameData.player_data_library[0]
	start()
	action_effect = jewel_effect(m, "jewel_sorcery_action")
	var attacks_before:int = d.out_of_game.attacks.size()
	var bullet_option:bool = active_option(action_effect, 1)
	check(bullet_option, "宝石行动阶段从游戏外打出阴炁弹")
	check(d.out_of_game.attacks.size() == attacks_before - 1 and not d.played_cards.is_empty(), "宝石选阴炁弹消耗一张并真实打出")
	print("OBS 阴炁弹游戏外前=", attacks_before, " 后=", d.out_of_game.attacks.size(), " 攻击区=", d.played_cards.size())

	setup()
	m = master()
	d = GameData.player_data_library[0]
	start()
	action_effect = jewel_effect(m, "jewel_sorcery_action")
	var discarded:BaseAttack = make_hand_card("strength:2")
	var drawn:BaseAttack = make_hand_card("agility:2")
	d.hand_cards.append(discarded)
	d.deck.append(drawn)
	check(EffectManager.request_manual_activation(action_effect, 0), "宝石行动阶段弃牌选项可请求")
	check(EffectManager.submit_option_choice(action_effect, [2]), "宝石弃牌选项可选择")
	var pending:Dictionary = EffectManager.get_pending_card_selection()
	check((pending.get("cards", []) as Array).has(discarded), "宝石弃牌选项只从手牌挑牌")
	check(EffectManager.submit_card_selection(action_effect, [discarded]), "宝石弃牌选项接受1张牌")
	check(d.discard.has(discarded) and d.hand_cards.has(drawn), "宝石弃1抽1保持手牌数量并换入牌库牌")

	for count in [0, 3, 4]:
		setup()
		m = master()
		d = GameData.player_data_library[0]
		start()
		action_effect = jewel_effect(m, "jewel_sorcery_action")
		var picks:Array = []
		for i in range(4):
			var hand_card = make_hand_card("strength:2")
			d.hand_cards.append(hand_card)
			if i < count: picks.append(hand_card)
			if i < 3: d.deck.append(make_hand_card("magic:2"))
		check(active_option(action_effect, 2), "宝石弃牌边界打开选牌" + str(count))
		var accepted:bool = EffectManager.submit_card_selection(action_effect, picks)
		if count == 3:
			check(accepted and d.hand_cards.size() == 4 and d.discard.size() == 3 and d.deck.is_empty(), "宝石允许弃3抽3并保持手牌4张")
		else:
			check(not accepted and d.hand_cards.size() == 4 and d.discard.is_empty() and m._other_things.size() == 10, "宝石拒绝弃牌数量" + str(count) + "且不消耗宝石")

	# 高潮回合：同一选项最多三次，第四次被真实入口拒绝。
	setup()
	m = master()
	d = GameData.player_data_library[0]
	LoadSituation.climax_situations = {1: true}
	start()
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.ACTION_PHASE, TimePoints.CLIMAX], ctx)
	var climax_effect:BaseEffect = jewel_effect(m, "jewel_sorcery_climax")
	magic_before = d.magic.number
	for i in range(3):
		check(active_option(climax_effect, 0), "高潮宝石获得1点魔力第%d次" % (i + 1))
	check(d.magic.number == magic_before + 3, "高潮宝石同一选项最多累计3点魔力")
	print("OBS 高潮宝石三次前魔力=", magic_before, " 后魔力=", d.magic.number, " 使用次数=", EffectManager.get_option_use_count(climax_effect, 0))
	active_option(climax_effect, 0)
	check(EffectManager.get_option_use_count(climax_effect, 0) == 3, "高潮宝石同一选项第四次不增加使用次数")
	for i in range(3):
		active_option(climax_effect, 1)
	check(EffectManager.get_option_use_count(climax_effect, 1) == 3, "高潮宝石阴炁弹选项最多3次计数")
	for i in range(3):
		d.deck.append(make_hand_card("magic:2"))
		if d.hand_cards.is_empty(): d.hand_cards.append(make_hand_card("strength:2"))
		var picked = d.hand_cards[0]
		check(active_option(climax_effect, 2) and EffectManager.submit_card_selection(climax_effect, [picked]), "高潮宝石弃牌选项真实结算第" + str(i + 1) + "次")
	check(EffectManager.get_total_use_count(climax_effect) == 9 and m._other_things.size() == 1, "高潮宝石共计9次并消耗9张宝石")
	active_option(climax_effect, 2)
	check(EffectManager.get_total_use_count(climax_effect) == 9 and m._other_things.size() == 1, "高潮宝石第10次不结算不消耗")

	# 升华技：被动增强魔术基础牌与阴炁弹；行动阶段吸收本回合所有玩家实际支付。
	setup()
	m = master()
	d = GameData.player_data_library[0]
	var upgrade:BaseSkill = m._upgrade_skill[0]
	check(not upgrade._is_awakened and not d.side.skills.has(upgrade), "宝石剑开局未自动解锁")
	check(awaken(m), "宝石剑调试解锁成功")
	check(d.side.skills.has(upgrade), "宝石剑解锁后进入技能区")
	var magic_attack:BaseAttack = make_hand_card("magic:2")
	d.hand_cards.append(magic_attack)
	check(RegularPlay.submit_group(0, [upgrade, magic_attack], [false, false], false, ctx), "宝石剑与魔术基础牌真实出牌")
	check(d.power.number == 10, "宝石剑使魔术基础牌威力精确加2")

	setup()
	m = master()
	d = GameData.player_data_library[0]
	check(awaken(m), "宝石剑技能区被动场景解锁")
	var passive_magic = make_hand_card("magic:2")
	var passive_strength = make_hand_card("strength:2")
	d.hand_cards.append_array([passive_magic, passive_strength])
	check(RegularPlay.submit_group(0, [passive_magic, passive_strength], [false, false], false, ctx), "宝石剑未打出时两张基础牌真实出牌")
	check(d.power.number == 6, "宝石剑技能区被动只增强魔术基础牌2点")

	setup()
	m = master()
	d = GameData.player_data_library[0]
	check(awaken(m), "宝石剑阴炁弹场景解锁")
	upgrade = m._upgrade_skill[0]
	var bullet:BaseAttack = FixtureClone.clone_template(m._specials.ATTACKS[0], ctx)
	var filler:BaseAttack = make_hand_card("strength:2")
	d.hand_cards.append(filler)
	check(RegularPlay.submit_group(0, [upgrade, filler], [false, false], false, ctx), "宝石剑与基础牌进入激活状态")
	var before_bullet:int = d.power.number
	check(await extra_attack(bullet), "宝石剑场景真实追加打出阴炁弹")
	check(d.power.number == before_bullet + 3, "宝石剑使阴炁弹威力精确加2")

	setup()
	m = master()
	d = GameData.player_data_library[0]
	check(awaken(m), "宝石剑吸魔场景解锁")
	upgrade = m._upgrade_skill[0]
	var free:BaseAttack = make_hand_card("strength:2")
	d.hand_cards.append(free)
	check(RegularPlay.submit_group(0, [upgrade, free], [false, false], false, ctx), "宝石剑进入激活状态")
	var payer:BaseAttack = make_hand_card("strength:5")
	var payer2:BaseAttack = make_hand_card("agility:5")
	GameData.player_data_library[1].magic.number = 12
	GameData.player_data_library[1].hand_cards.append_array([payer, payer2])
	GameProgress.current_player_id = 1
	check(RegularPlay.submit_group(1, [payer, payer2], [false, false], false, ctx), "其他玩家真实支付2点魔力")
	GameProgress.current_player_id = 0
	d.magic.number = 4
	var drain:BaseEffect = effect_named(upgrade._effects, "placeholder_jewel_sword_drain")
	magic_before = d.magic.number
	check(active_option(drain, 0), "宝石剑行动阶段吸收本回合支付魔力")
	check(d.magic.number == magic_before + 2, "宝石剑精确获得所有玩家实际花费的2点魔力")
	active_option(drain, 0)
	check(d.magic.number == magic_before + 2 and EffectManager.get_option_use_count(drain, 0) == 1, "宝石剑同回合吸魔不能第二次结算")
	GameLog.set_context(1, "battle")
	TimePointChecker.global_time_point([TimePoints.BATTLE_END], null, ctx)
	check(d.out_of_game.skills.has(upgrade), "宝石剑战斗结束后移除游戏")

	setup()
	m = master()
	d = GameData.player_data_library[0]
	check(awaken(m), "宝石剑零支付边界解锁")
	upgrade = m._upgrade_skill[0]
	free = make_hand_card("strength:2")
	d.hand_cards.append(free)
	check(RegularPlay.submit_group(0, [upgrade, free], [false, false], false, ctx), "宝石剑零支付组真实出牌")
	check(d.power.number == 8, "宝石剑不增强力量基础牌")
	TimePointChecker.global_time_point([TimePoints.BATTLE_END], null, ctx)
	check(d.played_cards.has(upgrade) and not d.out_of_game.skills.has(upgrade), "未用宝石剑吸魔能力不会在战斗结束移出")
	d.magic.number = 4
	drain = effect_named(upgrade._effects, "placeholder_jewel_sword_drain")
	check(active_option(drain, 0) and d.magic.number == 4, "宝石剑本回合零支付获得零点魔力")

	# 阴炁弹每局限一次：关闭后移出游戏并注销效果。
	setup()
	m = master()
	d = GameData.player_data_library[0]
	start()
	bullet = FixtureClone.clone_template(m._specials.ATTACKS[0], ctx)
	RegisterObjectEffects.new().exec(bullet, 0, ctx)
	check(await extra_attack(bullet), "阴炁弹通过真实追加入场")
	var second_bullet = d.out_of_game.attacks[0]
	var close_op:Dictionary = GameProgress.start_progress_operation("close_card", [bullet, 0, ctx], ctx)
	var close_receipt:Dictionary = await GameProgress.wait_progress_operation(close_op)
	check(close_receipt.get("ok", false) and close_receipt.get("value", false) == true, "阴炁弹真实关闭入口成功")
	check(d.out_of_game.attacks.has(bullet) and not d.played_cards.has(bullet), "阴炁弹关闭后移出游戏")
	check(EffectManager.effect_pool.find(bullet._effects[0]) == -1, "阴炁弹关闭后注销自身效果")
	check(d.out_of_game.attacks.has(second_bullet) and EffectManager.effect_pool.has(second_bullet._effects[0]), "关闭一张阴炁弹不注销游戏外其他副本")
	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
