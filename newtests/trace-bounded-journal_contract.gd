extends Node
const Trace = preload("res://scripts/system/global/execution_trace.gd")
const Generation = preload("res://scripts/system/session_generation.gd")
const Checkpoint = preload("res://scripts/match/rule_checkpoint.gd")
var checks:int = 0
var failures:Array = []
var source:Variant

class DeletionWitness extends RefCounted:
	var bucket:Array
	func _init(value:Array): bucket = value
	func _notification(what:int) -> void:
		if what == NOTIFICATION_PREDELETE: bucket.append("deleted")

func check(ok:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", ok)
	if not ok: failures.append(label)

func done(result:Dictionary) -> bool:
	return result.status == "COMPLETED"

func journal(trace, rows:int = 256, units:int = 30000):
	var result:Dictionary = trace.new_write_journal(source, {"max_rows":rows, "max_units":units, "max_scopes":8})
	check(done(result), "real Trace journal created with explicit quota")
	return result.journal

func scope(j):
	return j.begin_scope(source).handle

func patch(target:Dictionary, changes:Dictionary) -> Dictionary:
	return {"kind":"patch", "target":target, "changes":changes}

func _ready() -> void:
	await get_tree().process_frame
	var generation:Dictionary = Generation.begin_generation(&"bounded_trace_test")
	source = Generation.derive_context(generation.token, &"bounded_trace.fixture").context
	var trace = Trace.new()
	check(not done(trace.new_write_journal(source, {})), "no implicit budget")
	check(not done(trace.new_write_journal(null, {"max_rows":1,"max_units":1,"max_scopes":1})), "no source fabrication")
	check(not done(trace.new_write_journal(weakref(source), {"max_rows":1,"max_units":1,"max_scopes":1})), "source WeakRef not original handle")
	# Controllable history built by the real Trace, NOT O(1) authentication of an
	# arbitrary 51k raw graph. Low-level tests do not issue C/memo permissions.
	for i in range(51000):
		var id:int = trace.begin_call({}, "retained", [i], [])
		trace.end_call(id, i, "completed")
	var root:Array = trace.calls
	var first:Dictionary = root[0]
	var nested:Array = first.raw_parameters
	var alias:Dictionary = {"a":nested,"b":nested}
	alias["self"] = alias
	first["alias"] = alias
	var original_eid:int = trace.begin_execution()
	var active_id:int = trace.begin_call({}, "active", [], [])
	var active:Dictionary = root.back()
	var roots:Array = [trace.calls,trace._counters,trace.execution_stack,trace.call_stack,trace.loop_stack,trace.loop_depths]
	var j = journal(trace)
	var outer = scope(j)
	check(root.size() == 51001 and j.usage().rows == 0, "full history scope no capture/adoption claim")
	check(done(j.try_end_call(active_id, 77, "completed", source)), "real end_call patch executes")
	check(done(j.apply([patch(first, {"status":"changed", "extra":8, "alias":alias}), {"kind":"append","target":nested,"items":[99]}], source)), "completed entry and nested owner writes")
	var inner = scope(j)
	check(done(j.try_begin_call({}, "child", [], [], source)), "inner child via real Trace")
	var before:int = root.size()
	check(not done(j.restore(outer, source)) and root.size() == before, "nonLIFO restore zero writes")
	check(not done(j.release(outer, source)), "nonLIFO release rejected")
	check(done(j.release(inner, source)) and root.size() == before, "inner release retains successful child")
	check(done(j.prevalidate(outer, source)), "all records prevalidate")
	print("MECHANISM_COST ", JSON.stringify(j.usage()))
	check(done(j.restore(outer, source)), "outer restore after inner release")
	check(root.size() == 51001 and is_same(root, trace.calls) and is_same(root[0], first) and nested == [0] and first.status == "completed" and not first.has("extra"), "TARGET inner release retains outer undo full history")
	check(active.status == "running" and active.return_value == null and trace.call_stack.size() == 1 and is_same(trace.call_stack[0], active), "TARGET active patch same shared entry restored")
	check(is_same(first.alias,alias) and is_same(alias.a,nested) and is_same(alias.a,alias.b) and is_same(alias.self,alias), "nested alias cycle identity")
	check(trace.next_call_id == active_id and trace.next_execution_id == original_eid and is_same(trace._counters, roots[1]), "counter backing and ids restored")
	check(is_same(trace.execution_stack,roots[2]) and is_same(trace.call_stack,roots[3]) and is_same(trace.loop_stack,roots[4]) and is_same(trace.loop_depths,roots[5]), "all stack roots original identity")
	# Large trim/reset must account for removed slots AND displaced Array suffix.
	outer = scope(j)
	var before_usage:Dictionary = j.usage()
	check(not done(j.apply([{"kind":"trim","target":root,"index":0,"count":51000}], source)) and root.size() == 51001 and j.usage() == before_usage, "large trim pre-refusal zero live and ledger writes")
	check(not done(j.apply([{"kind":"trim","target":root,"index":0,"count":1}], source)) and root.size() == 51001, "large prefix shift charged not false constant trim")
	check(not done(j.try_reset(source)) and root.size() == 51001 and trace.next_call_id == active_id, "large reset pre-refusal complete history")
	check(done(j.release(outer,source)), "release rejected large plan")
	# Original total gate remains, separate from low-level controlled owner work.
	var checkpoint = Checkpoint.new()
	check(not checkpoint.capture([root],{},source) and checkpoint.error == "回滚检查点超出集合预算", "51k original collection gate still refuses")
	check(root.size() == 51001 and is_same(root[0],first) and is_same(first.raw_parameters,nested), "original total refusal keeps full history identity")
	checkpoint = null
	active_and_loops()
	containers_and_roots()
	budgets_and_faults()
	# Public raw writes remain an explicit unsupported-closure counterexample.
	var raw_trace = Trace.new()
	var raw_id:int = raw_trace.begin_call({},"raw",[],[])
	var retained:Dictionary = raw_trace.calls[0]
	raw_trace.end_call(raw_id, null, "completed")
	var raw_j = journal(raw_trace)
	var h = scope(raw_j)
	retained["bypass"] = 5
	check(done(raw_j.restore(h,source)) and retained.bypass == 5, "counterexample raw write not journaled never permission")
	h = scope(raw_j)
	Generation.begin_generation(&"bounded_trace_next")
	check(not done(raw_j.restore(h,source)) and not done(raw_j.release(h,source)) and retained.bypass == 5, "stale source refuses restore release zero writes")
	alias.erase("self")
	print("RESULT ", JSON.stringify({"suite":"trace-bounded-journal", "checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)

func active_and_loops() -> void:
	var trace = Trace.new()
	var eid:int = trace.begin_execution()
	var parent_id:int = trace.begin_call({},"parent",[],[])
	var parent:Dictionary = trace.calls.back()
	var dangling_id:int = trace.begin_call({},"dangling",[],[])
	var dangling:Dictionary = trace.calls.back()
	var j = journal(trace)
	var h = scope(j)
	check(done(j.try_end_call(parent_id, [9], "done", source)) and parent.status == "done" and dangling.status == "aborted" and trace.call_stack.is_empty(), "end_call patches parent plus dangling")
	check(done(j.restore(h,source)) and parent.status == "running" and parent.return_value == null and dangling.status == "running" and trace.call_stack.size() == 2 and is_same(trace.call_stack[1],dangling), "all dangling patches and shared entries restored")
	h = scope(j)
	check(done(j.try_push_loop(4,source)), "push loop explicit owner")
	var nested_execution:Dictionary = j.try_begin_execution(source)
	check(done(nested_execution) and trace.loop_depths == [0,1], "nested begin execution real method")
	check(done(j.try_push_loop(5,source)) and done(j.try_begin_call({},"nested",[],[],source)), "nested execution call and loop")
	check(done(j.try_end_execution(eid,source)) and trace.call_stack.is_empty() and trace.loop_stack.is_empty() and parent.status == "aborted" and dangling.status == "aborted", "end_execution closes all affected active patches loops")
	check(done(j.restore(h,source)) and parent.status == "running" and dangling.status == "running" and trace.execution_stack == [eid] and trace.loop_depths == [0] and trace.loop_stack.is_empty() and trace.next_execution_id == eid and trace.next_call_id == dangling_id, "end_execution full patch stacks counters restore")
	h = scope(j)
	check(done(j.try_push_loop(8,source)) and done(j.try_pop_loop(source)) and done(j.restore(h,source)) and trace.loop_stack.is_empty(), "push pop loop reverse descriptors")
	h = scope(j)
	check(done(j.try_end_call(999999,null,"ignored",source)) and done(j.try_end_execution(999999,source)) and done(j.restore(h,source)) and parent.status == "running", "legacy missing explicit ids stay idempotent")
	h = scope(j)
	check(done(j.try_reset(source)) and trace.calls.is_empty(), "small full reset recorded")
	check(done(j.restore(h,source)) and trace.calls.size() == 2 and is_same(trace.calls[0],parent) and is_same(trace.call_stack[0],parent) and parent.status == "running", "small reset preserves entry and stack identity")

func containers_and_roots() -> void:
	var trace = Trace.new()
	trace.begin_call({},"containers",[],[])
	var j = journal(trace)
	var h = scope(j)
	var array:Array = [1,2,3,4]
	var key:Array = ["key"]
	var dict:Dictionary = {key:array, "second":2}
	var original_keys:Array = dict.keys()
	check(done(j.apply([{"kind":"patch","target":array,"index":1,"value":20},patch(dict,{key:[9],"second":8,"new":1})],source)), "raw array dictionary patch descriptor")
	check(done(j.apply([{"kind":"trim","target":array,"index":1,"count":2}],source)) and array == [1,4], "small middle trim")
	check(done(j.apply([{"kind":"contents","target":dict,"value":{"other":[]}}],source)), "dictionary contents reset descriptor")
	check(done(j.restore(h,source)) and array == [1,2,3,4] and is_same(dict[key],array) and dict.second == 2 and dict.keys().size() == 2 and is_same(dict.keys()[0],key) and dict.keys()[1] == original_keys[1], "dictionary actual key order nested identity restored")
	h = scope(j)
	var old_roots:Array = [trace.calls,trace._counters,trace.execution_stack,trace.call_stack,trace.loop_stack,trace.loop_depths]
	var desc:Array = []
	for slot in ["calls","_counters","execution_stack","call_stack","loop_stack","loop_depths"]:
		desc.append({"kind":"root","slot":slot,"value":{} if slot == "_counters" else []})
	check(done(j.apply(desc,source)) and trace.calls.is_empty(), "explicit all six root replacements")
	check(done(j.restore(h,source)) and is_same(trace.calls,old_roots[0]) and is_same(trace._counters,old_roots[1]) and is_same(trace.execution_stack,old_roots[2]) and is_same(trace.call_stack,old_roots[3]) and is_same(trace.loop_stack,old_roots[4]) and is_same(trace.loop_depths,old_roots[5]), "TARGET exact root identity not equal replacement")
	h = scope(j)
	var inner = scope(j)
	check(done(j.apply([patch(dict,{"second":9})],source)) and done(j.restore(inner,source)) and dict.second == 2, "inner restore consumes only inner")
	check(not done(j.restore(inner,source)) and done(j.release(h,source)), "consumed cursor cannot restore twice")

func budgets_and_faults() -> void:
	var trace = Trace.new()
	var id:int = trace.begin_call({},"budget",[],[])
	var entry:Dictionary = trace.calls[0]
	var limited = journal(trace,1,30000)
	var h = scope(limited)
	var before:Dictionary = limited.usage()
	var result:Dictionary = limited.try_end_call(id,7,"done",source)
	check(not done(result) and result.reason == "budget" and limited.usage() == before and entry.status == "running" and entry.return_value == null and trace.call_stack.size() == 1, "TARGET compound row budget zero writes")
	check(done(limited.release(h,source)), "row refusal handle remains usable")
	var units = journal(trace,256,4)
	h = scope(units)
	before = units.usage()
	check(not done(units.try_begin_execution(source)) and units.usage() == before and trace.next_execution_id == 0 and trace.execution_stack.is_empty(), "unit budget before id assignment")
	check(not done(units.begin_scope(source)) and units.usage() == before, "inner scope no fresh full allowance")
	check(done(units.release(h,source)), "unit refusal release")
	var j = journal(trace)
	h = scope(j)
	before = j.usage()
	var typed:Array[int] = [1]
	var readonly:Array = [1]
	readonly.make_read_only()
	check(not done(j.apply([{"kind":"append","target":typed,"items":[2]}],source)) and typed == [1], "typed raw target rejected")
	check(not done(j.apply([{"kind":"append","target":readonly,"items":[2]}],source)) and readonly == [1], "readonly raw target rejected")
	check(not done(j.apply([patch(entry,{"bad":[{"deep":RefCounted.new()}]})],source)) and not entry.has("bad"), "deep unknown Object rejected")
	check(not done(j.apply([patch(entry,{"bad":{"deep":[Callable()]}})],source)) and not entry.has("bad"), "deep Callable rejected")
	check(not done(j.apply([patch(entry,{"bad":[weakref(trace)]})],source)), "deep WeakRef rejected")
	check(not done(j.apply([patch(entry,{"bad":[PackedInt32Array([1])]})],source)), "deep PackedArray rejected")
	check(not done(j.apply([patch(entry,{"bad":[typed]})],source)) and not done(j.apply([patch(entry,{"bad":[readonly]})],source)), "deep typed readonly leaves rejected")
	check(j.usage() == before, "all rejected descriptors leave ledger untouched")
	check(not done(j.apply([patch(entry,{"x":1}),patch(entry,{"y":2})],source)) and not entry.has("x"), "alias overlapping descriptors pre-refused")
	check(done(j.release(h,source)), "release after negative plans")
	var dict:Dictionary = {"a":1}
	var arr:Array = [2]
	h = scope(j)
	check(done(j.apply([patch(dict,{"a":9}),{"kind":"patch","target":arr,"index":0,"value":10}],source)), "two affected targets recorded")
	dict.make_read_only()
	before = j.usage()
	check(not done(j.prevalidate(h,source)) and not done(j.restore(h,source)) and dict.a == 9 and arr == [10] and j.usage() == before, "all target readonly prevalidation before any reverse writes")
	check(done(j.release(h,source)), "readonly fault evidence release")
	var saved_leaf:Array = [1]
	var saved_dict:Dictionary = {"leaf":saved_leaf}
	var unaffected:Array = [1]
	h = scope(j)
	check(done(j.apply([patch(saved_dict,{"leaf":[2]}),{"kind":"patch","target":unaffected,"index":0,"value":2}],source)), "nested old leaf recorded")
	saved_leaf.make_read_only()
	check(not done(j.restore(h,source)) and saved_dict.leaf == [2] and unaffected == [2], "saved nested readonly leaf rejects whole restore before first write")
	check(done(j.release(h,source)), "nested leaf fault release")
	var shape:Array = [1]
	h = scope(j)
	check(done(j.apply([{"kind":"patch","target":shape,"index":0,"value":2}],source)), "shape recorded")
	shape.clear() # unsupported raw bypass, must not cause restore index error
	check(not done(j.restore(h,source)) and shape.is_empty(), "raw shape change fails before inverse index write")
	check(done(j.release(h,source)), "shape fault cursor release")
	h = scope(j)
	var other:Variant = Generation.derive_context(source,&"bounded_trace.other").context
	var original_usage:Dictionary = j.usage()
	check(not done(j.try_end_call(id,8,"done",other)) and not done(j.restore(h,other)) and j.usage() == original_usage and entry.status == "running", "same generation different original source rejected")
	check(not done(j.try_end_call(id,[{"bad":RefCounted.new()}],"done",source)) and entry.status == "running", "unknown deep return rejected before active patch")
	check(done(j.release(h,source)), "original source releases after mismatch")
	# Deliberate raw protocol violation is NOT admitted. Outgoing pins still
	# prevent last-reference PREDELETE from running during reverse restoration.
	var witness_target:Dictionary = {"x":1}
	var bucket:Array = []
	var pins = journal(trace)
	h = scope(pins)
	check(done(pins.apply([patch(witness_target,{"x":2})],source)), "outgoing witness slot recorded")
	witness_target.x = DeletionWitness.new(bucket)
	check(done(pins.restore(h,source)) and witness_target.x == 1 and bucket.is_empty(), "outgoing raw witness strongly pinned through restore")
	pins = null
	check(bucket == ["deleted"], "PREDELETE delayed to explicit journal disposal not restore")
