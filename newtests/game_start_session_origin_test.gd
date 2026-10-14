extends Node

var checks:int = 0
var failures:Array = []
var seen:Dictionary = {}
var startup_effect:BaseEffect
var startup_master:BaseMaster
const RuleRandom = preload("res://scripts/match/rule_random.gd")

# 普通域已登记 set_property 的真实写入边界；测试钩子不作为规则 Callable。
# 不用于封闭能力域，也不宣称任意 setter 的能力闭包已经获证。
class DispatchProbe extends RefCounted:
	var host:Node
	var dispatched:bool = false:
		set(value):
			dispatched = value
			if value:
				host.observe_dispatch()
	func _init(owner:Node):
		host = owner

class ClearObserver extends RefCounted:
	var old:SessionContext
	var output:Dictionary
	var site:String
	var host:Node
	var action:String
	func _init(c:SessionContext, out:Dictionary, label:String, owner:Node = null, mode:String = ""):
		old = c
		output = out
		site = label
		host = owner
		action = mode
	func _notification(what:int):
		if what == NOTIFICATION_PREDELETE:
			output[site] = {"old_valid":SessionGeneration.validate_context(old).ok, "current":SessionGeneration.current_token().token}
			if host != null:
				host.on_clear(action)

func check(ok:bool, label:String) -> void:
	checks += 1
	if not ok: failures.append(label)
	print("CHECK ", label, " ", ok)

func context() -> SessionContext:
	return SessionGeneration.derive_context(SessionGeneration.current_token().token, &"A1-09.probe").context

func on_clear(action:String) -> void:
	if action in ["bind", "bind_invalidate"]:
		var c:SessionContext = context()
		seen["binding_context"] = c
		seen["invalidate_on_dispatch"] = action == "bind_invalidate"
		startup_effect = BaseEffect.new("A1-09-role-start", [TimePoints.GAME_START], 0, true, false)
		var origin:Dictionary = SessionGeneration.bind_origin(startup_effect, c.token(), &"A1-09.trusted_role_factory")
		seen["factory_bound"] = startup_effect.bind_runtime_context(origin.context)
		var probe := DispatchProbe.new(self)
		var f:BaseFunc = LoadHelper.load_funcs([{"func_name":"set_property", "parameters":[probe, "dispatched", true]}], startup_effect, c)[0]
		seen["func_bound"] = f.runtime_source_status(startup_effect, c).ok
		startup_effect.add_func(f)
		startup_effect.from = startup_master
		startup_master._effects = [startup_effect]
	elif action == "pause_guard":
		var c:SessionContext = context()
		seen["failed_token"] = c.token()
		var effect:BaseEffect = BaseEffect.new("A1-09-config-failure", [], 0, true, false)
		var binding:Dictionary = SessionGeneration.bind_origin(effect, c.token(), &"A1-09.guard_fixture")
		seen["guard_effect_bound"] = effect.bind_runtime_context(binding.context)
		for _i in 4:
			var f:BaseFunc = LoadHelper.load_funcs([{"func_name":"do_nothing", "parameters":[]}], effect, c)[0]
			seen["guard_func_bound"] = f.runtime_source_status(effect, c).ok
			effect.add_func(f)
		seen["guard_configured"] = EffectManager.configure_runtime_guard({"enabled":true, "steps":1, "seconds":0.0})
		seen["guard_registered"] = EffectManager.register_effect(effect, 0)
		seen["guard_effect"] = effect
		EffectManager.add_to_activation_pool(effect)
		EffectManager.run_pipeline()
		seen["guard_paused"] = EffectManager.runtime_guard_status().paused
	elif action == "invalidate":
		seen["failed_token"] = SessionGeneration.current_token().token
		SessionGeneration.invalidate_generation(&"A1-09.startup_failure")
	elif action == "rotate":
		seen["new_owner"] = SessionGeneration.begin_generation(&"A1-09.new_owner").token

func observe_dispatch() -> void:
	seen["dispatch_hits"] = int(seen.get("dispatch_hits", 0)) + 1
	seen["dispatch_token"] = SessionGeneration.current_token().token
	seen["dispatch_valid"] = startup_effect.runtime_source_status().ok
	if seen.get("invalidate_on_dispatch", false):
		seen["failed_token"] = SessionGeneration.current_token().token
		SessionGeneration.invalidate_generation(&"A1-09.dispatch_failure")

# end_session 会关闭随机流；每次夹具开局都重新声明，保持真实入口及返回值。
func start_fixture(ids:Array, assignments:Dictionary = {}, order:Array = [], guard:Dictionary = {}) -> bool:
	RuleRandom.start_seed(709)
	return GameStart.game_start(ids, assignments, order, guard)

func seed_old() -> SessionContext:
	GameStart.reset()
	var result:Dictionary = GameData.reset_game_session([0, 1])
	check(result.ok, "fixture public reset accepts")
	return result.context

func end_cases() -> void:
	var old:SessionContext = seed_old()
	seen.clear()
	EffectManager.messages.append(ClearObserver.new(old, seen, "end_runtime"))
	GameProgress.last_battle_result["observer"] = ClearObserver.new(old, seen, "end_progress")
	GameData.player_data_library[0]["observer"] = ClearObserver.new(old, seen, "end_players")
	GameStart.end_session()
	for site in ["end_runtime", "end_progress", "end_players"]:
		check(seen.has(site) and not seen[site].old_valid and seen[site].current == null, site + " observes closed before real cleanup")
	check(not SessionGeneration.current_token().ok and not SessionGeneration.validate_context(old).ok, "complete end remains closed")
	check(not GameData.loaded_masters.is_empty() and not GameData.loaded_servants.is_empty(), "closed end reloads formal templates")
	check(not GameData.player_data_library.is_empty(), "closed end setup creates templates without qualification")
	GameStart.end_session()
	check(not SessionGeneration.current_token().ok, "repeated end never reopens")

func binding_cases() -> void:
	var old:SessionContext = seed_old()
	seen.clear()
	startup_master = BaseMaster.new("A1-09-master", "", "", "", "")
	GameData.loaded_masters = [startup_master]
	GameData.loaded_servants = []
	GameData.player_data_library[0]["observer"] = ClearObserver.new(old, seen, "start_players", self, "bind")
	EffectManager.messages.append(ClearObserver.new(old, seen, "start_runtime"))
	GameProgress.last_battle_result["observer"] = ClearObserver.new(old, seen, "start_progress")
	var accepted:bool = start_fixture([0, 1])
	var c:SessionContext = seen.binding_context
	check(accepted and SessionGeneration.validate_context(c).ok, "composed start accepts original startup domain")
	for site in ["start_players", "start_runtime", "start_progress"]:
		check(seen.has(site) and not seen[site].old_valid and is_same(seen[site].current, c.token()), site + " observes same fresh domain before real cleanup")
	check(seen.get("factory_bound", false) and seen.get("func_bound", false), "trusted runtime role and function factory bound")
	check(seen.get("dispatch_hits", 0) == 1 and seen.get("dispatch_valid", false) and is_same(seen.get("dispatch_token"), c.token()), "first real role dispatch preserves binding domain")
	check(startup_effect.runtime_source_status().ok and is_same(SessionGeneration.current_token().token, c.token()), "bound role survives GameProgress start")
	check(GameProgress.current_round == 1 and not GameLog.query({"type":"time_point"}, null).is_empty(), "composed start runs first round and actual timepoints")
	check(not start_fixture([0, 1]) and is_same(SessionGeneration.current_token().token, c.token()), "already started rejection does not rotate")
	GameStart.end_session()
	check(not startup_effect.runtime_source_status().ok and not SessionGeneration.current_token().ok, "end invalidates externally retained role")
	startup_effect = null
	startup_master = null

func config_cases() -> void:
	GameStart.end_session()
	for config in [{"ids":[]}, {"ids":[0, 0]}, {"ids":[0, 1], "order":[0]}, {"ids":[0, 1], "order":[0, 0]}, {"ids":[0, 1], "assignments":{0:{}}}, {"ids":[0, 1], "guard":{"invalid":true}}]:
		var root:Dictionary = GameData.player_data_library
		var count:int = GameLog.query({}, null).size()
		var result:bool = start_fixture(config.ids, config.get("assignments", {}), config.get("order", []), config.get("guard", {}))
		check(not result and not SessionGeneration.current_token().ok and is_same(root, GameData.player_data_library) and count == GameLog.query({}, null).size(), "invalid config rejects before begin " + str(config))

func failure_cases() -> void:
	for site in ["players", "runtime", "progress"]:
		var old:SessionContext = seed_old()
		seen.clear()
		GameData.loaded_masters = []
		GameData.loaded_servants = []
		if site == "players":
			GameData.player_data_library[0]["observer"] = ClearObserver.new(old, seen, site, self, "invalidate")
		elif site == "runtime":
			EffectManager.messages.append(ClearObserver.new(old, seen, site, self, "invalidate"))
		else:
			GameProgress.last_battle_result["observer"] = ClearObserver.new(old, seen, site, self, "invalidate")
		var result:bool = start_fixture([0, 1])
		check(not result and not SessionGeneration.current_token().ok and not SessionGeneration.validate_context(old).ok, site + " startup failure stays closed and never revives old")
		check(not SessionGeneration.validate_token(seen.failed_token).ok, site + " failed new token unavailable")
		check(GameLog.query({"type":"time_point"}, null).is_empty(), site + " failed startup has no first dispatch")
		GameStart.end_session()
		check(not SessionGeneration.current_token().ok, site + " failed startup end remains closed")

func guard_noop() -> bool:
	return true

func guard_config_failure_case() -> void:
	var old:SessionContext = seed_old()
	seen.clear()
	EffectManager.effect_results.append(ClearObserver.new(old, seen, "guard_config_failure", self, "pause_guard"))
	var result:bool = start_fixture([0, 1], {}, [], {"enabled":false, "steps":0, "seconds":0.0})
	check(seen.get("guard_configured", false) and seen.get("guard_registered", false) and seen.get("guard_paused", false), "real guard pauses during startup cleanup")
	check(not result and not SessionGeneration.current_token().ok and not SessionGeneration.validate_token(seen.failed_token).ok, "valid configuration refused by live guard closes failed startup")
	check(GameLog.query({"type":"time_point", "tags":[TimePoints.GAME_START]}, null).is_empty() and GameProgress.current_round == 0, "configuration application failure has no first GAME_START dispatch")
	GameStart.end_session()

func pause_resume_case() -> void:
	GameStart.end_session()
	GameData.loaded_masters = []
	GameData.loaded_servants = []
	check(start_fixture([0, 1]), "pause fixture starts normally")
	var c:SessionContext = context()
	seen.clear()
	on_clear("pause_guard")
	check(seen.guard_paused and SessionGeneration.validate_context(c).ok, "same-session real guard pause preserves origin")
	var slices:int = 0
	while EffectManager.runtime_guard_status().paused and slices < 32:
		EffectManager.resume_runtime_guard()
		slices += 1
	check(not EffectManager.runtime_guard_status().paused and slices > 0 and is_same(SessionGeneration.current_token().token, c.token()) and seen.guard_effect.runtime_source_status().ok, "same-session real guard resume preserves token and role source")
	GameStart.end_session()
	seen.clear()

func dispatch_failure_case() -> void:
	var old:SessionContext = seed_old()
	seen.clear()
	startup_master = BaseMaster.new("A1-09-failing-master", "", "", "", "")
	GameData.loaded_masters = [startup_master]
	GameData.loaded_servants = []
	GameData.player_data_library[0]["observer"] = ClearObserver.new(old, seen, "dispatch_failure", self, "bind_invalidate")
	var result:bool = start_fixture([0, 1])
	check(seen.get("dispatch_hits", 0) == 1 and seen.get("dispatch_valid", false), "failure originates in real first role dispatch")
	check(not result and not SessionGeneration.current_token().ok and not SessionGeneration.validate_token(seen.failed_token).ok, "start consumes GameProgress rejection and closes failed domain")
	check(not SessionGeneration.validate_context(old).ok and GameProgress.current_round == 0, "dispatch failure never revives old or runs round tail")
	GameData.loaded_masters = []
	check(start_fixture([0, 1]), "failed startup releases started latch for explicit retry")
	GameStart.end_session()
	startup_effect = null
	startup_master = null

func reentry_cases() -> void:
	for site in ["start", "end"]:
		var old:SessionContext = seed_old()
		seen.clear()
		EffectManager.messages.append(ClearObserver.new(old, seen, site, self, "rotate"))
		if site == "start":
			check(not start_fixture([0, 1]), "start rejects callback authority replacement")
		else:
			GameProgress.current_round = 7
			GameStart.end_session()
			check(GameProgress.current_round == 7, "old end does not reset replacement authority progress")
		check(is_same(SessionGeneration.current_token().token, seen.new_owner) and not SessionGeneration.validate_context(old).ok, site + " preserves explicitly established replacement authority")
		GameStart.end_session()

func allocation_failure_case() -> void:
	var old:SessionContext = seed_old()
	seen.clear()
	GameData.player_data_library[0]["observer"] = ClearObserver.new(old, seen, "allocation")
	var members:Dictionary = GameData.player_data_library
	var result:bool = start_fixture([0, 1])
	check(not result and not SessionGeneration.current_token().ok and not SessionGeneration.validate_context(old).ok, "allocation failure closes and never resurrects old token")
	check(not seen.has("allocation") and is_same(members, GameData.player_data_library), "allocation failure precedes first cleanup")
	GameStart.end_session()

func standalone_cases() -> void:
	var old:SessionContext = seed_old()
	seen.clear()
	GameProgress.last_battle_result["observer"] = ClearObserver.new(old, seen, "standalone_progress")
	RuleRandom.start_seed(709)
	var result:Dictionary = GameProgress.start_game()
	check(result.ok and not SessionGeneration.validate_context(old).ok, "standalone start rotates old domain")
	check(seen.has("standalone_progress") and not seen.standalone_progress.old_valid and is_same(seen.standalone_progress.current, result.context.token()), "standalone first progress clear sees new domain")
	check(SessionGeneration.validate_context(result.context).ok and GameProgress.current_round == 1, "standalone actual dispatch remains current")
	GameStart.end_session()
	check(not SessionGeneration.current_token().ok, "standalone end closed")

func formal_cases() -> void:
	GameStart.end_session()
	var result:bool = start_fixture([0, 1])
	check(result and SessionGeneration.current_token().ok and GameProgress.current_round == 1, "formal loaded end start reaches first round")
	check(GameDataManager.find_player_data(0).master is BaseMaster and GameDataManager.find_player_data(0).servant is BaseServant, "formal default role binding remains available")
	var token:SessionToken = SessionGeneration.current_token().token
	var old:SessionContext = context()
	GameStart.end_session()
	check(not SessionGeneration.current_token().ok and not SessionGeneration.validate_context(old).ok, "formal end closes previous context")
	check(start_fixture([0, 1]) and not is_same(SessionGeneration.current_token().token, token), "formal restart uses fresh token")
	GameStart.end_session()
	var masters:Array = GameStart.get_masters_can_use()
	var servants:Array = GameStart.get_servants_can_use()
	var assignments:Dictionary = {0:{"master":masters[0], "servant":servants[0]}, 1:{"master":masters[1], "servant":servants[1]}}
	check(start_fixture([0, 1], assignments, [1, 0], {"enabled":false, "steps":0, "seconds":0.0}), "explicit formal assignments order and valid configuration accepted")
	check(GameDataManager.find_player_data(1).order.number == 0 and GameDataManager.find_player_data(0).order.number == 1, "explicit order retained in same-domain start")
	GameStart.end_session()

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var args:PackedStringArray = OS.get_cmdline_user_args()
	var mode:String = args[0] if not args.is_empty() else "all"
	if mode in ["all", "end"]: end_cases()
	if mode in ["all", "binding"]: binding_cases()
	if mode in ["all", "config"]: config_cases()
	if mode in ["all", "failure"]: failure_cases()
	if mode in ["all", "guard_failure"]: guard_config_failure_case()
	if mode in ["all", "pause_resume"]: pause_resume_case()
	if mode in ["all", "dispatch_failure"]: dispatch_failure_case()
	if mode in ["all", "reentry"]: reentry_cases()
	if mode == "allocation_failure": allocation_failure_case()
	if mode in ["all", "standalone"]: standalone_cases()
	if mode in ["all", "formal"]: formal_cases()
	GameStart.end_session()
	GameData.release_game_objects()
	RuleRandom.stop_tracking()
	print("RESULT ", JSON.stringify({"suite":"game_start_session_origin", "checks":checks, "failures":failures, "mode":mode}))
	get_tree().quit(0 if failures.is_empty() else 1)
