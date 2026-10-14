extends "res://tests/card_effect_runtime_test.gd"

func check(ok:bool, label:String) -> void:
	if label.begins_with("S0 skill factory"):
		label = "夹具正式角色工厂接受原来源：" + label.get_slice(": ",1)
	elif label.begins_with("runtime skill identity"):
		label = "夹具运行技能具备本局来源：" + label.get_slice(": ",1)
	elif label.begins_with("formal fixture play"):
		label = "夹具真实付费打出完成：" + label.get_slice(": ",1)
	checks += 1
	if not ok: failures.append(label)
	print("CHECK ", label, " ", ok)

func medea_scene(phase:int = 2, magic:int = 12) -> void:
	setup(3, magic)
	GameProgress.current_round = 4
	GameProgress.current_phase_index = phase
	GameLog.set_context(4, "action" if phase == 2 else "battle")
	place(MapData.miyama, 0, 0)
	place(MapData.miyama, 1, 1)
	place(MapData.shinto, 2, 0)

func card_ready(key:String):
	var card = skill_card("medea", key)
	GameData.player_data_library[0].servant_skills.append(card)
	check(EffectManager.register_effects(card._effects, 0), "正式效果登记：" + key)
	return card

func test_cost() -> void:
	for round_no in [4, 9]:
		medea_scene()
		GameProgress.current_round = round_no
		GameLog.set_context(round_no,"action")
		var card = card_ready("base_construction")
		# 回合开始的正式全局时点（报价基于本回合 X，不等出牌门内才算）
		TimePointChecker.global_time_point([TimePoints.DAY_START], null, fixture_context)
		var d:Dictionary = GameData.player_data_library[0]
		var before = d.magic.number
		var filler = LoadAttack.resolve("magic:2", fixture_context)
		d.hand_cards.append(filler)
		check(RegularPlay.submit_group(0, [card, filler], [false, true], false, fixture_context), "阵地建造回合%d真实批次提交" % round_no)
		await GameProgress.wait_progress_state({"ok":true,"completed":true,"context":fixture_context}, fixture_context)
		check(d.played_cards.has(card) and d.magic.number == before - max(0,16-round_no*2), "阵地建造X=16-回合×2回合%d精确扣费且负费不加魔力" % round_no)
	for round_no in [4,9]:
		medea_scene()
		GameProgress.current_round = round_no
		GameLog.set_context(round_no,"action")
		var quoted = card_ready("base_construction")
		var start = GameData.player_data_library[0].magic.number
		await fixture_play(quoted,0)
		check(quoted._cost.number == 16-round_no*2 and GameData.player_data_library[0].magic.number == start-max(0,16-round_no*2),"阵地建造正式技能操作回合%d动态公式及支付准确" % round_no)
	medea_scene(2, 8)
	GameProgress.current_round = 1
	GameLog.set_context(1,"action")
	var card = card_ready("base_construction")
	TimePointChecker.global_time_point([TimePoints.DAY_START], null, fixture_context)
	var d:Dictionary = GameData.player_data_library[0]
	var filler = LoadAttack.resolve("magic:2", fixture_context)
	d.hand_cards.append(filler)
	check(card._cost.number == 14 and not RegularPlay.submit_group(0,[card,filler],[false,true],false,fixture_context) and d.magic.number == 8 and not d.played_cards.has(card), "阵地建造费用14魔力8不足拒绝且不扣费")
	medea_scene()
	card = card_ready("base_construction")
	filler = LoadAttack.resolve("magic:2",fixture_context)
	TimePointChecker.dynamic_time_point([TimePoints.CARD_COST_CALCULATED],0,filler,fixture_context)
	check(card._cost.number==16 and filler._cost.number==0,"阵地建造费用只绑定自身其他攻击报价不触发公式")

func test_residue() -> void:
	for workshop in [true, false]:
		medea_scene()
		var card = card_ready("base_construction")
		await fixture_play(card, 0)
		var d:Dictionary = GameData.player_data_library[0]
		var area = MapData.magic_workshop if workshop else MapData.shinto
		RemoveFromBoard.new().exec(0, fixture_context)
		check(Deploy.new().exec(area._locations[1], 0, false, fixture_context), "残留夹具真实部署" + str(workshop))
		var before = d.magic.number
		var score = d.score.number
		TimePointChecker.dynamic_time_point([TimePoints.DEPLOY], 0, null, fixture_context)
		print("OBS 残留战区=",area._area_name," 魔力前后=",before,"/",d.magic.number," 战果前后=",score,"/",d.score.number)
		check(d.magic.number == before + (1 if workshop else 0) and d.score.number == score + (2 if workshop else 0), "残留部署魔术工房加1魔力2战果否则不加" + str(workshop))
	medea_scene()
	var card = card_ready("base_construction")
	await fixture_play(card,0)
	var d:Dictionary = GameData.player_data_library[0]
	var before = d.magic.number
	var score = d.score.number
	SetLocation.new().exec(MapData.magic_workshop._locations[1],0,false,true,true,fixture_context)
	check(d.magic.number == before and d.score.number == score, "效果移动入魔术工房不是部署不触发残留")
	var cleanup:Dictionary = GameProgress.start_progress_operation("discard_played_cards",[0],fixture_context)
	await GameProgress.wait_progress_operation(cleanup)
	check(d.played_cards.has(card) and card._is_activating,"阵地建造残留回合清理不返回技能区仍激活")
	CloseCard.new().exec(card,0,fixture_context)
	TimePointChecker.dynamic_time_point([TimePoints.DEPLOY],0,null,fixture_context)
	check(d.magic.number == before and d.score.number == score, "关闭的阵地建造不提供残留收益")

func test_breaker() -> void:
	for seals in [3, 1, 0]:
		medea_scene()
		var card = card_ready("rule_breaker")
		await fixture_play(card,0)
		var e = card._effects[0]
		GameData.player_data_library[1].command_spell_count.number = seals
		check(EffectManager.request_manual_activation(e,0) and EffectManager.submit_option_choice(e,[0]), "破戒行动阶段发动原令咒%d" % seals)
		check(EffectManager.submit_player_selection(e,[1]), "破戒同战场目标提交%d" % seals)
		var d:Dictionary = GameData.player_data_library[0]
		check(GameData.player_data_library[1].command_spell_count.number == max(0,seals-1), "破戒令咒减1且下限0原%d" % seals)
		check(DefeatBuff.get_defeat_count(1) == (1 if seals <= 1 else 0), "破戒原1枚或更少令其败北原%d" % seals)
		check(d.total_power_bonus.number == (10 if seals == 0 else 0), "破戒原0枚才总威力加10原%d" % seals)
		check(ReleaseTrueName.is_released(0), "破戒真名解放原%d" % seals)
		check(not EffectManager.request_manual_activation(e,0), "破戒每局一次第二次拒绝原%d" % seals)
		GameProgress.current_round += 1
		GameLog.set_context(GameProgress.current_round,"action")
		EffectManager.reset_round_option_counts()
		check(not EffectManager.request_manual_activation(e,0),"破戒每局一次跨回合仍拒绝原%d" % seals)
	medea_scene()
	var card = card_ready("rule_breaker")
	await fixture_play(card,0)
	var e = card._effects[0]
	EffectManager.request_manual_activation(e,0)
	EffectManager.submit_option_choice(e,[0])
	check(not EffectManager.submit_player_selection(e,[2]), "破戒不同战场目标拒绝")
	medea_scene()
	card = card_ready("rule_breaker")
	await fixture_play(card,0)
	e = card._effects[0]
	EffectManager.request_manual_activation(e,0)
	EffectManager.submit_option_choice(e,[0])
	var pending:Dictionary = EffectManager.get_pending_player_selection()
	print("OBS 破戒候选=",pending.get("candidates",[]))
	check((pending.get("candidates",[]) as Array).has(0), "破戒卡面一名玩家包含自己而非仅对手")

func test_divine() -> void:
	for lose in [true, false]:
		medea_scene(3)
		var removed = card_ready("rule_breaker")
		GameData.player_data_library[0].servant_skills.erase(removed)
		GameData.player_data_library[0].out_of_game.skills.append(removed)
		var card = card_ready("divine_words")
		await fixture_play(card,0)
		check(ReleaseTrueName.is_released(0), "神言魔术式打出真名解放")
		check(activate_effect(card._effects,"divine_words_retrieve_rule_breaker",0), "神言魔术式战斗阶段真实发动" + str(lose))
		var d:Dictionary = GameData.player_data_library[0]
		GameData.player_data_library[1].power.number = 100 if lose else 0
		var battle:Dictionary = BattleResolver.new(fixture_context).exec([0,1])
		await GameProgress.wait_progress_state({"ok":true,"completed":true,"context":fixture_context},fixture_context)
		print("OBS 神言胜者=",battle.get("winners_by_area",{})," 技能区=",d.side.skills.has(removed)," 移除区=",d.out_of_game.skills.has(removed))
		check(d.side.skills.has(removed) == lose and d.out_of_game.skills.has(removed) != lose, "神言失败回收一张移除破戒胜利不回收" + str(lose))

func test_servant_card() -> void:
	medea_scene()
	var prepared:Dictionary = MasterManager.prepare_role_runtime(named(GameData.loaded_servants,"medea"),fixture_context)
	var servant = prepared.object
	GameData.player_data_library[0].servant = servant
	var values:Dictionary = {"strength":[],"agility":[],"magic":[]}
	var specials:Array = []
	for attack in servant._specials.ATTACKS:
		if attack._category == BaseAttack.CATEGORY_BASIC and not attack._name in ["luck","preparation","surveil"]:
			for attribute in values:
				if attack._attributes.has(attribute): values[attribute].append(int(attack._power.number))
		else: specials.append(attack._name)
	for attribute in values: values[attribute].sort()
	specials.sort()
	check(servant._effects.is_empty() and values == {"strength":[],"agility":[2,3,4],"magic":[2,3,3,4,4,5]},"美狄亚从者牌无独立效果且力量空迅捷234魔术233445准确")
	check(servant._specials.ATTACKS.size()==12 and specials==["luck","preparation","surveil"],"美狄亚从者牌12张含各一张SurveilLuckPreparation")

func run() -> void:
	await test_servant_card()
	await test_cost()
	await test_residue()
	await test_breaker()
	await test_divine()
	print("RESULT checks=",checks," failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
