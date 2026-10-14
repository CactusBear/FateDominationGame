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
	var m = FixtureClone.clone_template(named(GameData.loaded_masters, "emiya_shirou"), ctx)
	check(m != null, "卫宫士郎使用正式本局御主工厂")
	if m == null:
		return null
	GameData.player_data_library[0].master = m
	check(EffectManager.register_effects(m._effects, 0), "卫宫士郎御主效果登记")
	return m

func start() -> void:
	TimePointChecker.global_time_point([TimePoints.GAME_START], null, ctx)

func awaken(m) -> bool:
	var session = DebugSession.new(null, ctx)
	var result:Dictionary = session.execute_action("skill.awaken", {"player": 0, "card_id": m._upgrade_skill[0].get_instance_id()})
	var duplicate:Dictionary = session.execute_action("skill.awaken", {"player": 0, "card_id": m._upgrade_skill[0].get_instance_id()})
	check(not duplicate.get("ok", false), "黄金剑重复觉醒不重复入技能区")
	session.shutdown()
	print("OBS awaken=", result, " side_skills=", GameData.player_data_library[0].side.skills.size())
	check(GameData.player_data_library[0].side.skills.has(m._upgrade_skill[0]), "调试觉醒实际派发入技能区效果")
	GameData.player_data_library[0].magic.number = 12
	return result.get("ok", false)

func play_extra(card:BaseSkill) -> bool:
	var op:Dictionary = GameProgress.start_progress_operation("add_skill", [card, 0, false], ctx)
	var receipt:Dictionary = await GameProgress.wait_progress_operation(op)
	return receipt.get("ok", false) and receipt.get("value", false) == true

func active(effect:BaseEffect) -> bool:
	if effect == null or not EffectManager.request_manual_activation(effect, 0):
		return false
	if effect.has_options():
		return EffectManager.submit_option_choice(effect, [0])
	return EffectManager.submit_active_choice(effect, true)

func run() -> void:
	# 御主牌：未熟与投影只在游戏开始结算，且数值/牌区精确。
	setup()
	var m = master()
	var d:Dictionary = GameData.player_data_library[0]
	var skills:Array = d.side.skills
	d.magic.number = 4
	TimePointChecker.global_time_point([TimePoints.DAY_END], null, ctx)
	check(d.magic.number == 4, "未熟在非游戏开始时点不改魔力")
	check(skills.is_empty(), "投影在非游戏开始时点不加入技能区")
	start()
	check(d.magic.number == 2, "未熟将游戏开始魔力设为2")
	var kanshou:BaseSkill = named(skills, "kanshou_and_bakuya")
	check(kanshou != null, "投影将干将·莫邪加入技能区")
	check(kanshou != null and kanshou._cost.number == 1 and kanshou._power.number == 5, "干将·莫邪印刷费用1威力5")
	check(kanshou != null and kanshou._need_extra_play, "干将·莫邪保留投影追加打出")

	# 干将·莫邪：真实常规出牌入口拒绝魔力不足，达到8点后接受。
	d.magic.number = 7
	var probe:BaseAttack = make_hand_card("strength:2")
	d.hand_cards.append(probe)
	check(not RegularPlay.submit_group(0, [kanshou, probe], [false, false], false, ctx), "干将·莫邪魔力7时不能打出")
	check(not await play_extra(kanshou), "干将·莫邪魔力7时追加入口也拒绝")
	check(not d.played_cards.has(kanshou), "干将·莫邪拒绝后未进入攻击区")
	setup()
	m = master()
	start()
	d = GameData.player_data_library[0]
	kanshou = named(d.side.skills, "kanshou_and_bakuya")
	d.magic.number = 8
	probe = make_hand_card("strength:2")
	d.hand_cards.append(probe)
	check(not RegularPlay.submit_group(0, [kanshou, probe], [false, false], false, ctx), "干将·莫邪不能作为普通常规出牌")
	check(await play_extra(kanshou), "干将·莫邪魔力8时追加打出成功")
	check(d.played_cards.has(kanshou) and d.power.number == 5, "干将·莫邪成功后进入攻击区并贡献5威力")
	print("OBS 干将追加后魔力=", d.magic.number)

	# 远离尘世的理想乡：第一次淘汰取消并清空魔力，第二次不再保护。
	setup()
	m = master()
	d = GameData.player_data_library[0]
	d.magic.number = 7
	var resolver := ClimaxResolver.new()
	check(not resolver.eliminate_player(0, ctx) and not d.is_out, "远离尘世的理想乡取消第一次淘汰")
	check(d.magic.number == 0, "远离尘世的理想乡第一次保护清空魔力")
	d.magic.number = 5
	check(resolver.eliminate_player(0, ctx) and d.is_out, "远离尘世的理想乡第二次淘汰正常生效")
	check(d.magic.number == 5, "远离尘世的理想乡第二次不再清空魔力")
	check(resolver.eliminate_player(1, ctx) and GameData.player_data_library[1].is_out, "远离尘世的理想乡不保护其他玩家")

	# 升华技：调试解锁才进入技能区；被动只增强力量/敏捷基本牌。
	setup()
	m = master()
	d = GameData.player_data_library[0]
	var upgrade:BaseSkill = m._upgrade_skill[0]
	check(not upgrade._is_awakened and not d.side.skills.has(upgrade), "必胜黄金之剑开局未自动解锁")
	check(awaken(m), "必胜黄金之剑调试解锁成功")
	check(d.side.skills.has(upgrade), "必胜黄金之剑解锁后进入技能区")
	var strength:BaseAttack = make_hand_card("strength:2")
	d.hand_cards.append(strength)
	check(RegularPlay.submit_group(0, [upgrade, strength], [false, false], false, ctx), "必胜黄金之剑与力量基本牌真实出牌")
	check(d.power.number == 12, "必胜黄金之剑使力量基本牌威力精确加2")
	print("OBS 黄金剑力量组总威力=", d.power.number)
	for attr in ["agility", "magic"]:
		setup()
		m = master()
		d = GameData.player_data_library[0]
		upgrade = m._upgrade_skill[0]
		check(awaken(m), "黄金剑属性边界解锁" + attr)
		var c:BaseAttack = make_hand_card(attr + ":2")
		d.hand_cards.append(c)
		check(RegularPlay.submit_group(0, [upgrade, c], [false, false], false, ctx), "黄金剑属性边界真实出牌" + attr)
		check(d.power.number == (12 if attr == "agility" else 10), "黄金剑敏捷加2魔术不加成" + attr)
		print("OBS 黄金剑属性=", attr, " 总威力=", d.power.number)

	setup()
	m = master()
	d = GameData.player_data_library[0]
	upgrade = m._upgrade_skill[0]
	check(awaken(m), "黄金剑未激活被动场景解锁")
	var a:BaseAttack = make_hand_card("strength:2")
	var b:BaseAttack = make_hand_card("agility:2")
	d.hand_cards.append_array([a, b])
	check(RegularPlay.submit_group(0, [a, b], [false, false], false, ctx), "黄金剑留在技能区时真实打出力量与敏捷")
	check(d.power.number == 8, "黄金剑被动不需激活也应分别加2")
	print("OBS 黄金剑未打出两基本牌总威力=", d.power.number)

	# 战斗阶段手动发动高潮回合+4；非高潮/第二次发动均不生效。
	setup()
	m = master()
	d = GameData.player_data_library[0]
	upgrade = m._upgrade_skill[0]
	check(awaken(m), "必胜黄金之剑第二个场景解锁")
	strength = make_hand_card("strength:2")
	d.hand_cards.append(strength)
	check(RegularPlay.submit_group(0, [upgrade, strength], [false, false], false, ctx), "必胜黄金之剑战斗场景出牌")
	var before_power:int = d.power.number
	GameProgress.current_phase_index = 3
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.BATTLE_PHASE, TimePoints.NON_CLIMAX], ctx)
	var non_climax_combat:BaseEffect = effect_named(upgrade._effects, "combat")
	check(not active(non_climax_combat) and d.power.number == before_power, "必胜黄金之剑非高潮战斗阶段不能加4")
	LoadSituation.climax_situations = {1: true}
	GameProgress.current_phase_index = 3
	GameLog.set_context(1, "battle")
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.BATTLE_PHASE, TimePoints.CLIMAX], ctx)
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_PHASE, TimePoints.CLIMAX], 0, null, ctx)
	var combat:BaseEffect = effect_named(upgrade._effects, "combat")
	check(active(combat), "必胜黄金之剑高潮战斗阶段可发动")
	check(d.power.number == before_power + 4, "必胜黄金之剑高潮回合威力精确加4")
	check(not active(combat), "必胜黄金之剑同一回合不能发动第二次")
	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
