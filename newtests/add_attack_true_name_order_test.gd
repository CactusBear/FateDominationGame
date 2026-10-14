extends Node

# B18 前置行为探针：公开加载声明 -> AddAttack -> 事实顺序/真实效果/归属。
# 不替换 operation、不窥读 EffectManager/GameProgress 私有状态；对照仅去掉词条。
var failures:Array = []
var checks:int = 0

func check(ok:bool, label:String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
	print("CHECK ", label, " ", ok)

func _ready() -> void:
	call_deferred("run")

func _number(value:int) -> Dictionary:
	return {"number":value, "can_change":true, "is_pure_number":true}

func _listener(name:String, point:String, bonus:int) -> Dictionary:
	return {
		"effect_name":name, "time_points":[point], "priority":0,
		"is_pure_passive":true, "is_residue":false, "effect_numbers":[],
		"funcs":[
			{"func_name":"is_true_name_released", "parameters":[-1], "var_index":0},
			{"func_name":"edit_power", "parameters":[null, BaseNumber.new(bonus), -1],
				"condition":{"self_var":0}}
		]
	}

func _case(with_keyword:bool) -> Dictionary:
	EffectManager.reset_runtime()
	GameLog.reset()
	GameLog.set_context(1, "action")
	GameData.player_data_library.clear()
	for id in range(2):
		var data:Dictionary = GameData.new_player_data()
		data["is_out"] = false
		GameData.player_data_library[id] = data
	GameProgress.reset_progress()
	GameProgress.current_round = 1
	# 故意与显式目标 1 不同，防止 resolve/效果归属误用当前行动者。
	GameProgress.current_player_id = 0
	TimePointChecker.set_phase_time_points([])
	var prefix:String = "keyword" if with_keyword else "plain"
	var declaration:Dictionary = {
		"attack_name":"b18_" + prefix, "attack_card_img":"", "attributes":[],
		"cost":_number(0), "power":_number(2),
		"keywords":[ApplyCardKeywords.TRUE_NAME_RELEASE] if with_keyword else [],
		"effects":[
			_listener("b18_revealed", TimePoints.SELF_CARD_REVEALED, 3),
			_listener("b18_played", TimePoints.SELF_PLAYED_CARD, 5)
		]
	}
	var attack:BaseAttack = LoadGame.load_attacks([declaration], "res://data", null)[0]
	check(attack.has_keyword(ApplyCardKeywords.TRUE_NAME_RELEASE) == with_keyword,
		prefix + " public loader preserves declared keyword")
	RegisterObjectEffects.new().exec(attack, 1)
	check(not ReleaseTrueName.is_released(1), prefix + " target starts unreleased")
	var accepted = AddAttack.new().exec(attack, 1)
	check(typeof(accepted) == TYPE_BOOL and accepted, prefix + " AddAttack returns true")
	var sequence:Array = []
	for entry:Dictionary in GameLog.query({}, null, -1):
		var tags:Array = entry.get("tags", [])
		if entry.get("type") == "true_name_release" and entry.get("actor") == 1:
			sequence.append("release")
		elif entry.get("type") == "time_point":
			if tags.has(TimePoints.TRUE_NAME_RELEASE) and entry.get("actor") == 1:
				sequence.append("release_time_point")
			elif entry.get("object") == attack and tags.has(TimePoints.CARD_REVEALED):
				sequence.append("revealed")
			elif entry.get("object") == attack and tags.has(TimePoints.PLAYED_CARD) and entry.get("actor") == 1:
				sequence.append("played_card")
	var expected:Array = ["release", "release_time_point", "revealed", "played_card"] if with_keyword else ["revealed", "played_card"]
	print("ORDER ", prefix, " actual=", sequence, " expected=", expected)
	check(sequence.size() == expected.size(), prefix + " exact event count")
	for index in range(expected.size()):
		check(index < sequence.size() and sequence[index] == expected[index],
			prefix + " order[%d] == %s" % [index, expected[index]])
	var target:Dictionary = GameDataManager.get_player_data(1)
	var other:Dictionary = GameDataManager.get_player_data(0)
	var power = (target["power"] as BaseNumber).number
	print("POWER ", prefix, " target=", power, " other=", (other["power"] as BaseNumber).number)
	check(power == (10 if with_keyword else 2), prefix + " final target power includes only eligible bonuses")
	check(ReleaseTrueName.is_released(1) == with_keyword, prefix + " final true-name state belongs to target")
	check(not ReleaseTrueName.is_released(0) and (other["power"] as BaseNumber).number == 0,
		prefix + " other player remains unreleased with zero power")
	var played:Array = target["played_cards"]
	check(played.size() == 1 and is_same(played[0], attack) and (other["played_cards"] as Array).is_empty(),
		prefix + " original attack belongs only to explicit target played zone")
	var plays:Array = GameLog.query({"type":"play", "actor":1}, null, -1)
	check(plays.size() == 1 and is_same(plays[0].get("object"), attack)
		and plays[0].get("data", {}).get("extra") == true,
		prefix + " exactly one extra-play fact retains original attack and actor")
	return {"power":power, "sequence":sequence}

func run() -> void:
	var keyword:Dictionary = _case(true)
	var plain:Dictionary = _case(false)
	check(keyword.power == plain.power + 8, "keyword/control differ by both real time-point bonuses (3 + 5)")
	check(keyword.sequence != plain.sequence, "keyword/control have different ordered facts")
	print("RESULT add_attack_true_name_order checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
