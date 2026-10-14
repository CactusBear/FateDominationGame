extends "res://tests/twelve_labors_lifecycle_test.gd"

# 复用真实发牌、整组出牌、战斗与回合收牌，不修改任何生产状态来替代规则结算。
func check(ok:bool, label:String) -> void:
	var text:String = label
	if label.is_valid_identifier() or (not label.contains("十二试炼") and not label.contains("幸运") and not label.contains("概览")):
		text = "十二试炼真实链路前置校验：" + label
	super.check(ok, text)

func run() -> void:
	for index in range(3):
		var copies:Array = lifecycle_setup()
		if copies.size() != 3: continue
		var d:Dictionary = GameDataManager.get_player_data(0)
		check(d.servant._specials.ATTACKS.size() == 12, "概览十二张攻击构成已加载")
		var names:Array = d.servant._specials.ATTACKS.map(func(a): return a._name)
		var expected:Array = ["strength:2", "strength:2", "strength:3", "strength:5", "strength:5", "strength:7", "strength:9", "agility:2", "agility:4", "agility:7", "special:luck", "special:luck"].map(func(key): return LoadAttack.resolve(key)._name)
		check(names == expected, "概览力量重复张数与两张幸运一致")
		if not play_pair(copies[index]): continue
		check(ReleaseTrueName.is_released(0), "十二试炼真名解放关键词真实触发")
		resolve_battle()
		check(d.score.number == 3, "十二试炼第%d张战败自己精确获得3战果" % (index + 1))
		for id in [1, 2]:
			var decreases:Array = GameLog.query({"type":"score_decrease", "actor":id}, 0)
			check(decreases.size() == 1 and decreases[0].data.delta == -3, "十二试炼第%d张令并列胜者%d分别失去3战果" % [index + 1, id])
		check(d.out_of_game.skills.has(copies[index]) and not d.played_cards.has(copies[index]) and not copies[index]._is_activating, "十二试炼第%d张战败自身移除且失活" % (index + 1))
		check(copies[index]._power.number == 5, "十二试炼第%d张不强化自身" % (index + 1))
		for other in range(3):
			if other != index:
				check(copies[other]._power.number == 8 and d.servant_skills.has(copies[other]), "十二试炼第%d张令其他第%d张永久加3威力且不移除" % [index + 1, other + 1])
		await next_action_round()
		check(d.out_of_game.skills.has(copies[index]) and not RegularPlay.candidates(0).has(copies[index]), "十二试炼第%d张移除后不可再次打出" % (index + 1))
		if play_pair():
			resolve_battle()
			check(d.score.number == 3, "十二试炼第%d张移除后下一战败不重复奖励" % (index + 1))
			for other in range(3):
				if other != index: check(copies[other]._power.number == 8, "十二试炼第%d张给予的加成跨回合保留且不重复" % (index + 1))
		copies = lifecycle_setup()
		if copies.size() == 3 and play_pair(copies[index]):
			d = GameDataManager.get_player_data(0)
			resolve_battle(true)
			check(d.out_of_game.skills.is_empty() and d.score.number != 3, "十二试炼第%d张获胜不触发战败效果" % (index + 1))
			check(copies[0]._power.number == 5 and copies[1]._power.number == 5 and copies[2]._power.number == 5, "十二试炼第%d张获胜不产生任何永久强化" % (index + 1))
	var copies:Array = lifecycle_setup()
	if copies.size() == 3 and play_pair():
		resolve_battle()
		var d:Dictionary = GameDataManager.get_player_data(0)
		check(d.score.number == 0 and d.out_of_game.skills.is_empty(), "十二试炼三张均未打出时战败不奖励不移除")
	await test_returned_copy_stays_idle_and_keeps_bonus()
	await audit_luck()
	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func luck_fixture() -> BaseAttack:
	super.setup(2, 10)
	SituationResolver.new().clear_all(fixture_context)
	place(MapData.miyama, 0, 0)
	place(MapData.miyama, 1, 1)
	enter_luck_action()
	var card:BaseAttack = LoadAttack.resolve("special:luck", fixture_context)
	var filler:BaseAttack = LoadAttack.resolve("strength:2", fixture_context)
	var d:Dictionary = GameDataManager.get_player_data(0)
	d.hand_cards.append_array([card, filler])
	RegisterObjectEffects.new().exec(card, 0, fixture_context)
	check(EffectManager.effect_pool.has(card._effects[0]), "幸运可信新建后登记原来源效果")
	check(RegularPlay.submit_group(0, [card, filler], [false, false], false, fixture_context), "幸运以0费用4威力和普通攻击真实打出")
	return card

func enter_luck_action() -> void:
	GameProgress.current_phase_index = 2
	GameProgress.current_player_id = 0
	GameLog.set_context(1, "action")
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.ACTION_PHASE, TimePoints.NON_CLIMAX])

func audit_luck() -> void:
	var card:BaseAttack = luck_fixture()
	GameProgress.current_phase_index = 3
	GameLog.set_context(1, "battle")
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.BATTLE_PHASE, TimePoints.NON_CLIMAX])
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_PHASE], 0, null, fixture_context)
	check(activate_effect(card._effects, "luck_ignore_defeat", 0), "幸运战斗阶段主动发动")
	Defeat.new().exec(0, fixture_context)
	print("OBS 幸运发动后直接败北层数=", DefeatBuff.get_defeat_count(0))
	check(DefeatBuff.get_defeat_count(0) == 0, "幸运发动后本回合无视后续直接败北")
	card = luck_fixture()
	enter_luck_action()
	check(not EffectManager.request_manual_activation(card._effects[0], 0), "幸运行动阶段不能发动战斗阶段能力")
	Defeat.new().exec(0, fixture_context)
	var blocked:BaseAttack = LoadAttack.resolve("special:luck", fixture_context)
	GameDataManager.get_player_data(0).hand_cards.append(blocked)
	check(not RegularPlay.submit_group(0, [blocked], [false], false, fixture_context), "幸运行动阶段已受直接败北后不能再打出")
	card = luck_fixture()
	GameProgress.current_phase_index = 3
	GameLog.set_context(1, "battle")
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.BATTLE_PHASE, TimePoints.NON_CLIMAX])
	Defeat.new().exec(0, fixture_context)
	check(DefeatBuff.get_defeat_count(0) == 1, "幸运未发动前直接败北真实生效")
	check(activate_effect(card._effects, "luck_ignore_defeat", 0), "幸运已打出且战斗阶段受败北后仍可发动")
	check(DefeatBuff.get_defeat_count(0) == 0, "幸运发动清除本回合战斗阶段既有直接败北")
