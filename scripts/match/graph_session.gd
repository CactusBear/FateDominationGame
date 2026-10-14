extends RefCounted
## 一次计划一张 M。结构建图不是执行准入：resolve 必须经 E2 + C 复验。
## 不调用旧 capture/restore/clone_data，不试读未知对象，不安装 live。
const Domain = preload("res://scripts/system/atomic_execution_domain.gd")
const Plan = preload("res://scripts/system/atomic_action_plan.gd")
const Random = preload("res://scripts/match/rule_random.gd")
var _plan_api:Script = Plan
var _domain:RefCounted
var _plan:RefCounted
var _context:Variant
var _binding:Variant
var _registry:RefCounted
var _admission:Variant
var _call_spec:Dictionary = {}
var _entries:Array = []
var _leaves:Array = []
var _pending:Array = []
var _protected:Array = []
var _ledger:Array = []
var _invalid:bool = false
var _reason:String = ""
var _closed:bool = false
var _random:Array = []
var _callables:Array = []
var _weak_proofs:Array = []
var _certificate:RefCounted = RefCounted.new()
var _max_entries:int = 100000
var _comparisons:int = 0
var _max_comparisons:int = 1000000
# 结构证书不反调 C；关联、执行和发布各持原阶段许可。
var _association:Variant
var _authenticating:bool = false
var _authentication_reentered:bool = false
var _structure:Array = []
var _structure_locked:bool = false
var _structure_identity:RefCounted = RefCounted.new()

static func local_support_view() -> Dictionary:
	return {"abi_version":1,"status":"unknown","proof":"not_complete",
		"mechanisms":["raw_two_phase_identity_memo","reverse_identity","tagged_leaf_registry","protected_write_ledger","rng_E3_raw_authoritative"],
		"unproven":["E2_C_execution_admission","all_protected_writer_coverage","object_factories_backing_adapters","Callable_WeakRef_executable_closure","formal_owner_integration"]}

static func _result(status:String, reason:String = "", value:Variant = null) -> Dictionary:
	return {"status":status,"reason":reason,"value":value}

func configure(domain:RefCounted, plan:RefCounted, context:Variant, limits:Dictionary = {}) -> Dictionary:
	if domain == null or plan == null or _domain != null or domain.get_script() != Domain or context == null:
		return _result("REJECTED","invalid_graph_configuration")
	for key in limits:
		if key not in ["max_entries","max_comparisons"] or not limits[key] is int or limits[key] <= 0:
			return _result("UNSUPPORTED","invalid_graph_budget")
	_domain = domain
	_plan = plan
	_context = context
	_max_entries = limits.get("max_entries",_max_entries)
	_max_comparisons = limits.get("max_comparisons",_max_comparisons)
	return _result("COMPLETED")

## C 是唯一 admission 签发者；这里仅接其真实 opaque 证据，不自造字符串许可。
func attach_execution(binding:Variant, registry:RefCounted, admission:Variant, call_spec:Dictionary) -> Dictionary:
	if not ResourceLoader.exists("res://scripts/system/atomic_setter_registry.gd"):
		return _result("UNSUPPORTED","missing_capability_registry")
	if registry == null or registry.get_script() != load("res://scripts/system/atomic_setter_registry.gd"):
		return _result("REJECTED","wrong_capability_registry")
	var previous:Array = [_binding,_registry,_admission,_call_spec]
	_binding = binding
	_registry = registry
	_admission = admission
	_call_spec = call_spec.duplicate(false)
	var checked:Dictionary = authenticate(Domain.current_frame().status == "COMPLETED")
	if checked.status != "COMPLETED":
		_binding = previous[0]
		_registry = previous[1]
		_admission = previous[2]
		_call_spec = previous[3]
	return checked

func authenticate(executing:bool = true) -> Dictionary:
	if _authenticating:
		_authentication_reentered = true
		return _result("FAULT","recursive_graph_authentication")
	_authenticating = true
	_authentication_reentered = false
	var checked:Dictionary = _authenticate(executing)
	_authenticating = false
	return _result("FAULT","recursive_graph_authentication") if _authentication_reentered else checked

func _authenticate(executing:bool) -> Dictionary:
	if executing and _call_spec.get("admission_kind") != "EXECUTE": return _result("REJECTED","graph_execute_stage_required")
	if not executing and _call_spec.get("admission_kind") not in ["FACTORY","SEAL_CHECK"]: return _result("REJECTED","graph_association_stage_required")
	if _closed or _invalid: return _result("REJECTED",_reason if _invalid else "graph_closed")
	if _domain == null: return _result("REJECTED","graph_not_configured")
	if not _plan_api.has_method("validate_execution_binding"):
		return _result("UNSUPPORTED","E2_not_installed")
	if _binding == null or _registry == null or _admission == null:
		return _result("UNSUPPORTED","missing_C_admission")
	var marker:Variant = null
	if executing:
		var frame:Dictionary = Domain.current_frame()
		if frame.status != "COMPLETED" or not is_same(frame.domain,_domain) or not is_same(frame.plan_identity,_plan) or not is_same(frame.original_context,_context):
			return _result("REJECTED","wrong_graph_frame")
		marker = frame.marker
	var checked:Dictionary = _plan_api.call("validate_execution_binding",_binding,_context,marker)
	if checked.get("status") != "COMPLETED": return checked
	if not is_same(checked.get("plan_identity"),_plan) or not is_same(checked.get("domain_identity"),_domain.identity()):
		return _result("REJECTED","wrong_graph_binding")
	if not _registry.has_method("validate_admission"): return _result("UNSUPPORTED","missing_C_validator")
	var admitted:Dictionary = _registry.validate_admission(_admission,_binding,_call_spec)
	if admitted.get("status") != "COMPLETED": return admitted
	if executing and not _registry.execution_scope_active(_admission): return _result("REJECTED","no_active_registered_execution_scope")
	return validate_graph()

func _index(value:Variant, reverse_direction:bool = false) -> int:
	for index in range(_entries.size()):
		_comparisons += 1
		if _comparisons > _max_comparisons:
			_reason = "graph_comparison_budget"
			return -1
		if is_same(_entries[index].private if reverse_direction else _entries[index].live,value): return index
	return -1

func reserve(live:Variant, private_value:Variant) -> Dictionary:
	if _domain == null or _closed or not _reference(live) or not _reference(private_value) or typeof(live) != typeof(private_value):
		return _result("REJECTED","invalid_graph_identity")
	if is_same(live,private_value): return _result("REJECTED","mutable_live_alias")
	var existing:int = _index(live)
	if existing >= 0:
		return _result("COMPLETED","",private_value) if is_same(_entries[existing].private,private_value) else _result("REJECTED","duplicate_live_mapping")
	if _index(private_value,true) >= 0: return _result("REJECTED","reverse_mapping_not_injective")
	if not _reason.is_empty(): return _result("UNSUPPORTED",_reason)
	if _entries.size() >= _max_entries: return _result("UNSUPPORTED","graph_entry_budget")
	var bound:Dictionary = _domain.bind_dependency(live,private_value)
	if bound.status != "COMPLETED": return bound
	_entries.append({"live":live,"private":private_value})
	return _result("COMPLETED","",private_value)

static func _reference(value:Variant) -> bool:
	return value is Object or value is Array or value is Dictionary

static func _scalar(value:Variant) -> bool:
	return typeof(value) in [TYPE_NIL,TYPE_BOOL,TYPE_INT,TYPE_FLOAT,TYPE_STRING,TYPE_STRING_NAME]

func _leaf(value:Variant) -> Dictionary:
	for entry in _leaves:
		if is_same(entry.value,value): return entry
	return {}

## 真递归不可变 raw 声明；不开放 Script/Resource/可变模板。
func prove_immutable(value:Variant) -> Dictionary:
	var queue:Array = [value]
	var seen:Array = []
	while not queue.is_empty():
		var item = queue.pop_back()
		if _scalar(item): continue
		if not (item is Array or item is Dictionary) or item.is_typed() or not item.is_read_only():
			return _result("UNSUPPORTED","not_recursively_immutable")
		var found:bool = false
		for visited in seen:
			if is_same(item,visited): found = true; break
		if found: continue
		seen.append(item)
		if seen.size() > _max_entries: return _result("UNSUPPORTED","immutable_budget")
		if item is Array: queue.append_array(item)
		else: queue.append_array(item.keys()); queue.append_array(item.values())
	var proof:RefCounted = RefCounted.new()
	_leaves.append({"value":value,"kind":"immutable_declaration","proof":proof,"plan":_plan})
	return _result("COMPLETED","",proof)

## 发行服务只做原句柄只读认证，绝不作为 provenance 叶子穿透。
func prove_provenance(value:Variant) -> Dictionary:
	if value is SessionContext:
		if not SessionGeneration.validate_context(value).ok: return _result("REJECTED","unissued_provenance")
	elif value is SessionToken:
		if not _context is SessionContext or not is_same(_context.token(),value) or not SessionGeneration.validate_context(_context).ok:
			return _result("REJECTED","unissued_token")
	else: return _result("UNSUPPORTED","not_provenance_leaf")
	var proof:RefCounted = RefCounted.new()
	_leaves.append({"value":value,"kind":"provenance_leaf","proof":proof,"plan":_plan})
	return _result("COMPLETED","",proof)

func validate_leaf(value:Variant, proof:Variant) -> Dictionary:
	var entry:Dictionary = _leaf(value)
	if entry.is_empty() or not is_same(entry.proof,proof) or not is_same(entry.plan,_plan):
		return _result("REJECTED","unregistered_leaf_proof")
	if entry.kind == "provenance_leaf":
		var source = value if value is SessionContext else _context
		if not source is SessionContext or not SessionGeneration.validate_context(source).ok: return _result("REJECTED","stale_leaf")
	return _result("COMPLETED","",value)

## BFS inventory: 所有壳先 reserve，pending 全齐后才填任何边。纯 raw 闭包之外拒绝。
func fork_raw(value:Variant) -> Dictionary:
	if not _reason.is_empty(): return _result("UNSUPPORTED",_reason)
	var result:Dictionary = _fork_raw(value)
	if result.status != "COMPLETED":
		_reason = result.reason
	return result

func _fork_raw(value:Variant) -> Dictionary:
	if _domain == null or _closed or _invalid: return _result("REJECTED","graph_unavailable")
	var queue:Array = [value]
	while not queue.is_empty():
		var item = queue.pop_front()
		if _scalar(item) or not _leaf(item).is_empty(): continue
		if item is Callable:
			var callable_mapping:Dictionary = _map(item)
			if callable_mapping.status != "COMPLETED": return callable_mapping
			continue
		if _index(item) >= 0: continue
		if not _reason.is_empty(): return _result("UNSUPPORTED",_reason)
		if item is Random.Scope:
			if item.get_script() != Random.Scope: return _result("UNSUPPORTED","unknown_rng_subclass")
			var forked:Dictionary = fork_stream(item.graph_stream_descriptor())
			if forked.status != "COMPLETED": return forked
			continue
		if not (item is Array or item is Dictionary) or item.is_typed() or item.is_read_only():
			return _result("UNSUPPORTED","unproven_object_or_native_edge")
		var shell:Variant = [] if item is Array else {}
		var reserved:Dictionary = reserve(item,shell)
		if reserved.status != "COMPLETED": return reserved
		var edges:Variant = item.duplicate(false)
		_pending.append({"live":item,"private":shell,"edges":edges})
		if item is Array: queue.append_array(item)
		else:
			for key in item:
				# Mutable collection keys have unstable hash semantics, never silently drop/collide.
				if key is Array or key is Dictionary: return _result("UNSUPPORTED","mutable_collection_key")
				queue.append(key)
				queue.append(item[key])
	for pending in _pending:
		if pending.private is Array:
			for edge in pending.edges:
				var mapped:Dictionary = _map(edge)
				if mapped.status != "COMPLETED": return mapped
				pending.private.append(mapped.value)
		else:
			for key in pending.edges:
				var mapped_key:Dictionary = _map(key)
				var mapped_value:Dictionary = _map(pending.edges[key])
				if mapped_key.status != "COMPLETED": return mapped_key
				if mapped_value.status != "COMPLETED": return mapped_value
				if pending.private.has(mapped_key.value): return _result("UNSUPPORTED","mapped_key_collision")
				pending.private[mapped_key.value] = mapped_value.value
	_pending.clear()
	return _map(value)

func _map(value:Variant, backwards:bool = false) -> Dictionary:
	if _scalar(value): return _result("COMPLETED","",value)
	if value is Callable:
		for entry in _callables:
			if (entry.private if backwards else entry.value) == value:
				return _result("COMPLETED","",entry.value if backwards else entry.private)
		return _result("UNSUPPORTED","unproved_callable")
	var leaf:Dictionary = _leaf(value)
	if not leaf.is_empty(): return validate_leaf(value,leaf.proof)
	var index:int = _index(value,backwards)
	if index >= 0: return _result("COMPLETED","",_entries[index].live if backwards else _entries[index].private)
	if not backwards and _index(value,true) >= 0: return _result("COMPLETED","",value)
	return _result("UNSUPPORTED",_reason if not _reason.is_empty() else "unbound_graph_reference")

## R05 单一解析器：先认证，再 tagged leaf，再 mutable M，缺证不借 L。
func resolve(value:Variant) -> Dictionary:
	var checked:Dictionary = authenticate(true)
	if checked.status != "COMPLETED": return checked
	return _map(value)

## 返回原 identity，不 deep duplicate；新 D 没获准 L 对应即拒绝。
func reverse(value:Variant) -> Dictionary:
	if _closed: return _result("REJECTED","graph_closed")
	return _map(value,true)

func protect_edge(owner:Variant, key:Variant) -> Dictionary:
	if _index(owner,true) < 0 or not _slot(owner,key): return _result("UNSUPPORTED","unproven_protected_slot")
	for edge in _protected:
		if is_same(edge.owner,owner) and is_same(edge.key,key): return _result("REJECTED","duplicate_protected_edge")
	_protected.append({"owner":owner,"key":key,"identity":owner[key]})
	return _result("COMPLETED")

static func _slot(owner:Variant,key:Variant) -> bool:
	if owner is Dictionary: return not owner.is_read_only() and not owner.is_typed() and owner.has(key)
	if owner is Array: return not owner.is_read_only() and not owner.is_typed() and key is int and key >= 0 and key < owner.size()
	return false

## 获证写点同步调用；记录每次写。换回也不清失效；无此调用的原脚本不能获证。
func write_edge(owner:Variant,key:Variant,value:Variant) -> Dictionary:
	if _closed or not _slot(owner,key) or _index(owner,true) < 0: return _result("REJECTED","unowned_edge_write")
	for edge in _protected:
		if is_same(edge.owner,owner) and is_same(edge.key,key):
			_ledger.append({"sequence":_ledger.size()+1,"plan":_plan,"owner":owner,"key":key,"old":owner[key],"new":value})
			if not is_same(value,edge.identity):
				_invalid = true
				_reason = "protected_identity_changed"
	owner[key] = value
	return _result("REJECTED",_reason) if _invalid else _result("COMPLETED")

func ledger() -> Array:
	var records:Array = []
	for entry in _ledger:
		var copy:Dictionary = entry.duplicate(false)
		copy.make_read_only()
		records.append(copy)
	records.make_read_only()
	return records

func validate_graph() -> Dictionary:
	if _closed or _invalid: return _result("REJECTED",_reason if _invalid else "graph_closed")
	if not _reason.is_empty(): return _result("UNSUPPORTED",_reason)
	for edge in _protected:
		if not _slot(edge.owner,edge.key) or not is_same(edge.owner[edge.key],edge.identity):
			_invalid = true
			_reason = "unobserved_protected_write"
			return _result("REJECTED",_reason)
	for stream in _random:
		var current:Dictionary = _stream_descriptor(stream.descriptor.identity)
		if current.is_empty() or not is_same(stream.backing,current.backing) or not is_same(stream.descriptor.native_cache,current.native_cache) or stream.backing.version != stream.version or current.exhausted:
			return _result("REJECTED","live_stream_version_changed")
	return _result("COMPLETED")

func _stream_descriptor(identity:Variant) -> Dictionary:
	if identity is Random.Scope and identity.get_script() == Random.Scope: return identity.graph_stream_descriptor()
	var descriptor:Dictionary = Random.graph_stream_descriptor()
	return descriptor if is_same(descriptor.identity,identity) else {}

## 同一个原流只 fork 一次，static/Scope 的 identity 不按 seed/state 合并。
func fork_stream(descriptor:Dictionary) -> Dictionary:
	for key in ["identity","backing","native_cache","version","exhausted"]:
		if not descriptor.has(key): return _result("UNSUPPORTED","incomplete_stream_descriptor")
	var current:Dictionary = _stream_descriptor(descriptor.identity)
	if current.is_empty() or not is_same(current.backing,descriptor.backing) or not is_same(current.native_cache,descriptor.native_cache) or current.version != descriptor.version:
		return _result("REJECTED","forged_or_stale_stream_descriptor")
	var existing:int = _index(descriptor.identity)
	if existing >= 0: return _result("COMPLETED","",_entries[existing].private)
	var backing:Dictionary = descriptor.backing
	if descriptor.exhausted or not backing.known or backing.mode != "known_stream": return _result("UNSUPPORTED","unknown_rng")
	var scope = Random.Scope.new(backing.seed.to_int(),backing.state.to_int(),true,"known_stream")
	var reserved:Dictionary = reserve(descriptor.identity,scope)
	if reserved.status != "COMPLETED": return reserved
	# backing 同 M，不复制成第二张图。新私有版本是计划内计数，不回灌 L。
	var state:Dictionary = scope.graph_stream_descriptor().backing
	var raw_reserved:Dictionary = reserve(backing,state)
	if raw_reserved.status != "COMPLETED": return raw_reserved
	_random.append({"descriptor":descriptor.duplicate(false),"backing":backing,"private":scope,"version":backing.version})
	return _result("COMPLETED","",scope)

func random_service_view():
	if authenticate(true).status != "COMPLETED": return null
	var descriptor:Dictionary = Random.graph_stream_descriptor()
	var mapped:Dictionary = _map(descriptor.identity)
	return mapped.value if mapped.status == "COMPLETED" and mapped.value is Random.Scope else null

func random_publication_writes() -> Dictionary:
	var checked:Dictionary = validate_graph()
	if checked.status != "COMPLETED": return checked
	var writes:Array = []
	for stream in _random:
		if stream.version == Random.MAX_VERSION: return _result("REJECTED","rng_version_exhausted")
		var private_backing:Dictionary = stream.private.graph_stream_descriptor().backing
		for key in ["known","mode","seed","state"]:
			writes.append({"target":stream.backing,"key":key,"value":private_backing[key],"kind":&"runtime"})
		writes.append({"target":stream.backing,"key":"version","value":stream.version+1,"kind":&"runtime"})
	# 描述本身不授发布/执行资格；聚合 owner 必须另验 E2/C 及完整闭包。
	return _result("COMPLETED","",writes)

## seal 前预建 raw 描述。调用方仍只能交 domain.seal/install_sealed，不存在 RNG commit。
func stage_random() -> Dictionary:
	var checked:Dictionary = authenticate(false)
	if checked.status != "COMPLETED": return checked
	var description:Dictionary = random_publication_writes()
	if description.status != "COMPLETED": return description
	for write in description.value:
		var staged:Dictionary = _domain.stage_slot(write.target,write.key,write.value,write.kind)
		if staged.status != "COMPLETED": return staged
	return _result("COMPLETED")

## 构造形状 != 执行证明。C 尚无可用准入时不重建、也不试调用。
func prove_callable(value:Callable, admission:Variant, spec:Dictionary) -> Dictionary:
	var checked:Dictionary = authenticate(false)
	if checked.status != "COMPLETED": return checked
	if not value.is_valid() or value.get_unbound_arguments_count() != 0: return _result("UNSUPPORTED","opaque_callable")
	var receiver:Dictionary = _map(value.get_object())
	if receiver.status != "COMPLETED": return receiver
	if not is_same(spec.get("receiver"),receiver.value) or spec.get("property_or_method",{}).get("name") != value.get_method():
		return _result("REJECTED","wrong_callable_spec")
	var proof:Dictionary = _registry.validate_admission(admission,_binding,spec)
	if proof.status != "COMPLETED": return proof
	var arguments:Array = []
	for argument in value.get_bound_arguments():
		var mapped:Dictionary = _map(argument)
		if mapped.status != "COMPLETED": return mapped
		arguments.append(mapped.value)
	var reconstructed:Callable = Callable(value.get_object(),value.get_method()).bindv(value.get_bound_arguments())
	if reconstructed != value: return _result("UNSUPPORTED","opaque_callable_shape")
	var private_callable:Callable = Callable(receiver.value,value.get_method()).bindv(arguments)
	var handle:RefCounted = RefCounted.new()
	_callables.append({"value":value,"private":private_callable,"admission":admission,"spec":spec.duplicate(false),"proof":handle})
	return _result("COMPLETED","",handle)

func prove_weak(value:WeakRef, admission:Variant, spec:Dictionary) -> Dictionary:
	var checked:Dictionary = authenticate(false)
	if checked.status != "COMPLETED": return checked
	if value.get_script() != null or not is_same(spec.get("receiver"),value): return _result("UNSUPPORTED","unproved_weak_owner")
	var proof:Dictionary = _registry.validate_admission(admission,_binding,spec)
	if proof.status != "COMPLETED": return proof
	# 弱句柄和 target 分别保 identity；未知 target 不能以 null 代替。
	var target:Dictionary = _map(value.get_ref())
	if target.status != "COMPLETED": return target
	var private_value:WeakRef = WeakRef.new() if target.value == null else weakref(target.value)
	return reserve(value,private_value)

func certificate() -> RefCounted:
	return _certificate

## 只读结构验证，不反调 C、不用 FRAME、不授执行。ASSOCIATION 由 Core 独立复验。
func validate_certificate(proof:Variant, expected:Dictionary = {}) -> Dictionary:
	if not is_same(proof,_certificate): return _result("REJECTED","unregistered_graph_certificate")
	if _domain == null: return _result("REJECTED","graph_not_configured")
	for key in expected:
		var actual:Variant
		match key:
			"plan": actual = _plan
			"domain": actual = _domain
			"context": actual = _context
			"association": actual = _association
			_: return _result("REJECTED","unknown_graph_identity_field")
		if not is_same(actual,expected[key]): return _result("REJECTED","graph_certificate_identity_mismatch")
	if _association == null: return _result("UNSUPPORTED","missing_graph_association")
	var association:Dictionary = Plan.validate_execution_binding(_association,_context)
	if association.status != "COMPLETED": return association
	if not is_same(association.plan_identity,_plan) or not is_same(association.domain_identity,_domain.identity()): return _result("REJECTED","wrong_graph_association")
	var checked:Dictionary = validate_graph()
	if checked.status != "COMPLETED": return checked
	if _structure_locked:
		if _entries.size() != _structure.size(): return _result("REJECTED","graph_inventory_changed")
		for entry in _structure:
			if entry.baseline == null: continue
			var live = entry.live
			var baseline = entry.baseline
			if live.size() != baseline.size(): return _result("REJECTED","live_raw_topology_changed")
			for key in (range(baseline.size()) if baseline is Array else baseline.keys()):
				if live is Dictionary and not live.has(key): return _result("REJECTED","live_raw_topology_changed")
				if not is_same(live[key],baseline[key]): return _result("REJECTED","live_raw_topology_changed")
	return _result("COMPLETED","",_structure_identity if _structure_locked else null)

func associate(binding:Variant) -> Dictionary:
	if _association != null: return _result("REJECTED","graph_association_already_set")
	var checked:Dictionary = Plan.validate_execution_binding(binding,_context)
	if checked.status != "COMPLETED": return checked
	if checked.binding_kind != "ASSOCIATION" or checked.phase != "OPEN" or not is_same(checked.plan_identity,_plan) or not is_same(checked.domain_identity,_domain.identity()): return _result("REJECTED","wrong_graph_association")
	_association = binding
	return _result("COMPLETED")

## 工厂完成后冻结 L 结构基线；D 标量可变，L 任一 raw 边漂移都不续签。
func lock_structure() -> Dictionary:
	var checked:Dictionary = authenticate(false)
	if checked.status != "COMPLETED": return checked
	if _call_spec.get("admission_kind") != "FACTORY" or _structure_locked: return _result("REJECTED","structure_lock_phase_closed")
	for entry in _entries:
		var baseline:Variant = entry.live.duplicate(false) if entry.live is Array or entry.live is Dictionary else null
		if baseline != null: baseline.make_read_only()
		_structure.append({"live":entry.live,"private":entry.private,"baseline":baseline})
	_structure_locked = true
	return _result("COMPLETED","",_structure_identity)

## C 审查所用只读映射，不是执行解析；不调用任何 receiver 方法。
func structural_mapping(value:Variant, proof:Variant, expected:Dictionary) -> Dictionary:
	var checked:Dictionary = validate_certificate(proof,expected)
	if checked.status != "COMPLETED": return checked
	if not _structure_locked: return _result("UNSUPPORTED","graph_structure_not_locked")
	return _map(value)

func structural_inventory(proof:Variant, expected:Dictionary) -> Dictionary:
	var checked:Dictionary = validate_certificate(proof,expected)
	if checked.status != "COMPLETED": return checked
	if not _structure_locked: return _result("UNSUPPORTED","graph_structure_not_locked")
	var entries:Array = []
	for entry in _entries:
		var view:Dictionary = entry.duplicate(false)
		view.make_read_only()
		entries.append(view)
	entries.make_read_only()
	return _result("COMPLETED","",entries)

func close() -> Dictionary:
	_closed = true
	# 原 L 环由原 owner 管；这里只断私有 raw 强边，且不处于发布窗口。
	if Domain.publication_is_open(): return _result("REJECTED","cleanup_inside_install_window")
	for entry in _entries:
		if entry.private is Array or entry.private is Dictionary:
			if not entry.private.is_read_only(): entry.private.clear()
	_entries.clear()
	_pending.clear()
	_leaves.clear()
	_random.clear()
	_protected.clear()
	_callables.clear()
	_weak_proofs.clear()
	_structure.clear()
	_call_spec.clear()
	_registry = null
	_admission = null
	_domain = null
	return _result("COMPLETED")
