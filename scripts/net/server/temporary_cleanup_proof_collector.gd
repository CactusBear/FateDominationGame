extends RefCounted

## 只读采证：不登记、不持锁、不释放、不选择、不删除；能力只能由可信本机组合根注入。
## 方法存在不是完整性证明。部署 registration boundary 必须真正约束所有 scope writers。
## 此接口不能认证恶意 provider；没有已审计边界时，组合根不得提供此能力。
const CONTRACT_VERSION:int = 1
const PROOF_VERSION:int = 2

static func collect(capability:Object, lease:Object, scope:Dictionary) -> Dictionary:
	if not is_instance_valid(capability): return _error("missing_registration_capability")
	for method in ["cleanup_registration_contract","cleanup_enumerate","cleanup_verify_enumeration","cleanup_verify_member"]:
		if not capability.has_method(method): return _error("missing_registration_capability:"+method)
	if not is_instance_valid(lease) or not lease.has_method("cleanup_lease_observe"): return _error("missing_deployment_lease")
	if not _scope_valid(scope): return _error("missing_or_invalid_proof_scope")
	var held:Dictionary = _read(lease,"cleanup_lease_observe",[scope.duplicate(true)])
	if not _lease_valid(held,scope): return _error("lease_not_held_or_invalid")
	var contract:Dictionary = _read(capability,"cleanup_registration_contract",[])
	if not _contract_valid(contract,scope): return _error("registration_contract_unavailable")
	var enumeration:Dictionary = _read(capability,"cleanup_enumerate",[lease])
	if not _version(enumeration,"enumeration_version") or not enumeration.get("registry_generation") is int or enumeration.registry_generation < 0 or not enumeration.get("entries") is Array: return _error("invalid_enumeration")
	var ids:Array = []
	for binding in enumeration.entries:
		if not binding is Dictionary or not _binding_valid(binding): return _error("invalid_instance_binding")
		if binding.instance_id in ids: return _error("duplicate_instance_binding")
		ids.append(binding.instance_id)
	var verified:Dictionary = _read(capability,"cleanup_verify_enumeration",[enumeration.duplicate(true),held.duplicate(true)])
	if not _version(verified,"verification_version") or not verified.get("enumeration") is Dictionary or not verified.get("lease") is Dictionary: return _error("enumeration_not_boundary_verified")
	if verified.enumeration != enumeration or verified.lease != held: return _error("enumeration_not_boundary_verified")
	if not verified.get("unregistered_writers") is Array or not verified.unregistered_writers.is_empty(): return _error("unknown_scope_writers")
	if not verified.get("pending_registrations") is int or verified.pending_registrations != 0: return _error("pending_registration")
	if not verified.get("registered_binding_ids") is Array: return _error("registry_membership_unverified")
	var registered:Array = verified.registered_binding_ids.duplicate()
	var seen:Array = []
	for id in registered:
		if not id is String or id.is_empty() or id in seen: return _error("registry_membership_unverified")
		seen.append(id)
	ids.sort()
	registered.sort()
	if ids != registered: return _error("incomplete_instance_enumeration")
	var current:Array = []
	var members:Array = []
	for binding in enumeration.entries:
		var member:Dictionary = _read(capability,"cleanup_verify_member",[binding.duplicate(true),held.duplicate(true)])
		if not member.get("binding") is Dictionary or not member.get("lease_id") is String: return _error("member_binding_or_generation_changed")
		if member.binding != binding or not member.get("registry_generation") is int or member.registry_generation != enumeration.registry_generation or member.lease_id != held.lease_id or not member.get("lease_epoch") is int or member.lease_epoch != held.epoch: return _error("member_binding_or_generation_changed")
		for field in ["identity_status","process_state","handle_state","job_state"]:
			if not member.get(field) is String: return _error("invalid_member_observation")
		if member.identity_status != "verified" or member.process_state not in ["RUNNING","EXITED"]: return _error("unknown_process_identity_or_state")
		if member.process_state == "RUNNING":
			if member.handle_state != "HELD" or member.job_state != "ACTIVE": return _error("inconsistent_running_handles")
			current.append(binding.instance_id)
		else:
			if member.handle_state != "RELEASED" or member.job_state != "EMPTY_RELEASED": return _error("exited_handles_not_released")
		members.append(member)
	# 结束时读回完整枚举/合同/租约，而非曾遍历过数组就 complete=true。
	if _read(capability,"cleanup_enumerate",[lease]) != enumeration: return _error("registry_changed_during_collection")
	if _read(capability,"cleanup_registration_contract",[]) != contract: return _error("registration_contract_changed")
	if _read(lease,"cleanup_lease_observe",[scope.duplicate(true)]) != held: return _error("lease_lost_or_changed")
	current.sort()
	return {"ok":true,"proof_version":PROOF_VERSION,"diagnostic_only":true,"removed_files":0,"scope":scope.duplicate(true),"capability_object_id":capability.get_instance_id(),"lease_object_id":lease.get_instance_id(),"contract":contract,"lease":held,"enumeration":enumeration,"boundary_verification":verified,"members":members,"current_instances":current}

## 每个调用步骤后重新采证，前一次 proof 不构成持续授权；整个输出必须精确相同。
static func revalidate(proof:Dictionary, capability:Object, lease:Object, scope:Dictionary) -> Dictionary:
	if not proof.get("proof_version") is int or proof.proof_version != PROOF_VERSION or not proof.get("ok") is bool or not proof.ok: return _error("invalid_collected_proof")
	var current:Dictionary = collect(capability,lease,scope)
	if not current.ok: return current
	if current != proof: return _error("lifecycle_proof_changed_between_steps")
	return current

static func _read(source:Object, method:String, args:Array) -> Dictionary:
	if not is_instance_valid(source) or not source.has_method(method): return {}
	var value:Variant = source.callv(method,args)
	return value.duplicate(true) if value is Dictionary else {}

static func _scope_valid(scope:Dictionary) -> bool:
	if not scope.get("deployment_id") is String or scope.deployment_id.is_empty(): return false
	for field in ["approved_roots","protected_paths"]:
		if not scope.get(field) is Array: return false
		for path in scope[field]:
			if not path is String or path.is_empty(): return false
	return not scope.approved_roots.is_empty()

static func _version(value:Dictionary, field:String) -> bool:
	return value.get(field) is int and value[field] == CONTRACT_VERSION

static func _lease_valid(held:Dictionary, scope:Dictionary) -> bool:
	return _version(held,"lease_version") and held.get("scope") is Dictionary and held.scope == scope and held.get("held") is bool and held.held and held.get("mode") is String and held.mode == "exclusive" and held.get("lease_id") is String and not held.lease_id.is_empty() and held.get("epoch") is int and held.epoch >= 0

static func _contract_valid(contract:Dictionary, scope:Dictionary) -> bool:
	if not _version(contract,"contract_version") or not contract.get("scope") is Dictionary or contract.scope != scope: return false
	var required:Dictionary = {"registration_boundary":"before_start_until_all_handles_released","enumeration_source":"authoritative_ownership_boundary","writer_exclusion":"all_scope_writers_require_same_lease"}
	for field in required:
		if not contract.get(field) is String or contract[field] != required[field]: return false
	return true

static func _binding_valid(binding:Dictionary) -> bool:
	if binding.size() != 4: return false
	for field in ["room","instance_id","authority_host_mode"]:
		if not binding.get(field) is String or binding[field].is_empty(): return false
	return binding.get("pid") is int and binding.pid > 0

static func _error(reason:String) -> Dictionary:
	return {"ok":false,"error":reason,"proof_version":PROOF_VERSION,"diagnostic_only":true,"removed_files":0}
