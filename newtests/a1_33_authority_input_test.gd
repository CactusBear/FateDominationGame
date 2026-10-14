extends Node

var checks: int = 0
var failures: Array = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
	print("CHECK ", label, " ", ok)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	SessionGeneration.invalidate_generation(&"a1_33_test_reset")
	var generation: Dictionary = SessionGeneration.begin_generation(&"a1_33_test_start")
	check(generation.get("ok", false), "test generation starts")
	if not generation.get("ok", false):
		finish()
		return
	var token: SessionToken = generation.token
	var subject: BaseCard = BaseCard.new()
	var bound: Dictionary = SessionGeneration.bind_origin(subject, token, &"a1_33_test_source")
	check(bound.get("ok", false), "trusted source object binds")
	var context: SessionContext = bound.get("context")
	check(SessionGeneration.validate_context(context).get("ok", false), "captured context validates")
	GameData.player_data_library[0] = {"source": subject}
	check(is_same(MatchDriver.capture_runtime_context(), context), "driver captures an existing runtime source")
	GameData.player_data_library.clear()

	var driver = MatchDriver.new(null, context)
	check(driver.prepare_step(0.0) == "", "driver accepts only a captured source")
	var dispatcher = preload("res://scripts/match/match_command_dispatcher.gd").new(Callable(), Callable())
	var valid_rejected: Dictionary = dispatcher.dispatch(-1, "unknown", {}, null, Callable(), context)
	check(not valid_rejected.ok and valid_rejected.result == false, "valid source preserves a false dispatch result")
	SessionGeneration.invalidate_generation(&"a1_33_test_rotate")
	check(driver.prepare_step(0.0) == "", "driver rejects stale captured source")
	check(driver.step(0.0) == false, "stale local driver does not advance")

	var old_dispatcher = preload("res://scripts/match/match_command_dispatcher.gd").new(Callable(), Callable())
	var rejected: Dictionary = old_dispatcher.dispatch(-1, "unknown", {}, null, Callable(), null)
	check(not rejected.ok and rejected.result == null, "old inbound without source is rejected")

	var authority = preload("res://scripts/net/authority/match_authority.gd").new()
	check(not authority.submit(1, 0, "end_action", {}), "authority rejects an inbound command before start")

	finish()

func finish() -> void:
	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
