extends Node

var checks:int = 0
var failures:Array = []
var observations:Dictionary = {}

class ClearObserver extends RefCounted:
	var context:SessionContext
	var observed:Dictionary
	var rotate:bool
	func _init(c:SessionContext, out:Dictionary, reenter:bool = false):
		context = c
		observed = out
		rotate = reenter
	func _notification(what:int):
		if what == NOTIFICATION_PREDELETE:
			observed["valid_at_clear"] = SessionGeneration.validate_context(context).ok
			observed["hits"] = int(observed.get("hits", 0)) + 1
			if rotate:
				observed["new_token"] = SessionGeneration.begin_generation(&"probe_clear_reentry").token

func check(ok:bool, label:String):
	checks += 1
	if not ok: failures.append(label)
	print("CHECK ", label, " ", ok)

func fresh() -> SessionContext:
	GameData.reset_game_session([0, 1, 2])
	for id in [0, 1, 2]:
		SetPlayerData.new().exec("is_out", false, id)
	GameLog.reset()
	return SessionGeneration.derive_context(SessionGeneration.current_token().token, &"probe_progress").context

func reset_cases():
	var old:SessionContext = fresh()
	var root:Dictionary = GameData.player_data_library
	var member:Dictionary = root[0]
	var areas:Array = MapData.areas
	var out:Dictionary = {}
	GameProgress.last_battle_result["observer"] = ClearObserver.new(old, out)
	GameProgress.reset_progress(false)
	check(out.get("hits", 0) == 1, "reset real clear observer ran")
	check(not out.get("valid_at_clear", true), "reset revokes before first clear callback")
	check(not SessionGeneration.validate_context(old).ok, "reset rejects old context with identical members and map")
	check(is_same(root, GameData.player_data_library) and is_same(member, root[0]) and is_same(areas, MapData.areas), "reset preserves member root member and map identity")
	check(SessionGeneration.current_token().ok, "reset opens explicit default domain")
	check(GameProgress.current_round == 0 and GameProgress.current_phase_index == -1, "reset clears progress")

func composition_cases():
	var c:SessionContext = fresh()
	var template:BaseAttack = BaseAttack.new("A1-08-template", "", [], BaseNumber.new(2), BaseNumber.new(3))
	var servant:BaseServant = BaseServant.new("A1-08-servant", "", "", "", "")
	servant._specials = {"ATTACKS":[template]}
	SetPlayerData.new().exec("servant", servant, 0)
	var subject:BaseEffect = install_listener(TimePoints.GAME_START, Callable(self, "observe_start_source"), c)
	observations["startup_context"] = c
	observations["startup_hits"] = 0
	var binding:Dictionary = SessionGeneration.origin_of(subject)
	var out:Dictionary = GameProgress.call("start_game", c)
	check(out.ok and is_same(out.context, c), "start returns original verified startup context")
	check(is_same(SessionGeneration.current_token().token, c.token()), "start retains exact outer token")
	check(binding.ok and SessionGeneration.origin_of(subject).ok, "prebound trusted runtime survives composed start")
	check(GameProgress.current_round == 1 and not GameLog.query({"type":"time_point"}, null).is_empty(), "composed start executes real first round and dispatch")
	check(SessionGeneration.validate_context(c).ok, "ordinary round and phase never rotate domain")
	check(observations.get("startup_hits", 0) == 1 and observations.get("startup_valid", false), "prebound runtime GAME_START listener dispatches in exact outer domain")
	var dealt:Array = GameDataManager.find_player_data(0).hand_cards + GameDataManager.find_player_data(0).deck
	check(dealt.size() == 1 and not is_same(dealt[0], template) and is_same(SessionGeneration.current_token().token, c.token()), "real composed start deals cloned template card without changing outer domain")
	EffectManager.unregister_effect(subject)
	var old:SessionContext = c
	out = GameProgress.call("start_game")
	check(out.ok and not SessionGeneration.validate_context(old).ok, "standalone start revokes old context")
	check(SessionGeneration.validate_context(out.context).ok and GameProgress.current_round == 1, "standalone start opens before real dispatch")
	c = out.context
	for invalid in [old, SessionContext.new(c.token(), &"forged"), 42, {}, RefCounted.new()]:
		var token:SessionToken = SessionGeneration.current_token().token
		var round_before:int = GameProgress.current_round
		var logs_before:int = GameLog.query({}, null).size()
		out = GameProgress.call("start_game", invalid)
		check(not out.ok and is_same(token, SessionGeneration.current_token().token) and round_before == GameProgress.current_round and logs_before == GameLog.query({}, null).size(), "invalid start never clears rotates or dispatches type=" + str(typeof(invalid)))
	out = GameProgress.call("reset_progress", false, null, &"invalidate")
	check(out.ok and not SessionGeneration.current_token().ok and not SessionGeneration.validate_context(c).ok, "explicit shutdown reset stays closed")
	out = GameProgress.call("reset_progress", false, null, &"invalidate")
	check(out.ok and not SessionGeneration.current_token().ok, "repeated shutdown reset never reopens")

func reentry_cases():
	var c:SessionContext = fresh()
	var out:Dictionary = {}
	GameProgress.last_battle_result["observer"] = ClearObserver.new(c, out, true)
	var result:Dictionary = GameProgress.call("start_game", c)
	check(out.get("hits", 0) == 1, "start real clear reentry callback ran")
	check(not result.ok and is_same(SessionGeneration.current_token().token, out.new_token), "old start rejects clear reentry without replacing new owner domain")
	check(GameProgress.current_round == 0 and GameLog.query({"type":"time_point"}, null).is_empty(), "old start performs no dispatch after clear reentry")

func saved_tail_cases():
	var c:SessionContext = fresh()
	GameProgress.call("reset_progress", false, c)
	var old_tail:Callable = Callable(GameProgress, "_dispatch_game_start").bind(c)
	var old_finish:Callable = Callable(GameProgress, "end_current_player_action").bind(c)
	GameProgress.reset_progress()
	GameProgress.current_round = 4
	GameProgress.current_phase_index = 2
	GameProgress.current_player_id = 0
	GameProgress.current_phase_player_index = 1
	var before:int = GameLog.query({}, null).size()
	old_tail.call()
	check(GameProgress.current_round == 4 and GameLog.query({}, null).size() == before, "saved startup tail cannot refresh source after progress-only reset")
	check(not old_finish.call() and GameProgress.current_player_id == 0 and GameProgress.current_phase_player_index == 1 and GameLog.query({}, null).size() == before, "saved action finish cannot advance after progress-only reset")

func async_cases():
	var c:SessionContext = fresh()
	GameProgress.call("reset_progress", false, c)
	GameProgress.current_round = 1
	get_tree().paused = true
	GameProgress.end_round()
	await get_tree().process_frame
	GameProgress.reset_progress()
	GameProgress.current_round = 5
	var before:int = GameLog.query({}, null).size()
	get_tree().paused = false
	await get_tree().process_frame
	await get_tree().process_frame
	check(GameProgress.current_round == 5 and GameLog.query({}, null).size() == before, "paused end-round tail rejects old captured context after reset")
	c = SessionGeneration.derive_context(SessionGeneration.current_token().token, &"probe_round").context
	GameProgress.current_round = 1
	get_tree().paused = true
	GameProgress.call("end_round", c)
	await get_tree().process_frame
	var progress_before:Array = [GameProgress.current_round, GameProgress.current_phase_index, GameProgress.current_player_id]
	SessionGeneration.begin_generation(&"probe_async_external_switch")
	check(progress_before == [GameProgress.current_round, GameProgress.current_phase_index, GameProgress.current_player_id] and not SessionGeneration.validate_context(c).ok, "paused external switch revokes source without touching public progress")
	GameProgress.current_round = int(GameProgress.total_rounds.number)
	get_tree().paused = false
	await get_tree().process_frame
	await get_tree().process_frame
	check(GameProgress.current_round == int(GameProgress.total_rounds.number) and not GameProgress.is_game_over and GameLog.query({"type":"game_end"}, null).is_empty(), "paused tail cannot advance or end new domain after external switch")
	c = SessionGeneration.derive_context(SessionGeneration.current_token().token, &"probe_round").context
	GameProgress.call("reset_progress", false, c)
	GameProgress.current_round = 1
	GameProgress.end_round()
	await get_tree().process_frame
	print("ASYNC_OBS ", JSON.stringify({"round":GameProgress.current_round, "context_valid":SessionGeneration.validate_context(c).ok, "game_over":GameProgress.is_game_over, "waiting":EffectManager.is_waiting_for_choice(), "active":GameDataManager.get_active_player_ids()}))
	check(GameProgress.current_round == 2 and SessionGeneration.validate_context(c).ok, "legal same-domain end-round advances without rotation")

func observe_start_source():
	observations["startup_hits"] += 1
	observations["startup_valid"] = SessionGeneration.validate_context(observations.startup_context).ok

func install_listener(point:String, callback:Callable, c:SessionContext) -> BaseEffect:
	var e:BaseEffect = BaseEffect.new("A1-08-real-callback", [point], 0, true, false)
	var f:BaseFunc = BaseFunc.new(callback, [])
	f._name = "a1_08_callback"
	e._funcs = [f]
	var bound:Dictionary = SessionGeneration.bind_origin(e, c.token(), &"probe_trusted_listener")
	e.bind_runtime_context(bound.context)
	SessionGeneration.bind_origin(f, c.token(), &"probe_trusted_listener_func")
	EffectManager.register_effect(e, 0)
	return e

func switch_during_day_end():
	observations["callback_hits"] = int(observations.get("callback_hits", 0)) + 1
	observations["new_token"] = SessionGeneration.begin_generation(&"probe_external_lifecycle").token
	GameProgress.current_round = int(GameProgress.total_rounds.number)

func callback_cases():
	var c:SessionContext = fresh()
	GameProgress.call("reset_progress", false, c)
	GameProgress.current_round = 1
	var e:BaseEffect = install_listener(TimePoints.DAY_END, Callable(self, "switch_during_day_end"), c)
	var progress_before:Array = [GameProgress.current_round, GameProgress.current_phase_index, GameProgress.current_player_id]
	observations.clear()
	GameProgress.end_round()
	check(observations.get("callback_hits", 0) == 1, "real DAY_END listener performs synchronous generation switch")
	check(progress_before[0] == 1 and not SessionGeneration.validate_context(c).ok, "external lifecycle invalidates original synchronous round source")
	check(GameProgress.current_round == int(GameProgress.total_rounds.number) and not GameProgress.is_game_over and GameLog.query({"type":"game_end"}, null).is_empty(), "old synchronous end-round cannot advance or finish new domain")
	check(is_same(observations.get("new_token"), SessionGeneration.current_token().token), "old synchronous tail never replaces new owner token")
	EffectManager.unregister_effect(e)

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run")

func run():
	var mode:String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "all"
	if mode in ["all", "reset"]: reset_cases()
	if mode in ["all", "composition"]: composition_cases()
	if mode in ["all", "reentry"]: reentry_cases()
	if mode in ["all", "tails"]: saved_tail_cases()
	if mode in ["all", "async"]: await async_cases()
	if mode in ["all", "callback"]: callback_cases()
	print("RESULT ", JSON.stringify({"suite":"A1-08-" + mode, "checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
