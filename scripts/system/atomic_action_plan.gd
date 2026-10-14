extends RefCounted
## A4 ABI v1. 不透明句柄属于进程 registry；没有卡牌业务/来源补票/自动 adapter。
## 受信 owner 注册是能力边界，不是任意 GDScript 沙箱或声明即证明的捷径。
const Domain = preload("res://scripts/system/atomic_execution_domain.gd")
const ABI_VERSION:int = 1
enum State { NEW, PREPARING, PENDING, PREPARED, COMMITTED, ABORTED, FAULT }
static var _plans:Dictionary = {}
static var _manifests:Dictionary = {}
# E2 控制元数据不属于规则图/历史；不回滚、不复用、不作为动作 receipt。
static var _domains:Dictionary = {}
static var _execution_bindings:Dictionary = {}
static var _authorized_markers:Dictionary = {}
static var _source_validation_busy:bool = false
static var _source_validation_reentered:bool = false

## 唯一注册入口，后继 Capability owner 交完整 support_manifest 与聚合 participant。
## 本批没有任何生产注册。注册对象须由受信引导审查；字符串 proof 不是安全沙箱。
static func register_participant_manifest(participant_manifest:Dictionary) -> Dictionary:
	if not Thread.is_main_thread() or Domain.publication_is_open():
		return _result("UNSUPPORTED", null, null, "registration_closed")
	var adapter:Variant = participant_manifest.get("adapter")
	var support:Variant = participant_manifest.get("support_manifest")
	if not (adapter is RefCounted) or not (support is Dictionary):
		return _result("UNSUPPORTED", null, null, "missing_owner_adapter")
	if not (support.get("abi_version") is int) or support.abi_version != ABI_VERSION or not (support.get("status") is String) or support.status != "supported" or not (support.get("proof") is String) or support.proof != "owner_registered_closed_domain":
		return _result("UNSUPPORTED", null, null, "unproven_participant_manifest")
	for field in ["required_roots", "required_adapters", "state_domains", "participants"]:
		if not (support.get(field) is Array) or support[field].is_empty():
			return _result("UNSUPPORTED", null, null, "incomplete_support_manifest")
	for method in [&"validate_original_context", &"open_domain", &"prepare", &"resume", &"seal"]:
		if not adapter.has_method(method):
			return _result("UNSUPPORTED", null, null, "missing_participant_method")
	var identity:RefCounted = RefCounted.new()
	_manifests[identity] = {"adapter":adapter, "support_manifest":support.duplicate(true)}
	var result:Dictionary = _result("COMPLETED", null, null)
	result["participant_manifest"] = identity
	return result

# 设计 §4.1: begin(original_context, declared_action_closure, participant_manifest) -> plan / unsupported
static func begin(original_context:Variant, declared_action_closure:Variant, participant_manifest:Variant) -> Dictionary:
	if not Thread.is_main_thread() or Domain.publication_is_open() or Domain.current_frame().status == "COMPLETED":
		return _result("UNSUPPORTED", null, original_context, "independent_begin_not_allowed_in_frame_or_window")
	if not _registered(_manifests, participant_manifest):
		return _result("UNSUPPORTED", null, original_context, "unregistered_participant_manifest")
	var handle:RefCounted = RefCounted.new()
	_plans[handle] = {"state":State.NEW, "context":original_context, "closure":declared_action_closure,
		"participant":_manifests[participant_manifest], "domain":Domain.new(), "continuation":null,
		"receipt":null, "reason":"", "busy":false, "participant_manifest":participant_manifest,
		"phase":null, "invocation":null, "marker":null}
	_domains[_plans[handle].domain.identity()] = handle
	return _view(handle, "COMPLETED")

# prepare(plan) -> COMPLETED(prepared plan) | PENDING(owned continuation) | REJECTED(reason)
static func prepare(plan:Variant) -> Dictionary:
	if not _registered(_plans, plan):
		return _result("REJECTED", null, null, "invalid_plan_identity")
	var record:Dictionary = _plans[plan]
	if _terminal(record.state):
		return _terminal_view(plan)
	if record.state != State.NEW:
		return _reject(plan, "prepare_not_new")
	return _execute(plan, false, null)

# resume(plan, authenticated_input, original_context) -> 同三态；输入鉴权由 participant 原算法负责。
static func resume(plan:Variant, authenticated_input:Variant, original_context:Variant) -> Dictionary:
	if not _registered(_plans, plan):
		return _result("REJECTED", null, original_context, "invalid_plan_identity")
	var record:Dictionary = _plans[plan]
	if _terminal(record.state):
		return _terminal_view(plan)
	if not is_same(record.context, original_context):
		return _reject(plan, "original_context_identity_mismatch")
	if record.state != State.PENDING:
		return _reject(plan, "resume_not_pending")
	return _execute(plan, true, authenticated_input)

# commit(prepared_plan) -> COMPLETED(receipt) | REJECTED(before first live write)
static func commit(prepared_plan:Variant) -> Dictionary:
	if not _registered(_plans, prepared_plan):
		return _result("REJECTED", null, null, "invalid_plan_identity")
	var plan:RefCounted = prepared_plan
	var record:Dictionary = _plans[plan]
	if _terminal(record.state):
		return _terminal_view(plan)
	if record.state != State.PREPARED or record.busy:
		return _reject(plan, "commit_not_prepared")
	var window_result:Dictionary = Domain.acquire_publication_window()
	if window_result.status != "COMPLETED":
		return _reject(plan, window_result.reason)
	var window:RefCounted = window_result.window
	record.busy = true
	record.phase = "SEAL"
	# 所有可拒绝 source/version/identity/closure/余额检查在 seal 前；调用期间仍零 live 写。
	var validation:Variant = record.participant.adapter.validate_original_context(record.context)
	if not _completed(validation):
		Domain.release_publication_window(window)
		record.busy = false
		return _reject(plan, _reason(validation, "context_validation_failed"))
	if _terminal(record.state):
		Domain.release_publication_window(window)
		record.busy = false
		return _terminal_view(plan)
	var sealed:Variant = record.participant.adapter.seal(record.domain, record.context)
	if _terminal(record.state):
		Domain.release_publication_window(window)
		record.busy = false
		return _terminal_view(plan)
	if not _completed(sealed):
		Domain.release_publication_window(window)
		record.busy = false
		return _reject(plan, _reason(sealed, "participant_not_sealed"))
	# outbox 是预建、递归冻结的数据，不调用接收者；Object/Callable 不是输送载体。
	var packed:Dictionary = _freeze_data(sealed.get("outbox", []))
	if packed.status != "COMPLETED" or not (packed.value is Array):
		Domain.release_publication_window(window)
		record.busy = false
		return _reject(plan, "unsupported_outbox_carrier")
	var receipt:Dictionary = {"plan_identity":plan, "original_context":record.context,
		"state":"COMMITTED", "outbox":packed.value, "notification_boundary":"after_complete_install"}
	var domain_seal:Dictionary = record.domain.seal(window)
	if domain_seal.status != "COMPLETED":
		Domain.release_publication_window(window)
		record.busy = false
		return _reject(plan, domain_seal.reason)
	# 从此没有 participant 调用、await、Object.set、规则信号，也没有业务拒绝。
	record.phase = "INSTALL" # 内部禁认证区间，不是公开 phase 或第八态。
	var installed:Dictionary = record.domain.install_sealed(window)
	if installed.status != "COMPLETED":
		record.state = State.FAULT
		record.reason = installed.reason
		record.busy = false
		Domain.release_publication_window(window)
		return _view(plan, "FAULT")
	receipt.make_read_only()
	record.receipt = receipt
	record.continuation = null
	record.state = State.COMMITTED
	record.busy = false
	# 唯一线性化点：全部 rule/journal/runtime 已装完、COMMITTED 已存，才开放读取/通知。
	Domain.release_publication_window(window)
	return _view(plan, "COMPLETED")

# abort(plan, reason) -> terminal abort receipt；已提交只读旧回执，不倒退成拒绝。
static func abort(plan:Variant, reason:String) -> Dictionary:
	if not _registered(_plans, plan):
		return _result("REJECTED", null, null, "invalid_plan_identity")
	if _terminal(_plans[plan].state):
		return _terminal_view(plan)
	return _reject(plan, reason)

static func inspect(plan:Variant) -> Dictionary:
	if not _registered(_plans, plan):
		return _result("REJECTED", null, null, "invalid_plan_identity")
	return _view(plan, "COMPLETED" if _plans[plan].state in [State.NEW, State.PREPARED, State.COMMITTED] else ("PENDING" if _plans[plan].state in [State.PREPARING, State.PENDING] else ("FAULT" if _plans[plan].state == State.FAULT else "REJECTED")))

## E2 ABI v1：null marker 仅关联；COMPLETED 是认证结果，不是动作完成。
static func execution_binding(domain_identity:Variant, original_context:Variant, frame_marker:Variant=null) -> Dictionary:
	if not Thread.is_main_thread():
		return _binding_view(null, "REJECTED", "binding_main_thread_required")
	if _source_validation_busy:
		_source_validation_reentered = true
		return _binding_view(null, "FAULT", "recursive_source_validation")
	if not _registered(_domains, domain_identity):
		return _binding_view(null, "REJECTED", "invalid_domain_identity")
	var plan:RefCounted = _domains[domain_identity]
	var gate:Dictionary = _binding_gate(plan, original_context, frame_marker, true)
	if gate.status != "COMPLETED":
		return _binding_view(plan, gate.status, gate.reason)
	var record:Dictionary = _plans[plan]
	var handle:RefCounted = RefCounted.new()
	var kind:String = "ASSOCIATION" if frame_marker == null else "FRAME"
	_execution_bindings[handle] = {"handle":handle, "binding_kind":kind, "plan":plan,
		"domain":record.domain, "domain_identity":domain_identity, "context":record.context,
		"participant_manifest":record.participant_manifest, "invocation":record.invocation,
		"phase":record.phase, "frame_marker":frame_marker, "revoked":false}
	return _binding_view(plan, "COMPLETED", "", handle, kind, frame_marker)

static func validate_execution_binding(binding:Variant, original_context:Variant, frame_marker:Variant=null) -> Dictionary:
	if not Thread.is_main_thread():
		return _binding_view(null, "REJECTED", "binding_main_thread_required")
	if _source_validation_busy:
		_source_validation_reentered = true
		return _binding_view(null, "FAULT", "recursive_source_validation")
	if not _registered(_execution_bindings, binding):
		return _binding_view(null, "REJECTED", "invalid_execution_binding")
	var signed:Dictionary = _execution_bindings[binding]
	var plan:RefCounted = signed.plan
	var record:Dictionary = _plans[plan]
	if not is_same(signed.handle, binding) or not is_same(signed.domain, record.domain) or not is_same(signed.domain_identity, record.domain.identity()) or not is_same(signed.context, record.context) or not is_same(signed.participant_manifest, record.participant_manifest):
		return _binding_view(plan, "FAULT", "binding_registry_inconsistent", null, signed.binding_kind)
	if signed.revoked:
		return _binding_view(plan, "REJECTED", "execution_binding_revoked", null, signed.binding_kind)
	# FRAME 不能以省略/null marker 降级；ASSOCIATION 也不能升级成 FRAME。
	if (signed.binding_kind == "ASSOCIATION" and frame_marker != null) or (signed.binding_kind == "FRAME" and (frame_marker == null or not is_same(signed.frame_marker, frame_marker))):
		return _binding_view(plan, "REJECTED", "binding_kind_or_marker_mismatch", null, signed.binding_kind)
	if signed.binding_kind == "FRAME" and (not is_same(signed.invocation, record.invocation) or signed.phase != record.phase):
		return _binding_view(plan, "REJECTED", "binding_invocation_expired", null, signed.binding_kind)
	var gate:Dictionary = _binding_gate(plan, original_context, frame_marker, false)
	if gate.status != "COMPLETED":
		return _binding_view(plan, gate.status, gate.reason, null, signed.binding_kind)
	return _binding_view(plan, "COMPLETED", "", binding, signed.binding_kind, signed.frame_marker)

static func _binding_gate(plan:RefCounted, context:Variant, marker:Variant, issuing:bool) -> Dictionary:
	var record:Dictionary = _plans[plan]
	if record.domain.get_script() != Domain or not _registered(_domains, record.domain.identity()) or not is_same(_domains[record.domain.identity()], plan) or not _registered(_manifests, record.participant_manifest) or not is_same(_manifests[record.participant_manifest], record.participant):
		return {"status":"FAULT", "reason":"plan_domain_registry_inconsistent"}
	if _terminal(record.state):
		return {"status":"REJECTED", "reason":"terminal_execution_binding"}
	if not (context is RefCounted) or not is_same(record.context, context):
		return {"status":"REJECTED", "reason":"original_context_identity_mismatch"}
	if not record.domain._execution_binding_active():
		return {"status":"REJECTED", "reason":"execution_domain_revoked"}
	if record.phase == "INSTALL" or (Domain.publication_is_open() and record.phase != "SEAL"):
		return {"status":"REJECTED", "reason":"binding_installation_closed"}
	if issuing and (record.state != State.PREPARING or not record.busy or record.invocation == null or record.phase not in ["OPEN", "PREPARE", "RESUME"]):
		return {"status":"REJECTED", "reason":"binding_issuance_phase_closed"}
	if marker != null:
		if not _registered(_authorized_markers, marker):
			return {"status":"REJECTED", "reason":"marker_not_core_authorized"}
		var authorized:Dictionary = _authorized_markers[marker]
		if record.state != State.PREPARING or not record.busy or record.phase not in ["PREPARE", "RESUME"] or record.invocation == null or not is_same(record.marker, marker) or not is_same(authorized.invocation, record.invocation) or not is_same(authorized.plan, plan) or not is_same(authorized.domain, record.domain) or not is_same(authorized.domain_identity, record.domain.identity()) or not is_same(authorized.context, context) or not is_same(authorized.participant_manifest, record.participant_manifest):
			return {"status":"REJECTED", "reason":"marker_invocation_mismatch"}
		var frame:Dictionary = Domain.current_frame()
		if frame.status != "COMPLETED" or not is_same(frame.marker, marker) or not is_same(frame.plan_identity, plan) or not is_same(frame.domain, record.domain) or not is_same(frame.original_context, context) or Domain.publication_is_open():
			return {"status":"REJECTED", "reason":"marker_not_current_core_frame"}
	var checked:Dictionary = _binding_source(record)
	if checked.status != "COMPLETED":
		return checked
	# 受信 validator 应只读；返回后仍重验终态/域，不能借重入撤销后洗票。
	if _terminal(record.state) or not record.domain._execution_binding_active():
		return {"status":"REJECTED", "reason":"binding_revoked_during_validation"}
	return {"status":"COMPLETED", "reason":""}

static func _binding_source(record:Dictionary) -> Dictionary:
	# 这只是受信 bootstrap 的机制证明元数据；结构齐全不替代闭包审查。
	# 不接新的 callback；仅调用原聚合 adapter 的固定只读来源方法。
	var proof:Variant = record.participant.support_manifest.get("source_validation")
	if not (proof is Dictionary) or not (proof.get("abi_version") is int) or proof.abi_version != ABI_VERSION or not (proof.get("read_only") is bool) or not proof.read_only or not (proof.get("validator_script") is Script) or not is_same(proof.validator_script, record.participant.adapter.get_script()):
		return {"status":"UNSUPPORTED", "reason":"missing_read_only_source_validation_proof"}
	_source_validation_busy = true
	_source_validation_reentered = false
	var validation:Variant = record.participant.adapter.validate_original_context(record.context)
	_source_validation_busy = false
	if _source_validation_reentered:
		return {"status":"FAULT", "reason":"recursive_source_validation"}
	if not (validation is Dictionary) or not (validation.get("status") is String) or (validation.has("reason") and not (validation.reason is String)):
		return {"status":"FAULT", "reason":"source_validator_protocol_violation"}
	match validation.status:
		"COMPLETED": return {"status":"COMPLETED", "reason":""}
		"REJECTED", "UNSUPPORTED", "FAULT": return {"status":validation.status, "reason":_reason(validation, "source_validation_failed")}
		_: return {"status":"FAULT", "reason":"source_validator_protocol_violation"}

static func _revoke_invocation(record:Dictionary) -> void:
	if record.marker != null:
		_authorized_markers.erase(record.marker)
	for signed in _execution_bindings.values():
		if signed.binding_kind == "FRAME" and is_same(signed.invocation, record.invocation):
			signed.revoked = true
	record.marker = null
	record.invocation = null
	record.phase = null

static func _binding_view(plan:Variant, status:String, reason:String, binding:Variant=null, kind:Variant=null, marker:Variant=null) -> Dictionary:
	var result:Dictionary = _result(status, null, null, reason)
	result.merge({"binding":binding, "binding_kind":kind, "domain_identity":null,
		"participant_manifest":null, "phase":null, "frame_marker":null, "abi_version":ABI_VERSION})
	if plan != null:
		var record:Dictionary = _plans[plan]
		result.plan_identity = plan
		result.original_context = record.context
		result.receipt = record.receipt
		result["state"] = State.keys()[record.state]
		result.domain_identity = record.domain.identity()
		result.participant_manifest = record.participant_manifest
		result.phase = "TERMINAL" if _terminal(record.state) else ("SEAL" if record.phase in ["SEAL", "INSTALL"] else (State.keys()[record.state] if record.state in [State.PENDING, State.PREPARED] else record.phase))
		if status == "COMPLETED" and kind == "FRAME": result.frame_marker = marker
	result.make_read_only()
	return result

static func _execute(plan:RefCounted, resuming:bool, input:Variant) -> Dictionary:
	var record:Dictionary = _plans[plan]
	if not Thread.is_main_thread() or Domain.publication_is_open() or record.busy:
		return _reject(plan, "execution_boundary_busy")
	record.state = State.PREPARING
	record.busy = true
	var adapter = record.participant.adapter
	var validation:Variant = adapter.validate_original_context(record.context)
	if not _completed(validation):
		record.busy = false
		return _reject(plan, _reason(validation, "context_validation_failed"))
	if _terminal(record.state):
		record.busy = false
		return _terminal_view(plan)
	record.invocation = RefCounted.new()
	record.phase = "OPEN" if not resuming else null
	if not resuming:
		var opened:Variant = adapter.open_domain(record.domain, record.context, record.closure, record.participant.support_manifest)
		if not _completed(opened):
			record.busy = false
			return _reject(plan, _reason(opened, "domain_not_supported"))
		if _terminal(record.state):
			record.busy = false
			return _terminal_view(plan)
	var entered:Dictionary = record.domain.enter_frame(plan, record.context)
	if entered.status != "COMPLETED":
		record.busy = false
		return _reject(plan, entered.reason)
	# 只能在 Core 自己 enter 返回后登记；公开查询绝不追认手工帧。
	record.phase = "RESUME" if resuming else "PREPARE"
	record.marker = entered.frame_marker
	_authorized_markers[entered.frame_marker] = {"plan":plan, "domain":record.domain,
		"domain_identity":record.domain.identity(), "context":record.context,
		"participant_manifest":record.participant_manifest, "invocation":record.invocation}
	var outcome:Variant
	if resuming:
		outcome = adapter.resume(record.domain, record.continuation, input, record.context)
	else:
		outcome = adapter.prepare(record.domain, record.closure, record.context)
	var left:Dictionary = Domain.leave_frame(entered.frame_marker)
	_revoke_invocation(record)
	record.busy = false
	if left.status != "COMPLETED":
		record.state = State.FAULT
		record.reason = "participant_frame_leak"
		return _view(plan, "FAULT")
	if _terminal(record.state):
		return _terminal_view(plan)
	if not (outcome is Dictionary) or not (outcome.get("status") is String):
		record.state = State.FAULT
		record.reason = "participant_protocol_violation"
		record.domain.discard()
		return _view(plan, "FAULT")
	match outcome.status:
		"COMPLETED":
			record.state = State.PREPARED
			record.continuation = null
			return _view(plan, "COMPLETED")
		"PENDING":
			if not (outcome.get("continuation") is RefCounted):
				return _reject(plan, "missing_owned_continuation")
			record.state = State.PENDING
			record.continuation = outcome.continuation
			return _view(plan, "PENDING")
		"REJECTED", "UNSUPPORTED":
			return _reject(plan, _reason(outcome, "prepare_rejected"))
		_:
			record.state = State.FAULT
			record.reason = "unknown_participant_status"
			record.domain.discard()
			return _view(plan, "FAULT")

static func _freeze_data(value:Variant, ancestors:Array = []) -> Dictionary:
	if typeof(value) in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME]:
		return {"status":"COMPLETED", "value":value}
	if not (value is Array or value is Dictionary) or ancestors.size() >= 128:
		return {"status":"UNSUPPORTED", "value":null}
	for ancestor in ancestors:
		if is_same(ancestor, value):
			return {"status":"UNSUPPORTED", "value":null}
	var branch:Array = ancestors.duplicate()
	branch.append(value)
	var copy:Variant = [] if value is Array else {}
	if value is Array:
		for item in value:
			var frozen:Dictionary = _freeze_data(item, branch)
			if frozen.status != "COMPLETED": return frozen
			copy.append(frozen.value)
	else:
		for key in value:
			if typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME, TYPE_INT]:
				return {"status":"UNSUPPORTED", "value":null}
			var frozen:Dictionary = _freeze_data(value[key], branch)
			if frozen.status != "COMPLETED": return frozen
			copy[key] = frozen.value
	copy.make_read_only()
	return {"status":"COMPLETED", "value":copy}

static func _registered(registry:Dictionary, handle:Variant) -> bool:
	return handle is RefCounted and registry.has(handle)

static func _terminal(state:int) -> bool:
	return state in [State.COMMITTED, State.ABORTED, State.FAULT]

static func _completed(result:Variant) -> bool:
	return result is Dictionary and result.get("status") is String and result.status == "COMPLETED"

static func _reason(result:Variant, fallback:String) -> String:
	if result is Dictionary and result.get("reason") is String and not result.reason.is_empty():
		return result.reason
	return fallback

static func _reject(plan:RefCounted, reason:String) -> Dictionary:
	var record:Dictionary = _plans[plan]
	if _terminal(record.state):
		return _terminal_view(plan)
	_revoke_invocation(record)
	record.state = State.ABORTED
	record.reason = reason
	record.continuation = null
	record.domain.discard()
	var receipt:Dictionary = {"plan_identity":plan, "original_context":record.context,
		"state":"ABORTED", "reason":reason}
	receipt.make_read_only()
	record.receipt = receipt
	return _view(plan, "REJECTED")

static func _terminal_view(plan:RefCounted) -> Dictionary:
	var state:int = _plans[plan].state
	return _view(plan, "COMPLETED" if state == State.COMMITTED else ("FAULT" if state == State.FAULT else "REJECTED"))

static func _view(plan:RefCounted, status:String) -> Dictionary:
	var record:Dictionary = _plans[plan]
	if record.state == State.FAULT and record.receipt == null:
		var fault_receipt:Dictionary = {"plan_identity":plan, "original_context":record.context,
			"state":"FAULT", "reason":record.reason, "authority_must_stop":true}
		fault_receipt.make_read_only()
		record.receipt = fault_receipt
	var result:Dictionary = _result(status, plan, record.context, record.reason, record.continuation, record.receipt)
	result["state"] = State.keys()[record.state]
	return result

static func _result(status:String, plan_identity:Variant, original_context:Variant, reason:String = "", continuation:Variant = null, receipt:Variant = null) -> Dictionary:
	return {"status":status, "plan_identity":plan_identity, "original_context":original_context,
		"reason":reason, "continuation":continuation, "receipt":receipt}
