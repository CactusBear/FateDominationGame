extends Node

# B30 前置：真实 PlayAttack 单卡显式 ignore_limit 分支，不经过 AddAttack/RegularPlay。
# 只用公开加载/登记/查询 API；无私有状态读取。无词条与默认拒绝为独立对照。
var checks:int = 0
var failures:Array = []

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
	GameProgress.reset_progress()
	GameLog.reset()
	GameLog.set_context(1, "action")
	GameProgress.current_round = 1
	GameProgress.current_phase_index = 2
	GameProgress.current_player_id = 1
	TimePointChecker.set_phase_time_points([])
	GameData.player_data_library.clear()
	for id in range(2):
		var data:Dictionary = GameData.new_player_data()
		data["is_out"] = false
		GameData.player_data_library[id] = data
	var target:Dictionary = GameDataManager.get_player_data(1)
	target["magic"] = BaseNumber.new(6)
	target["play_limit"] = BaseNumber.new(0)
	var prefix:String = "keyword" if with_keyword else "plain"
	var attack:BaseAttack = LoadGame.load_attacks([{
		"attack_name":"b30_" + prefix, "attack_card_img":"", "attributes":["strength"],
		"cost":_number(2), "power":_number(2),
		"keywords":[ApplyCardKeywords.TRUE_NAME_RELEASE] if with_keyword else [],
		"effects":[
			_listener("b30_revealed", TimePoints.SELF_CARD_REVEALED, 3),
			_listener("b30_played", TimePoints.SELF_PLAYED_CARD, 5)
		]
	}], "res://data", null)[0]
	target["hand_cards"].append(attack)
	RegisterObjectEffects.new().exec(attack, 1)
	check(attack.has_keyword(ApplyCardKeywords.TRUE_NAME_RELEASE) == with_keyword,
		prefix + " loader preserves declared keyword")
	check(not ReleaseTrueName.is_released(1), prefix + " target starts unreleased")
	# 默认单卡入口没有 activating_eff 必须拒绝；不能偷走 AddAttack。
	check(not PlayAttack.new().exec(attack, 1), prefix + " default single-card entry rejects")
	check((target["magic"] as BaseNumber).number == 6
		and (target["power"] as BaseNumber).number == 0
		and target["hand_cards"].has(attack) and target["played_cards"].is_empty()
		and not ReleaseTrueName.is_released(1) and GameLog.query({"type":"play"}, null, -1).is_empty(),
		prefix + " rejected entry leaves resources source and keyword untouched")
	check(PlayAttack.new().exec(attack, 1, null, null, true),
		prefix + " explicit ignore_limit PlayAttack accepts at zero play_limit")
	var power = (target["power"] as BaseNumber).number
	var magic = (target["magic"] as BaseNumber).number
	print("BUSINESS ", prefix, " power=", power, " magic=", magic)
	check(power == (10 if with_keyword else 2),
		prefix + " PlayAttack power includes eligible revealed and played bonuses")
	check(ReleaseTrueName.is_released(1) == with_keyword,
		prefix + " PlayAttack true-name result belongs to target")
	check(magic == 4, prefix + " PlayAttack pays printed cost (unlike AddAttack)")
	var other:Dictionary = GameDataManager.get_player_data(0)
	check(not ReleaseTrueName.is_released(0) and (other["power"] as BaseNumber).number == 0
		and other["played_cards"].is_empty(), prefix + " other player is untouched")
	check(target["played_cards"].size() == 1 and is_same(target["played_cards"][0], attack)
		and not target["hand_cards"].has(attack),
		prefix + " PlayAttack moves original hand attack into target played zone")
	check(attack.has_attribute("strength"), prefix + " declared attribute survives")
	var plays:Array = GameLog.query({"type":"play", "actor":1}, null, -1)
	check(plays.size() == 1 and is_same(plays[0].get("object"), attack)
		and plays[0].get("data", {}).get("extra") == true
		and not plays[0].get("tags", []).has("extra"),
		prefix + " PlayAttack fact retains original actor and differs from AddAttack tags")
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
	check(sequence == expected, prefix + " PlayAttack release precedes revealed and played facts")
	return {"power":power, "magic":magic, "sequence":sequence}

func run() -> void:
	var keyword:Dictionary = _case(true)
	var plain:Dictionary = _case(false)
	check(keyword.power == plain.power + 8, "PlayAttack keyword/control differ by real bonuses (3 + 5)")
	check(keyword.sequence != plain.sequence, "PlayAttack keyword/control differ in ordered facts")
	check(keyword.magic == plain.magic, "keyword/control pay equal cost")
	EffectManager.reset_runtime()
	print("RESULT play_attack_keyword_behavior checks=", checks, " failures=", JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
