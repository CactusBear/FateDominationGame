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

func skills() -> Dictionary:
	var servant = named(GameData.loaded_servants, "artoria_pendragon")
	var result:Dictionary = {}
	for template in servant._specials.get("SKILLS", []):
		var card = FixtureClone.clone_template(template, ctx)
		result[card._name] = card
		RegisterObjectEffects.new().exec(card, 0, ctx)
	print("OBS 阿尔托莉雅技能键=", result.keys())
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

func battle_window(climax:bool) -> void:
	GameProgress.current_phase_index = 3
	GameProgress.current_player_id = 0
	var round_tp:String = TimePoints.CLIMAX if climax else TimePoints.NON_CLIMAX
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.BATTLE_PHASE, round_tp], ctx)
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_PHASE, round_tp], 0, null, ctx)

func battle_area():
	for area in MapData.areas:
		if area._score_need_win and area._locations.size() >= 2:
			return area
	return null

func place_pair(area, include_third:bool = false) -> void:
	check(area != null, "找到可会战且有两个席位的战场")
	if area == null:
		return
	check(SetLocation.new().exec(area._locations[0], 0, false, true, true, ctx), "阿尔托莉雅进入战场")
	check(SetLocation.new().exec(area._locations[1], 1, false, true, true, ctx), "同战场对手进入战场")
	if include_third:
		var other = MapData.shinto if area == MapData.miyama else MapData.miyama
		check(SetLocation.new().exec(other._locations[0], 2, false, true, true, ctx), "异战场对手进入战场")

func attack(name:String, attributes:Array, cost:int, power:int) -> BaseAttack:
	return LoadAttack._create_attack({"attack_name":name, "_dir_path":"", "attack_card_img":"", "attributes":attributes,
		"cost":{"number":cost,"can_change":true,"is_pure_number":true}, "power":{"number":power,"can_change":true,"is_pure_number":true}, "effects":[]}, ctx)

func test_np_bloom() -> void:
	setup()
	var d:Dictionary = GameData.player_data_library[0]
	var all := skills()
	var card = all["mana_resistance"]
	if not play_skill(card): return
	battle_window(false)
	var bloom := effect_of(card, "np_bloom_score")
	var low:BaseAttack = attack("np_cost_3", ["noble_phantasm"], 3, 8)
	d.played_cards.append(low)
	var before:int = d.score.number
	check(activate(bloom), "宝具绽放：打出本回合最高消耗宝具时可发动")
	check(d.score.number == before + 1, "宝具绽放：消耗3的最高宝具精确获得1战果")
	check(not activate(bloom) and d.score.number == before + 1, "宝具绽放：同回合第二次发动拒绝且战果不重复增加")

	setup()
	d = GameData.player_data_library[0]
	all = skills()
	card = all["mana_resistance"]
	if not play_skill(card): return
	battle_window(false)
	var high:BaseAttack = attack("np_cost_4", ["noble_phantasm"], 4, 8)
	d.played_cards.append(high)
	before = d.score.number
	check(activate(effect_of(card, "np_bloom_score")), "宝具绽放：消耗4宝具可发动")
	check(d.score.number == before + 2, "宝具绽放：消耗4额外获得1战果，总计2")

	setup()
	d = GameData.player_data_library[0]
	all = skills()
	card = all["mana_resistance"]
	if not play_skill(card): return
	battle_window(false)
	var lower:BaseAttack = attack("np_low", ["noble_phantasm"], 2, 8)
	var higher:BaseAttack = attack("np_high", ["noble_phantasm"], 5, 8)
	d.played_cards.append(lower)
	d.hand_cards.append(higher)
	before = d.score.number
	check(not activate(effect_of(card, "np_bloom_score")), "宝具绽放反例：不是最高消耗宝具时拒绝发动")
	check(d.score.number == before, "宝具绽放反例：非最高宝具不改变战果")

	setup()
	d = GameData.player_data_library[0]
	all = skills()
	card = all["mana_resistance"]
	if not play_skill(card): return
	d.hand_cards.append(attack("并列最高未打出宝具", ["noble_phantasm"], 4, 8))
	d.played_cards.append(attack("并列最高已打出宝具", ["noble_phantasm"], 4, 8))
	battle_window(false)
	before = d.score.number
	check(activate(effect_of(card, "np_bloom_score")), "宝具绽放并列边界：打出并列最高消耗宝具仍可发动")
	check(d.score.number == before + 2, "宝具绽放并列边界：并列最高消耗4仍获得2战果")

	setup()
	d = GameData.player_data_library[0]
	all = skills()
	card = all["mana_resistance"]
	if not play_skill(card): return
	battle_window(false)
	before = d.score.number
	check(not activate(effect_of(card, "np_bloom_score")) and d.score.number == before, "宝具绽放反例：未打出宝具不能获得战果")

func test_zero_magic() -> void:
	setup()
	var area = battle_area()
	place_pair(area, true)
	var all := skills()
	var card = all["mana_resistance"]
	if not play_skill(card): return
	var same:Dictionary = GameData.player_data_library[1]
	var elsewhere:Dictionary = GameData.player_data_library[2]
	var same_magic:BaseAttack = attack("same_magic", ["magic"], 0, 5)
	var same_strength:BaseAttack = attack("same_strength", ["strength"], 0, 6)
	var other_magic:BaseAttack = attack("other_magic", ["magic"], 0, 7)
	same.played_cards.append_array([same_magic, same_strength])
	elsewhere.played_cards.append(other_magic)
	SyncPower.new().exec(1)
	SyncPower.new().exec(2)
	battle_window(false)
	check(activate(effect_of(card, "zero_opponent_magic_power")), "魔术抗性：同战场对手的魔术属性攻击可归零")
	check(same.power.number == 6, "魔术抗性：同战场魔术攻击归零但力量攻击保留6")
	check(same_strength._power.number == 6, "魔术抗性：同战场非魔术攻击不受影响")
	check(elsewhere.power.number == 7, "魔术抗性反例：异战场魔术攻击不受影响")
	check(not activate(effect_of(card, "zero_opponent_magic_power")) and same.power.number == 6, "魔术抗性：同回合第二次发动拒绝且威力不再扣减")

func test_wind_cost() -> void:
	setup()
	var all := skills()
	var wind = all["wind_barrier"]
	var d:Dictionary = GameData.player_data_library[0]
	TimePointChecker.dynamic_time_point([TimePoints.CARD_COST_CALCULATED], 0, wind, ctx)
	check(wind._cost.number == 2, "风王结界：真名隐藏时费用从4降为2")
	check(ReleaseTrueName.new().exec(0, ReleaseTrueName.DEFAULT_SHOWN_AREAS, ctx), "风王结界：真名解放入口成功")
	check(wind._cost.number == 4, "风王结界反例：真名解放后恢复印刷费用4")
	check(HideTrueName.new().exec(0, HideTrueName.DEFAULT_HIDDEN_AREAS, ctx), "风王结界：重新隐藏真名入口成功")
	check(wind._cost.number == 2, "风王结界：重新隐藏后仍只降到2，不重复叠加")
	check(d.magic.number >= 0, "风王结界费用测试未造成负魔力")

func test_zero_strength() -> void:
	setup()
	var area = battle_area()
	place_pair(area, true)
	var all := skills()
	var card = all["wind_barrier"]
	if not play_skill(card): return
	var same:Dictionary = GameData.player_data_library[1]
	var elsewhere:Dictionary = GameData.player_data_library[2]
	var same_strength:BaseAttack = attack("same_strength", ["strength"], 0, 5)
	var same_magic:BaseAttack = attack("same_magic", ["magic"], 0, 6)
	var other_strength:BaseAttack = attack("other_strength", ["strength"], 0, 7)
	same.played_cards.append_array([same_strength, same_magic])
	elsewhere.played_cards.append(other_strength)
	SyncPower.new().exec(1)
	SyncPower.new().exec(2)
	battle_window(false)
	check(activate(effect_of(card, "zero_opponent_strength_power")), "风王结界：同战场对手的力量属性攻击可归零")
	check(same.power.number == 6, "风王结界：同战场力量攻击归零但魔术攻击保留6")
	check(same_magic._power.number == 6, "风王结界：同战场非力量攻击不受影响")
	check(elsewhere.power.number == 7, "风王结界反例：异战场力量攻击不受影响")
	check(not activate(effect_of(card, "zero_opponent_strength_power")) and same.power.number == 6, "风王结界：同回合第二次发动拒绝且威力不再扣减")

func test_excalibur_combat() -> void:
	setup(1)
	var all := skills()
	var d:Dictionary = GameData.player_data_library[0]
	var card = all["excalibur"]
	if not play_skill(card): return
	LoadSituation.climax_situations = {1: true}
	battle_window(true)
	var before:int = d.power.number
	print("OBS 誓约胜利之剑高潮=", GameProgress.is_climax_round(), " phase_points=", TimePointChecker.phase_time_points, " matched=", EffectManager.get_matched_time_points(effect_of(card, "combat")), " card_state=", EffectManager.card_state_allows(effect_of(card, "combat")))
	check(activate(effect_of(card, "combat")), "誓约胜利之剑：高潮回合战斗阶段可发动")
	check(d.power.number == before + 4, "誓约胜利之剑：合计威力精确增加4")
	check(card._power.number == 12, "誓约胜利之剑：卡面印刷威力保持12")
	check(not activate(effect_of(card, "combat")) and d.power.number == before + 4, "誓约胜利之剑：同回合第二次发动拒绝且不重复加4")

	setup(1)
	all = skills()
	d = GameData.player_data_library[0]
	card = all["excalibur"]
	if not play_skill(card): return
	battle_window(false)
	before = d.power.number
	check(not activate(effect_of(card, "combat")), "誓约胜利之剑反例：非高潮回合不能发动")
	check(d.power.number == before, "誓约胜利之剑反例：非高潮回合不增加威力")

func test_round11_victory() -> void:
	setup(11)
	var all := skills()
	var d:Dictionary = GameData.player_data_library[0]
	var card = all["excalibur"]
	if not play_skill(card): return
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_WIN], 0, null, ctx)
	check(bool(d.get("victory_override", false)), "誓约胜利之剑：赢得第11回合战斗获得胜利")

	setup(10)
	all = skills()
	d = GameData.player_data_library[0]
	card = all["excalibur"]
	if not play_skill(card): return
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_WIN], 0, null, ctx)
	check(not bool(d.get("victory_override", false)), "誓约胜利之剑反例：第10回合胜利不触发游戏胜利")

func test_zero_attribute_includes_skill() -> void:
	for pair in [["mana_resistance", "zero_opponent_magic_power", "wind_barrier", 2], ["wind_barrier", "zero_opponent_strength_power", "excalibur", 0]]:
		setup()
		place_pair(battle_area())
		var all:Dictionary = skills()
		var source:BaseSkill = all[pair[0]]
		if not play_skill(source): continue
		var servant = named(GameData.loaded_servants, "artoria_pendragon")
		var target:BaseSkill = FixtureClone.clone_template(named(servant._specials.SKILLS, pair[2]), ctx)
		RegisterObjectEffects.new().exec(target, 1, ctx)
		if not play_skill(target, 1): continue
		battle_window(false)
		check(activate(effect_of(source, pair[1])), "归零技能攻击边界：正式发动 " + str(pair[1]))
		var enemy:Dictionary = GameData.player_data_library[1]
		print("OBS ", pair[1], " 已打出敌方技能=", target._name, " 实际合计威力=", enemy.power.number, " 期望=", pair[3])
		check(enemy.power.number == pair[3], "归零技能攻击边界：" + str(pair[1]) + " 也必须归零已打出的同属性技能攻击")

func test_servant_overview() -> void:
	setup()
	var servant = FixtureClone.clone_template(named(GameData.loaded_servants, "artoria_pendragon"), ctx)
	var expected:Array = ["strength:2", "strength:3", "strength:4", "strength:4", "strength:4", "strength:5", "agility:3", "magic:2", "magic:3", "special:surveil", "special:luck", "special:luck"]
	var actual:Array = servant._specials.get("ATTACKS", []).map(func(card): return card._name)
	var wanted:Array = expected.map(func(reference): return LoadAttack.resolve(reference, ctx)._name)
	check(actual == wanted and actual.size() == 12, "阿尔托莉雅从者牌：十二张攻击构成、属性数值和重复张数与卡面一致")
	check(servant._effects.is_empty() and servant._specials.get("SKILLS", []).size() == 3 and servant._specials.get("BUFFS", []).is_empty(), "阿尔托莉雅从者牌：无额外文字效果且仅含三张技能，无附带牌")

func run() -> void:
	test_servant_overview()
	test_np_bloom()
	test_zero_magic()
	test_wind_cost()
	test_zero_strength()
	test_zero_attribute_includes_skill()
	test_excalibur_combat()
	test_round11_victory()
	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func _ready() -> void:
	call_deferred("run")
