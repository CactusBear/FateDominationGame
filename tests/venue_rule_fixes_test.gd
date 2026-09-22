extends Node

var failures:Array[String] = []
var checks:int = 0

func check(ok:bool, label:String) -> void:
	checks += 1
	if !ok:
		failures.append(label)
	print("CHECK ", label, " ", ok)

func template(pool:Array, key:String):
	for card in pool:
		if card._name == key:
			return card
	return null

func func_name_of(func_data) -> String:
	if func_data is BaseFunc:
		return func_data._name
	if func_data is Dictionary:
		return str(func_data.get("func_name", ""))
	return ""

func parameters_of(func_data) -> Array:
	if func_data is BaseFunc:
		return func_data._parameters
	if func_data is Dictionary:
		return func_data.get("parameters", []) as Array
	return []

func find_func(funcs:Array, func_name:String):
	for func_data in funcs:
		if func_name_of(func_data) == func_name:
			return func_data
		for parameter in parameters_of(func_data):
			if parameter is Array:
				var nested = find_func(parameter, func_name)
				if nested != null:
					return nested
	return null

func run() -> void:
	# A01: 倒数排名必须按照战果而不是威力。
	var desperate = template(LoadEvent.events, "desperate_measure")
	var rank_func = find_func(desperate._effects[0]._power_query, "get_rank_by_data_number")
	var rank_parameters = parameters_of(rank_func)
	check(rank_func != null and rank_parameters[0] == "score", "A01 desperate measure ranks score")

	# A02: foreach 的当前玩家应填第0个参数（store_value 的唯一空槽）。
	for event_name in ["cooperation", "occupy_high_ground"]:
		var event_card = template(LoadEvent.events, event_name)
		var foreach_func = find_func(event_card._effects[0]._power_query, "foreach_func")
		var foreach_parameters = parameters_of(foreach_func)
		check(foreach_func != null and foreach_parameters[2] == 0, "A02 " + event_name + " fills player at parameter 0")
	var hope = template(LoadSituation.situations, "hope_for_future")
	var hope_foreach = find_func(hope._effects[0]._power_query, "foreach_func")
	var hope_foreach_parameters = parameters_of(hope_foreach)
	check(hope_foreach != null and hope_foreach_parameters[2] == 0, "A02 hope for future fills player at parameter 0")

	# A03: 高潮局势只按顺位链中的在场玩家人数判定。
	for situation_name in ["night_of_fate", "gate_of_hell", "heavens_feel"]:
		var situation = template(LoadSituation.climax_situations.values(), situation_name)
		var length_func = situation._effects[0]._funcs[0]
		var nested = parameters_of(length_func)[0] as Dictionary
		check(nested.get("func_name", "") == "get_active_players_id", "A03 " + situation_name + " counts active players")

	# A07: 只限攻击牌类型，不能把类别限制为基础攻击。
	var contain = template(LoadEvent.events, "contain_third_party")
	var contain_foreach = find_func(contain._effects[0]._power_query, "foreach_func")
	var attack_contribution = parameters_of(contain_foreach)[0][0] as Dictionary
	check(attack_contribution["parameters"][5] == "", "A07 contain third party accepts every BaseAttack category")

	# A08: 战斗结束后，只给本回合该区域实际参战者魔力。
	var ley_line = template(LoadEvent.events, "ley_line")
	var ley_effect = ley_line._effects[0]
	check(ley_effect._time_points == [TimePoints.BATTLE_END], "A08 ley line resolves at battle end")
	check(find_func(ley_effect._funcs, "get_area_round_participants") != null, "A08 ley line queries area round participants")
	GameLog.reset()
	GameLog.set_context(1, "battle")
	var round_area = MapData.areas[1]
	GameLog.record("battle", 2, -1, round_area._area_name, null, ["battle"], {"players": [2, 4]})
	GameLog.record("battle", 4, -1, round_area._area_name, null, ["battle"], {"players": [2, 4]})
	check(GetAreaRoundParticipants.new().exec(round_area) == [2, 4], "A08 participants are unique and scoped to the round area")

	# 命运之战：JSON 1/2 与 BaseNumber 印刷威力可规范匹配。
	check(MatchFunc.new().exec(BaseNumber.new(1), [1, 2]), "fate battle matches BaseNumber against JSON integers")

	print("RESULT checks=", checks, " failures=", failures)
	var result = FileAccess.open("res://venue_rule_fixes_result.json", FileAccess.WRITE)
	result.store_string(JSON.stringify({"checks": checks, "failures": failures}))
	result.close()
	get_tree().quit(0 if failures.is_empty() else 1)

func _ready() -> void:
	call_deferred("run")
