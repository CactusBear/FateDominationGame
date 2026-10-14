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

func setup(player_count: int = 3, phase: int = 2, magic: int = 30) -> void:
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
	var servant = named(GameData.loaded_servants, "medusa")
	var template = named(servant._specials.get("SKILLS", []), skill_key)
	var card: BaseSkill = FixtureClone.clone_template(template, ctx)
	card._is_activating = active
	GameData.player_data_library[player_id].servant_skills.append(card)
	RegisterObjectEffects.new().exec(card, player_id, ctx)
	return card

func make_attack(key: String) -> BaseAttack:
	return FixtureClone.clone_template(LoadAttack.resolve(key), ctx)

func activate(effect: BaseEffect) -> bool:
	if not EffectManager.request_manual_activation(effect, 0):
		return false
	if effect.has_options():
		return bool(EffectManager.submit_option_choice(effect, [0]))
	return bool(EffectManager.submit_active_choice(effect, true))

func play_skill(card: BaseSkill) -> bool:
	GameProgress.current_phase_index = 2
	GameProgress.current_player_id = 0
	GameLog.set_context(GameProgress.current_round, "action")
	GameData.player_data_library[0].regular_play_min.number = 1
	return bool(RegularPlay.submit_group(0, [card], [false], false, ctx))

func activate_location(effect: BaseEffect, location: BaseLocation) -> bool:
	if not EffectManager.request_manual_activation(effect, 0):
		return false
	if not EffectManager.submit_option_choice(effect, [0]):
		return false
	return bool(EffectManager.submit_location_selection(effect, location))

func test_riding_draw() -> void:
	setup(1, 2, 30)
	var riding := skill("riding", 0, false)
	var attack := make_attack("strength:2")
	var drawn := make_attack("agility:2")
	var data: Dictionary = GameData.player_data_library[0]
	data.hand_cards.append(attack)
	data.deck.append(drawn)
	data.regular_play_min.number = 2
	check(RegularPlay.submit_group(0, [riding, attack], [false, false], false, ctx), "骑乘与基础攻击同批真实打出")
	check(data.hand_cards.has(drawn) and data.deck.is_empty(), "骑乘同批基础攻击真实抽1张牌")
	setup(1, 2, 30)
	riding = skill("riding", 0, false)
	drawn = make_attack("agility:2")
	data = GameData.player_data_library[0]
	data.deck.append(drawn)
	check(play_skill(riding), "骑乘单独真实打出")
	check(data.deck.has(drawn) and not data.hand_cards.has(drawn), "骑乘未与基础攻击同批不抽牌")

func test_riding_summon() -> void:
	setup(1, 2, 30)
	var riding := skill("riding")
	var low_cards: Array = []
	for index in range(4):
		var low := make_attack("strength:2")
		low_cards.append(low)
		GameData.player_data_library[0].hand_cards.append(low)
	var high := make_attack("strength:5")
	GameData.player_data_library[0].hand_cards.append(high)
	TimePointChecker.dynamic_time_point([TimePoints.ACTION_PHASE], 0, null, ctx)
	var effect := effect_named(riding, "riding_mount_summon_play_low_power_cards")
	check(EffectManager.request_manual_activation(effect, 0), "坐骑召唤行动阶段真实发动")
	check(EffectManager.submit_option_choice(effect, [0]), "坐骑召唤提交选项")
	var pending: Dictionary = EffectManager.get_pending_card_selection()
	check(not (pending.get("cards", []) as Array).has(high), "坐骑召唤排除基本威力大于3的手牌")
	check(EffectManager.submit_card_selection(effect, [low_cards[0], low_cards[1], low_cards[2]]), "坐骑召唤至多3张选择被接受")
	check(GameData.player_data_library[0].played_cards.has(low_cards[0]) and GameData.player_data_library[0].played_cards.has(low_cards[1]) and GameData.player_data_library[0].played_cards.has(low_cards[2]), "坐骑召唤真实打出3张低威力手牌")
	check(not GameData.player_data_library[0].played_cards.has(low_cards[3]), "坐骑召唤第四张低威力手牌未超过至多3张")

func test_bellerophon() -> void:
	setup(3, 2, 30)
	check(place(0, MapData.shinto2), "骑英之缰绳非战场边界起点落位")
	var card := skill("bellerophon", 0, false)
	check(play_skill(card), "骑英之缰绳真实打出")
	check(IsTrueNameReleased.new().exec(0), "骑英之缰绳真实真名解放")
	var data: Dictionary = GameData.player_data_library[0]
	var magic_before: int = data.magic.number
	check(activate_location(effect_named(card, "bellerophon_redeploy_terrain"), MapData.scout0), "骑英之缰绳移动至非战场席位")
	check(data.location == MapData.scout0, "骑英之缰绳非战场移动真实生效")
	check(data.magic.number == magic_before, "骑英之缰绳移入非战场不是部署且不获得魔术工房魔力")
	setup(3, 2, 30)
	check(SetLocation.new().exec(MapData.magic_workshop0, 0, false, true, true, ctx), "骑英之缰绳战场正例起点落位")
	check(Deploy.new().exec(MapData.miyama0, 1, false, ctx), "骑英之缰绳目标战场已有玩家1")
	check(Deploy.new().exec(MapData.miyama1, 2, false, ctx), "骑英之缰绳目标战场已有玩家2")
	card = skill("bellerophon", 0, false)
	check(play_skill(card), "骑英之缰绳战场正例真实打出")
	check(activate_location(effect_named(card, "bellerophon_redeploy_terrain"), MapData.miyama2), "骑英之缰绳移动并重新部署地利")
	check(GetLocation.new().exec(0) == MapData.miyama1, "骑英之缰绳占据目标战场地利")
	check(GetLocation.new().exec(1) == MapData.miyama2 and GetLocation.new().exec(2) == MapData.miyama2, "骑英之缰绳原地利占领者移至目标战场")

func petrification_case(has_magic: bool) -> void:
	setup(2, 2, 30)
	check(place(0, MapData.miyama0), "石化之魔眼己方落位%s" % has_magic)
	check(place(1, MapData.miyama1), "石化之魔眼对手落位%s" % has_magic)
	var card := skill("eyes_of_petrification")
	var effect := effect_named(card, "petrification_defeat_if_no_magic_attack")
	if has_magic:
		GameData.player_data_library[1].played_cards.append(make_attack("magic:3"))
	TimePointChecker.dynamic_time_point([TimePoints.ACTION_PHASE], 0, null, ctx)
	check(EffectManager.get_pending_active_effect() == effect, "石化之魔眼进入行动阶段激活窗口%s" % has_magic)
	check(EffectManager.submit_active_choice(effect, true), "石化之魔眼行动阶段真实发动%s" % has_magic)
	GameProgress.current_phase_index = 3
	GameProgress.current_player_id = 0
	GameLog.set_context(1, "battle")
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.BATTLE_PHASE, TimePoints.NON_CLIMAX], ctx)
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_PHASE_START], 0, null, ctx)
	check(DefeatBuff.is_defeated(1) == (not has_magic), "石化之魔眼仅在对手无魔术属性攻击时令其败北%s" % has_magic)

func run() -> void:
	test_riding_draw()
	test_riding_summon()
	test_bellerophon()
	petrification_case(false)
	petrification_case(true)
	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
