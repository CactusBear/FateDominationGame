extends Node

var checks:int = 0
var failures:Array = []
var observations:Dictionary = {}

func check(ok:bool, label:String) -> void:
	checks += 1
	if !ok:
		failures.append(label)
	print("CHECK ", label, " ", ok)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	# Capture known-player outputs identically on baseline/candidate, including object identity.
	var reset:Dictionary = GameData.reset_game_session([0, 1, 2])
	check(bool(reset.get("ok", false)), "fixture_session_ready")
	var own:Dictionary = GameData.player_data_library[0]
	var opponent:Dictionary = GameData.player_data_library[1]
	var clone:Dictionary = GameData.player_data_library[2]
	own.is_out = false
	opponent.is_out = false
	clone.is_out = false
	clone.controller = 0
	var area := BaseMapArea.new("readonly_query_fixture")
	var seat := BaseLocation.new(BaseNumber.new(0), BaseNumber.new(2), -1)
	var second := BaseLocation.new(BaseNumber.new(0), BaseNumber.new(3), -1)
	area._locations = [seat, second]
	seat.from = area
	second.from = area
	seat._players = [0, 1, 2]
	second._players = [0]
	own.location = seat
	opponent.location = seat
	clone.location = seat
	own.location_benefit_bonus = BaseNumber.new(4)
	GameLog.record("deploy", 0, -1, "", seat, [], {})
	GameLog.record("deploy", 0, -1, "", second, [], {})
	var attack := BaseAttack.new("readonly_attack", "", ["fixture_shared", "fixture_a"])
	var other_attack := BaseAttack.new("readonly_other", "", ["fixture_shared", "fixture_b"])
	own.played_cards = [attack, other_attack]
	own.hand_cards = [attack]
	own["fixture_dict"] = {"a": 1, "b": 2}
	own["fixture_int"] = 7
	own["fixture_float"] = 1.5
	observations["number"] = [GetDataNumber.new().exec("magic", 0), GetDataNumber.new().exec("hand_cards", 0), GetDataNumber.new().exec("fixture_dict", 0), GetDataNumber.new().exec("fixture_int", 0), GetDataNumber.new().exec("fixture_float", 0), GetDataNumber.new().exec("absent", 0)]
	check(observations.number == [4, 1, 2, 7, null, null], "known_number_contract")
	observations["shared"] = GetSharedAttackAttribute.new().exec(0)
	check(observations.shared == "fixture_shared", "known_shared_attribute")
	var found = FindPlayerArrayContaining.new().exec(attack, 0)
	check(is_same(found, own.hand_cards), "known_array_first_match_identity")
	check(FindPlayerArrayContaining.new().exec("missing", 0) == null, "known_array_not_found")
	own.extra_zones = {"fixture": ["extra_item"]}
	check(is_same(FindPlayerArrayContaining.new().exec("extra_item", 0), own.extra_zones.fixture), "known_extra_zone_identity")
	observations["benefit"] = GetEffectiveLocationBenefit.new().exec(0)
	check(observations.benefit == 9, "known_multiple_seats_bonus_once")
	observations["engaged"] = IsEngaged.new().exec(0)
	check(observations.engaged, "known_opponent_engaged")
	opponent.is_out = true
	check(!IsEngaged.new().exec(0), "known_own_clone_not_opponent")
	opponent.is_out = false
	area._score_need_win = false
	check(!IsEngaged.new().exec(0), "known_nonbattle_area_not_engaged")
	area._score_need_win = true
	own.location = null
	check(GetEffectiveLocationBenefit.new().exec(0) == 0, "known_no_location_benefit_zero")
	check(!IsEngaged.new().exec(0), "known_no_location_not_engaged")
	own.location = seat

	# Each query gets its own unknown ID; compare exact keys immediately, not a late aggregate.
	var queries:Array = [
		["number", func(id): return GetDataNumber.new().exec("absent", id), null],
		["shared", func(id): return GetSharedAttackAttribute.new().exec(id), null],
		["benefit", func(id): return GetEffectiveLocationBenefit.new().exec(id), 0],
		["array", func(id): return FindPlayerArrayContaining.new().exec("missing", id), null],
		["engaged", func(id): return IsEngaged.new().exec(id), false]
	]
	for index in queries.size():
		var query:Array = queries[index]
		for unknown in [91000 + index, -91000 - index]:
			var keys:Array = GameData.player_data_library.keys()
			var result = query[1].call(unknown)
			check(result == query[2], "unknown_" + query[0] + "_default_" + str(unknown))
			check(!GameData.player_data_library.has(unknown) and GameData.player_data_library.keys() == keys, "unknown_" + query[0] + "_no_create_" + str(unknown))
			GameData.player_data_library.erase(unknown)

	# Existing getter and real command consumers retain their lazy-create contract.
	var lazy:Dictionary = GameDataManager.get_player_data(92000)
	check(GameData.player_data_library.has(92000) and is_same(lazy, GameData.player_data_library[92000]), "legacy_getter_creates_same_dictionary")
	check(lazy.magic.number == 4 and lazy.command_spell_count.number == 3, "legacy_getter_default_resources")
	check(is_same(GameDataManager.get_player_data(92000), lazy), "legacy_getter_reuses_dictionary")
	EditLives.new().exec(null, BaseNumber.new(2), 92001)
	check(GameData.player_data_library.has(92001), "legacy_edit_lives_creates_unknown")
	check(GameData.player_data_library[92001].lives.number == 3, "legacy_edit_lives_creates_and_writes")
	var skill := BaseSkill.new("readonly_skill", "", [])
	check(is_same(AddSkillToSkillZone.new().exec(skill, 92002), skill), "legacy_add_skill_accepts_unknown")
	check(GameData.player_data_library.has(92002) and GameData.player_data_library[92002].side.skills.has(skill), "legacy_add_skill_creates_and_writes")
	# Reflection keeps the original implementation runnable for the RED baseline.
	if GameDataManager.has_method("get_player_data_readonly"):
		var keys:Array = GameData.player_data_library.keys()
		var absent:Dictionary = GameDataManager.call("get_player_data_readonly", 93000)
		check(absent.is_empty() and GameData.player_data_library.keys() == keys, "readonly_entry_missing_no_create")
		absent["probe"] = true
		check(!GameData.player_data_library.has(93000), "readonly_empty_result_is_not_inserted")
		check(is_same(GameDataManager.call("get_player_data_readonly", 0), own), "readonly_entry_known_same_dictionary")
	print("OBSERVATIONS ", JSON.stringify(observations))
	print("PATHS ", JSON.stringify({"user":OS.get_user_data_dir(), "pid":OS.get_process_id()}))
	print("RESULT ", JSON.stringify({"suite":"readonly_query_no_create", "checks":checks, "failures":failures}))
	GameData.release_game_objects()
	get_tree().quit(0 if failures.is_empty() else 1)
