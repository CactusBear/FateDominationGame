extends Node
const Plan = preload("res://scripts/system/atomic_action_plan.gd")
const Domain = preload("res://scripts/system/atomic_execution_domain.gd")
var checks:int = 0
var failures:Array = []

class Probe extends RefCounted:
	signal observed
	var setter_calls:int = 0
	var callback_calls:int = 0
	var value:Variant:
		set(v):
			setter_calls += 1
			value = v
	func callback() -> void:
		callback_calls += 1

class LifetimeProbe extends RefCounted:
	var witness:Dictionary
	func _init(w:Dictionary) -> void:
		witness = w
	func _notification(what:int) -> void:
		if what == NOTIFICATION_PREDELETE:
			witness.deleted += 1
			if Domain.publication_is_open(): witness.in_window += 1

func check(ok:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", ok)
	if not ok: failures.append(label)

func install(d, label:String) -> void:
	var w:Dictionary = Domain.acquire_publication_window()
	check(w.status == "COMPLETED", label + " window")
	check(d.seal(w.window).status == "COMPLETED", label + " seal")
	check(d.install_sealed(w.window).status == "COMPLETED", label + " install")
	check(d.install_sealed(w.window).status == "FAULT", label + " single install")
	Domain.release_publication_window(w.window)

func reject_install(d, reason:String, label:String) -> void:
	var w:Dictionary = Domain.acquire_publication_window()
	var result:Dictionary = d.seal(w.window)
	check(result.status == "REJECTED" and result.reason.begins_with(reason), label + " full seal rejection")
	check(d.install_sealed(w.window).status == "FAULT", label + " unsealed cannot install")
	Domain.release_publication_window(w.window)
	d.discard()

func containers() -> void:
	var object:Probe = Probe.new()
	object.observed.connect(object.callback)
	var nested:Array = [7]
	for pair in [[[1], [1, object, nested]], [[1, 2, 3], [object]], [[1], []], [[], [object]], [[], []]]:
		var d = Domain.new()
		var target:Array = pair[0]
		var alias:Array = target
		var old:Array = target.duplicate(false)
		var prepared:Array = pair[1]
		var expected:Array = prepared.duplicate(false)
		check(d.stage_container_contents(target, prepared, &"journal").status == "COMPLETED", "array contents staged")
		check(target == old and is_same(alias, target), "array stage zero live writes")
		prepared.append("late outer mutation")
		install(d, "array resize")
		check(is_same(target, alias) and target.size() == expected.size(), "array resize retains identity")
		for i in range(expected.size()): check(is_same(target[i], expected[i]), "array shallow prepared identity")
	var dictionary:Dictionary = {"remove":1, "retain":nested}
	var alias:Dictionary = dictionary
	var prepared:Dictionary = {object:nested, "add":object, &"name":2, 8:"integer"}
	var d = Domain.new()
	check(d.stage_container_contents(dictionary, prepared, &"runtime").status == "COMPLETED", "dictionary key add delete replace staged")
	check(dictionary.has("remove") and not dictionary.has(object), "dictionary stage zero live writes")
	prepared.clear()
	install(d, "dictionary key changes")
	check(is_same(alias, dictionary) and dictionary.size() == 4 and not dictionary.has("remove") and not dictionary.has("retain"), "dictionary identity and deleted keys")
	check(is_same(dictionary.keys()[0], object) and is_same(dictionary[object], nested) and is_same(dictionary.add, object), "dictionary Object key value shallow identity")
	check(dictionary[&"name"] == 2 and dictionary[8] == "integer", "dictionary primitive key identities")
	var empty = Domain.new()
	check(empty.stage_container_contents(dictionary, {}, &"rule").status == "COMPLETED", "dictionary clear staged")
	install(empty, "dictionary clear")
	check(dictionary.is_empty() and is_same(dictionary, alias), "dictionary clear identity")
	var self_target:Array = [object]
	var self_domain = Domain.new()
	check(self_domain.stage_container_contents(self_target, self_target, &"rule").status == "COMPLETED", "prepared same target snapshots safely")
	install(self_domain, "same target snapshot")
	check(is_same(self_target[0], object), "same target snapshot retains element")
	check(object.setter_calls == 0 and object.callback_calls == 0, "raw containers no setters callbacks signals")
	var witness:Dictionary = {"deleted":0, "in_window":0}
	var retired:Array = [LifetimeProbe.new(witness)]
	var lifetime = Domain.new()
	check(lifetime.stage_container_contents(retired, [], &"rule").status == "COMPLETED", "old Object pinned by baseline")
	install(lifetime, "old Object retirement")
	check(witness.deleted == 0 and witness.in_window == 0, "assign cannot trigger predelete callback inside window")
	lifetime = null
	check(witness.deleted == 1 and witness.in_window == 0, "baseline release only outside installation window")

func invalid_and_overlap() -> void:
	var typed:Array[int] = [1]
	var typed_dict:Dictionary[String, int] = {"x":1}
	var readonly:Array = [1]
	readonly.make_read_only()
	var readonly_dict:Dictionary = {"x":1}
	readonly_dict.make_read_only()
	var probe:Probe = Probe.new()
	for pair in [[typed, [2]], [typed_dict, {"x":2}], [readonly, [2]], [readonly_dict, {}], [probe, {}], [Callable(probe, "callback"), []], [PackedInt32Array([1]), []], [[], {}], [{}, []], [[], probe], [[], Callable(probe, "callback")]]:
		var d = Domain.new()
		check(d.stage_container_contents(pair[0], pair[1], &"rule").reason == "unsupported_backing_container", "unsupported target or prepared type rejected")
		reject_install(d, "container_write_set_failed:", "invalid contents")
	check(probe.setter_calls == 0 and probe.callback_calls == 0, "unsupported carrier never invokes Object Callable")
	for reverse in [false, true]:
		for target in [[1], {"x":1}]:
			var d = Domain.new()
			var key:Variant = 0 if target is Array else "x"
			var prepared:Variant = [2, 3] if target is Array else {"y":2}
			var first:Dictionary = d.stage_container_contents(target, prepared, &"rule") if reverse else d.stage_slot(target, key, 2, &"rule")
			var second:Dictionary = d.stage_slot(target, key, 2, &"rule") if reverse else d.stage_container_contents(target, prepared, &"rule")
			check(first.status == "COMPLETED" and second.reason == "overlapping_backing_target", "same target mixed writes both orders rejected")
			reject_install(d, "container_write_set_failed:", "mixed writes")
			check(target[key] == 1 and target.size() == 1, "mixed writes never install partial")
	for target in [[1], {"x":1}]:
		var d = Domain.new()
		var prepared:Variant = [2] if target is Array else {"y":2}
		check(d.stage_container_contents(target, prepared, &"rule").status == "COMPLETED", "first container staged")
		check(d.stage_container_contents(target, prepared, &"journal").reason == "duplicate_backing_container", "duplicate target irrespective of kind rejected")
		reject_install(d, "container_write_set_failed:", "duplicate container")
	for variant in ["bad_container", "bad_slot_after", "bad_slot_before", "unknown_kind", "duplicate_slot"]:
		var d = Domain.new()
		var facts:Array = [1]
		var rule:Dictionary = {"amount":9}
		if variant == "bad_slot_before": check(d.stage_slot([], 0, 1, &"rule").status == "REJECTED", "earlier slot error recorded")
		check(d.stage_slot(rule, "amount", 6, &"rule").status == "COMPLETED", "valid rule staged before failure")
		check(d.stage_container_contents(facts, [1, 2], &"journal").status == "COMPLETED", "valid facts staged before failure")
		if variant == "bad_container": check(d.stage_container_contents([], {}, &"rule").status == "REJECTED", "partial contents failure")
		if variant == "bad_slot_after": check(d.stage_slot([], 0, 1, &"rule").status == "REJECTED", "partial slot failure")
		if variant == "unknown_kind": check(d.stage_container_contents([], [], &"unknown").status == "REJECTED", "unknown contents kind")
		if variant == "duplicate_slot": check(d.stage_slot(rule, "amount", 3, &"rule").status == "REJECTED", "partial duplicate slot failure")
		reject_install(d, "container_write_set_failed:", variant)
		check(facts == [1] and rule.amount == 9, variant + " zero partial install")

func baselines() -> void:
	for variant in ["array_length", "array_scalar", "array_identity", "array_readonly", "dict_length", "dict_key", "dict_order", "dict_identity", "dict_readonly"]:
		var d = Domain.new()
		var target:Variant = [{"v":1}] if variant.begins_with("array") else {"a":{"v":1}, "b":2}
		var prepared:Variant = [3, 4] if target is Array else {"new":3}
		var rule:Dictionary = {"amount":9}
		check(d.stage_slot(rule, "amount", 6, &"rule").status == "COMPLETED", variant + " rule staged")
		check(d.stage_container_contents(target, prepared, &"journal").status == "COMPLETED", variant + " contents staged")
		match variant:
			"array_length": target.append(2)
			"array_scalar": target[0] = 2
			"array_identity": target[0] = {"v":1}
			"array_readonly": target.make_read_only()
			"dict_length": target["c"] = 3
			"dict_key": target.erase("b"); target["c"] = 2
			"dict_order":
				var first:Variant = target.a
				target.erase("a")
				target["a"] = first
			"dict_identity": target.a = {"v":1}
			"dict_readonly": target.make_read_only()
		reject_install(d, "backing_container_changed", variant)
		check(rule.amount == 9, variant + " seal baseline failure prevents unrelated rule install")
	var nested:Dictionary = {"v":1}
	var target:Array = [nested]
	var d = Domain.new()
	check(d.stage_container_contents(target, [nested], &"rule").status == "COMPLETED", "shallow baseline staged")
	nested.v = 2
	install(d, "shallow baseline graph owner responsibility")
	check(is_same(target[0], nested) and nested.v == 2, "core checks shallow identity not substitute deep graph proof")

func source_guards() -> void:
	var source:String = FileAccess.get_file_as_string("res://scripts/system/atomic_execution_domain.gd")
	var body:String = source.split("func install_sealed(window:Variant) -> Dictionary:")[1].split("func discard()")[0]
	for forbidden in ["await ", ".emit(", ".call(", ".callv(", ".set(", ".get(", "Callable", "REJECTED"]:
		check(not body.contains(forbidden), "install no executable hook or business rejection " + forbidden)
	check(body.contains(".assign(contents.prepared)") and body.contains("contents.target.clear()") and body.contains("contents.target[key] = contents.prepared[key]"), "install only builtin contents writes")
	check(body.contains('"FAULT", "invalid_install_boundary"'), "invalid native boundary stays FAULT not business rejection")
	var found:bool = false
	for method in Domain.new().get_script().get_script_method_list():
		if method.name == "stage_container_contents":
			var names:Array = []
			for arg in method.args: names.append(str(arg.name))
			check(names == ["target", "prepared_items", "kind"], "new ABI literal argument names")
			found = true
	check(found, "raw contents ABI present")

func slot_retirement() -> void:
	for mixed in [false, true]:
		var witness:Dictionary = {"deleted":0, "in_window":0}
		var target:Dictionary = {"old":LifetimeProbe.new(witness)}
		var d = Domain.new()
		check(d.stage_slot(target, "old", null, &"rule").status == "COMPLETED", "old slot Object replacement staged")
		if mixed:
			check(d.stage_container_contents([], [1], &"journal").status == "COMPLETED", "slot retirement with new container batch")
		var window:Dictionary = Domain.acquire_publication_window()
		check(d.seal(window.window).status == "COMPLETED", "slot retirement seal")
		check(d.install_sealed(window.window).status == "COMPLETED", "slot retirement install")
		check(witness.deleted == 0 and witness.in_window == 0, "old slot assignment cannot trigger PREDELETE inside window")
		Domain.release_publication_window(window.window)
		d = null
		check(witness.deleted == 1 and witness.in_window == 0, "old slot keepalive retires only outside window")

func _ready() -> void:
	containers()
	invalid_and_overlap()
	baselines()
	source_guards()
	slot_retirement()
	print("RESULT ", JSON.stringify({"suite":"A4-core2-guards", "checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
