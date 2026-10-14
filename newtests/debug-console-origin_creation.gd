extends Node

const RR = preload("res://scripts/match/rule_random.gd")
var checks:int = 0
var failures:Array = []

class InvalidateDuringClear extends RefCounted:
	func _notification(what:int) -> void:
		if what == NOTIFICATION_PREDELETE:
			SessionGeneration.invalidate_generation(&"debug-console-origin.failed_start")

func check(value:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", value)
	if not value:
		failures.append(label)

func saved_context() -> Variant:
	return GameStart.call("startup_context") if GameStart.has_method("startup_context") else null

func stored_value(object:Object, key:String) -> Variant:
	for property in object.get_property_list():
		if str(property.name) == key:
			return object.get(key)
	return null

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	print("USER_DIR ", OS.get_user_data_dir())
	GameStart.end_session()
	check(saved_context() == null, "closed producer has no saved receipt")
	GameData.loaded_masters = []
	GameData.loaded_servants = []
	RR.start_seed(817)
	check(GameStart.game_start([0, 1]), "real GameStart startup accepts")
	var original:Variant = saved_context()
	check(original is SessionContext and SessionGeneration.validate_context(original).ok, "successful producer hands off real original context")
	check(original != null and is_same(original, saved_context()), "handoff preserves saved identity without reissuing")
	check(original != null and original.origin() == &"GameStart.startup", "handoff retains startup origin")
	var console = preload("res://assets/scenes/debug/debug_console.tscn").instantiate()
	console.initialize(null)
	check(original != null and is_same(stored_value(console.session, "source_context"), original), "production console constructor passes exact producer value to Session")
	check(original != null and is_same(stored_value(console.session.registry, "source_context"), original), "production Session constructor passes exact producer value to Registry")
	check(not GameStart.game_start([0, 1]) and original != null and is_same(saved_context(), original), "duplicate start rejection retains successful original receipt")
	var old_session:DebugSession = console.session
	var old_registry:DebugCommandRegistry = old_session.registry
	console.initialize(null)
	check(stored_value(old_session, "source_context") == null and stored_value(old_registry, "source_context") == null, "reinitialize releases old saved references")
	check(original != null and is_same(stored_value(console.session, "source_context"), original), "reinitialize consumes same successful receipt")
	var rotated:Dictionary = GameData.reset_game_session([0, 1])
	check(rotated.ok and not SessionGeneration.validate_context(original).ok, "public lifecycle replacement invalidates old source")
	check(saved_context() == null, "replacement does not reissue a current context through handoff")
	console.initialize(null)
	check(stored_value(console.session, "source_context") == null and stored_value(console.session.registry, "source_context") == null, "missing producer source remains missing at creation boundary")
	console.session.shutdown()
	console.free()
	GameStart.end_session()
	check(saved_context() == null, "end clears saved receipt")
	GameData.loaded_masters = []
	GameData.loaded_servants = []
	RR.start_seed(818)
	EffectManager.messages.append(InvalidateDuringClear.new())
	check(not GameStart.game_start([0, 1]), "real startup failure rejects")
	check(saved_context() == null, "failed startup never publishes receipt")
	GameStart.end_session()
	GameData.loaded_masters = []
	GameData.loaded_servants = []
	RR.start_seed(819)
	check(GameStart.game_start([0, 1]), "explicit successful retry accepts")
	var retry:Variant = saved_context()
	check(retry is SessionContext and SessionGeneration.validate_context(retry).ok and not is_same(retry, original), "retry publishes only its own original receipt")
	GameStart.reset()
	check(saved_context() == null, "reset clears saved receipt without replacement")
	GameStart.end_session()
	RR.stop_tracking()
	print("RESULT ", JSON.stringify({"suite":"debug-console-origin_creation", "checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
