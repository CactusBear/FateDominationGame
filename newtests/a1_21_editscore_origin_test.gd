extends Node

var checks:int = 0
var failures:Array[String] = []
var replace_mode:String = ""
var replacement:BaseNumber
var replace_marker:bool = false:
	set(value):
		replace_marker = value
		if value:
			replace_during_before()

func check(value:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", value)
	if not value:
		failures.append(label)

func new_session() -> SessionContext:
	var result:Dictionary = GameData.reset_game_session([0, 1])
	check(result.get("ok", false), "session reset accepted")
	GameLog.reset()
	return result.get("context") as SessionContext

func make_effect(name:String, funcs:Array, context:SessionContext, points:Array = []) -> BaseEffect:
	var loaded:Array = LoadHelper.load_effects([{
		"effect_name":name,
		"time_points":points,
		"priority":0,
		"is_pure_passive":true,
		"is_residue":false,
		"effect_numbers":[],
		"funcs":funcs
	}], null, context)
	check(loaded.size() == 1, "runtime effect created " + name)
	if loaded.is_empty():
		return null
	var effect:BaseEffect = loaded[0]
	effect._trigger_player_id = 0
	check(EffectManager.register_effect(effect, 0), "runtime effect registered " + name)
	return effect

func reset_probe_state() -> void:
	replace_mode = ""
	replacement = null
	replace_marker = false

func replace_during_before() -> void:
	if replace_mode == "score":
		replacement = BaseNumber.new(70)
		GameDataManager.find_player_data(0)["score"] = replacement
	elif replace_mode == "dictionary":
		var replacement_data:Dictionary = GameData.new_player_data()
		replacement_data["score"] = BaseNumber.new(80)
		GameData.player_data_library[0] = replacement_data

func install_replacement_listener(context:SessionContext, mode:String) -> void:
	replace_mode = mode
	make_effect("replace-" + mode, [{
		"func_name":"set_property",
		"parameters":[self, "replace_marker", true]
	}], context, ["self_" + TimePoints.BEFORE_SCORE_ADD])

func score_effect(context:SessionContext, name:String, amount:int) -> BaseEffect:
	return make_effect(name, [{
		"func_name":"edit_score",
		"parameters":[null, BaseNumber.new(amount), 0]
	}], context)

func same_session_score_is_legal() -> void:
	reset_probe_state()
	var context:SessionContext = new_session()
	var effect:BaseEffect = score_effect(context, "same-session-score", 3)
	EffectManager.activate_effect(effect)
	check(GameDataManager.find_player_data(0).score.number == 3, "same-session score change remains legal")
	check(GameLog.query({"type":"score_add", "actor":0}).size() == 1, "same-session score fact remains emitted")

func stale_source_cannot_reward_reused_id() -> void:
	reset_probe_state()
	var old_context:SessionContext = new_session()
	var old_effect:BaseEffect = score_effect(old_context, "old-score-source", 5)
	var old_score:BaseNumber = GameDataManager.find_player_data(0).score
	var fresh_context:SessionContext = new_session()
	var fresh_score:BaseNumber = GameDataManager.find_player_data(0).score
	EffectManager.activate_effect(old_effect)
	check(not SessionGeneration.validate_context(old_context).get("ok", false), "old source is stale after reset")
	check(SessionGeneration.validate_context(fresh_context).get("ok", false), "fresh source remains current")
	check(fresh_score.number == 0 and old_score.number == 0, "old source cannot change reused member score")
	check(GameLog.query({"type":"score_add"}).is_empty(), "stale source emits no score fact")

func replacement_is_rejected(mode:String) -> void:
	reset_probe_state()
	var context:SessionContext = new_session()
	var original_data:Dictionary = GameDataManager.find_player_data(0)
	var original_score:BaseNumber = original_data.get("score") as BaseNumber
	install_replacement_listener(context, mode)
	var effect:BaseEffect = score_effect(context, "replace-score-" + mode, 4)
	EffectManager.activate_effect(effect)
	var current:Dictionary = GameDataManager.find_player_data(0)
	check(is_same(current, original_data) if mode == "score" else not is_same(current, original_data), "replacement shape observed " + mode)
	check(original_score.number == 0, "original score is not changed after " + mode + " replacement")
	check(current.get("score").number == (70 if mode == "score" else 80), "replacement score is preserved for " + mode)
	check(GameLog.query({"type":"score_add"}).is_empty(), "replacement rejects score fact for " + mode)

func no_frame_direct_call_is_not_authorized() -> void:
	var context:SessionContext = new_session()
	var score:BaseNumber = GameDataManager.find_player_data(0).score
	EditScore.new().exec(null, BaseNumber.new(9), 0)
	check(SessionGeneration.validate_context(context).get("ok", false), "session remains current after direct rejection")
	check(score.number == 0, "no-frame direct score call does not default to writing")

func _ready() -> void:
	print("ENV user_dir=", OS.get_user_data_dir(), " pid=", OS.get_process_id())
	same_session_score_is_legal()
	stale_source_cannot_reward_reused_id()
	replacement_is_rejected("score")
	replacement_is_rejected("dictionary")
	no_frame_direct_call_is_not_authorized()
	EffectManager.activating_eff = null
	GameData.release_game_objects()
	print("RESULT ", JSON.stringify({"suite":"a1_21_editscore_origin", "checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
