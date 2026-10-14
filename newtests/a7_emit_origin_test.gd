extends Node

const Router = preload("res://scripts/system/operation_router.gd")
const Emit = preload("res://scripts/system/operations/EmitTimePoint.gd")
var emit_script:Script = Emit
var checks:int = 0
var failures:Array = []
var hits:int = 0
var marker:bool = false:
	set(value):
		marker = value
		if value: hits += 1

func check(ok:bool, label:String) -> void:
	checks += 1
	if not ok: failures.append(label)
	print("CHECK ", label, " ", ok)

func start() -> SessionContext:
	var setup:Dictionary = GameData.reset_game_session([0, 1])
	check(setup.ok, "PRE session")
	GameData.player_id = 0
	GameLog.reset()
	TimePointChecker.phase_time_points = []
	return setup.context

func args(point:String, id:int, source:Variant) -> Array:
	for method in emit_script.get_script_method_list():
		if method.name == "exec" and method.args.size() >= 3:
			return [point, id, source]
	return [point, id]

func emit(point:String, id:int, source:Variant) -> void:
	var operation = Emit.new()
	Callable(operation, "exec").callv(args(point, id, source))

func facts(point:String) -> int:
	return GameLog.query({"type":"time_point", "tags":point}, null, -1).size()

func tables() -> Array:
	return [GameData.player_data_library[0].current_time_points.duplicate(), GameData.player_data_library[1].current_time_points.duplicate()]

func listener(context:SessionContext, point:String, owner:int) -> void:
	var effects:Array = LoadHelper.load_effects([{
		"effect_name":"a7_listener", "time_points":[point], "priority":0,
		"is_pure_passive":true, "is_residue":false, "need_activate":false,
		"effect_numbers":[], "funcs":[{"func_name":"set_property", "parameters":[self,"marker",true]}]
	}], null, context)
	check(effects.size() == 1, "PRE listener factory")
	if effects.size() == 1:
		check(EffectManager.register_effect(effects[0], owner), "PRE listener registered")

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	print("USER_PATH ", OS.get_user_data_dir())
	var context:SessionContext = start()
	check(not EffectManager.execution_context().ok, "explicit action has no frame")
	var initial:Array = tables()
	emit("a7_missing", -1, null)
	check(facts("a7_missing") == 0 and tables() == initial, "missing source rejects before facts and tables")
	Router.exec_registered("emit_time_point", ["a7_router_only", -1], context)
	check(facts("a7_router_only") == 0 and tables() == initial, "router eligibility is not business authority")
	for bad in [{"token":"forged"}, SessionContext.new()]:
		emit("a7_bad", -1, bad)
		check(facts("a7_bad") == 0 and tables() == initial, "malformed and unissued source rejects")
		Router.exec_registered("emit_time_point", args("a7_bad_route", -1, bad), context)
		check(facts("a7_bad_route") == 0 and tables() == initial, "valid router cannot wash invalid business source")
	emit("", -1, context)
	check(GameLog.query({}).is_empty() and tables() == initial, "empty time point remains no-op")
	emit("a7_global", -1, context)
	check(facts("a7_global") == 1, "explicit no-frame global emits one fact")
	check(GameData.player_data_library[0].dynamic_time_points.is_empty() and GameData.player_data_library[1].dynamic_time_points.is_empty(), "global transient consumed after discovery")
	check(not GameData.player_data_library[0].dynamic_time_points.has("self_a7_global"), "global never borrows local player")
	check(not EffectManager.execution_context().ok, "explicit source does not create frame")
	context = start()
	emit("a7_dynamic", 0, context)
	check(facts("a7_dynamic") == 1, "explicit player emits one fact")
	check(GameData.player_data_library[0].dynamic_time_points.is_empty(), "actor transient consumed after discovery")
	check(GameData.player_data_library[1].dynamic_time_points.is_empty(), "other transient consumed after discovery")
	var keys:Array = GameData.player_data_library.keys()
	initial = tables()
	emit("a7_unknown", 987654, context)
	check(facts("a7_unknown") == 0 and tables() == initial and GameData.player_data_library.keys() == keys, "unknown actor never creates player or fact")
	context = start()
	TimePointChecker.set_phase_time_points(["a7_phase"], context)
	emit("a7_phase_event", -1, context)
	check(TimePointChecker.phase_time_points == ["a7_phase"] and GameData.player_data_library[0].current_time_points.has("a7_phase"), "emit preserves phase window")
	# 真监听由正式 LoadHelper 工厂创建，通过正式登记与 TPC 发现，不自造效果帧。
	for spec in [["a7_listen_global", -1, "a7_listen_global", 0], ["a7_listen_player", 0, "a7_listen_player", 0], ["a7_listen_self", 0, "self_a7_listen_self", 0], ["a7_listen_others", 0, "others_a7_listen_others", 1]]:
		context = start()
		listener(context, spec[2], spec[3])
		hits = 0
		emit(spec[0], spec[1], context)
		check(hits == 1, "registered real listener " + spec[2])
		check(facts(spec[0]) == 1, "listener dispatch fact " + spec[0])
		check(not EffectManager.execution_context().ok, "listener frame never leaks " + spec[2])
	context = start()
	var operation = Emit.new()
	var saved:Callable = Callable(operation, "exec").bindv(args("a7_saved", -1, context))
	var old_data:Dictionary = GameData.player_data_library[0]
	var generation:Dictionary = SessionGeneration.begin_generation(&"a7_same_dictionary")
	var fresh:Dictionary = SessionGeneration.derive_context(generation.token, &"a7_new_action")
	check(fresh.ok and not SessionGeneration.validate_context(context).ok, "PRE old action revoked")
	check(is_same(old_data, GameData.player_data_library[0]), "same-ID player identity retained")
	initial = tables()
	saved.call()
	emit("a7_stale", -1, context)
	Router.exec_registered("emit_time_point", args("a7_old_business", -1, context), fresh.context)
	check(GameLog.query({}).is_empty() and tables() == initial, "saved and stale actions never write new generation")
	emit("a7_new", -1, fresh.context)
	check(facts("a7_new") == 1, "new original context remains legal")
	print("RESULT ", JSON.stringify({"checks":checks,"failures":failures,"suite":"a7_emit_origin"}))
	get_tree().quit(0 if failures.is_empty() else 1)
