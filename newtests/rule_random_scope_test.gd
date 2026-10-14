extends Node

const Random = preload("res://scripts/match/rule_random.gd")
var checks: int = 0
var failures: Array[String] = []

func check(label: String, passed: bool) -> void:
	checks += 1
	print("CHECK ", label, " ", passed)
	if not passed: failures.append(label)

func observe_forecast(before: Dictionary, after: Dictionary, forecast: Array, live: Array) -> void:
	check("forecast_live_state_identical", before == after)
	check("forecast_real_sequence_identical", forecast == live)

func legacy_sequence() -> Array:
	var items: Array = ["a", "b", "c", "d", "e"]
	var result: Array = [Random.int_in_range(-17, 29), Random.float_in_range(-3.5, 9.25), Random.pick(items)]
	Random.shuffle(items)
	result.append(items)
	return result

func original_probe() -> void:
	# 旧公开入口只有同一个 live 静态流；这里只观察，不伪造 fork。
	Random.start_seed(42815)
	var before: Dictionary = Random.snapshot()
	var forecast: Array = legacy_sequence()
	var after: Dictionary = Random.snapshot()
	var live: Array = legacy_sequence()
	observe_forecast(before, after, forecast, live)
	check("legacy_restore_still_works", Random.restore(before))
	check("legacy_restore_sequence", legacy_sequence() == forecast)
	Random.stop_tracking()

func _ready() -> void:
	print("ENV ", OS.get_user_data_dir())
	original_probe()
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures, "suite": "rule_random_scope"}))
	get_tree().quit(0 if failures.is_empty() else 1)
