extends Node
const FixtureClone = preload("res://newtests/fixture_clone.gd")
var ctx: SessionContext
var master: BaseMaster
var d: Dictionary
var checks: int = 0
var failures: Array = []

func _ready(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures.append(label)
	print("CHECK ", label, " ", ok)
func named(arr: Array, key: String):
	for o in arr:
		if o != null and o._name == key: return o
	return null
func setup(start: bool = true):
	var reset: Dictionary = EffectManager.reset_runtime()
	ctx = reset.get("context")
	GameLog.reset(); GameLog.set_context(1, "action")
	GameData.player_data_library.clear()
	GameProgress.is_game_over = false
	GameProgress.current_round = 1
	GameProgress.current_phase_index = 2
	GameProgress.current_player_id = 0
	MapData.active_situation = null
	MapData.situations.clear()
	for a in MapData.areas:
		a._events.clear()
		for loc in a._locations: loc._players.clear()
	for id in range(3):
		var p: Dictionary = GameData.new_player_data()
		p.is_out = false; p.order.number = id; p.magic.number = 12
		GameData.player_data_library[id] = p
	d = GameData.player_data_library[0]
	d.master = named(GameData.loaded_masters, "kuzuki_souichirou")
	MasterManager.bind_master_effects(0, ctx)
	master = d.master
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.ACTION_PHASE], ctx)
	if start: TimePointChecker.global_time_point([TimePoints.GAME_START], null, ctx)
func card(key: String): return FixtureClone.clone_template(LoadAttack.resolve(key), ctx)
func snake(): return FixtureClone.clone_template(master._specials.ATTACKS[0], ctx)
func place(area: BaseMapArea, id: int = 0, index: int = 0):
	return SetLocation.new().exec(area._locations[index], id, false, true, true, ctx)
func phase(index: int, actor: int = 0):
	GameProgress.current_phase_index = index; GameProgress.current_player_id = actor
	var tp: String = str(GameProgress.phases[index].mid)
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, tp], ctx)
	TimePointChecker.dynamic_time_point([tp], actor, null, ctx)
func awaken():
	var session = DebugSession.new(null, ctx)
	var result: Dictionary = session.execute_action("skill.awaken", {"player": 0, "card_id": master._upgrade_skill[0].get_instance_id()})
	session.shutdown()
	print("OBS 觉醒入口 ", result)
	return result.get("ok", false)
func isolated_awakened_dispatch():
	# 入口断链时仅隔离测试正式生命周期时点；不重签效果、不修改觉醒状态。
	var skill = master._upgrade_skill[0]
	RegisterObjectEffects.new().exec(skill, 0, ctx)
	TimePointChecker.dynamic_time_point([TimePoints.SKILL_AWAKENED], 0, skill, ctx)
func activate(e):
	if e == null or not EffectManager.request_manual_activation(e, 0): return false
	if e.has_options(): return EffectManager.submit_option_choice(e, [0])
	return EffectManager.submit_active_choice(e, true)
var score_fixture_serial: int = 0
func change_score(delta: int, actor: int):
	score_fixture_serial += 1
	var tp: String = "audit_score_" + str(score_fixture_serial)
	var descriptor: Dictionary = {"effect_name": tp, "time_points": ["self_" + tp], "priority": 0, "is_pure_passive": true, "is_residue": false, "effect_numbers": [{"number": delta, "can_change": true, "is_pure_number": true}], "funcs": [{"func_name": "edit_score", "parameters": [null, {"number_index": 0}, actor], "var_index": -1}]}
	var effects: Array = LoadHelper.load_effects([descriptor], master, ctx)
	if effects.is_empty(): return
	EffectManager.register_effect(effects[0], actor)
	TimePointChecker.dynamic_time_point([tp], actor, null, ctx)
func end_battle():
	phase(3)
	TimePointChecker.player_time_point([TimePoints.BATTLE_PHASE_END], 0, null, ctx)
func score_cases():
	setup(); place(MapData.miyama)
	end_battle()
	check(d.score.number == 1, "局外人非工房未获战果阶段结束获得1点")
	end_battle()
	check(d.score.number == 1, "局外人同回合再次阶段结束不重复获战果")
	GameProgress.current_round = 2; GameLog.set_context(2, "battle")
	end_battle()
	check(d.score.number == 2, "局外人下一回合重新获得1点")
	setup(); place(MapData.magic_workshop)
	end_battle()
	check(d.score.number == 2, "局外人工房唯一玩家获得2点")
	setup(); place(MapData.magic_workshop); place(MapData.magic_workshop, 1, 1)
	end_battle()
	check(d.score.number == 1, "局外人工房有其他玩家仅获得1点")
	setup(); place(MapData.miyama)
	change_score(3, 0)
	end_battle()
	check(d.score.number == 3, "局外人本回合已获得战果不再奖励")
	setup(); place(MapData.miyama)
	change_score(3, 1)
	end_battle()
	check(d.score.number == 1, "局外人仅他人获得战果不阻止自身奖励")
	setup(); place(MapData.miyama)
	change_score(1, 0)
	change_score(-1, 0)
	end_battle()
	check(d.score.number == 0, "局外人获得后失去战果仍视为本回合获得过")
	setup(); place(MapData.magic_workshop)
	TimePointChecker.player_time_point([TimePoints.BATTLE_PHASE_END], 1, null, ctx)
	check(d.score.number == 0, "局外人他人结束时点不提前奖励")
	TimePointChecker.global_time_point([TimePoints.BATTLE_PHASE_END], null, ctx)
	check(d.score.number == 0, "局外人全局结束时点不重复玩家级奖励")
func movement_cases():
	setup(); d.magic.number = 4
	var loc = DeployRules.deploy_to_area(MapData.magic_workshop, 0, ctx)
	check(loc != null and d.location == loc, "局外人仍能真实部署工房")
	check(d.magic.number == 4, "局外人部署工房无法获得魔力")
	var other: Dictionary = GameData.player_data_library[1]; other.magic.number = 4
	var other_loc = DeployRules.deploy_to_area(MapData.magic_workshop, 1, ctx)
	check(other_loc != null and other_loc._magic.number > 0 and other.magic.number == 4 + other_loc._magic.number, "非葛木部署工房获得印刷席位魔力")
	var magic_before = d.magic.number
	EditMagic.new().exec(null, BaseNumber.new(2), 0, "", null, ctx)
	check(d.magic.number == magic_before + 2, "局外人不禁止非部署效果获得2点魔力")
	var buff = master._specials.BUFFS[0]
	print("OBS 工房禁魔 buff_attached=", d.buffs.has(buff), " buff_origin=", SessionGeneration.origin_of(buff), " magic_after_deploy=", magic_before)
	setup(); place(MapData.magic_workshop)
	d.magic.number = 4
	var raw = MapData.magic_workshop._move_cost.number
	Move.new().exec(BaseNumber.new(1), 0, false, false, ctx)
	print("OBS 工房离开原费用=", raw, " 实付=", 4 - d.magic.number)
	check(d.location.get_from() == MapData.magic_workshop._linked_map_area and d.magic.number == 4 - max(0, raw - 1), "局外人常规离开工房移动成本减1")
	setup(); place(MapData.miyama); d.magic.number = 4
	raw = MapData.miyama._move_cost.number
	Move.new().exec(BaseNumber.new(1), 0, false, false, ctx)
	check(d.magic.number == 4 - raw, "局外人从非工房离开没有减1")
	setup(); place(MapData.magic_workshop); d.magic.number = 0
	var old = d.location
	var expected = max(0, MapData.magic_workshop._move_cost.number - 1)
	Move.new().exec(BaseNumber.new(1), 0, false, false, ctx)
	check((d.location == old if expected > 0 else d.location != old) and d.magic.number == 0, "局外人折后费用不足拒绝且魔力不为负")
	setup(); place(MapData.magic_workshop); d.magic.number = 4
	SetLocation.new().exec(MapData.miyama._locations[0], 0, true, true, true, ctx)
	check(d.magic.number == 4, "局外人效果移动不扣常规成本不结算部署魔力")
func upgrade_cases():
	setup(false)
	var magic_hand = card("magic:2"); var magic_deck = card("magic:2"); var magic_discard = card("magic:2")
	var keep = card("agility:2"); var played_magic = card("magic:2")
	d.hand_cards.append_array([magic_hand, keep]); d.deck.append(magic_deck); d.discard.append(magic_discard)
	d.played_cards.append(played_magic)
	TimePointChecker.global_time_point([TimePoints.GAME_START], null, ctx)
	check(not master._upgrade_skill[0]._is_awakened and d.hand_cards.has(magic_hand), "完美呼吸正常开局不自动解锁不移除魔术牌")
	check(awaken(), "完美呼吸真实调试觉醒入口接受")
	check(not d.hand_cards.has(magic_hand) and not d.deck.has(magic_deck) and not d.discard.has(magic_discard) and d.out_of_game.attacks.has(magic_hand) and d.out_of_game.attacks.has(magic_deck) and d.out_of_game.attacks.has(magic_discard), "完美呼吸解锁立即移除手牌牌库弃牌堆全部魔术牌")
	check(not awaken(), "完美呼吸第二次觉醒被拒绝")
	isolated_awakened_dispatch()
	check(not d.hand_cards.has(magic_hand) and not d.deck.has(magic_deck) and not d.discard.has(magic_discard) and d.out_of_game.attacks.has(magic_hand) and d.out_of_game.attacks.has(magic_deck) and d.out_of_game.attacks.has(magic_discard), "完美呼吸隔离生命周期时点确实移除三区魔术牌")
	check(d.hand_cards.has(keep) and d.played_cards.has(played_magic), "完美呼吸移除保留非魔术牌和已打出魔术牌")
	var late = card("magic:2"); d.hand_cards.append(late)
	TimePointChecker.dynamic_time_point([TimePoints.CARD_TO_HAND], 0, late, ctx)
	check(d.hand_cards.has(late), "完美呼吸只解锁当下移除不持续删除后来魔术牌")

	setup(); place(MapData.miyama); awaken(); isolated_awakened_dispatch()
	var a = card("agility:2"); var b = card("agility:2")
	d.hand_cards.append_array([a, b])
	check(RegularPlay.submit_group(0, [a, b], [false, false], false, ctx), "完美呼吸两张迅捷基础牌真实整批出牌接受")
	print("OBS 迅捷双牌合计威力=", d.power.number)
	check(d.power.number == 10 and a._power.number == 2 and b._power.number == 2, "完美呼吸迅捷基础牌每张威力加3合计10不改印刷值")
	var power_before = d.power.number
	TimePointChecker.dynamic_time_point([TimePoints.CARD_TO_HAND], 0, a, ctx)
	check(d.power.number == power_before, "完美呼吸非出牌时点不增加迅捷基础威力")
	var c = card("agility:2"); d.hand_cards.append(c)
	check(not RegularPlay.submit_group(0, [c], [false], false, ctx), "常规出牌边界不能用不足两张的组测试加成")

	setup(); place(MapData.miyama); awaken(); isolated_awakened_dispatch()
	var strength = card("strength:2"); var strength2 = card("strength:2"); d.hand_cards.append_array([strength, strength2])
	check(RegularPlay.submit_group(0, [strength, strength2], [false, false], false, ctx) and d.power.number == 4, "完美呼吸非迅捷基础牌无加3")
	setup(); place(MapData.miyama); awaken(); isolated_awakened_dispatch()
	var s = snake(); strength = card("strength:2"); d.hand_cards.append_array([s, strength])
	check(RegularPlay.submit_group(0, [s, strength], [false, false], false, ctx) and d.power.number == 7, "蛇力量迅捷零费威力5且非基础不加3")
	setup(); place(MapData.miyama)
	a = card("agility:2"); b = card("agility:2"); d.hand_cards.append_array([a, b])
	check(RegularPlay.submit_group(0, [a, b], [false, false], false, ctx) and d.power.number == 4, "完美呼吸未觉醒迅捷基础牌没有加成")
func snake_cases():
	setup(); place(MapData.miyama)
	var hand_snake = snake(); var discard_snake = snake(); var played_snake = snake()
	d.hand_cards.append(hand_snake); d.discard.append(discard_snake); d.played_cards.append(played_snake)
	var deck_snakes: Array = d.deck.duplicate()
	var other_snake = snake(); GameData.player_data_library[1].hand_cards.append(other_snake)
	check(named(hand_snake._effects, "perfect_breathing_snake_attack") == null, "蛇未觉醒没有花6魔力能力")
	awaken()
	check(named(hand_snake._effects, "perfect_breathing_snake_attack") != null, "完美呼吸真实解锁立即授予蛇能力")
	isolated_awakened_dispatch()
	var all_granted: bool = true
	for s in deck_snakes + [hand_snake, discard_snake, played_snake]:
		all_granted = all_granted and named(s._effects, "perfect_breathing_snake_attack") != null
	check(all_granted, "完美呼吸隔离时点为牌库手牌弃牌已出蛇均添加能力文字")
	print("OBS 授予蛇能力手牌效果数=", hand_snake._effects.size(), " 牌库蛇数=", deck_snakes.size())
	for entry in GameLog.all_func_calls():
		if entry.get("effect_name") == "placeholder_perfect_breathing_snake_becomes_attack" and entry.get("func_name") in ["store_value", "build_effect", "add_to_array", "register_object_effects"]:
			print("OBS 授予函数 ", entry)
	check(named(other_snake._effects, "perfect_breathing_snake_attack") == null, "完美呼吸不为其他玩家的蛇授予能力")
	var e = named(hand_snake._effects, "perfect_breathing_snake_attack")
	check(e != null and e.runtime_source_status().get("ok", false) and EffectManager.effect_pool.has(e), "蛇新授予效果具有本局来源并正式登记")
	phase(3)
	check(d.played_cards.has(played_snake) and d.hand_cards.has(hand_snake) and d.magic.number == 12, "蛇战斗阶段不会自动入场或自动扣6")
	var accepted: bool = activate(e)
	print("OBS 蛇能力 accepted=", accepted, " magic=", d.magic.number, " in_hand=", d.hand_cards.has(hand_snake), " in_play=", d.played_cards.has(hand_snake), " source=", e.runtime_source_status() if e != null else {})
	check(accepted and d.magic.number == 6 and d.played_cards.has(hand_snake) and not d.hand_cards.has(hand_snake) and hand_snake._is_activating and not hand_snake._is_concealed, "蛇战斗阶段花6魔力加入攻击明置激活")
	check(not activate(e) and d.magic.number == (6 if accepted else 12), "蛇同回合第二次发动被拒绝不重复扣费")
	d.magic.number = 5
	check(not activate(e) and d.magic.number == 5, "蛇魔力仅5不足6拒绝不扣费")
	# 前一正例已把 hand_snake 打入攻击；行动阶段反例换一张仍在手牌的已授予能力的蛇。
	var action_snake = discard_snake
	d.discard.erase(action_snake); d.hand_cards.append(action_snake)
	var action_e = named(action_snake._effects, "perfect_breathing_snake_attack")
	d.magic.number = 12; phase(2)
	check(action_e != null and not activate(action_e) and d.hand_cards.has(action_snake) and d.magic.number == 12, "蛇行动阶段不能发动战斗阶段能力")
	var late = snake(); d.hand_cards.append(late)
	TimePointChecker.dynamic_time_point([TimePoints.CARD_TO_HAND], 0, late, ctx)
	check(named(late._effects, "perfect_breathing_snake_attack") != null, "完美呼吸后来进入手牌的蛇获得能力")
	var before: int = hand_snake._effects.size()
	TimePointChecker.dynamic_time_point([TimePoints.CARD_TO_HAND], 0, late, ctx)
	check(hand_snake._effects.size() == before, "完美呼吸再次入手时点不重复添加蛇能力文字")
func run():
	setup(false)
	check(d.deck.is_empty(), "暗杀术游戏开始前没有蛇")
	TimePointChecker.global_time_point([TimePoints.DAY_START], null, ctx)
	check(d.deck.is_empty(), "暗杀术非游戏开始时点不加蛇")
	TimePointChecker.global_time_point([TimePoints.GAME_START], null, ctx)
	check(d.deck.size() == 2 and d.deck[0] != d.deck[1] and d.deck[0]._name == "snake" and d.deck[1]._name == "snake", "暗杀术游戏开始加入两张独立蛇")
	check(GameData.player_data_library[1].deck.is_empty(), "暗杀术不给其他玩家牌库加蛇")
	if d.deck.size() == 2:
		check(d.deck[0]._cost.number == 0 and d.deck[0]._power.number == 5 and d.deck[0]._attributes == ["strength", "agility"] and d.deck[0]._effects.is_empty(), "蛇卡面力量迅捷费用0威力5没有原生文字效果")
	movement_cases(); score_cases(); upgrade_cases(); snake_cases()
	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
