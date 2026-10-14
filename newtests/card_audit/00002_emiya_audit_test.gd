extends Node
const FixtureClone = preload("res://newtests/fixture_clone.gd")

var ctx:SessionContext = null
var failures:Array = []
var checks:int = 0

func check(ok:bool, label:String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
	print("CHECK ", label, " ", ok)

func named(pool:Array, key:String):
	for item in pool:
		if item != null and item._name == key:
			return item
	return null

func _reset_ctx() -> SessionContext:
	var reset:Dictionary = EffectManager.reset_runtime()
	return reset.get("context") if reset.get("ok", false) else null

func setup(round_number:int = 1, player_count:int = 3) -> void:
	ctx = _reset_ctx()
	GameLog.reset()
	GameLog.set_context(round_number, "battle")
	GameData.player_data_library.clear()
	for id in range(player_count):
		var d:Dictionary = GameData.new_player_data()
		d.is_out = false
		d.order.number = id
		GameData.player_data_library[id] = d
	for area in MapData.areas:
		area._events.clear()
		for loc in area._locations:
			(loc._players as Array).clear()
	RestoreLocationBenefits.new().exec()
	GameProgress.is_game_over = false
	GameProgress.current_round = round_number
	GameProgress.current_phase_index = 3
	GameProgress.current_player_id = 0
	LoadSituation.climax_situations = {}
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.BATTLE_PHASE, TimePoints.NON_CLIMAX], ctx)

func servant_skills() -> Dictionary:
	var servant = named(GameData.loaded_servants, "emiya")
	var result:Dictionary = {}
	for template in servant._specials.get("SKILLS", []):
		var card = FixtureClone.clone_template(template, ctx)
		result[card._name] = card
		RegisterObjectEffects.new().exec(card, 0, ctx)
	return result

func play_skill(card:BaseSkill, player_id:int = 0) -> bool:
	var d:Dictionary = GameData.player_data_library[player_id]
	GameProgress.current_phase_index = 2
	GameProgress.current_player_id = player_id
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.ACTION_PHASE, TimePoints.NON_CLIMAX], ctx)
	var filler:BaseAttack = LoadAttack.resolve("strength:2", ctx)
	d.servant_skills.append(card)
	d.hand_cards.append(filler)
	d.magic.number = 40
	var accepted:bool = RegularPlay.submit_group(player_id, [card, filler], [false, false], false, ctx)
	check(accepted and d.played_cards.has(card) and card._is_activating, "正式整组出牌激活技能：" + card._name)
	return accepted

func effect_of(card, effect_name:String) -> BaseEffect:
	for effect in card._effects:
		if effect._name == effect_name:
			return effect
	return null

func activate(effect:BaseEffect) -> bool:
	if effect == null or not EffectManager.request_manual_activation(effect, 0):
		return false
	if effect.has_options():
		return EffectManager.submit_option_choice(effect, [0])
	return EffectManager.submit_active_choice(effect, true)

func battle_area():
	for area in MapData.areas:
		if area._score_need_win and area._locations.size() >= 2:
			return area
	return null

func place_pair(area, include_third:bool = false) -> void:
	check(area != null, "找到可会战且有两个席位的战场")
	if area == null:
		return
	check(SetLocation.new().exec(area._locations[0], 0, false, true, true, ctx), "卫宫进入战场")
	check(SetLocation.new().exec(area._locations[1], 1, false, true, true, ctx), "同战场对手进入战场")
	if include_third:
		var other = MapData.shinto if area == MapData.miyama else MapData.miyama
		check(SetLocation.new().exec(other._locations[0], 2, false, true, true, ctx), "异战场对手进入战场")

func attack(name:String, attributes:Array, cost:int, power:int) -> BaseAttack:
	return LoadAttack._create_attack({"attack_name":name, "_dir_path":"", "attack_card_img":"", "attributes":attributes,
		"cost":{"number":cost,"can_change":true,"is_pure_number":true}, "power":{"number":power,"can_change":true,"is_pure_number":true}, "effects":[]}, ctx)

func battle_window() -> void:
	GameProgress.current_phase_index = 3
	GameProgress.current_player_id = 0
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.BATTLE_PHASE, TimePoints.NON_CLIMAX], ctx)
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_PHASE, TimePoints.NON_CLIMAX], 0, null, ctx)

func action_window() -> void:
	GameProgress.current_phase_index = 2
	GameProgress.current_player_id = 0
	GameLog.set_context(GameProgress.current_round, "action")
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.ACTION_PHASE, TimePoints.NON_CLIMAX], ctx)
	TimePointChecker.dynamic_time_point([TimePoints.ACTION_PHASE, TimePoints.NON_CLIMAX], 0, null, ctx)

func test_zero_agility() -> void:
	setup()
	var area = battle_area()
	place_pair(area, true)
	var all := servant_skills()
	var card = all["seven_rings_of_blazing_heaven"]
	if not play_skill(card): return
	var same:Dictionary = GameData.player_data_library[1]
	var elsewhere:Dictionary = GameData.player_data_library[2]
	var same_agility:BaseAttack = attack("same_agility", ["agility"], 0, 5)
	var same_magic:BaseAttack = attack("same_magic", ["magic"], 0, 6)
	var other_agility:BaseAttack = attack("other_agility", ["agility"], 0, 7)
	same.played_cards.append_array([same_agility, same_magic])
	elsewhere.played_cards.append(other_agility)
	SyncPower.new().exec(1)
	SyncPower.new().exec(2)
	battle_window()
	check(activate(effect_of(card, "zero_opponent_agility_power")), "炽天覆七重圆环：同战场所有对手的迅捷攻击可归零")
	check(same.power.number == 6, "炽天覆七重圆环：同战场迅捷归零但魔术威力保留6")
	check(elsewhere.power.number == 7, "炽天覆七重圆环反例：异战场迅捷攻击不受影响")
	check(not activate(effect_of(card, "zero_opponent_agility_power")) and same.power.number == 6, "炽天覆七重圆环：同回合不可重复发动归零")

func test_terrain_triple() -> void:
	setup()
	var area = battle_area()
	place_pair(area)
	var loc:BaseLocation = area._locations[0]
	var d:Dictionary = GameData.player_data_library[0]
	var all := servant_skills()
	var card = all["pseudo_spiral_sword"]
	if not play_skill(card): return
	check(ReleaseTrueName.is_released(0), "伪·螺旋剑：正式出牌自动真名解放")
	check(Deploy.new().exec(loc, 0, true, ctx), "伪·螺旋剑：玩家部署到地利位")
	var before:int = int(loc._benefit.number)
	action_window()
	var eff:BaseEffect = effect_of(card, "terrain_advantage_triple")
	if EffectManager.waiting_effect == eff:
		check(EffectManager.submit_active_choice(eff, true), "伪·螺旋剑：行动阶段确认发动")
	check(loc._benefit.number == before * 3, "伪·螺旋剑：地利变为3倍")
	GameProgress.current_round = 2
	action_window()
	check(EffectManager.waiting_effect != eff and loc._benefit.number == before * 3, "伪·螺旋剑反例：第二回合仍不能重复使用每局一次地利三倍")

	setup()
	area = battle_area()
	place_pair(area)
	loc = area._locations[0]
	d = GameData.player_data_library[0]
	all = servant_skills()
	card = all["pseudo_spiral_sword"]
	card._is_activating = false
	d.played_cards.append(card)
	check(Deploy.new().exec(loc, 0, true, ctx), "伪·螺旋剑反例：部署未激活玩家")
	before = int(loc._benefit.number)
	action_window()
	eff = effect_of(card, "terrain_advantage_triple")
	check(EffectManager.waiting_effect != eff and loc._benefit.number == before, "伪·螺旋剑反例：未激活不改变地利")

func test_battle_win_score() -> void:
	setup()
	var area = battle_area()
	place_pair(area)
	var all := servant_skills()
	var card = all["pseudo_spiral_sword"]
	var d:Dictionary = GameData.player_data_library[0]
	if not play_skill(card): return
	battle_window()
	var eff := effect_of(card, "battle_win_score_gain")
	var before:int = d.score.number
	check(activate(eff), "伪·螺旋剑：战斗阶段效果可发动")
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_WIN], 0, null, ctx)
	check(d.score.number == before + 4, "伪·螺旋剑：赢得本场战斗获得4战果")
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_WIN], 0, null, ctx)
	check(d.score.number == before + 4, "伪·螺旋剑：一次登记只奖励一次，不因重复胜利时点再加4")

	setup()
	area = battle_area()
	place_pair(area)
	all = servant_skills()
	card = all["pseudo_spiral_sword"]
	d = GameData.player_data_library[0]
	if not play_skill(card): return
	battle_window()
	before = d.score.number
	check(activate(effect_of(card, "battle_win_score_gain")), "伪·螺旋剑反例：战斗阶段仍可登记延迟效果")
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_LOSE], 0, null, ctx)
	check(d.score.number == before, "伪·螺旋剑反例：战败不获得4战果")

func test_unlimited_blade_works() -> void:
	setup()
	var d:Dictionary = GameData.player_data_library[0]
	d.magic.number = 20
	var all := servant_skills()
	var card:BaseSkill = all["unlimited_blade_works"]
	var hand_a:BaseAttack = attack("hand_a", ["strength"], 0, 1)
	var deck_a:BaseAttack = attack("deck_a", ["agility"], 0, 2)
	var discard_a:BaseAttack = attack("discard_a", ["magic"], 0, 3)
	d.hand_cards = [hand_a]
	d.deck = [deck_a]
	d.discard = [discard_a]
	if not play_skill(card): return
	var eff:BaseEffect = effect_of(card, "rebuild_hand_from_all_zones")
	check(EffectManager.waiting_effect == eff, "无限剑制：打出时进入重组手牌选择")
	check(EffectManager.submit_option_choice(eff, [0]), "无限剑制：确认重组手牌选项进入选牌")
	var pending:Dictionary = EffectManager.get_pending_card_selection()
	check(pending.get("max", 0) == 12 and (pending.get("cards", []) as Array).has(deck_a) and (pending.get("cards", []) as Array).has(discard_a), "无限剑制：选牌候选含手牌、牌库和弃牌堆且上限12")
	var played_attack:BaseAttack = null
	for item in d.played_cards:
		if item is BaseAttack: played_attack = item
	check(played_attack != null and (pending.get("cards", []) as Array).has(played_attack), "无限剑制：候选包括真实已打出的攻击")
	check(EffectManager.submit_card_selection(eff, [hand_a, deck_a, discard_a, played_attack]), "无限剑制：提交四个卡面牌区的合法选牌")
	check(d.hand_cards.has(hand_a) and d.hand_cards.has(deck_a) and d.hand_cards.has(discard_a), "无限剑制：三张来源牌组成手牌")
	check(not d.deck.has(deck_a) and not d.discard.has(discard_a), "无限剑制：被选牌从原牌区移入手牌")
	check(d.hand_cards.has(played_attack) and not d.played_cards.has(played_attack) and not played_attack._is_activating, "无限剑制：已打出的牌回到手牌并失活")

func test_residue() -> void:
	setup()
	var d:Dictionary = GameData.player_data_library[0]
	d.magic.number = 20
	var all := servant_skills()
	var card:BaseSkill = all["unlimited_blade_works"]
	var hand_card:BaseAttack = attack("hand_a", ["strength"], 0, 1)
	d.hand_cards = [hand_card]
	if not play_skill(card): return
	var rebuild:BaseEffect = effect_of(card, "rebuild_hand_from_all_zones")
	if EffectManager.waiting_effect == rebuild:
		check(EffectManager.submit_option_choice(rebuild, [0]), "无限剑制残留：重组选项进入选牌")
		check(EffectManager.submit_card_selection(rebuild, [hand_card]), "无限剑制残留：完成打出时重组选择")
	check(d.play_limit.number == 4 and d.regular_play_min.number == 0 and not d.can_draw_card, "无限剑制残留：常规出牌为0~4张且禁止抽牌")
	d.hand_cards.clear()
	TimePointChecker.dynamic_time_point([TimePoints.PREPARE_PHASE], 0, null, ctx)
	check(d.play_limit.number == 2 and d.regular_play_min.number == 2 and d.can_draw_card, "无限剑制残留反例：手牌为0时恢复常规规则")
	check(card._is_closed, "无限剑制残留：手牌为0时关闭此牌")

func ubw_selection_fixture(hand_count:int, deck_count:int) -> Dictionary:
	setup()
	var all:Dictionary = servant_skills()
	var d:Dictionary = GameData.player_data_library[0]
	for i in range(hand_count):
		d.hand_cards.append(attack("留存手牌%d" % i, ["strength"], 0, 1))
	for i in range(deck_count):
		d.deck.append(attack("候选牌库%d" % i, ["magic"], 0, 2))
	var ubw:BaseSkill = all["unlimited_blade_works"]
	d.servant_skills.append(all["seven_rings_of_blazing_heaven"])
	if not play_skill(ubw): return {}
	var eff:BaseEffect = effect_of(ubw, "rebuild_hand_from_all_zones")
	check(EffectManager.submit_option_choice(eff, [0]), "无限剑制边界：正式出牌后进入重组选牌")
	return {"card":ubw, "effect":eff, "data":d, "spare_skill":all["seven_rings_of_blazing_heaven"]}

func test_ubw_selection_boundaries() -> void:
	var fixture:Dictionary = ubw_selection_fixture(0, 13)
	if fixture.is_empty(): return
	var d:Dictionary = fixture.data
	var deck:Array = d.deck.duplicate()
	check(not EffectManager.submit_card_selection(fixture.effect, deck), "无限剑制反例：13张超过至多12张必须拒绝")
	check(d.hand_cards.is_empty() and d.deck.size() == 13, "无限剑制反例：超限拒绝不改变牌区")
	fixture = ubw_selection_fixture(0, 12)
	if fixture.is_empty(): return
	d = fixture.data
	deck = d.deck.duplicate()
	check(EffectManager.submit_card_selection(fixture.effect, deck), "无限剑制：至多12张上界恰好12张允许")
	check(d.hand_cards.size() == 12 and d.deck.is_empty(), "无限剑制：12张全部真实移入手牌")
	fixture = ubw_selection_fixture(1, 1)
	if fixture.is_empty(): return
	d = fixture.data
	var candidate = d.deck[0]
	print("OBS 无限剑制必选手牌数=", EffectManager.get_pending_card_selection().get("required_cards", []).size())
	# 用户裁定 23：原手牌必选——只选牌库牌必须被拒，手牌不变
	var hand_before:Array = d.hand_cards.duplicate()
	check(not EffectManager.submit_card_selection(fixture.effect, [candidate]), "无限剑制原手牌必选：只选牌库牌被拒")
	check(d.hand_cards == hand_before, "无限剑制原手牌必选：被拒后手牌不变")
	fixture = ubw_selection_fixture(0, 1)
	if fixture.is_empty(): return
	var pending:Dictionary = EffectManager.get_pending_card_selection()
	print("OBS 无限剑制候选含未打出技能=", (pending.get("cards", []) as Array).has(fixture.spare_skill))
	check(not (pending.get("cards", []) as Array).has(fixture.spare_skill), "无限剑制反例：候选不能包含不在卡面四个牌区中的未打出技能")
	check(not EffectManager.submit_card_selection(fixture.effect, [fixture.spare_skill]), "无限剑制反例：实际提交未打出技能必须拒绝")

func test_ubw_draw_and_last_card() -> void:
	var fixture:Dictionary = ubw_selection_fixture(1, 1)
	if fixture.is_empty(): return
	var d:Dictionary = fixture.data
	var hand:BaseAttack = d.hand_cards[0]
	check(EffectManager.submit_card_selection(fixture.effect, [hand]), "无限剑制残留边界：保留一张手牌完成重组")
	var deck:Array = d.deck.duplicate()
	DrawCardFromPlDeckToHand.new().exec(0, 0, ctx)
	check(d.hand_cards == [hand] and d.deck == deck, "无限剑制残留：真实抽牌入口不能抽牌")
	action_window()
	check(RegularPlay.submit_group(0, [hand], [false], false, ctx), "无限剑制残留：允许常规出牌只打一张")
	print("OBS 无限剑制打出最后手牌后 hand=", d.hand_cards.size(), " closed=", fixture.card._is_closed, " can_draw=", d.can_draw_card)
	check(d.hand_cards.is_empty() and fixture.card._is_closed, "无限剑制残留：最后一张手牌打出时立即关闭此牌")
	check(d.can_draw_card, "无限剑制残留：空手关闭后恢复抽牌")

func test_agility_skill_zero() -> void:
	setup()
	place_pair(battle_area())
	var all:Dictionary = servant_skills()
	var source:BaseSkill = all["seven_rings_of_blazing_heaven"]
	if not play_skill(source): return
	var servant = named(GameData.loaded_servants, "emiya")
	var target:BaseSkill = FixtureClone.clone_template(named(servant._specials.SKILLS, "pseudo_spiral_sword"), ctx)
	RegisterObjectEffects.new().exec(target, 1, ctx)
	if not play_skill(target, 1): return
	battle_window()
	check(activate(effect_of(source, "zero_opponent_agility_power")), "圆环技能攻击边界：真实发动归零")
	var enemy:Dictionary = GameData.player_data_library[1]
	print("OBS 圆环敌方伪·螺旋剑 实际合计威力=", enemy.power.number, " 期望=2")
	check(enemy.power.number == 2, "圆环技能攻击边界：已打出的迅捷技能攻击威力也必须归零")

func test_servant_overview() -> void:
	setup()
	var servant = FixtureClone.clone_template(named(GameData.loaded_servants, "emiya"), ctx)
	var expected:Array = ["strength:2", "strength:3", "agility:2", "agility:2", "agility:3", "agility:4", "magic:2", "magic:3", "magic:4", "special:surveil", "special:preparation", "special:preparation"]
	var actual:Array = servant._specials.get("ATTACKS", []).map(func(card): return card._name)
	var wanted:Array = expected.map(func(reference): return LoadAttack.resolve(reference, ctx)._name)
	check(actual == wanted and actual.size() == 12, "卫宫从者牌：十二张攻击构成、属性数值和重复张数与卡面一致")
	check(servant._effects.is_empty() and servant._specials.get("SKILLS", []).size() == 3 and servant._specials.get("BUFFS", []).is_empty(), "卫宫从者牌：无额外文字效果且仅含三张技能，无附带牌")

func run() -> void:
	test_servant_overview()
	test_zero_agility()
	test_agility_skill_zero()
	test_terrain_triple()
	test_battle_win_score()
	test_unlimited_blade_works()
	test_residue()
	test_ubw_selection_boundaries()
	test_ubw_draw_and_last_card()
	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func _ready() -> void:
	call_deferred("run")
