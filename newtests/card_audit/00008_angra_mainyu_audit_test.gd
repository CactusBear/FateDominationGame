extends "res://tests/ichi_no_tachi_test.gd"

# 原夹具负责来源克隆和选择，本审计将技能入场与战斗事实替换为真实公开规则入口。
func fixture(key:String) -> BaseSkill:
	setup()
	preload("res://scripts/match/rule_random.gd").start_seed(8008)
	MapData.active_situation = null
	for area in MapData.areas:
		for loc in area._locations: loc._players.clear()
	for id in [0, 1]:
		check(SetLocation.new().exec(MapData.miyama._locations[id], id, false, true, true, ctx), "夹具真实落位玩家%d" % id)
	GameProgress.current_phase_index = 2
	GameLog.set_context(1, "action")
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.ACTION_PHASE, TimePoints.NON_CLIMAX])
	var prepared:Dictionary = MasterManager.prepare_role_runtime(named(GameData.loaded_servants, "angra_mainyu"), ctx)
	check(prepared.ok, "安哥拉从者由可信工厂实例化")
	var servant = prepared.object
	GameData.player_data_library[0].servant = servant
	var card:BaseSkill = named(servant._specials.SKILLS, key)
	var d:Dictionary = GameData.player_data_library[0]
	d.servant_skills.append(card)
	RegisterObjectEffects.new().exec(card, 0, ctx)
	check(EffectManager.effect_pool.has(card._effects[0]), "技能登记真实来源：" + key)
	var filler = make_hand_card("strength:2")
	d.hand_cards.append(filler)
	check(RegularPlay.submit_group(0, [card, filler], [false, true], false, ctx), "技能真实整组打出：" + key)
	if key == "verg_avesta": check(ReleaseTrueName.is_released(0), "万象真名解放关键词真实触发")
	TimePointChecker.dynamic_time_point([TimePoints.ACTION_PHASE], 0, null, ctx)
	return card

func use_card(card:BaseSkill) -> void:
	check(EffectManager.request_manual_activation(card._effects[0], 0), "正式主动入口可发动：" + card._name)
	check(EffectManager.submit_option_choice(card._effects[0], [0]), "正式选项入口执行：" + card._name)

func end_battle() -> void:
	GameProgress.current_phase_index = 3
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.BATTLE_PHASE, TimePoints.NON_CLIMAX])
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_END], 0, null, ctx)

func choose_discard(cards:Array) -> void:
	var choice = EffectManager.waiting_effect
	check(choice != null, "万象战斗结束才询问弃牌")
	if choice == null: return
	check(EffectManager.submit_option_choice(choice, [0]), "万象进入弃牌选择")
	check(not EffectManager.submit_card_selection(choice, [cards[0], cards[0], cards[1], cards[2]]), "万象必须弃4张互异牌不能重复同一张")
	check(EffectManager.waiting_selection == choice, "万象非法弃牌提交保留原等待且未移牌")
	check(EffectManager.submit_card_selection(choice, cards), "万象真实提交精确4张弃牌")

func steal_from(id:int) -> void:
	var choice = EffectManager.waiting_effect
	check(choice != null, "万象每张复仇者独立询问偷取")
	if choice == null: return
	check(EffectManager.submit_option_choice(choice, [0]), "万象进入胜者选择")
	check(EffectManager.submit_player_selection(choice, [id]), "万象选择真实胜者%d" % id)

func third_player() -> void:
	var d:Dictionary = GameData.new_player_data()
	d.is_out = false
	d.order.number = 2
	d.magic.number = 10
	GameData.player_data_library[2] = d
	check(SetLocation.new().exec(MapData.miyama._locations[2], 2, false, true, true, ctx), "夹具第三玩家真实落位")

func real_battle(winners:Array, participants:Array = [0, 1], round_number:int = 1) -> void:
	GameProgress.current_round = round_number
	GameProgress.current_phase_index = 3
	GameLog.set_context(round_number, "battle")
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.BATTLE_PHASE, TimePoints.NON_CLIMAX])
	for id in participants:
		GameData.player_data_library[id].power.number = 0
		GameData.player_data_library[id].total_power_bonus.number = 100 if winners.has(id) else 0
	var result:Dictionary = BattleResolver.new(ctx).exec(participants)
	check(result.get("winners_by_area", {}).get(MapData.miyama._area_name, []) == winners, "真实战斗判定胜者" + str(winners))

func action(round_number:int) -> void:
	GameProgress.current_round = round_number
	GameProgress.current_phase_index = 2
	GameProgress.current_player_id = 0
	GameLog.set_context(round_number, "action")
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.ACTION_PHASE, TimePoints.NON_CLIMAX])

func run() -> void:
	var card:BaseSkill = fixture("left_right_fang")
	var d:Dictionary = GameData.player_data_library[0]
	var expected:Array = ["strength:2", "strength:2", "strength:3", "agility:2", "agility:2", "agility:3", "agility:4", "magic:2", "magic:3", "special:avenger_class", "special:avenger_class", "special:avenger_class"].map(func(key): return LoadAttack.resolve(key)._name)
	check(d.servant._specials.ATTACKS.map(func(a): return a._name) == expected, "概览力量迅捷魔术与三张复仇者构成逐张一致")
	d.deck.append(make_hand_card("strength:2"))
	d.discard.append(make_hand_card("magic:3"))
	var before_magic = d.magic.number
	use_card(card)
	check(d.hand_cards.size() == 2 and d.discard.is_empty() and d.deck.is_empty(), "左右咬同战场有对手抽2张且耗尽牌堆后洗弃牌")
	check(d.magic.number == before_magic, "左右咬有对手不同时获得4魔力")
	check(not EffectManager.request_manual_activation(card._effects[0], 0), "左右咬同回合不得第二次发动")
	card = fixture("left_right_fang")
	d = GameData.player_data_library[0]
	RemoveFromBoard.new().exec(1, ctx)
	d.magic.number = 3
	use_card(card)
	check(d.magic.number == 7 and d.hand_cards.is_empty(), "左右咬独自战场精确获得4魔力且不抽牌")
	card = fixture("left_right_fang")
	d = GameData.player_data_library[0]
	RemoveFromBoard.new().exec(0, ctx)
	before_magic = d.magic.number
	use_card(card)
	check(d.magic.number == before_magic and d.hand_cards.is_empty(), "左右咬未在战场不获魔力不抽牌")
	for magic in [2, 3]:
		card = fixture("left_right_fang")
		d = GameData.player_data_library[0]
		var cleanup:Dictionary = GameProgress.start_progress_operation("discard_played_cards", [0], ctx)
		await GameProgress.wait_progress_operation(cleanup, false)
		GameProgress.current_round = 2
		action(2)
		d.magic.number = magic
		var filler = make_hand_card("strength:2")
		d.hand_cards.append(filler)
		var accepted:bool = RegularPlay.submit_group(0, [card, filler], [false, true], false, ctx)
		check(accepted == (magic == 3), "左右咬低于8魔力仍须付足3费用：余额%d" % magic)
		check(d.magic.number == (0 if magic == 3 else 2), "左右咬低魔力支付不透支且拒绝不扣费：余额%d" % magic)
	await audit_binding()
	await audit_avesta()
	await audit_avenger()
	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func audit_binding() -> void:
	for state in ["无前回合战斗", "上一回合战败", "上一回合获胜", "上一回合未参战"]:
		var card:BaseSkill = fixture("eternal_binding")
		var d:Dictionary = GameData.player_data_library[0]
		if state == "上一回合战败": real_battle([1])
		if state == "上一回合获胜": real_battle([0])
		if state == "上一回合未参战":
			third_player()
			RemoveFromBoard.new().exec(0, ctx)
			real_battle([1], [1, 2])
		action(2)
		var a = make_hand_card("special:avenger_class")
		var b = make_hand_card("special:avenger_class")
		var ordinary = make_hand_card("strength:2")
		d.discard.append_array([a, b, ordinary])
		RegisterObjectEffects.new().exec(a, 0, ctx)
		RegisterObjectEffects.new().exec(b, 0, ctx)
		check(EffectManager.effect_pool.has(a._effects[0]) and EffectManager.effect_pool.has(b._effects[0]), "复仇者由可信新建登记")
		use_card(card)
		check(d.discard == [ordinary], "永世束缚取尽全部复仇者但不取普通牌：" + state)
		var lost:bool = state == "上一回合战败"
		check((d.played_cards.has(a) and d.played_cards.has(b) and not d.hand_cards.has(a)) if lost else (d.hand_cards.has(a) and d.hand_cards.has(b) and not d.played_cards.has(a)), "永世束缚仅本人上一回合战败才加入攻击：" + state)
		if lost: check(a._is_activating and not a._is_concealed and not a._is_closed, "永世束缚回收攻击明置激活且打开")
		check(not EffectManager.request_manual_activation(card._effects[0], 0), "永世束缚每回合不能重复发动：" + state)

func audit_avesta() -> void:
	var card:BaseSkill = fixture("verg_avesta")
	var d:Dictionary = GameData.player_data_library[0]
	third_player()
	var a = make_hand_card("special:avenger_class")
	var b = make_hand_card("special:avenger_class")
	var ordinary = make_hand_card("strength:2")
	d.hand_cards.append_array([a, b, ordinary])
	use_card(card)
	check(d.hand_cards.size() == 3 and not EffectManager.is_waiting_for_choice(), "万象行动阶段仅预约不提前弃置")
	real_battle([1, 2], [0, 1, 2])
	for id in [1, 2]: GameData.player_data_library[id].score.number = 10
	end_battle()
	choose_discard([a, b, ordinary, card])
	check(d.hand_cards.is_empty() and d.discard.has(a) and d.discard.has(b) and d.discard.has(ordinary), "万象战斗结束后精确弃4张允许手牌与打出区混选")
	check(not d.played_cards.has(card) and d.side.skills.has(card) and not d.discard.has(card), "万象技能弃置返回技能侧区不混入攻击弃牌堆")
	var before = d.score.number
	steal_from(1)
	steal_from(2)
	check(d.score.number == before + 4 and GameData.player_data_library[1].score.number == 8 and GameData.player_data_library[2].score.number == 8, "万象每弃1张复仇者偷2战果且可选不同并列胜者")
	check(not EffectManager.is_waiting_for_choice(), "万象偷取次数恰为弃置复仇者数")
	end_battle()
	check(not EffectManager.is_waiting_for_choice() and d.score.number == before + 4, "万象预约只结算一次")
	for won in [true, false]:
		card = fixture("verg_avesta")
		d = GameData.player_data_library[0]
		a = make_hand_card("special:avenger_class")
		d.hand_cards.append(a)
		use_card(card)
		real_battle([0] if won else [1])
		end_battle()
		check(d.hand_cards.is_empty() and d.discard.has(a) and d.played_cards.has(card), "万象不足4张弃光手牌但保留打出区：获胜=" + str(won))
		if won:
			check(not EffectManager.is_waiting_for_choice(), "万象本人获胜即使弃复仇者也不偷战果")
		else:
			var theft = EffectManager.waiting_effect
			check(theft != null and EffectManager.choice_allows_cancel(theft), "万象战败偷取是可选而非强制")
			if theft != null: EffectManager.submit_active_choice(theft, false)
			check(not EffectManager.is_waiting_for_choice(), "万象可放弃偷取且不留下等待")
	card = fixture("verg_avesta")
	d = GameData.player_data_library[0]
	third_player()
	RemoveFromBoard.new().exec(0, ctx)
	a = make_hand_card("special:avenger_class")
	d.hand_cards.append(a)
	use_card(card)
	real_battle([1], [1, 2])
	end_battle()
	check(not EffectManager.is_waiting_for_choice(), "万象本人未参战不应被别处战斗误判战败并偷取")

func audit_avenger() -> void:
	fixture("left_right_fang")
	var d:Dictionary = GameData.player_data_library[0]
	var source = make_hand_card("special:avenger_class")
	var other = make_hand_card("strength:2")
	d.hand_cards.append_array([source, other])
	RegisterObjectEffects.new().exec(source, 0, ctx)
	check(EffectManager.effect_pool.has(source._effects[0]), "复仇者原来源登记")
	# 本回合已有常规出牌，追加攻击使用真实进程 operation 入口。
	for card in [source, other]:
		var op:Dictionary = GameProgress.start_progress_operation("play_attack", [card, 0], ctx)
		var completed:Dictionary = await GameProgress.wait_progress_operation(op)
		check(completed.ok and completed.value == true, "复仇者与其余攻击真实追加打出")
	var before_other = other._power.number
	var before_source = source._power.number
	var before_total = d.power.number
	GameProgress.current_phase_index = 3
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.BATTLE_PHASE, TimePoints.NON_CLIMAX])
	print("OBS 复仇者时点前：manual=", source._effects[0]._is_manual, " activating=", source._is_activating, " concealed=", source._is_concealed, " pool=", EffectManager.effect_pool.has(source._effects[0]))
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_PHASE], 0, null, ctx)
	var flush:Dictionary = await GameProgress.wait_progress_state({"ok":true, "completed":true, "context":ctx}, ctx)
	check(flush.ok, "复仇者阶段时点真实执行完成")
	print("OBS 复仇者时点后：allows=", EffectManager.card_state_allows(source._effects[0]), " matched=", EffectManager.get_matched_time_points(source._effects[0]), " settled=", EffectManager.resolved_effects.get(source._effects[0]))
	check(d.power.number == before_total, "复仇者战斗阶段能力未主动发动前不应自动加威力")
	check(EffectManager.request_manual_activation(source._effects[0], 0), "复仇者战斗阶段加威力能力可主动发动")
	# 数据改为「单选项 + 每回合一次」后，正式入口走选项提交；无选项时仍走直接确认。
	if EffectManager.waiting_effect == source._effects[0]:
		if source._effects[0].has_options(): EffectManager.submit_option_choice(source._effects[0], [0])
		else: EffectManager.submit_active_choice(source._effects[0], true)
	print("OBS 复仇者战斗阶段威力变化=", d.power.number - before_total)
	check(d.power.number == before_total + 1 and source._power.number == before_source and other._power.number == before_other, "复仇者其余一张攻击精确贡献加1且不强化自身或技能")
	real_battle([1])
	var op:Dictionary = GameProgress.start_progress_operation("discard_played_cards", [0], ctx)
	await GameProgress.wait_progress_operation(op, false)
	check(d.played_cards.has(source) and source._is_activating, "复仇者败战后无声业火残留不弃置")
	GameProgress.current_round = 2
	GameLog.set_context(2, "battle")
	EffectManager.reset_phase_window_settlements()
	real_battle([0, 1], [0, 1], 2)
	check(not source._is_closed, "复仇者并列胜利但未战胜对手仍残留")
	EffectManager.reset_phase_window_settlements()
	real_battle([0], [0, 1], 3)
	print("OBS 复仇者真正获胜后的状态：closed=", source._is_closed, " activating=", source._is_activating)
	check(source._is_closed and source._is_concealed, "复仇者真正战胜一名对手后关闭终止残留")
	op = GameProgress.start_progress_operation("discard_played_cards", [0], ctx)
	await GameProgress.wait_progress_operation(op, false)
	check(not d.played_cards.has(source) and d.discard.has(source), "复仇者战胜对手关闭后回合收牌真正进入弃牌堆")
