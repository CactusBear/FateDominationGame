class_name ExecutionTrace
extends RefCounted

#执行追踪：一次效果执行里每次 func 调用的开始/结束/父子关系/循环路径。
#只负责追踪本身，不认识卡牌规则、玩家解析、效果私有字段、数值对象——
#上下文与参数快照都由 GameLog（适配层）在调用前准备好传进来。
#存的是"当时的值"：数值已经是数字，活对象已经是身份标识，历史不跟着对象之后的变化走

var calls:Array = []            # 执行日志条目（调试/验证/回放用，读为主）
var _counters:Dictionary = {"next_execution_id":0, "next_call_id":0}
var next_execution_id:int:
	get: return _counters.next_execution_id
	set(value): _counters.next_execution_id = value
var next_call_id:int:
	get: return _counters.next_call_id
	set(value): _counters.next_call_id = value
var execution_stack:Array = []  # 存 execution_id
var call_stack:Array = []       # 存条目 Dictionary 本身，按条目定位收栈
var loop_stack:Array = []       # 循环路径，由循环类 operation 压/弹
#每个执行进入时的循环栈深度：结束时恢复到该深度，只清掉本执行期间新增的层。
#异常收尾若只清栈不恢复深度，本执行里压了循环却抛错没弹，残留会污染之后的调用
var loop_depths:Array = []


# TRACE_MANAGED_REVISION_BEGIN
# Owner metadata is graph-external. An observation is NOT an admission ticket.
const MANAGED_WRITER_ABI:StringName = &"execution_trace/managed_writer/1"
const MANAGED_WRITER_META:StringName = &"trace_managed_writer"
const MANAGED_WRITER_FAULT:StringName = &"trace_managed_writer_fault"
const MANAGED_VERSION_MAX:int = 9223372036854775807
const ManagedGeneration = preload("res://scripts/system/session_generation.gd")

func _init() -> void:
	set_meta(MANAGED_WRITER_META, [0])
	set_meta(MANAGED_WRITER_FAULT, false)

func _managed_backing_valid() -> bool:
	if not has_meta(MANAGED_WRITER_META): return false
	var fault:Variant = get_meta(MANAGED_WRITER_FAULT, true)
	if typeof(fault) != TYPE_BOOL or fault: return false
	var value:Variant = get_meta(MANAGED_WRITER_META)
	return value is Array and not value.is_typed() and not value.is_read_only() and value.size() == 1 and typeof(value[0]) == TYPE_INT and value[0] >= 0 and value[0] < MANAGED_VERSION_MAX

func _managed_trace_write() -> void:
	# Legacy void/int methods cannot report a new failure. Never suppress their
	# business writes: latch an invalid observation instead of wrapping/replacing.
	if not _managed_backing_valid():
		set_meta(MANAGED_WRITER_FAULT, true)
		return
	var backing:Array = get_meta(MANAGED_WRITER_META)
	backing[0] += 1

func _managed_roots() -> Array:
	return [calls, _counters, execution_stack, call_stack, loop_stack, loop_depths]

func managed_writer_snapshot(original_context:Variant = null) -> Dictionary:
	if not _managed_backing_valid(): return _managed_observation_failure("invalid_or_exhausted_metadata")
	if original_context != null and not ManagedGeneration.validate_context(original_context).get("ok", false): return _managed_observation_failure("stale_original_context")
	var roots:Array = _managed_roots()
	var covered:Array = [&"reset", &"begin_execution", &"end_execution", &"begin_call", &"end_call", &"journal_try_methods", &"journal_apply_fixed_roots_and_bounded_active_entries", &"journal_restore_recorded_managed_targets"]
	var uncovered:Array = [&"raw_root_assignment_swap_back", &"raw_root_contents", &"raw_retained_nested", &"scalar_counter_assignment", &"journal_apply_unclassified_retained_or_nested", &"journal_active_entry_outside_classification_bounds", &"GameLog_raw_loops_and_generic_restore", &"legacy_F_raw_install", &"arbitrary_native_thread_metadata"]
	roots.make_read_only()
	covered.make_read_only()
	uncovered.make_read_only()
	var result:Dictionary = {"status":"COMPLETED", "reason":"", "abi":MANAGED_WRITER_ABI, "scope":&"managed_trace_methods_only", "closure_status":"UNSUPPORTED", "owner":self, "roots":roots, "writer_version":get_meta(MANAGED_WRITER_META)[0], "original_context":original_context, "covered":covered, "uncovered":uncovered}
	result.make_read_only()
	return result

func managed_writer_matches(expected:Variant, original_context:Variant = null) -> bool:
	if not _managed_backing_valid() or not expected is Dictionary: return false
	if typeof(expected.get("status")) != TYPE_STRING or expected.status != "COMPLETED": return false
	if typeof(expected.get("abi")) != TYPE_STRING_NAME or expected.abi != MANAGED_WRITER_ABI or typeof(expected.get("scope")) != TYPE_STRING_NAME or expected.scope != &"managed_trace_methods_only": return false
	if not is_same(expected.get("owner"), self) or not is_same(expected.get("original_context"), original_context): return false
	if original_context != null and not ManagedGeneration.validate_context(original_context).get("ok", false): return false
	var roots:Variant = expected.get("roots")
	if not roots is Array or roots.size() != 6: return false
	if not is_same(roots[0], calls) or not is_same(roots[1], _counters) or not is_same(roots[2], execution_stack) or not is_same(roots[3], call_stack) or not is_same(roots[4], loop_stack) or not is_same(roots[5], loop_depths): return false
	return typeof(expected.get("writer_version")) == TYPE_INT and expected.writer_version == get_meta(MANAGED_WRITER_META)[0]

func _managed_observation_failure(reason:String) -> Dictionary:
	var result:Dictionary = {"status":"UNSUPPORTED", "reason":reason, "abi":MANAGED_WRITER_ABI, "closure_status":"UNSUPPORTED"}
	result.make_read_only()
	return result
# TRACE_MANAGED_REVISION_END


func reset() -> void:
	_managed_trace_write() # TRACE_REVISION_LEGACY
	calls.clear()
	next_execution_id = 0
	next_call_id = 0
	execution_stack.clear()
	call_stack.clear()
	loop_stack.clear()
	loop_depths.clear()


func begin_execution() -> int:
	_managed_trace_write() # TRACE_REVISION_LEGACY
	next_execution_id += 1
	execution_stack.append(next_execution_id)
	loop_depths.append(loop_stack.size())
	return next_execution_id


#结束一次执行。显式传编号时按编号定位收栈（幂等：找不到就什么都不做，不误弹别的）；
#不传编号时才结束栈顶。
func end_execution(eid:int = 0) -> void:
	var target:int = eid
	if target <= 0 and !execution_stack.is_empty():
		target = int(execution_stack[execution_stack.size() - 1])
	var start:int = execution_stack.find(target) if target > 0 else -1
	if start != -1:
		_managed_trace_write() # TRACE_REVISION_LEGACY
		#target 与比它更内层、还没结束的执行一起收尾：
		#内层若抛错没走到自己的 end_execution，它的调用也在这里清掉，不会永远留在栈上
		var closing:Array = []
		for i in range(start, execution_stack.size()):
			closing.append(int(execution_stack[i]))
		var kept:Array = []
		for call in call_stack:
			if closing.has(int(call.get("execution_id", -1))):
				if call.get("status", "") == "running":
					call["status"] = "aborted"
			else:
				kept.append(call)
		call_stack.assign(kept)
		#循环栈恢复到这些执行里最早进入时的深度：它们压的循环层一并清掉，
		#外层（start 之前）的循环层不动
		if start < loop_depths.size():
			loop_stack.resize(int(loop_depths[start]))
			loop_depths.resize(start)
		execution_stack.resize(start)
		return
	#显式传了编号但找不到：这次执行已经被收过了，幂等地什么都不做，不误弹栈顶
	if eid > 0:
		return
	if !execution_stack.is_empty():
		_managed_trace_write() # TRACE_REVISION_LEGACY
		execution_stack.pop_back()
		loop_depths.pop_back()


func begin_call(ctx:Dictionary, func_name:String, raw_snapshot, resolved_snapshot) -> int:
	_managed_trace_write() # TRACE_REVISION_LEGACY
	next_call_id += 1
	var eid:int = execution_stack[execution_stack.size() - 1] if !execution_stack.is_empty() else 0
	var parent_id:int = 0
	if !call_stack.is_empty():
		parent_id = int((call_stack[call_stack.size() - 1] as Dictionary).get("call_id", 0))
	var entry:Dictionary = {
		"call_id" : next_call_id,
		"parent_call_id" : parent_id,
		"execution_id" : eid,
		"round" : ctx.get("round", 0),
		"phase" : ctx.get("phase", ""),
		"effect_name" : ctx.get("effect_name", ""),
		"func_name" : func_name,
		"raw_parameters" : raw_snapshot,
		"resolved_parameters" : resolved_snapshot,
		"return_value" : null,
		"status" : "running",
		"trigger_player_id" : ctx.get("trigger_player_id", -1),
		"trigger_time_points" : (ctx.get("trigger_time_points", []) as Array).duplicate(),
		"loop_path" : loop_stack.duplicate(),
	}
	call_stack.append(entry)
	calls.append(entry)
	return next_call_id


#按 call_id 结束一次调用：把返回值快照与最终状态填回 begin 落下的那条。
#幂等：编号不在活动调用栈里（已结束/已随执行收尾/编号错）时不改任何东西，
#重复结束不会把已写好的结果改掉。本条之后的残留（嵌套里抛错没结束的调用）
#一并标成 aborted 弹出
func end_call(call_id:int, result_snapshot, status:String) -> void:
	if call_id <= 0:
		return
	var idx:int = -1
	for i in range(call_stack.size() - 1, -1, -1):
		if int((call_stack[i] as Dictionary).get("call_id", -1)) == call_id:
			idx = i
			break
	if idx == -1:
		return
	_managed_trace_write() # TRACE_REVISION_LEGACY
	var entry:Dictionary = call_stack[idx]
	entry["return_value"] = result_snapshot
	entry["status"] = status
	for i in range(call_stack.size() - 1, idx, -1):
		var dangling = call_stack[i]
		if dangling is Dictionary and dangling.get("status", "") == "running":
			dangling["status"] = "aborted"
		call_stack.remove_at(i)
	call_stack.remove_at(idx)


# Low-level mechanism ONLY. No admission, graph registration, shared meter or live attach.
# Inputs identify already-validated original targets; public raw aliases still bypass it.
# COMPLETED below is never a C permission or an A4 commit receipt.
func new_write_journal(original_source:Variant, limits:Dictionary) -> Dictionary:
	for key in ["max_rows", "max_units", "max_scopes"]:
		if typeof(limits.get(key)) != TYPE_INT or limits[key] <= 0:
			return {"status":"UNSUPPORTED", "reason":"explicit_budget_required"}
	if limits.size() != 3:
		return {"status":"UNSUPPORTED", "reason":"explicit_budget_required"}
	var journal := WriteJournal.new(self, original_source, limits)
	if not journal._authenticated:
		return {"status":"UNSUPPORTED", "reason":"original_source_required"}
	return {"status":"COMPLETED", "reason":"", "journal":journal}


# Explicit shared mode; no lookup of current checkpoint, no new allowance.
func new_shared_write_journal(original_source:Variant, limits:Dictionary, budget_owner:Variant, lease:Variant, work_bounds:Dictionary) -> Dictionary:
	const Parent = preload("res://scripts/match/rule_checkpoint.gd")
	if not budget_owner is RefCounted or not is_same(budget_owner.get_script(), Parent):
		return {"status":"UNSUPPORTED", "reason":"exact_budget_owner_required"}
	if not WriteJournal.valid_work_bounds(work_bounds):
		return {"status":"UNSUPPORTED", "reason":"explicit_work_bounds_required"}
	if limits.size() != 3: return {"status":"UNSUPPORTED", "reason":"explicit_budget_required"}
	for key in ["max_rows", "max_units", "max_scopes"]:
		if typeof(limits.get(key)) != TYPE_INT or limits[key] <= 0:
			return {"status":"UNSUPPORTED", "reason":"explicit_budget_required"}
	var valid:Dictionary = budget_owner.validate_budget_lease(lease, original_source)
	if valid.status != "COMPLETED": return valid
	# Source's own read-only diagnostic query is authentication bootstrap.
	# Charge our subsequent cold issuance-table scan before journal allocation.
	var provenance:Dictionary = WriteJournal.Source.lifecycle_diagnostics()
	var costs:Dictionary = {"collections":10, "comparisons":provenance.contexts + provenance.issued_tokens + 6, "values":80 + 4 * (provenance.contexts + provenance.issued_tokens), "objects":1}
	var paid:Dictionary = budget_owner.reserve_budget(lease, costs, original_source)
	if paid.status != "COMPLETED": return paid
	var journal := WriteJournal.new(self, original_source, limits)
	if not journal._authenticated: return {"status":"UNSUPPORTED", "reason":"original_source_required"}
	# Object metadata is graph-external, not a script-field exemption/registry.
	journal.set_meta(&"trace_shared_budget", {"owner":budget_owner, "lease":lease, "context":original_source,
		"bounds":work_bounds.duplicate(false), "active":false, "visits":0, "containers":0, "slots":0})
	return {"status":"COMPLETED", "reason":"", "journal":journal, "budget_mode":"shared_upper_bound", "parent_reservation":costs}


## Explicit public-frame bounded authentication; legacy factories never opt in.
func new_bounded_shared_write_journal(original_source:Variant, limits:Dictionary, budget_owner:Variant, lease:Variant, work_bounds:Dictionary) -> Dictionary:
	const Parent = preload("res://scripts/match/rule_checkpoint.gd")
	if not budget_owner is RefCounted or not is_same(budget_owner.get_script(), Parent):
		return {"status":"UNSUPPORTED", "reason":"exact_budget_owner_required"}
	if not WriteJournal.valid_work_bounds(work_bounds): return {"status":"UNSUPPORTED", "reason":"explicit_work_bounds_required"}
	if limits.size() != 3: return {"status":"UNSUPPORTED", "reason":"explicit_budget_required"}
	for key in ["max_rows", "max_units", "max_scopes"]:
		if typeof(limits.get(key)) != TYPE_INT or limits[key] <= 0: return {"status":"UNSUPPORTED", "reason":"explicit_budget_required"}
	var valid:Dictionary = budget_owner.validate_budget_lease_bounded(lease, original_source)
	if valid.status != "COMPLETED": return valid
	# No cold Source scan or diagnostics here: the ORIGINAL parent's cache is authority.
	var costs:Dictionary = {"collections":10, "comparisons":6, "values":80, "objects":1}
	var paid:Dictionary = budget_owner.reserve_budget_bounded(lease, costs, original_source)
	if paid.status != "COMPLETED": return paid
	var journal := WriteJournal.new(self, original_source, limits, budget_owner, lease)
	if not journal._authenticated: return {"status":"UNSUPPORTED", "reason":"original_source_required"}
	journal.set_meta(&"trace_shared_budget", {"owner":budget_owner, "lease":lease, "context":original_source,
		"bounds":work_bounds.duplicate(false), "active":false, "visits":0, "containers":0, "slots":0,
		"bounded_auth":true})
	return {"status":"COMPLETED", "reason":"", "journal":journal, "budget_mode":"shared_bounded_auth", "parent_reservation":paid.reservation}

class WriteJournal extends RefCounted:
	const Source = preload("res://scripts/system/session_generation.gd")
	const ROOTS = ["calls", "_counters", "execution_stack", "call_stack", "loop_stack", "loop_depths"]
	var _trace
	var _authenticated:bool = false
	var _source:Variant
	var _source_token:RefCounted
	var _source_origin:StringName
	var _limits:Dictionary
	var _records:Array = []
	var _scopes:Array = []
	# Bounded, prepaid outgoing pins survive restore/release until journal disposal.
	var _retired:Array = []
	# Lifetime cumulative work/retention reservations: no refund or new inner grant.
	var _units:int = 0

	func _init(trace:RefCounted, source:Variant, limits:Dictionary, budget_owner:Variant = null, lease:Variant = null):
		# Direct bounded construction must validate the real original parent lease.
		if not trace is ExecutionTrace or source is WeakRef: return
		if budget_owner == null:
			if not Source.validate_original_context(source).ok: return
		else:
			const Parent = preload("res://scripts/match/rule_checkpoint.gd")
			if not budget_owner is RefCounted or not is_same(budget_owner.get_script(), Parent): return
			if budget_owner.validate_budget_lease_bounded(lease, source).status != "COMPLETED": return
		if limits.size() != 3: return
		for key in ["max_rows", "max_units", "max_scopes"]:
			if typeof(limits.get(key)) != TYPE_INT or limits[key] <= 0: return
		_trace = trace
		_source = source
		_source_token = source.token()
		_source_origin = source.origin()
		_limits = limits.duplicate(false)
		_limits.make_read_only()
		_authenticated = true

	# These counters bound one prepaid traversal; they hold no allowance/balance.
	static func valid_work_bounds(bounds:Dictionary) -> bool:
		if bounds.size() != 5: return false
		for key in ["descriptors", "slots", "leaf_visits", "leaf_containers", "stack_slots"]:
			# Arithmetic-domain ceiling only, not a rule budget increase.
			if typeof(bounds.get(key)) != TYPE_INT or bounds[key] < 0 or bounds[key] > 67108863: return false
		return true

	func _shared_data() -> Dictionary:
		return get_meta(&"trace_shared_budget", {})

	func _bound_slots(count:int, plan:Dictionary) -> bool:
		var shared:Dictionary = _shared_data()
		if shared.is_empty(): return true
		if not shared.active or count < 0 or count > shared.bounds.slots - shared.slots:
			plan.reason = "shared_slots_bound"
			return false
		shared.slots += count
		return true

	func _shared_enter(kind:String, source:Variant) -> Dictionary:
		var shared:Dictionary = _shared_data()
		if shared.is_empty(): return _result()
		const Parent = preload("res://scripts/match/rule_checkpoint.gd")
		if shared.active or not is_same(source, _source) or not is_same(source, shared.context): return _result("shared_source_or_reentry")
		if not shared.owner is RefCounted or not is_same(shared.owner.get_script(), Parent): return _result("exact_budget_owner_required")
		if not valid_work_bounds(shared.bounds): return _result("explicit_work_bounds_required")
		var b:Dictionary = shared.bounds
		var d:int = b.descriptors
		var slots:int = b.slots
		var v:int = b.leaf_visits
		var k:int = b.leaf_containers
		var t:int = b.stack_slots
		var r:int = _records.size()
		# Scope handle creation/consumption never traverses descriptors or leaves.
		if kind == "begin_scope" or kind == "release":
			d = 0
			slots = 0
			v = 0
			k = 0
			t = 0
		var walks:int = 2 * slots + 2 * d + 4
		# Independent dimensions, derived from actual algorithm loops/shells.
		# Includes this operation's reverse scans/pins; unused prepaid work never refunds.
		var costs:Dictionary = {"collections":20 + 8 * d + 3 * t + 2 * walks + slots + v,
			"comparisons":12 + v * k + 6 * v + d * d + d * (d + r) + slots * slots + 2 * t * t + 4 * t,
			"values":160 + 32 * d + 4 * walks + 16 * v + 16 * slots + 18 * t + 12 * v * k + slots * slots + 4 * t * t + 8 * d * (d + r),
			"objects":1 if kind == "begin_scope" else 0}
		# Independent managed-revision delta. Never reuse the old D^2/T^2 terms:
		# six root identities + at most T active entries per prepared row;
		# two retained bool key/value slots, four accesses per scan candidate;
		# <= D row markers OR one legacy marker (D+1 conservatively covers both).
		# Each marker: <=48 comparisons / <=192 value accesses, no new shell/object.
		# Restore pays again; prevalidate may leave this reservation unused, no refund.
		# Scope/release perform no classification or Trace marker work.
		if kind != "begin_scope" and kind != "release":
			costs.comparisons += 6 * d + d * t + 48 * (d + 1)
			costs.values += 2 * d + 4 * d * t + 192 * (d + 1)
		var bounded:bool = shared.get("bounded_auth", false)
		var mode:String = "shared_bounded_auth" if bounded else "shared_upper_bound"
		var paid:Dictionary
		if bounded:
			paid = shared.owner.reserve_budget_bounded(shared.lease, costs, source)
		else:
			paid = shared.owner.reserve_budget(shared.lease, costs, source)
		if paid.status != "COMPLETED":
			paid["budget_mode"] = mode
			paid["parent_reservation"] = {}
			return paid
		shared.active = true
		shared.visits = 0
		shared.containers = 0
		shared.slots = 0
		# Diagnostic reservation is not an authority token or a second meter.
		return {"status":"COMPLETED", "reason":"", "parent_reservation":paid.reservation if bounded else costs}

	func _shared_leave(result:Dictionary, receipt:Dictionary) -> Dictionary:
		var shared:Dictionary = _shared_data()
		if shared.is_empty(): return result
		shared.active = false
		result["budget_mode"] = "shared_bounded_auth" if shared.get("bounded_auth", false) else "shared_upper_bound"
		result["parent_reservation"] = receipt.get("parent_reservation", {})
		return result

	func _result(reason:String = "", status:String = "UNSUPPORTED") -> Dictionary:
		return {"status":"COMPLETED" if reason.is_empty() else status, "reason":reason}

	func _valid_source(source:Variant) -> bool:
		# Factory validated this exact issued handle once. Do not repeat the
		# issuance-table scan in each bounded write; this is NOT C admission.
		if not _authenticated or not is_same(source, _source): return false
		var shared:Dictionary = _shared_data()
		if not shared.is_empty() and not shared.active: return false
		var current:Dictionary = Source.current_token()
		return current.ok and is_same(current.token, _source_token) and is_same(source.token(), _source_token) and source.origin() == _source_origin

	func usage() -> Dictionary:
		return {"units":_units, "rows":_records.size(), "scopes":_scopes.size()}

	func _local_begin_scope(source:Variant) -> Dictionary:
		if not _valid_source(source): return _result("stale_or_different_source")
		if _scopes.size() >= _limits.max_scopes or _units + 3 > _limits.max_units:
			return _result("budget")
		var handle:RefCounted = RefCounted.new()
		_scopes.append({"handle":handle, "mark":_records.size()})
		_units += 3 # handle, mark and its later consume
		return {"status":"COMPLETED", "reason":"", "handle":handle}

	func _cursor(handle:Variant, source:Variant) -> bool:
		return _valid_source(source) and not _scopes.is_empty() and is_same(handle, _scopes.back().handle)

	func _plan() -> Dictionary:
		return {"cost":0, "reason":"", "rows":[], "seen":[]}

	func _bill(plan:Dictionary, count:int) -> bool:
		if not plan.reason.is_empty(): return false
		if count < 0 or count > _limits.max_units - _units - plan.cost:
			plan.reason = "budget"
			return false
		plan.cost += count
		return true

	func _raw(value:Variant) -> bool:
		return (value is Array or value is Dictionary) and not value.is_typed() and not value.is_read_only()

	# Iterative, budgeted deep-leaf check. The local seen list is cycle detection,
	# NOT an identity registry or an ownership/admission mapping.
	func _leaves(value:Variant, plan:Dictionary) -> bool:
		if not _bill(plan, 1): return false
		var shared:Dictionary = _shared_data()
		if not shared.is_empty() and shared.visits >= shared.bounds.leaf_visits:
			plan.reason = "shared_leaf_visits_bound"
			return false
		var pending:Array = [value]
		while not pending.is_empty():
			if not _bill(plan, 1): return false
			if not shared.is_empty():
				if shared.visits >= shared.bounds.leaf_visits:
					plan.reason = "shared_leaf_visits_bound"
					return false
				shared.visits += 1
			var item:Variant = pending.pop_back()
			if item is Array or item is Dictionary:
				if not _raw(item):
					plan.reason = "typed_or_readonly"
					return false
				var known:bool = false
				for old in plan.seen:
					if not _bill(plan, 1): return false
					if is_same(old, item):
						known = true
						break
				if known: continue
				var slots:int = item.size() * (2 if item is Dictionary else 1)
				if not shared.is_empty():
					if shared.containers >= shared.bounds.leaf_containers or slots > shared.bounds.leaf_visits - shared.visits - pending.size():
						plan.reason = "shared_leaf_scan_bound"
						return false
					shared.containers += 1
				if not _bill(plan, slots + 3): return false
				plan.seen.append(item)
				if item is Array:
					for child in item: pending.append(child)
				else:
					for key in item:
						pending.append(key)
						pending.append(item[key])
			elif typeof(item) not in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME]:
				plan.reason = "unsupported_leaf"
				return false
		return true

	func _contents(target:Variant) -> Dictionary:
		return {"kind":"contents", "target":target, "value":target}

	func _root(slot:String) -> Variant:
		match slot:
			"calls": return _trace.calls
			"_counters": return _trace._counters
			"execution_stack": return _trace.execution_stack
			"call_stack": return _trace.call_stack
			"loop_stack": return _trace.loop_stack
			"loop_depths": return _trace.loop_depths
		return null

	func _set_root(slot:String, value:Variant) -> void:
		# Explicit fixed slots only; never Object.set / user callbacks.
		match slot:
			"calls": _trace.calls = value
			"_counters": _trace._counters = value
			"execution_stack": _trace.execution_stack = value
			"call_stack": _trace.call_stack = value
			"loop_stack": _trace.loop_stack = value
			"loop_depths": _trace.loop_depths = value

	func _prepare(descriptors:Array, plan:Dictionary) -> bool:
		var shared:Dictionary = _shared_data()
		if not shared.is_empty() and descriptors.size() > shared.bounds.descriptors:
			plan.reason = "shared_descriptors_bound"
			return false
		if descriptors.is_typed() or descriptors.is_read_only():
			plan.reason = "invalid_descriptors"
			return false
		if descriptors.size() > _limits.max_rows - _records.size():
			plan.reason = "budget"
			return false
		# Prepay every later virtual-size/alias prevalidation comparison and pin slot.
		if not _bill(plan, descriptors.size() * 8 + (descriptors.size() + _records.size()) * descriptors.size() * 4): return false
		for descriptor in descriptors:
			if not descriptor is Dictionary or typeof(descriptor.get("kind")) != TYPE_STRING:
				plan.reason = "invalid_descriptor"
				return false
			var kind:String = descriptor.kind
			var target:Variant = descriptor.get("target")
			if kind == "root":
				if typeof(descriptor.get("slot")) != TYPE_STRING or descriptor.slot not in ROOTS:
					plan.reason = "invalid_root_slot"
					return false
				target = _root(descriptor.slot)
			if not _raw(target):
				plan.reason = "typed_or_readonly_target"
				return false
			# Reject overlapping targets within one group, including alias roots.
			for previous in plan.rows:
				if not _bill(plan, 1): return false
				if is_same(previous.target, target) or (kind == "root" and previous.kind == "root" and previous.slot == descriptor.slot):
					plan.reason = "overlapping_descriptors"
					return false
			var row:Dictionary = {"kind":kind, "target":target}
			match kind:
				"patch":
					if target is Dictionary:
						var changes:Variant = descriptor.get("changes")
						if not changes is Dictionary or not _leaves(changes, plan):
							if plan.reason.is_empty(): plan.reason = "invalid_changes"
							return false
						if not _bound_slots(target.size() + changes.size() * 2, plan): return false
						if not _bill(plan, target.size() * changes.size() + changes.size() * 8): return false
						row["slots"] = []
						for key in changes:
							var present:bool = false
							var original_key:Variant = key
							# Raw container keys require EXACT stored key identity. Never
							# run recursive value equality on an unvalidated old key.
							for old_key in target:
								if typeof(old_key) == typeof(key) and (is_same(old_key, key) if key is Array or key is Dictionary else old_key == key):
									original_key = old_key
									present = true
									break
							if not present and (key is Array or key is Dictionary):
								plan.reason = "new_container_key_requires_protocol"
								return false
							var old:Variant = target.get(original_key) if present else null
							if not _leaves(original_key, plan) or not _leaves(old, plan): return false
							row.slots.append({"key":original_key, "present":present, "old":old, "value":changes[key]})
					else:
						var index:Variant = descriptor.get("index")
						if typeof(index) != TYPE_INT or index < 0 or index >= target.size():
							plan.reason = "invalid_index"
							return false
						if not _bound_slots(2, plan): return false
						if not _bill(plan, 6) or not _leaves(target[index], plan) or not _leaves(descriptor.get("value"), plan): return false
						row.merge({"index":index, "old":target[index], "value":descriptor.get("value")})
				"append":
					var items:Variant = descriptor.get("items")
					if not target is Array or not items is Array:
						plan.reason = "invalid_append"
						return false
					if not _bound_slots(items.size(), plan): return false
					if not _bill(plan, items.size() * 4 + 2) or not _leaves(items, plan): return false
					row.merge({"size":target.size(), "items":items.duplicate(false)})
				"trim":
					var index:Variant = descriptor.get("index")
					var count:Variant = descriptor.get("count")
					if not target is Array or typeof(index) != TYPE_INT or typeof(count) != TYPE_INT or index < 0 or count < 0 or index > target.size() or count > target.size() - index:
						plan.reason = "invalid_trim"
						return false
					# Charge displaced suffix too: prefix removal is NOT O(count).
					if not _bound_slots(target.size() - index + count, plan): return false
					if not _bill(plan, (target.size() - index) * 4 + count * 3 + 2): return false
					row.merge({"index":index, "count":count, "size":target.size(), "items":target.slice(index, index + count)})
					if not _leaves(row.items, plan): return false
				"contents":
					var value:Variant = descriptor.get("value")
					if typeof(value) != typeof(target) or not _raw(value):
						plan.reason = "invalid_contents"
						return false
					if not _bound_slots(target.size() + value.size(), plan): return false
					if not _bill(plan, (target.size() + value.size()) * (8 if target is Dictionary else 4) + 2): return false
					if not _leaves(target, plan) or not _leaves(value, plan): return false
					row.merge({"old":target.duplicate(false), "value":value.duplicate(false), "max_size":maxi(target.size(), value.size())})
				"root":
					var value:Variant = descriptor.get("value")
					if typeof(value) != typeof(target) or not _raw(value):
						plan.reason = "invalid_root_value"
						return false
					if not _bill(plan, 6) or not _leaves(value, plan): return false
					# Old root is an already-validated target input, not O(1) adoption.
					row.merge({"slot":descriptor.slot, "value":value})
				_:
					plan.reason = "unknown_descriptor"
					return false
			row["managed_trace_target"] = kind == "root" or _managed_target(target, shared, plan) # TRACE_REVISION_ATTRIBUTION
			plan.rows.append(row)
		if not plan.rows.is_empty(): plan.rows[0]["leaf_guards"] = plan.seen
		return true

	func _reserve(descriptors:Array, source:Variant, plan:Dictionary) -> Dictionary:
		if not _valid_source(source): return _result("stale_or_different_source")
		if _scopes.is_empty(): return _result("scope_required")
		if not _prepare(descriptors, plan): return _result(plan.reason)
		# Private inverse/forward references are all strong. No partial reservation.
		_records.append_array(plan.rows)
		_units += plan.cost
		return _result()

	func _assign(target:Variant, value:Variant) -> void:
		if target is Array:
			target.assign(value)
		else:
			target.clear()
			for key in value: target[key] = value[key]

	# TRACE_MANAGED_ROWS_BEGIN
	func _managed_target(target:Variant, shared:Dictionary, plan:Dictionary) -> bool:
		if is_same(target, _trace.calls) or is_same(target, _trace._counters) or is_same(target, _trace.execution_stack) or is_same(target, _trace.call_stack) or is_same(target, _trace.loop_stack) or is_same(target, _trace.loop_depths): return true
		if not target is Dictionary: return false
		# Only active entries, never scan complete calls/history or nested values.
		# Shared classification is restricted to the declared stack work boundary.
		if not shared.is_empty() and _trace.call_stack.size() > shared.bounds.stack_slots: return false
		# Preserve the previous per-scan local ceiling in shared mode as well.
		if _trace.call_stack.size() > _limits.max_units - _units: return false
		# Local mode prepays the ENTIRE candidate scan from this group's plan.
		# All rows share the same remaining units; no D-times reuse of one allowance.
		# Outside the classification bound preserve the old unclassified write/fault
		# contract, rather than scanning first or fabricating owner provenance.
		if shared.is_empty():
			var candidates:int = _trace.call_stack.size()
			if candidates > _limits.max_units - _units - plan.cost: return false
			if not _bill(plan, candidates): return false
		for entry in _trace.call_stack:
			if is_same(entry, target): return true
		return false

	func _managed_row_has_write(row:Dictionary, reverse:bool) -> bool:
		match row.kind:
			"root": return not is_same(_root(row.slot), row.target if reverse else row.value)
			"patch": return not row.slots.is_empty() if row.target is Dictionary else true
			"append": return not row.items.is_empty()
			"trim": return row.count > 0
			"contents": return not row.target.is_empty() or not (row.old if reverse else row.value).is_empty()
		return false

	func _managed_row_write(row:Dictionary, reverse:bool) -> void:
		if not _managed_row_has_write(row, reverse): return
		if row.kind == "root" or row.get("managed_trace_target", false):
			_trace._managed_trace_write()
		else:
			# Arbitrary descriptor target has no owner proof. Do not invent a
			# Trace write/version, but never leave a positive observation usable.
			_trace.set_meta(MANAGED_WRITER_FAULT, true)
	# TRACE_MANAGED_ROWS_END

	func _forward(row:Dictionary) -> void:
		_managed_row_write(row, false) # TRACE_REVISION_FORWARD
		match row.kind:
			"patch":
				if row.target is Dictionary:
					for slot in row.slots: row.target[slot.key] = slot.value
				else: row.target[row.index] = row.value
			"append": row.target.append_array(row.items)
			"trim":
				for i in range(row.index, row.size - row.count): row.target[i] = row.target[i + row.count]
				row.target.resize(row.size - row.count)
			"contents": _assign(row.target, row.value)
			"root": _set_root(row.slot, row.value)

	func _local_apply(descriptors:Array, source:Variant) -> Dictionary:
		var plan:Dictionary = _plan()
		var reserved:Dictionary = _reserve(descriptors, source, plan)
		if reserved.status != "COMPLETED": return reserved
		for row in plan.rows: _forward(row)
		return {"status":"COMPLETED", "reason":"", "cost":plan.cost, "rows":plan.rows.size()}

	func _check_restore(handle:Variant, source:Variant) -> Dictionary:
		if not _cursor(handle, source): return _result("stale_or_non_lifo_cursor")
		# Virtual lengths validate the ENTIRE reverse sequence before first write.
		var shared:Dictionary = _shared_data()
		if not shared.is_empty():
			if _records.size() > shared.bounds.descriptors: return _result("shared_restore_rows_bound")
			var guards:int = 0
			for row in _records: guards += row.get("leaf_guards", []).size()
			if guards > shared.bounds.leaf_visits: return _result("shared_restore_guards_bound")
		var sizes:Array = []
		for i in range(_records.size() - 1, _scopes.back().mark - 1, -1):
			var row:Dictionary = _records[i]
			for leaf in row.get("leaf_guards", []):
				if not _raw(leaf): return _result("restore_leaf_readonly_or_typed", "FAULT")
			if not _raw(row.target): return _result("restore_target_readonly_or_typed", "FAULT")
			if row.kind == "root" and not _raw(_root(row.slot)): return _result("restore_root_readonly_or_typed", "FAULT")
			if not shared.is_empty():
				var pin_slots:int = 0
				match row.kind:
					"contents": pin_slots = maxi(row.target.size(), row.old.size()) * (2 if row.target is Dictionary else 1)
					"append": pin_slots = maxi(row.target.size() - row.size, 0)
					"trim": pin_slots = row.size - row.index
					"patch": pin_slots = row.slots.size() if row.target is Dictionary else 1
				if not _bound_slots(pin_slots, {"reason":""}): return _result("shared_restore_slots_bound")
			var size:int = row.target.size()
			var found:Variant = null
			for state in sizes:
				if is_same(state.target, row.target):
					found = state
					size = state.size
					break
			if found == null:
				found = {"target":row.target, "size":size}
				sizes.append(found)
			match row.kind:
				"append":
					if size != row.size + row.items.size(): return _result("restore_shape_changed", "FAULT")
					found.size = row.size
				"trim":
					if size != row.size - row.count: return _result("restore_shape_changed", "FAULT")
					found.size = row.size
				"patch":
					if row.target is Array and row.index >= size: return _result("restore_shape_changed", "FAULT")
				"contents":
					if size > row.max_size: return _result("restore_shape_changed", "FAULT")
					found.size = row.old.size()
		return _result()

	func _local_prevalidate(handle:Variant, source:Variant) -> Dictionary:
		if not _cursor(handle, source): return _result("stale_or_non_lifo_cursor")
		# Extra public inspections are charged; the actual restore is prepaid.
		var plan:Dictionary = _plan()
		var shared:Dictionary = _shared_data()
		if not shared.is_empty() and _records.size() > shared.bounds.descriptors: return _result("shared_restore_rows_bound")
		var inspected:int = _records.size() * (_records.size() + 3)
		for row in _records: inspected += row.get("leaf_guards", []).size()
		if not _bill(plan, inspected): return _result(plan.reason)
		var checked:Dictionary = _check_restore(handle, source)
		if checked.status == "COMPLETED": _units += plan.cost
		return checked

	func _pin(row:Dictionary) -> Variant:
		# Pin outgoing slots too, even a raw bypass value. Pins survive the whole
		# reverse pass, so PREDELETE cannot run in the restore write window.
		match row.kind:
			"root": return _root(row.slot)
			"contents": return row.target.duplicate(false)
			"append": return row.target.slice(row.size)
			"trim": return row.target.slice(row.index)
			"patch":
				if row.target is Array: return row.target[row.index] if row.index < row.target.size() else null
				var slots:Array = []
				for slot in row.slots: slots.append(row.target.get(slot.key))
				return slots
		return null

	func _reverse(row:Dictionary) -> void:
		_managed_row_write(row, true) # TRACE_REVISION_RESTORE
		match row.kind:
			"patch":
				if row.target is Dictionary:
					for slot in row.slots:
						if slot.present: row.target[slot.key] = slot.old
						else: row.target.erase(slot.key)
				else: row.target[row.index] = row.old
			"append": row.target.resize(row.size)
			"trim":
				row.target.resize(row.size)
				for i in range(row.size - row.count - 1, row.index - 1, -1): row.target[i + row.count] = row.target[i]
				for i in range(row.count): row.target[row.index + i] = row.items[i]
			"contents": _assign(row.target, row.old)
			"root": _set_root(row.slot, row.target)

	func _local_restore(handle:Variant, source:Variant) -> Dictionary:
		var checked:Dictionary = _check_restore(handle, source)
		if checked.status != "COMPLETED": return checked
		var mark:int = _scopes.back().mark
		# Pin only at the row's reverse stage: work is bounded by that row, not
		# by the largest later live stack multiplied by all earlier snapshots.
		for i in range(_records.size() - 1, mark - 1, -1):
			_retired.append(_pin(_records[i]))
			_reverse(_records[i])
		_records.resize(mark)
		_scopes.pop_back()
		return _result()

	func _local_release(handle:Variant, source:Variant) -> Dictionary:
		if not _cursor(handle, source): return _result("stale_or_non_lifo_cursor")
		_scopes.pop_back()
		# Inner release must leave outer inverse rows and lifetime charges intact.
		if _scopes.is_empty(): _records.clear()
		return _result()

	func _schema(plan:Dictionary, source:Variant) -> bool:
		if not _valid_source(source) or _scopes.is_empty():
			plan.reason = "source_or_scope_required"
			return false
		var shared:Dictionary = _shared_data()
		if not shared.is_empty() and _trace.call_stack.size() + _trace.execution_stack.size() + _trace.loop_depths.size() + _trace.loop_stack.size() > shared.bounds.stack_slots:
			plan.reason = "shared_stack_bound"
			return false
		for slot in ROOTS:
			if not _raw(_root(slot)):
				plan.reason = "typed_or_readonly_target"
				return false
		if typeof(_trace._counters.get("next_call_id")) != TYPE_INT or typeof(_trace._counters.get("next_execution_id")) != TYPE_INT:
			plan.reason = "invalid_counters"
			return false
		if not _bill(plan, 12 + _trace.call_stack.size() * 8 + _trace.execution_stack.size() * 2 + _trace.loop_depths.size() * 2): return false
		for entry in _trace.call_stack:
			if not entry is Dictionary or not _raw(entry) or typeof(entry.get("call_id")) != TYPE_INT or typeof(entry.get("execution_id")) != TYPE_INT or typeof(entry.get("status")) != TYPE_STRING:
				plan.reason = "invalid_call_stack"
				return false
		for value in _trace.execution_stack:
			if typeof(value) != TYPE_INT:
				plan.reason = "invalid_execution_stack"
				return false
		for depth in _trace.loop_depths:
			if typeof(depth) != TYPE_INT or depth < 0:
				plan.reason = "invalid_loop_depth"
				return false
		return true

	func _local_try_begin_execution(source:Variant) -> Dictionary:
		var plan:Dictionary = _plan()
		if not _schema(plan, source): return _result(plan.reason)
		if not _bill(plan, 20): return _result(plan.reason)
		var reserved:Dictionary = _reserve([_contents(_trace._counters),
			{"kind":"append", "target":_trace.execution_stack, "items":[]},
			{"kind":"append", "target":_trace.loop_depths, "items":[]}], source, plan)
		if reserved.status != "COMPLETED": return reserved
		var id:int = _trace.begin_execution()
		plan.rows[1].items.append(id)
		plan.rows[2].items.append(_trace.loop_stack.size())
		return {"status":"COMPLETED", "reason":"", "execution_id":id}

	func _local_try_begin_call(ctx:Dictionary, name:String, raw:Variant, resolved:Variant, source:Variant) -> Dictionary:
		var plan:Dictionary = _plan()
		if not _schema(plan, source): return _result(plan.reason)
		if not _leaves(ctx, plan) or not _leaves(raw, plan) or not _leaves(resolved, plan) or not _leaves(_trace.loop_stack, plan): return _result(plan.reason)
		if not ctx.get("trigger_time_points", []) is Array: return _result("invalid_time_points")
		# Old method allocates exactly one 14-slot entry + two shallow path arrays.
		if not _bound_slots(14 + ctx.get("trigger_time_points", []).size() + _trace.loop_stack.size(), plan): return _result(plan.reason)
		if not _bill(plan, 40 + ctx.get("trigger_time_points", []).size() + _trace.loop_stack.size()): return _result(plan.reason)
		var reserved:Dictionary = _reserve([_contents(_trace._counters), _contents(_trace.call_stack),
			{"kind":"append", "target":_trace.calls, "items":[]}], source, plan)
		if reserved.status != "COMPLETED": return reserved
		plan.rows[1].max_size = _trace.call_stack.size() + 1
		var id:int = _trace.begin_call(ctx, name, raw, resolved)
		# Hold the newly allocated entry as well, before any later restore releases it.
		plan.rows.back().items.append(_trace.calls.back())
		return {"status":"COMPLETED", "reason":"", "call_id":id}

	func _local_try_end_call(id:int, result:Variant, status:String, source:Variant) -> Dictionary:
		var plan:Dictionary = _plan()
		if not _schema(plan, source): return _result(plan.reason)
		if not _bill(plan, _trace.call_stack.size() * 5): return _result(plan.reason)
		var index:int = -1
		for i in range(_trace.call_stack.size() - 1, -1, -1):
			if int(_trace.call_stack[i].get("call_id", -1)) == id:
				index = i
				break
		if index < 0 or id <= 0: return _reserve([], source, plan)
		var descriptors:Array = [_contents(_trace.call_stack)]
		for i in range(index, _trace.call_stack.size()):
			var entry:Dictionary = _trace.call_stack[i]
			var changes:Dictionary = {"return_value":result, "status":status} if i == index else {"status":"aborted"}
			if i == index or entry.get("status", "") == "running": descriptors.append({"kind":"patch", "target":entry, "changes":changes})
		var reserved:Dictionary = _reserve(descriptors, source, plan)
		if reserved.status != "COMPLETED": return reserved
		_trace.end_call(id, result, status)
		return _result()

	func _local_try_end_execution(eid:int, source:Variant) -> Dictionary:
		var plan:Dictionary = _plan()
		if not _schema(plan, source): return _result(plan.reason)
		# Charge every legacy find/has scan, including closing.has for each call.
		var n:int = _trace.execution_stack.size()
		if not _bill(plan, n * (_trace.call_stack.size() + 3) * 3 + _trace.call_stack.size() * 8 + _trace.loop_stack.size() * 2): return _result(plan.reason)
		var target:int = eid
		if target <= 0 and n > 0: target = int(_trace.execution_stack.back())
		var start:int = _trace.execution_stack.find(target) if target > 0 else -1
		if start < 0:
			if eid > 0 or n == 0: return _reserve([], source, plan)
			var fallback:Dictionary = _reserve([_contents(_trace.execution_stack), _contents(_trace.loop_depths)], source, plan)
			if fallback.status != "COMPLETED": return fallback
			_trace.end_execution(eid)
			return _result()
		var desired_depth:int = int(_trace.loop_depths[start]) if start < _trace.loop_depths.size() else _trace.loop_stack.size()
		if not _bill(plan, maxi(desired_depth - _trace.loop_stack.size(), 0) * 4): return _result(plan.reason)
		var descriptors:Array = [_contents(_trace.execution_stack), _contents(_trace.loop_depths), _contents(_trace.loop_stack), _contents(_trace.call_stack)]
		var closing:Array = _trace.execution_stack.slice(start)
		for entry in _trace.call_stack:
			if closing.has(int(entry.get("execution_id", -1))) and entry.get("status", "") == "running":
				descriptors.append({"kind":"patch", "target":entry, "changes":{"status":"aborted"}})
		var reserved:Dictionary = _reserve(descriptors, source, plan)
		if reserved.status != "COMPLETED": return reserved
		plan.rows[2].max_size = maxi(plan.rows[2].max_size, desired_depth)
		_trace.end_execution(eid)
		return _result()

	func _local_try_push_loop(index:int, source:Variant) -> Dictionary:
		if not _valid_source(source): return _result("stale_or_different_source")
		return _local_apply([{"kind":"append", "target":_trace.loop_stack, "items":[index]}], source)

	func _local_try_pop_loop(source:Variant) -> Dictionary:
		if not _valid_source(source): return _result("stale_or_different_source")
		if _trace.loop_stack.is_empty(): return _local_apply([], source)
		return _local_apply([{"kind":"trim", "target":_trace.loop_stack, "index":_trace.loop_stack.size() - 1, "count":1}], source)

	func _local_try_reset(source:Variant) -> Dictionary:
		if not _valid_source(source): return _result("stale_or_different_source")
		var descriptors:Array = []
		for slot in ROOTS: descriptors.append(_contents(_root(slot)))
		var plan:Dictionary = _plan()
		var reserved:Dictionary = _reserve(descriptors, source, plan)
		if reserved.status != "COMPLETED": return reserved
		_trace.reset()
		return _result()

	func begin_scope(source:Variant) -> Dictionary:
		var receipt:Dictionary = _shared_enter("begin_scope", source)
		if receipt.status != "COMPLETED": return receipt
		return _shared_leave(_local_begin_scope(source), receipt)

	func apply(descriptors:Array, source:Variant) -> Dictionary:
		var receipt:Dictionary = _shared_enter("apply", source)
		if receipt.status != "COMPLETED": return receipt
		return _shared_leave(_local_apply(descriptors, source), receipt)

	func prevalidate(handle:Variant, source:Variant) -> Dictionary:
		var receipt:Dictionary = _shared_enter("prevalidate", source)
		if receipt.status != "COMPLETED": return receipt
		return _shared_leave(_local_prevalidate(handle, source), receipt)

	func restore(handle:Variant, source:Variant) -> Dictionary:
		var receipt:Dictionary = _shared_enter("restore", source)
		if receipt.status != "COMPLETED": return receipt
		return _shared_leave(_local_restore(handle, source), receipt)

	func release(handle:Variant, source:Variant) -> Dictionary:
		var receipt:Dictionary = _shared_enter("release", source)
		if receipt.status != "COMPLETED": return receipt
		return _shared_leave(_local_release(handle, source), receipt)

	func try_begin_execution(source:Variant) -> Dictionary:
		var receipt:Dictionary = _shared_enter("try_begin_execution", source)
		if receipt.status != "COMPLETED": return receipt
		return _shared_leave(_local_try_begin_execution(source), receipt)

	func try_end_execution(eid:int, source:Variant) -> Dictionary:
		var receipt:Dictionary = _shared_enter("try_end_execution", source)
		if receipt.status != "COMPLETED": return receipt
		return _shared_leave(_local_try_end_execution(eid, source), receipt)

	func try_begin_call(ctx:Dictionary, name:String, raw:Variant, resolved:Variant, source:Variant) -> Dictionary:
		var receipt:Dictionary = _shared_enter("try_begin_call", source)
		if receipt.status != "COMPLETED": return receipt
		return _shared_leave(_local_try_begin_call(ctx, name, raw, resolved, source), receipt)

	func try_end_call(id:int, result:Variant, status:String, source:Variant) -> Dictionary:
		var receipt:Dictionary = _shared_enter("try_end_call", source)
		if receipt.status != "COMPLETED": return receipt
		return _shared_leave(_local_try_end_call(id, result, status, source), receipt)

	func try_push_loop(index:int, source:Variant) -> Dictionary:
		var receipt:Dictionary = _shared_enter("try_push_loop", source)
		if receipt.status != "COMPLETED": return receipt
		return _shared_leave(_local_try_push_loop(index, source), receipt)

	func try_pop_loop(source:Variant) -> Dictionary:
		var receipt:Dictionary = _shared_enter("try_pop_loop", source)
		if receipt.status != "COMPLETED": return receipt
		return _shared_leave(_local_try_pop_loop(source), receipt)

	func try_reset(source:Variant) -> Dictionary:
		var receipt:Dictionary = _shared_enter("try_reset", source)
		if receipt.status != "COMPLETED": return receipt
		return _shared_leave(_local_try_reset(source), receipt)
