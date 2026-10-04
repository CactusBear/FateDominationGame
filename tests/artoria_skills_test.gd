extends Node

# 阿尔托莉雅技能牌的规则回归（用正式模板克隆，走真实的手动发动入口）：
# ① 牌上带阶段的能力每回合只能发动一次（基础规则「能力的使用限制」），换回合后恢复；
# ② 誓约胜利之剑「合计威力+4」只加本回合合计威力，不改卡面威力，回合结束 SyncPower 还原；
# ③ 「赢得第11回合的战斗获得胜利」只在牌激活时生效，也只在第 11 回合生效。
var failures:Array = []
var checks:int = 0


func check(ok:bool, label:String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
	print("CHECK ", label, " ", ok)


func _ready() -> void:
	call_deferred("run")


func setup(round:int, climax:bool) -> Dictionary:
	EffectManager.reset_runtime(); GameLog.reset(); GameLog.set_context(round, "battle")
	GameData.player_data_library.clear()
	for id in range(2):
		GameData.player_data_library[id] = GameData.new_player_data()
		GameData.player_data_library[id].is_out = false
	MapData.active_situation = null
	GameProgress.is_game_over = false
	GameProgress.current_round = round
	GameProgress.current_phase_index = 3
	GameProgress.current_player_id = 0
	LoadSituation.climax_situations = {round: true} if climax else {}
	var skills := {}
	for servant in GameData.loaded_servants:
		if servant._name == "artoria_pendragon":
			for template in servant._specials.get("SKILLS", []):
				var card = CloneObject.new().exec(template)
				skills[card._name] = card
				RegisterObjectEffects.new().exec(card, 0)
	var d:Dictionary = GameData.player_data_library[0]
	d.servant_skills = skills.values()
	return skills


func open_battle_window() -> void:
	var round_tp:String = TimePoints.CLIMAX if GameProgress.is_climax_round() else TimePoints.NON_CLIMAX
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.BATTLE_PHASE, round_tp])
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_PHASE, round_tp], 0)


func effect_of(card, effect_name:String) -> BaseEffect:
	for effect in card._effects:
		if effect._name == effect_name:
			return effect
	return null


func activate(effect:BaseEffect) -> bool:
	if not EffectManager.request_manual_activation(effect, 0):
		return false
	if effect.has_options():
		return EffectManager.submit_option_choice(effect, [0])
	return EffectManager.submit_active_choice(effect, true)


func run() -> void:
	var previous_climax:Dictionary = LoadSituation.climax_situations
	var previous_situation = MapData.active_situation
	var skills := setup(1, true)
	check(skills.size() == 3, "artoria has three skill cards")
	var d:Dictionary = GameData.player_data_library[0]
	var enemy:Dictionary = GameData.player_data_library[1]
	# 两人同在一处会战斗的战场
	var area:BaseMapArea = null
	for a in MapData.areas:
		if a._score_need_win and a._locations.size() >= 2:
			area = a
			break
	check(area != null, "a battle area with two seats exists")
	SetLocation.new().exec(area._locations[0], 0, false, true)
	SetLocation.new().exec(area._locations[1], 1, false, true)
	enemy.played_cards.append_array([
		BaseAttack.new("probe_strength", "", [Attributes.STRENGTH], BaseNumber.new(0), BaseNumber.new(5)),
		BaseAttack.new("probe_magic", "", [Attributes.MAGIC], BaseNumber.new(0), BaseNumber.new(3)),
	])
	SyncPower.new().exec(1)
	check(enemy.power.number == 8, "enemy starts at 8 power")
	for card in skills.values():
		card._is_activating = true
		d.played_cards.append(card)
	SyncPower.new().exec(0)
	var base_power:int = d.power.number
	open_battle_window()

	# ① 每回合一次
	var cases := [
		["wind_barrier", "zero_opponent_strength_power"],
		["mana_resistance", "zero_opponent_magic_power"],
		["excalibur", "combat"],
	]
	for pair in cases:
		var effect := effect_of(skills[pair[0]], pair[1])
		check(effect != null, "%s carries %s" % pair)
		if effect == null:
			continue
		check(activate(effect), "%s can be activated once" % pair[1])
		check(not EffectManager.can_manual_activate(effect, 0), "%s cannot be activated again this round" % pair[1])
	check(enemy.power.number == 0, "strength and magic zeroed exactly once " + str(enemy.power.number))
	# ② 合计威力+4，卡面不变
	var blade = skills["excalibur"]
	check(blade._power.number == 12, "excalibur printed power stays 12 " + str(blade._power.number))
	check(d.power.number == base_power + 4, "total power gains 4 once " + str(d.power.number - base_power))
	SyncPower.new().exec(0)
	check(d.power.number == base_power, "round-end sync removes the temporary bonus")
	# 换回合后次数恢复
	EffectManager.reset_round_option_counts()
	open_battle_window()
	var wind_zero := effect_of(skills["wind_barrier"], "zero_opponent_strength_power")
	check(wind_zero != null and EffectManager.can_manual_activate(wind_zero, 0), "a new round allows the ability again")

	# ③ 第 11 回合胜利：未激活不生效
	skills = setup(11, false)
	d = GameData.player_data_library[0]
	blade = skills["excalibur"]
	blade._is_activating = false
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_WIN], 0)
	check(not bool(d.get("victory_override", false)), "round 11 win does nothing while the blade is not active")
	blade._is_activating = true
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_WIN], 0)
	check(bool(d.get("victory_override", false)), "round 11 win grants victory while the blade is active")
	skills = setup(10, false)
	d = GameData.player_data_library[0]
	skills["excalibur"]._is_activating = true
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_WIN], 0)
	check(not bool(d.get("victory_override", false)), "winning another round does not grant victory")

	# 审计反例：未打出宝具不能获得宝具绽放战果。
	skills = setup(1, false)
	d = GameData.player_data_library[0]
	open_battle_window()
	var bloom := effect_of(skills["mana_resistance"], "np_bloom_score")
	var score_before = d.score.number
	check(not activate(bloom), "no NP: bloom is refused at the real activation entry")
	check(d.score.number == score_before, "no NP: score stays unchanged")

	LoadSituation.climax_situations = previous_climax
	MapData.active_situation = previous_situation
	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
