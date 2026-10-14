extends Node

var checks:int = 0
var failures:Array = []

func check(ok:bool, label:String) -> void:
	checks += 1
	print("CHECK ", ok, " ", label)
	if not ok:
		failures.append(label)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	GameLog.reset()
	GameLog.set_context(7, "record_log_test_phase")

	var entry:Dictionary = AllOperations.get_entry("record_log")
	check(entry.get("class", "") == "RecordLog", "record_log is registered")
	var operation:RefCounted = AllOperations.create_instance_of("record_log")
	check(operation != null and operation.has_method("exec"), "registry creates RecordLog operation")
	if operation == null or not operation.has_method("exec"):
		print("RESULT ", JSON.stringify({"suite":"record_log_operation", "checks":checks, "failures":failures}))
		get_tree().quit(1)
		return

	var object_token:RefCounted = RefCounted.new()
	var tags:Array = ["caller_tag", "second_tag"]
	var params:Dictionary = {
		"caller_field": "caller_value",
		"nested": {"number": 3, "items": ["a", "b"]},
		"flag": true,
	}
	var tags_before:Array = tags.duplicate(true)
	var params_before:Dictionary = params.duplicate(true)
	var returned:Dictionary = operation.exec(
		"caller_fact_type", 17, 23, "caller_place", object_token, tags, params)

	check(returned.get("type") == "caller_fact_type", "returned type comes from caller")
	check(returned.get("actor") == 17 and returned.get("target") == 23, "returned actor and target come from caller")
	check(returned.get("place") == "caller_place", "returned place comes from caller")
	check(is_same(returned.get("object"), object_token), "returned object identity comes from caller")
	check(returned.get("tags", []) == tags_before and returned.get("data", {}) == params_before, "returned tags and fields are unchanged")
	check(tags == tags_before and params == params_before, "caller containers are not mutated")

	var facts:Array = GameLog.query({"type":"caller_fact_type"}, null)
	check(facts.size() == 1, "query finds the fact recorded through operation")
	if facts.size() == 1:
		var fact:Dictionary = facts[0]
		check(fact.get("round") == 7 and fact.get("phase") == "record_log_test_phase", "GameLog context is preserved")
		check(fact.get("actor") == 17 and fact.get("target") == 23 and fact.get("place") == "caller_place", "query preserves scalar parameters")
		check(is_same(fact.get("object"), object_token), "query preserves object identity")
		check(fact.get("tags", []) == tags_before and fact.get("data", {}) == params_before, "query preserves tags and fields")

	tags.append("mutated_after_call")
	params["caller_field"] = "mutated_after_call"
	var isolated:Array = GameLog.query({"type":"caller_fact_type"}, null)
	if isolated.size() == 1:
		check(isolated[0].get("tags", []) == tags_before and isolated[0].get("data", {}) == params_before, "stored fact is isolated from later caller mutation")
	else:
		check(false, "stored fact is isolated from later caller mutation")

	print("RESULT ", JSON.stringify({"suite":"record_log_operation", "checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
