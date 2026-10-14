extends "res://tests/card_effect_runtime_test.gd"

func check(ok:bool, label:String) -> void:
	if label.begins_with("S0 skill factory"):
		label = "夹具正式角色工厂接受原来源：" + label.get_slice(": ",1)
	elif label.begins_with("runtime skill identity"):
		label = "夹具运行技能具备本局来源：" + label.get_slice(": ",1)
	elif label.begins_with("formal fixture play"):
		label = "夹具真实付费打出完成：" + label.get_slice(": ",1)
	elif label.begins_with("formal command spell"):
		label = "夹具真实绑定玩家自己的令咒"
	checks += 1
	if not ok: failures.append(label)
	print("CHECK ",label," ",ok)

func opponent_attack(card) -> void:
	var phase = GameProgress.current_phase_index
	var id = GameProgress.current_player_id
	GameProgress.current_phase_index = 2
	GameProgress.current_player_id = 1
	var filler = LoadAttack.resolve("strength:2",fixture_context)
	GameData.player_data_library[1].hand_cards.append_array([card,filler])
	check(RegularPlay.submit_group(1,[card,filler],[false,true],false,fixture_context),"对手攻击夹具真实同属性常规批次入场")
	await GameProgress.wait_progress_state({"ok":true,"completed":true,"context":fixture_context},fixture_context)
	GameProgress.current_phase_index = phase
	GameProgress.current_player_id = id

func scene(phase:int = 3, magic:int = 12) -> void:
	setup(3,magic)
	GameProgress.current_phase_index = phase
	GameLog.set_context(1,"battle" if phase == 3 else "action")
	place(MapData.miyama,0,0)
	place(MapData.miyama,1,1)
	place(MapData.shinto,2,0)

func ready_card(key:String):
	var card = skill_card("sasaki_kojirou",key)
	GameData.player_data_library[0].servant_skills.append(card)
	check(EffectManager.register_effects(card._effects,0),"真实技能效果登记："+key)
	return card

func test_threshold() -> void:
	for key in ["ichi_no_tachi","ni_no_tachi"]:
		scene(2,7)
		var card = ready_card(key)
		var d:Dictionary = GameData.player_data_library[0]
		var filler = LoadAttack.resolve("strength:2",fixture_context)
		d.hand_cards.append(filler)
		var accepted = RegularPlay.submit_group(0,[card,filler],[false,true],false,fixture_context)
		await GameProgress.wait_progress_state({"ok":true,"completed":true,"context":fixture_context},fixture_context)
		check(accepted == (key == "ichi_no_tachi") and d.played_cards.has(card) == accepted,"少于8魔力只豁免一之太刀不豁免二之太刀："+key)
	scene(2,4)
	var card = ready_card("ichi_no_tachi")
	var filler = LoadAttack.resolve("strength:2",fixture_context)
	GameData.player_data_library[0].hand_cards.append(filler)
	check(not RegularPlay.submit_group(0,[card,filler],[false,true],false,fixture_context),"一之太刀魔力4不足费用5仍拒绝")

func test_ichi() -> void:
	scene()
	var card = ready_card("ichi_no_tachi")
	await fixture_play(card,0)
	var first = effect_named(card._effects,"ichi_no_tachi_close_and_play_strength")
	var next = effect_named(card._effects,"ichi_no_tachi_close_engaged_attack")
	var victim = LoadAttack.resolve("strength:2",fixture_context)
	await opponent_attack(victim)
	check(not EffectManager.request_manual_activation(next,0) and not victim._is_closed,"一之太刀若如此前提未满足不得关闭对手")
	var strength = LoadAttack.resolve("strength:2",fixture_context)
	var agility = LoadAttack.resolve("agility:2",fixture_context)
	var class_card = LoadAttack.find_special("berserker_class_strength_3_7",fixture_context)
	var d:Dictionary = GameData.player_data_library[0]
	d.hand_cards.append_array([strength,agility,class_card])
	check(EffectManager.request_manual_activation(first,0) and EffectManager.submit_option_choice(first,[0]),"一之太刀战斗阶段真实请求和选项")
	var pending:Dictionary = EffectManager.get_pending_card_selection()
	var candidates:Array = pending.get("cards",[])
	check(candidates.has(strength) and not candidates.has(agility),"一之太刀仅提供力量不提供迅捷")
	check(not candidates.has(class_card),"一之太刀只允许力量基础攻击不允许力量职阶牌")
	var before = d.magic.number
	check(EffectManager.submit_card_selection(first,[strength]),"一之太刀选择力量基础攻击")
	check(card._is_closed and not card._is_activating and not d.played_cards.has(card),"一之太刀先关闭此牌回技能区")
	check(d.played_cards.has(strength) and not d.hand_cards.has(strength) and d.magic.number == before+2,"一之太刀打出力量基础攻击精确获得2魔力")
	print("OBS 一太打出=",d.played_cards.has(strength)," 离手=",not d.hand_cards.has(strength)," 魔力前后=",before,"/",d.magic.number)
	check(not EffectManager.request_manual_activation(first,0),"一之太刀关闭后不可再次发动前半段")
	check(EffectManager.request_manual_activation(next,0) and EffectManager.submit_option_choice(next,[0]),"一之太刀前半成功后允许连带关闭")
	check(EffectManager.submit_player_selection(next,[1]) and EffectManager.submit_card_selection(next,[victim]),"一之太刀交战目标的一张基础攻击合法")
	check(victim._is_closed,"一之太刀真实关闭交战玩家基础攻击")

func test_ichi_target_filter() -> void:
	scene()
	var card = ready_card("ichi_no_tachi")
	await fixture_play(card,0)
	var first = effect_named(card._effects,"ichi_no_tachi_close_and_play_strength")
	var next = effect_named(card._effects,"ichi_no_tachi_close_engaged_attack")
	var strength = LoadAttack.resolve("strength:2",fixture_context)
	GameData.player_data_library[0].hand_cards.append(strength)
	EffectManager.request_manual_activation(first,0)
	EffectManager.submit_option_choice(first,[0])
	EffectManager.submit_card_selection(first,[strength])
	var victim = LoadAttack.find_special("berserker_class_strength_3_7",fixture_context)
	await opponent_attack(victim)
	EffectManager.request_manual_activation(next,0)
	EffectManager.submit_option_choice(next,[0])
	check(not EffectManager.submit_player_selection(next,[2]),"一之太刀不允许关闭不同战场玩家")
	EffectManager.request_manual_activation(next,0)
	EffectManager.submit_option_choice(next,[0])
	EffectManager.submit_player_selection(next,[1])
	var candidates:Array = EffectManager.get_pending_card_selection().get("cards",[])
	check(not candidates.has(victim),"一之太刀关闭目标只允许基础攻击不允许职阶攻击")
	check(EffectManager.submit_card_selection(next,[]),"一之太刀至多一张允许选择零张")
	check(not victim._is_closed,"一之太刀选择零张不关闭任何牌")

func test_ni() -> void:
	scene(2)
	var card = ready_card("ni_no_tachi")
	await fixture_play(card,0)
	var opponent = skill_card("medea","rule_breaker")
	GameData.player_data_library[1].servant_skills.append(opponent)
	await fixture_play(opponent,1)
	EffectManager.register_effects(opponent._effects,1)
	check(activate_effect(card._effects,"ni_no_tachi_lock_opponent_abilities",0),"二之太刀行动阶段真实发动")
	GameProgress.current_player_id=1
	check(not EffectManager.request_manual_activation(opponent._effects[0],1),"二之太刀同战场对手行动阶段能力拒绝")
	var command = fixture_command_spell(1)
	check(not EffectManager.request_manual_activation(command._effects[0],1),"二之太刀同战场对手自己的令咒拒绝")
	check(GameData.player_data_library[1].command_spell_count.number == 3,"二之太刀被拒令咒不消耗")
	var outside = fixture_command_spell(2)
	GameProgress.current_player_id=2
	check(EffectManager.can_manual_activate(outside._effects[0],2),"二之太刀不同战场对手不受禁令")
	GameProgress.current_phase_index=3
	GameProgress.current_player_id=1
	var battle = skill_card("medea","divine_words")
	GameData.player_data_library[1].servant_skills.append(battle)
	await fixture_play(battle,1)
	EffectManager.register_effects(battle._effects,1)
	check(not EffectManager.request_manual_activation(battle._effects[0],1),"二之太刀同战场对手战斗阶段能力拒绝")
	check(CloseCard.new().exec(card,0,fixture_context),"二之太刀真实关闭来源")
	check(EffectManager.can_manual_activate(battle._effects[0],1),"二之太刀来源关闭禁令失效")

func test_san() -> void:
	for count in [2,1]:
		scene(2)
		var card = ready_card("san_no_tachi")
		var d:Dictionary = GameData.player_data_library[0]
		var cards:Array = []
		var flags:Array = []
		for i in range(count):
			var filler = LoadAttack.resolve("agility:2",fixture_context)
			d.hand_cards.append(filler)
			cards.append(filler); flags.append(false)
		if count == 1:
			var wrong = LoadAttack.resolve("strength:2",fixture_context)
			d.hand_cards.append(wrong)
			cards.append(wrong); flags.append(true)
		cards.append(card); flags.append(false)
		check(RegularPlay.submit_group(0,cards,flags,false,fixture_context) == (count==2),"三之太刀超出常规两张同批%d张迅捷才可追加" % count)
		await GameProgress.wait_progress_state({"ok":true,"completed":true,"context":fixture_context},fixture_context)
		check(d.played_cards.has(card) == (count==2),"三之太刀同批%d张迅捷真实入场判定" % count)
	for both in [true,false]:
		scene(2)
		var card = ready_card("san_no_tachi")
		var d:Dictionary = GameData.player_data_library[0]
		var a = LoadAttack.resolve("agility:2",fixture_context)
		var b = LoadAttack.resolve("agility:2",fixture_context)
		d.hand_cards.append_array([a,b])
		check(RegularPlay.submit_group(0,[a,b,card],[false,false,false],false,fixture_context),"燕返夹具三之太刀合法同批入场")
		await GameProgress.wait_progress_state({"ok":true,"completed":true,"context":fixture_context},fixture_context)
		if both: await fixture_play(ready_card("ni_no_tachi"),0)
		await fixture_play(ready_card("ichi_no_tachi"),0)
		GameProgress.current_phase_index=3
		TimePointChecker.dynamic_time_point([TimePoints.BATTLE_PHASE],0,null,fixture_context)
		check(ReleaseTrueName.is_released(0)==both and d.total_power_bonus.number==(3 if both else 0),"燕返一二太同时在战场才真名解放合计加3"+str(both))

func test_nonbasic_execution() -> void:
	scene()
	var card = ready_card("ichi_no_tachi")
	await fixture_play(card,0)
	var first = effect_named(card._effects,"ichi_no_tachi_close_and_play_strength")
	var next = effect_named(card._effects,"ichi_no_tachi_close_engaged_attack")
	var nonbasic = LoadAttack.find_special("berserker_class_strength_3_7",fixture_context)
	GameData.player_data_library[0].hand_cards.append(nonbasic)
	EffectManager.request_manual_activation(first,0)
	EffectManager.submit_option_choice(first,[0])
	var accepted = EffectManager.submit_card_selection(first,[nonbasic])
	print("OBS 非基础力量提交=",accepted," 入场=",GameData.player_data_library[0].played_cards.has(nonbasic))
	check(not accepted and not GameData.player_data_library[0].played_cards.has(nonbasic),"一之太刀真实入口必须拒绝打出力量职阶攻击")
	var opponent = LoadAttack.find_special("berserker_class_strength_3_7",fixture_context)
	await opponent_attack(opponent)
	EffectManager.request_manual_activation(next,0)
	EffectManager.submit_option_choice(next,[0])
	EffectManager.submit_player_selection(next,[1])
	accepted = EffectManager.submit_card_selection(next,[opponent])
	print("OBS 非基础关闭提交=",accepted," 已关闭=",opponent._is_closed)
	check(not accepted and not opponent._is_closed,"一之太刀真实入口必须拒绝关闭职阶攻击")

func test_servant_card() -> void:
	scene()
	var prepared:Dictionary = MasterManager.prepare_role_runtime(named(GameData.loaded_servants,"sasaki_kojirou"),fixture_context)
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
	check(servant._effects.is_empty() and values=={"strength":[2,3,4],"agility":[2,3,3,4,5,5],"magic":[]},"小次郎从者牌无独立效果且力量234迅捷233455魔术空准确")
	check(servant._specials.ATTACKS.size()==12 and specials==["luck","luck","surveil"],"小次郎从者牌12张含Surveil一张Luck两张")

func run() -> void:
	await test_servant_card()
	await test_threshold()
	await test_ichi()
	await test_ichi_target_filter()
	await test_nonbasic_execution()
	await test_ni()
	await test_san()
	print("RESULT checks=",checks," failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
