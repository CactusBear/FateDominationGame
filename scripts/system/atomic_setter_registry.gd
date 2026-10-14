extends RefCounted
## 单一能力登记表；构造参数是宿主受信审查边界，不是给任意脚本的自助许可。
## 本版只审查已有 G raw/RNG E3 闭包，不开放解释器、访问器、Callable 或模型发布。
const Plan = preload("res://scripts/system/atomic_action_plan.gd")
const Domain = preload("res://scripts/system/atomic_execution_domain.gd")
const Graph = preload("res://scripts/match/graph_session.gd")
const Random = preload("res://scripts/match/rule_random.gd")
const ABI_VERSION:int = 1
const MECHANISM:StringName = &"G_raw_RNG_E3_int_v1"
const REQUIRED:Array = ["target_script","source_sha256","inheritance_chain","native_base","property_or_method","receiver","adapter","adapter_script","abi_version","prepare_kind","participants","participant_manifest","readable_roots","writable_roots","publish_adapter","mechanism","reviewed_versions","native_version"]
var _owners:Array = []
var _registrations:Dictionary = {}
var _admissions:Dictionary = {}
var _busy:bool = false
var _reentered:bool = false
var _epoch:RefCounted = RefCounted.new()

## bootstrap 必须先审核精确内存 Script 对应的源文本及全部运行依赖。
## 不从路径或当前文件 SHA 自动推断安全。无受审记录的实例没有可登记机制。
func _init(reviewed_owners:Array = []) -> void:
	for item in reviewed_owners:
		if item is Dictionary and item.get("owner") is RefCounted and item.get("spec") is Dictionary:
			_owners.append({"owner":item.owner,"spec":_snapshot(item.spec)})

static func _result(status:String, reason:String = "", admission:Variant = null) -> Dictionary:
	return {"status":status,"reason":reason,"admission":admission,"execution_binding":null,"admission_kind":null,
		"plan_identity":null,"original_context":null,"continuation":null,"receipt":null,"binding":null,"binding_kind":null,
		"domain_identity":null,"participant_manifest":null,"phase":null,"frame_marker":null,"abi_version":ABI_VERSION}

# metadata 的 identity 值不复制；审核文本/数组壳冻结，不深拷贝游戏根。
static func _snapshot(value:Variant, identity_value:bool = false) -> Variant:
	if identity_value or not (value is Array or value is Dictionary): return value
	var copy:Variant = [] if value is Array else {}
	if value is Array:
		for item in value: copy.append(_snapshot(item))
	else:
		for key in value: copy[key] = _snapshot(value[key],key in ["identity","receiver","adapter","owner","arguments"])
	copy.make_read_only()
	return copy

static func _same(a:Variant, b:Variant, identity_value:bool = false) -> bool:
	if identity_value or typeof(a) != typeof(b) or not (a is Array or a is Dictionary): return is_same(a,b)
	if a.size() != b.size(): return false
	for key in (range(a.size()) if a is Array else a.keys()):
		if b is Dictionary and not b.has(key): return false
		if not _same(a[key],b[key],key in ["identity","receiver","adapter","owner","arguments"]): return false
	return true

func register_owner(owner:Variant, spec:Dictionary) -> Dictionary:
	if not Thread.is_main_thread() or Domain.current_frame().status == "COMPLETED" or Domain.publication_is_open(): return _result("REJECTED","owner_registration_closed")
	for approved in _owners:
		if is_same(approved.owner,owner) and _same(approved.spec,spec):
			var checked:Dictionary = _review(spec)
			if checked.status != "COMPLETED": return checked
			var registration:RefCounted = RefCounted.new()
			_registrations[registration] = {"owner":owner,"spec":_snapshot(spec),"epoch":_epoch}
			return {"status":"COMPLETED","reason":"","owner_registration":registration}
	return _result("UNSUPPORTED","owner_not_reviewed")

func close() -> Dictionary:
	if Domain.publication_is_open() or Domain.current_frame().status == "COMPLETED": return _result("REJECTED","registry_cleanup_inside_execution")
	_epoch = RefCounted.new()
	_admissions.clear()
	_registrations.clear()
	_owners.clear()
	return _result("COMPLETED")

func revoke_owner(registration:Variant) -> Dictionary:
	if not (registration is RefCounted) or not _registrations.has(registration): return _result("REJECTED","unregistered_owner")
	_registrations.erase(registration)
	return _result("COMPLETED")

func _review(spec:Dictionary) -> Dictionary:
	for field in REQUIRED:
		if not spec.has(field): return _result("UNSUPPORTED","incomplete_adapter_spec")
	if not (spec.abi_version is int) or spec.abi_version != ABI_VERSION or spec.mechanism != MECHANISM or spec.prepare_kind != "domain_service": return _result("UNSUPPORTED","unknown_adapter_mechanism")
	if not is_same(spec.target_script,Random) or not is_same(spec.receiver,Random) or not (spec.adapter is RefCounted) or not is_same(spec.adapter.get_script(),spec.adapter_script): return _result("REJECTED","wrong_receiver_or_script")
	if not _same(spec.property_or_method,{"kind":"method","name":&"int_in_range","parameters":[TYPE_INT,TYPE_INT],"return":TYPE_INT}): return _result("UNSUPPORTED","undeclared_accessor")
	var chain:Array = []
	var current:Script = Random
	while current != null:
		chain.append(current)
		current = current.get_base_script()
	if not _same(spec.inheritance_chain,chain) or spec.native_base != (spec.target_script as Script).get_instance_base_type(): return _result("REJECTED","inheritance_changed")
	if not spec.reviewed_versions is Array or spec.reviewed_versions.is_empty(): return _result("UNSUPPORTED","missing_runtime_source_mapping")
	var reviewed:Array = []
	for version in spec.reviewed_versions:
		if not (version is Dictionary) or not (version.get("script") is Script) or not (version.get("reviewed_source") is String) or not (version.get("source_sha256") is String): return _result("UNSUPPORTED","missing_runtime_source_mapping")
		var script:Script = version.script
		if not script.has_source_code() or script.get_source_code() != version.reviewed_source or version.reviewed_source.sha256_text() != version.source_sha256: return _result("REJECTED","runtime_source_mapping_changed")
		reviewed.append(script)
	for dependency in [get_script(),Random,Graph,Plan,Domain,spec.adapter_script,preload("res://scripts/system/session_generation.gd"),preload("res://scripts/system/session_context.gd"),preload("res://scripts/system/session_token.gd")]:
		if not dependency in reviewed: return _result("UNSUPPORTED","incomplete_reviewed_dependencies")
	if not spec.source_sha256 is String or spec.source_sha256 != (spec.target_script as Script).get_source_code().sha256_text() or not _same(spec.native_version,Engine.get_version_info()): return _result("REJECTED","source_or_native_version_changed")
	if not _same(spec.participants,[spec.adapter]) or not _same(spec.publish_adapter,{"abi_version":1,"mechanism":&"G_stage_random_Core_raw_slots","callback_free":true}): return _result("UNSUPPORTED","missing_callback_free_publisher")
	if not spec.readable_roots is Array or spec.readable_roots.size() != 2 or not spec.writable_roots is Array or spec.writable_roots.size() != 1: return _result("UNSUPPORTED","incomplete_root_closure")
	var descriptor:Dictionary = Random.graph_stream_descriptor()
	if not _same(spec.readable_roots[0],{"name":&"raw_arguments","identity":spec.readable_roots[0].get("identity"),"mutable":true,"version":1}) or not (spec.readable_roots[0].identity is Array or spec.readable_roots[0].identity is Dictionary): return _result("UNSUPPORTED","undeclared_raw_root")
	if not _same(spec.readable_roots[1],{"name":&"random_stream","identity":descriptor.identity,"mutable":true,"version":1}) or not _same(spec.writable_roots,[{"name":&"random_stream","identity":descriptor.identity,"domain":"D","version":1}]): return _result("REJECTED","wrong_random_roots")
	return _result("COMPLETED")

func _gate(binding:Variant, spec:Dictionary, certificate:Variant) -> Dictionary:
	var registration:Variant = spec.get("owner_registration")
	if not (registration is RefCounted) or not _registrations.has(registration): return _result("REJECTED","unregistered_owner")
	var registered:Dictionary = _registrations[registration]
	if not is_same(registered.epoch,_epoch): return _result("REJECTED","registration_epoch_revoked")
	for field in REQUIRED:
		if not spec.has(field) or not _same(registered.spec[field],spec[field],field in ["receiver","adapter"]): return _result("REJECTED","call_spec_changed")
	var review:Dictionary = _review(registered.spec)
	if review.status != "COMPLETED": return review
	if not (spec.get("graph") is RefCounted) or not is_same(spec.graph.get_script(),Graph) or not (spec.get("domain") is RefCounted) or not is_same(spec.domain.get_script(),Domain): return _result("REJECTED","wrong_graph_or_domain")
	if not spec.get("arguments") is Array or spec.arguments.size() != 3 or not (spec.arguments[0] is int) or not (spec.arguments[1] is int) or not is_same(spec.arguments[2],registered.spec.readable_roots[0].identity): return _result("REJECTED","argument_identity_mismatch")
	var stage:Variant = spec.get("admission_kind")
	if stage not in ["FACTORY","EXECUTE","SEAL_CHECK"]: return _result("UNSUPPORTED","unknown_admission_stage")
	if not (spec.get("kind") is String) or spec.kind != ("constructor" if stage == "FACTORY" else "method"): return _result("UNSUPPORTED","unknown_call_kind")
	if stage == "SEAL_CHECK":
		var prior:Variant = spec.get("prepared_admission")
		if not (prior is RefCounted) or not _admissions.has(prior): return _result("REJECTED","missing_executed_closure")
		var executed:Dictionary = _admissions[prior]
		if not executed.consumed or not executed.get("executed",false) or executed.spec.admission_kind != "EXECUTE": return _result("REJECTED","missing_executed_closure")
		for field in ["owner_registration","graph","domain","original_context","plan_identity","participant_manifest","association","arguments"]:
			if not is_same(executed.spec.get(field),spec.get(field)): return _result("REJECTED","seal_closure_identity_changed")
	var marker:Variant = null
	if stage == "EXECUTE":
		var frame:Dictionary = Domain.current_frame()
		if frame.status != "COMPLETED": return _result("REJECTED","no_core_execution_frame")
		marker = frame.marker
	var core:Dictionary = Plan.validate_execution_binding(binding,spec.get("original_context"),marker)
	if core.status != "COMPLETED": return core
	if not is_same(core.plan_identity,spec.get("plan_identity")) or not is_same(core.domain_identity,spec.domain.identity()) or not is_same(core.participant_manifest,spec.get("participant_manifest")): return _result("REJECTED","call_core_identity_mismatch")
	if (stage == "FACTORY" and (core.binding_kind != "ASSOCIATION" or core.phase != "OPEN")) or (stage == "EXECUTE" and (core.binding_kind != "FRAME" or core.phase not in ["PREPARE","RESUME"])) or (stage == "SEAL_CHECK" and (core.binding_kind != "ASSOCIATION" or core.phase != "SEAL")): return _result("REJECTED","admission_stage_closed")
	var association:Dictionary = Plan.validate_execution_binding(spec.get("association"),spec.get("original_context"))
	if association.status != "COMPLETED": return association
	if not is_same(association.plan_identity,core.plan_identity) or not is_same(association.domain_identity,core.domain_identity): return _result("REJECTED","cross_plan_association")
	var expected:Dictionary = {"plan":core.plan_identity,"domain":spec.domain,"context":core.original_context,"association":spec.association}
	var graph:Dictionary = spec.graph.validate_certificate(certificate,expected)
	if graph.status != "COMPLETED": return graph
	if stage != "FACTORY":
		if graph.value == null: return _result("UNSUPPORTED","unlocked_graph_closure")
		var inventory:Dictionary = spec.graph.structural_inventory(certificate,expected)
		if inventory.status != "COMPLETED": return inventory
		for entry in inventory.value:
			if entry.live is Array or entry.live is Dictionary:
				if not (entry.private is Array or entry.private is Dictionary) or entry.live.is_typed() or entry.private.is_typed(): return _result("UNSUPPORTED","unproved_inventory_entry")
			elif not is_same(entry.live,Random.graph_stream_descriptor().identity) or not (entry.private is Random.Scope) or entry.private.get_script() != Random.Scope:
				return _result("UNSUPPORTED","undeclared_object_or_stream")
		var raw:Dictionary = _raw_closure(registered.spec.readable_roots[0].identity,spec.graph,certificate,expected)
		if raw.status != "COMPLETED": return raw
		var mapped:Dictionary = spec.graph.structural_mapping(Random.graph_stream_descriptor().identity,certificate,expected)
		if mapped.status != "COMPLETED" or not mapped.value is Random.Scope or mapped.value.get_script() != Random.Scope: return _result("UNSUPPORTED","missing_private_random_scope")
	return {"status":"COMPLETED","reason":"","core":core,"expected":expected}

# 有界 raw 闭包，只收标量与无类型容器；不调用未知 getter/new/callback。
func _raw_closure(root:Variant, graph:RefCounted, certificate:Variant, expected:Dictionary) -> Dictionary:
	var queue:Array = [root]
	var seen:Array = []
	while not queue.is_empty():
		var value = queue.pop_back()
		if typeof(value) in [TYPE_NIL,TYPE_BOOL,TYPE_INT,TYPE_FLOAT,TYPE_STRING,TYPE_STRING_NAME]: continue
		if not (value is Array or value is Dictionary) or value.is_typed() or value.is_read_only(): return _result("UNSUPPORTED","unproved_raw_edge")
		var visited:bool = false
		for previous in seen:
			if is_same(previous,value): visited = true; break
		if visited: continue
		seen.append(value)
		if seen.size() > 1024: return _result("UNSUPPORTED","raw_closure_budget")
		var mapped:Dictionary = graph.structural_mapping(value,certificate,expected)
		if mapped.status != "COMPLETED" or is_same(mapped.value,value): return _result("REJECTED","raw_root_not_private")
		if value is Array: queue.append_array(value)
		else: queue.append_array(value.keys()); queue.append_array(value.values())
	return _result("COMPLETED")

func _admission_view(checked:Dictionary, admission:Variant = null, binding:Variant = null, spec:Dictionary = {}) -> Dictionary:
	var result:Dictionary = _result(checked.status,checked.get("reason",""),admission)
	if checked.status == "COMPLETED" and checked.get("core") is Dictionary:
		result.merge(checked.core,true)
		result.admission = admission
		result.execution_binding = binding
		result.admission_kind = spec.get("admission_kind")
	result.make_read_only()
	return result

func admit_call(execution_binding:Variant, call_spec:Dictionary, graph_certificate:Variant) -> Dictionary:
	if _busy:
		_reentered = true
		return _result("FAULT","recursive_capability_validation")
	_busy = true
	_reentered = false
	var checked:Dictionary = _gate(execution_binding,call_spec,graph_certificate)
	_busy = false
	if _reentered: return _result("FAULT","recursive_capability_validation")
	if checked.status != "COMPLETED": return _admission_view(checked)
	var admission:RefCounted = RefCounted.new()
	_admissions[admission] = {"binding":execution_binding,"spec":_snapshot(call_spec),"arguments":call_spec.arguments.duplicate(false),"argument_identity":call_spec.arguments,"certificate":graph_certificate,"consumed":false,"active":false}
	return _admission_view(checked,admission,execution_binding,call_spec)

func validate_admission(admission:Variant, execution_binding:Variant, call_spec:Dictionary) -> Dictionary:
	if _busy:
		_reentered = true
		return _result("FAULT","recursive_capability_validation")
	if not (admission is RefCounted) or not _admissions.has(admission): return _result("REJECTED","unregistered_admission")
	var record:Dictionary = _admissions[admission]
	if not is_same(record.binding,execution_binding) or not _same(record.spec,call_spec) or not is_same(record.argument_identity,call_spec.get("arguments")): return _result("REJECTED","admission_call_identity_mismatch")
	if record.arguments.size() != call_spec.arguments.size(): return _result("REJECTED","argument_identity_mismatch")
	for index in range(record.arguments.size()):
		if not is_same(record.arguments[index],call_spec.arguments[index]): return _result("REJECTED","argument_identity_mismatch")
	if record.consumed and not record.active: return _result("REJECTED","admission_already_consumed")
	_busy = true
	_reentered = false
	var checked:Dictionary = _gate(execution_binding,call_spec,record.certificate)
	_busy = false
	return _result("FAULT","recursive_capability_validation") if _reentered else _admission_view(checked,admission if checked.status == "COMPLETED" else null,execution_binding,call_spec)

func execution_scope_active(admission:Variant) -> bool:
	return admission is RefCounted and _admissions.has(admission) and _admissions[admission].active

## 唯一真实业务消费：验许可后在原 Core FRAME 同步执行原 static sampler。
## scope 只维持本次同步调用，不签子帧、不回调宿主、不增加 commit 点。
func execute_random(admission:Variant, binding:Variant, spec:Dictionary) -> Dictionary:
	var checked:Dictionary = validate_admission(admission,binding,spec)
	if checked.status != "COMPLETED": return checked
	if spec.admission_kind != "EXECUTE": return _result("REJECTED","execute_permit_required")
	var record:Dictionary = _admissions[admission]
	if record.active or record.consumed: return _result("REJECTED","admission_already_consumed")
	record.active = true
	var attached:Dictionary = spec.graph.attach_execution(binding,self,admission,spec)
	var mapped:Dictionary = spec.graph.resolve(spec.arguments[2]) if attached.status == "COMPLETED" else attached
	var value:Variant = Random.int_in_range(spec.arguments[0],spec.arguments[1]) if mapped.status == "COMPLETED" else null
	record.active = false
	record.consumed = true
	if mapped.status != "COMPLETED": return mapped
	if not (value is int): return _result("REJECTED","private_random_execution_failed")
	record["executed"] = true
	return {"status":"COMPLETED","reason":"","value":value,"mapped_argument":mapped.value}
