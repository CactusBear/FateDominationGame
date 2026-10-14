extends Node
const FixtureClone = preload("res://newtests/fixture_clone.gd")

var ctx: SessionContext = null
var checks: int = 0
var failures: Array = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
	print("CHECK ", label, " ", ok)

func _ready() -> void:
	call_deferred("run")

func named(objects: Array, key: String):
	for object in objects:
		if object != null and object._name == key:
			return object
	return null

func effect_named(card: BaseSkill, key: String) -> BaseEffect:
	for effect: BaseEffect in card._effects:
		if effect._name == key:
			return effect
	return null

func setup(player_count: int = 3, phase: int = 2, magic: int = 20) -> void:
	var reset: Dictionary = EffectManager.reset_runtime()
	ctx = reset.get("context") if reset.get("ok", false) else null
	GameLog.reset()
	GameData.effects.clear()
	GameData.player_data_library.clear()
	MapData.active_situation = null
	for area: BaseMapArea in MapData.areas:
		area._events.clear()
		area._buffs.clear()
		for location: BaseLocation in area._locations:
			location._players.clear()
	for id in range(player_count):
		var data: Dictionary = GameData.new_player_data()
		data.is_out = false
		data.order.number = id
		data.magic.number = magic
		data.score.number = 10
		GameData.player_data_library[id] = data
	GameProgress.is_game_over = false
	GameProgress.current_round = 1
	GameProgress.current_phase_index = phase
	GameProgress.current_player_id = 0
	GameLog.set_context(1, "action" if phase == 2 else "battle")
	if phase == 2:
		TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.ACTION_PHASE, TimePoints.NON_CLIMAX], ctx)
	else:
		TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.BATTLE_PHASE, TimePoints.NON_CLIMAX], ctx)

func place(player_id: int, location: BaseLocation) -> bool:
	return bool(SetLocation.new().exec(location, player_id, false, true, true, ctx))

func skill(skill_key: String, player_id: int = 0, active: bool = true) -> BaseSkill:
	var servant = named(GameData.loaded_servants, "cu_chulainn")
	var template = named(servant._specials.get("SKILLS", []), skill_key)
	var card: BaseSkill = FixtureClone.clone_template(template, ctx)
	card._is_activating = active
	GameData.player_data_library[player_id].servant_skills.append(card)
	RegisterObjectEffects.new().exec(card, player_id, ctx)
	return card

func activate(effect: BaseEffect) -> bool:
	if not EffectManager.request_manual_activation(effect, 0):
		return false
	if effect.has_options():
		return bool(EffectManager.submit_option_choice(effect, [0]))
	return bool(EffectManager.submit_active_choice(effect, true))

func battle_effect_case(winner: int) -> void:
	setup(3, 3, 20)
	for id in range(3):
		check(place(id, MapData.miyama._locations[id]), "突穿死翔之枪真实战场落位%d" % id)
	GameData.player_data_library[0].power.number = 30 if winner == 0 else 0
	GameData.player_data_library[1].power.number = 30 if winner == 1 else 0
	GameData.player_data_library[2].power.number = 0
	var card := skill("gae_bolg_piercing", 0)
	var effect := effect_named(card, "battle_end_score_per_opponent")
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_PHASE], 0, null, ctx)
	check(activate(effect), "突穿死翔之枪战斗阶段真实发动%d" % winner)
	var before: Dictionary = {}
	for id in range(3):
		before[id] = GameData.player_data_library[id].score.number
	var result: Dictionary = BattleResolver.new(ctx).exec([0, 1, 2])
	check(not result.get("details_by_area", {}).get(MapData.miyama._area_name, {}).is_empty(), "突穿死翔之枪经过真实战斗结算%d" % winner)
	var own_adds: Array = GameLog.query({"type": "score_add", "actor": 0}, null)
	var own_effect_add := false
	for entry: Dictionary in own_adds:
		if int(entry.get("data", {}).get("delta", 0)) == 2:
			own_effect_add = true
	check(own_effect_add, "突穿死翔之枪按两名交战对手获得2战果%d" % winner)
	var loser_drop_1 := false
	var loser_drop_2 := false
	for entry: Dictionary in GameLog.query({"type": "score_decrease", "actor": 1}, null):
		if int(entry.get("data", {}).get("delta", 0)) == -2:
			loser_drop_1 = true
	for entry: Dictionary in GameLog.query({"type": "score_decrease", "actor": 2}, null):
		if int(entry.get("data", {}).get("delta", 0)) == -2:
			loser_drop_2 = true
	check(loser_drop_1 == (winner == 0) and loser_drop_2 == (winner == 0),
		"突穿死翔之枪只在自己获胜时令每名交战对手失去2战果%d" % winner)

func test_move() -> void:
	setup(1, 2, 20)
	check(place(0, MapData.miyama0), "战斗续行起点落位")
	var card := skill("battle_continuation")
	var effect := effect_named(card, "move_anywhere_except_workshop")
	TimePointChecker.dynamic_time_point([TimePoints.ACTION_PHASE], 0, null, ctx)
	check(EffectManager.request_manual_activation(effect, 0), "战斗续行行动阶段真实发动")
	check(EffectManager.submit_option_choice(effect, [0]), "战斗续行提交移动选项")
	check(not EffectManager.submit_location_selection(effect, MapData.magic_workshop0), "战斗续行拒绝魔术工房")
	setup(1, 2, 20)
	check(place(0, MapData.miyama0), "战斗续行正例起点落位")
	card = skill("battle_continuation")
	effect = effect_named(card, "move_anywhere_except_workshop")
	TimePointChecker.dynamic_time_point([TimePoints.ACTION_PHASE], 0, null, ctx)
	var magic_before: int = GameData.player_data_library[0].magic.number
	check(activate(effect) and EffectManager.submit_location_selection(effect, MapData.scout0), "战斗续行移动至非魔术工房地点")
	check(GameData.player_data_library[0].location == MapData.scout0, "战斗续行真实更新位置")
	check(GameData.player_data_library[0].magic.number == magic_before, "效果移动不是部署且不凭移动获得魔力")

func test_piercing_cost() -> void:
	setup(1, 2, 30)
	var spear := skill("gae_bolg_piercing_heart", 0, false)
	var other := skill("gae_bolg_piercing", 0, false)
	var initial: int = spear._cost.number
	GameData.player_data_library[0].regular_play_min.number = 2
	check(RegularPlay.submit_group(0, [other, spear], [false, false], false, ctx), "穿刺死棘之枪与另一张技能同批真实打出")
	check(spear._cost.number == initial + 2, "穿刺死棘之枪只在自身打出时增加2费用")
	check(other._cost.number == 7, "另一张技能不被穿刺死棘之枪改费")
	CloseCard.new().exec(spear, 0, ctx)
	GameProgress.current_round = 2
	GameLog.set_context(2, "action")
	GameData.player_data_library[0].regular_play_min.number = 1
	check(RegularPlay.submit_group(0, [spear], [false], false, ctx), "穿刺死棘之枪第二回合再次真实打出")
	check(spear._cost.number == initial + 4, "穿刺死棘之枪费用增长永久且可叠加")

func test_pierce_heart() -> void:
	for opponents in [1, 2]:
		setup(opponents + 1, 3, 20)
		check(place(0, MapData.miyama._locations[0]), "贯穿心脏己方落位%d" % opponents)
		for id in range(1, opponents + 1):
			check(place(id, MapData.miyama._locations[id]), "贯穿心脏对手落位%d-%d" % [opponents, id])
		var card := skill("gae_bolg_piercing_heart")
		var effect := effect_named(card, "placeholder_pierce_heart_single_opponent_defeat")
		TimePointChecker.dynamic_time_point([TimePoints.BATTLE_PHASE], 0, null, ctx)
		var submitted: bool = activate(effect)
		if opponents == 1:
			check(submitted, "贯穿心脏单一对手真实发动")
		else:
			print("OBS 贯穿心脏多对手提交=", submitted)
		for id in range(1, opponents + 1):
			check(DefeatBuff.get_defeat_count(id) == (1 if opponents == 1 else 0),
				"贯穿心脏单一对手条件结算%d-%d" % [opponents, id])

func run() -> void:
	test_move()
	test_piercing_cost()
	test_pierce_heart()
	battle_effect_case(0)
	battle_effect_case(1)
	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
