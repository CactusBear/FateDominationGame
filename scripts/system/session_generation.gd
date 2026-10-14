class_name SessionGeneration
extends RefCounted
const AtomicDomain = preload("res://scripts/system/atomic_execution_domain.gd")
const AtomicPlan = preload("res://scripts/system/atomic_action_plan.gd")

## Only original session provenance, never membership/payment/rules/transactions/auth.
## Static process-local metadata: checkpoint owners must treat handles as graph leaves.
## Main-thread service; trusted producers own freshness and declared origin callsites.
static var _current:SessionToken = null
static var _issued_tokens:Array[WeakRef] = []
static var _bindings:Array[Dictionary] = []
static var _contexts:Array[Dictionary] = []
static var _last_lifecycle_reason:StringName = &""
# 加速索引（实例号 → 记录）；三个数组仍是唯一权威，命中后仍用 is_same 复核，实例号复用不会误认。
static var _issued_index:Dictionary = {}
static var _binding_index:Dictionary = {}
static var _context_index:Dictionary = {}

static func current_token() -> Dictionary:
	if in_private_frame(): return {"ok":false, "token":null, "reason":&"private_token_not_public"}
	if _current == null:
		return {"ok":false, "token":null, "reason":&"no_session"}
	return {"ok":true, "token":_current, "reason":&"current"}

static func validate_token(token:Variant) -> Dictionary:
	if in_private_frame(): return {"ok":false, "reason":&"private_token_not_public"}
	if token == null:
		return {"ok":false, "reason":&"missing_token"}
	var candidate:Object = _resolve_object(token)
	if not candidate is SessionToken or not _was_issued(candidate):
		return {"ok":false, "reason":&"invalid_token"}
	if _current == null:
		return {"ok":false, "reason":&"no_session"}
	if not is_same(candidate, _current):
		return {"ok":false, "reason":&"stale_session"}
	return {"ok":true, "reason":&"current"}

static func begin_generation(reason:StringName) -> Dictionary:
	if in_private_frame(): return {"ok":false, "token":null, "reason":&"use_private_reset_service"}
	_invalidate_private_plans()
	# Revoke before allocation. No path takes a caller-supplied token as current.
	_current = null
	_last_lifecycle_reason = reason
	_collect_dead_records()
	var candidate:SessionToken = _allocate_token()
	if candidate == null or _was_issued(candidate):
		return {"ok":false, "token":null, "reason":&"generation_unavailable"}
	_issued_tokens.append(weakref(candidate))
	_issued_index[candidate.get_instance_id()] = weakref(candidate)
	_current = candidate
	return {"ok":true, "token":candidate, "reason":&"current"}

static func invalidate_generation(reason:StringName) -> Dictionary:
	if in_private_frame(): return {"ok":false, "token":null, "reason":&"use_private_reset_service"}
	_invalidate_private_plans()
	_current = null
	_last_lifecycle_reason = reason
	_collect_dead_records()
	return {"ok":true, "token":null, "reason":&"invalidated"}

static func bind_origin(subject:Object, token:Variant, origin:StringName) -> Dictionary:
	if in_private_frame(): return _context_failure(&"private_origin_registration_unsupported")
	# Explicit trusted production boundary, not a consumer fallback or origin whitelist.
	var valid:Dictionary = validate_token(token)
	if not valid.ok:
		return _context_failure(_binding_reason(valid.reason))
	var candidate:Object = _resolve_object(subject)
	if candidate == null or origin == &"":
		return _context_failure(&"unbound_origin")
	var existing:Dictionary = _binding_record(candidate)
	if not existing.is_empty():
		if not is_same(existing.token, _resolve_object(token)) or existing.origin != origin:
			return _context_failure(&"origin_rebind_denied")
		return {"ok":true, "context":existing.context, "reason":&"current"}
	_collect_dead_records()
	var context:SessionContext = _issue_context(_resolve_object(token) as SessionToken, origin)
	if context == null:
		return _context_failure(&"unbound_origin")
	# Commit once, after all validation/allocation; retained old records are never erased.
	var binding:Dictionary = {"subject":weakref(candidate), "token":context.token(), "origin":origin, "context":context}
	_bindings.append(binding)
	_binding_index[candidate.get_instance_id()] = binding
	return {"ok":true, "context":context, "reason":&"current"}

static func origin_of(subject:Variant) -> Dictionary:
	var candidate:Object = _resolve_object(subject)
	if candidate == null:
		return _context_failure(&"unbound_origin")
	var record:Dictionary = _binding_record(candidate)
	if record.is_empty():
		return _context_failure(&"unbound_origin")
	if not validate_context(record.context).ok:
		return _context_failure(&"stale_session")
	return {"ok":true, "context":record.context, "reason":&"current"}

static func derive_context(parent:Variant, origin:StringName) -> Dictionary:
	if in_private_frame(): return _context_failure(&"private_context_derivation_denied")
	if origin == &"":
		return _context_failure(&"unbound_origin")
	var candidate:Object = _resolve_object(parent)
	var source:SessionToken = null
	var valid:Dictionary
	if candidate is SessionToken:
		valid = validate_token(candidate)
		source = candidate as SessionToken
	elif candidate is SessionContext:
		valid = validate_context(candidate)
		if valid.ok:
			source = _context_record(candidate).token
	else:
		var found:Dictionary = origin_of(candidate)
		if not found.ok:
			return _context_failure(found.reason)
		source = _context_record(found.context).token
		valid = validate_token(source)
	if not valid.ok:
		return _context_failure(&"stale_session" if valid.reason in [&"stale_session", &"no_session"] else &"unbound_origin")
	_collect_dead_records()
	var context:SessionContext = _issue_context(source, origin)
	if context == null:
		return _context_failure(&"unbound_origin")
	return {"ok":true, "context":context, "reason":&"current"}

static func validate_context(context:Variant) -> Dictionary:
	if in_private_frame():
		var private_source:Dictionary = private_lifecycle()
		if private_source.status != "COMPLETED": return {"ok":false, "reason":&"missing_private_lifecycle"}
		var attached:Dictionary = private_source.service.attach_current_plan()
		if not attached.ok: return attached
		return private_source.service.source_status(context)
	return validate_original_context(context)

static func _resolve_object(value:Variant) -> Object:
	if typeof(value) != TYPE_OBJECT or not is_instance_valid(value):
		return null
	if value is WeakRef:
		var target:Object = value.get_ref()
		return target if is_instance_valid(target) else null
	return value

static func _was_issued(candidate:Object) -> bool:
	var reference:WeakRef = _issued_index.get(candidate.get_instance_id())
	if reference == null: return false
	var live:Object = reference.get_ref()
	return is_instance_valid(live) and is_same(live, candidate)

static func _binding_record(subject:Object) -> Dictionary:
	var record:Dictionary = _binding_index.get(subject.get_instance_id(), {})
	if record.is_empty(): return {}
	var live:Object = record.subject.get_ref()
	return record if is_instance_valid(live) and is_same(live, subject) else {}

static func _context_record(context:Object) -> Dictionary:
	var record:Dictionary = _context_index.get(context.get_instance_id(), {})
	if record.is_empty(): return {}
	var live:Object = record.handle.get_ref()
	return record if is_instance_valid(live) and is_same(live, context) else {}

static func _issue_context(token:SessionToken, origin:StringName) -> SessionContext:
	var context:SessionContext = _allocate_context(token, origin)
	if context == null:
		invalidate_generation(&"generation_unavailable")
		return null
	var record:Dictionary = {"handle":weakref(context), "token":token, "origin":origin}
	_contexts.append(record)
	_context_index[context.get_instance_id()] = record
	return context

static func _allocate_token() -> SessionToken:
	return SessionToken.new()

static func _allocate_context(token:SessionToken, origin:StringName) -> SessionContext:
	return SessionContext.new(token, origin)

static func _binding_reason(reason:StringName) -> StringName:
	if reason in [&"stale_session", &"no_session"]:
		return &"stale_session"
	return &"invalid_token"

static func _context_failure(reason:StringName) -> Dictionary:
	return {"ok":false, "context":null, "reason":reason}

static func _collect_dead_records() -> void:
	# Writes only. No TTL/cap and no reclamation while a subject/handle is reachable.
	for index:int in range(_bindings.size() - 1, -1, -1):
		if not is_instance_valid(_bindings[index].subject.get_ref()):
			_bindings.remove_at(index)
	for index:int in range(_contexts.size() - 1, -1, -1):
		if not is_instance_valid(_contexts[index].handle.get_ref()):
			_contexts.remove_at(index)
	for index:int in range(_issued_tokens.size() - 1, -1, -1):
		if not is_instance_valid(_issued_tokens[index].get_ref()):
			_issued_tokens.remove_at(index)
	# 索引只删已死项；同号新记录（实例号复用）已覆盖旧项时保留。
	for key in _binding_index.keys():
		if not is_instance_valid(_binding_index[key].subject.get_ref()): _binding_index.erase(key)
	for key in _context_index.keys():
		if not is_instance_valid(_context_index[key].handle.get_ref()): _context_index.erase(key)
	for key in _issued_index.keys():
		if not is_instance_valid(_issued_index[key].get_ref()): _issued_index.erase(key)

# 原始 backing 是唯一权威存储，不是提交后再同步 Node 字段的旁挂副本。
# 只供受信聚合/Graph owner 使用；不是可执行闭包准入证书。
class ModelBacking:
	extends RefCounted
	var _state:Dictionary
	func _init(initial:Dictionary):
		_state = initial
	func resolve() -> Dictionary:
		var frame:Dictionary = preload("res://scripts/system/atomic_execution_domain.gd").current_frame()
		if frame.status != "COMPLETED":
			return {"status":"COMPLETED", "reason":"", "value":_state}
		var bound:Dictionary = preload("res://scripts/system/atomic_execution_domain.gd").rebind_dependency(_state)
		if bound.status != "COMPLETED" or not bound.value is Dictionary:
			return {"status":"UNSUPPORTED", "reason":"unbound_model_backing"}
		return bound
	func read(key:StringName, fallback:Variant) -> Variant:
		var state:Dictionary = resolve()
		return state.value.get(key, fallback) if state.status == "COMPLETED" else fallback
	func write(key:StringName, value:Variant) -> void:
		var state:Dictionary = resolve()
		if state.status == "COMPLETED":
			var previous:Variant = state.value.get(key)
			# L façade 的引用换后换回必须粘滞失效；不靠最终 hash。
			# 嵌套 raw 容器直写仍须 G/C ledger 证明，不能由此推定已覆盖。
			if not SessionGeneration.in_private_frame() and (previous is Array or previous is Dictionary or previous is Object) and not is_same(previous, value):
				SessionGeneration._invalidate_private_plans()
			state.value[key] = value
	func backing() -> Dictionary:
		# 不在 D 中透出 L target；seal 之前聚合 owner 保存安装描述。
		if preload("res://scripts/system/atomic_execution_domain.gd").current_frame().status == "COMPLETED":
			return {}
		return _state
	func bind(domain:Variant, prepared:Dictionary) -> Dictionary:
		if not (domain is AtomicDomain): return {"status":"UNSUPPORTED", "reason":"invalid_private_domain"}
		if preload("res://scripts/system/atomic_execution_domain.gd").current_frame().status == "COMPLETED" or preload("res://scripts/system/atomic_execution_domain.gd").publication_is_open():
			return {"status":"UNSUPPORTED", "reason":"model_binding_closed"}
		if is_same(prepared, _state) or prepared.is_typed() or prepared.is_read_only() or prepared.size() != _state.size():
			return {"status":"UNSUPPORTED", "reason":"invalid_private_model"}
		for key in _state:
			if not prepared.has(key) or typeof(prepared[key]) != typeof(_state[key]):
				return {"status":"UNSUPPORTED", "reason":"private_model_schema"}
			var value:Variant = _state[key]
			if value is Object and (not is_same(value.get_script(), prepared[key].get_script()) or value.get_class() != prepared[key].get_class()):
				return {"status":"UNSUPPORTED", "reason":"private_model_object_schema"}
			if (value is Array or value is Dictionary or value is Object) and value != null and is_same(value, prepared[key]):
				return {"status":"UNSUPPORTED", "reason":"live_model_alias"}
		# 深层 alias/WeakRef/Callable 必须由同一 Graph memo 证明；这里不 duplicate 图。
		return domain.bind_dependency(_state, prepared)

# 私有生命周期不签 SessionToken/SessionContext，也不写 L 的发行/绑定表。
class PrivateLifecycle:
	extends RefCounted
	var original_context:SessionContext
	var _domain:WeakRef
	var _plan:RefCounted
	var _association:RefCounted
	var _frame_binding:RefCounted = null
	var _frame_marker:RefCounted = null
	var _reset_marker:RefCounted = null
	var _revoked:bool = false
	var _resetting:bool = false
	var _epoch:RefCounted = RefCounted.new()
	var _revoked_epochs:Array = []
	var _steps:Array = []
	func _init(domain:Variant, source:SessionContext, association:Dictionary):
		_domain = weakref(domain)
		original_context = source
		_plan = association.plan_identity
		_association = association.binding
	func source_status(candidate:Variant) -> Dictionary:
		if not is_same(candidate, original_context):
			return {"ok":false, "reason":&"original_context_identity_mismatch"}
		var valid:Dictionary = SessionGeneration.validate_original_context(candidate)
		if not valid.ok: return valid
		var authenticated:Dictionary = _authenticate_frame()
		if not authenticated.ok: return authenticated
		# 只让已认证 reset 的同一 marker 完成原同步清值，不给陌生帧借权。
		if _revoked and (not _resetting or not is_same(_reset_marker, _frame_marker)):
			return {"ok":false, "reason":&"private_generation_revoked"}
		return {"ok":true, "reason":&"current"}
	# Core 唯一签发 marker；这里只缓存公开 handle，不追认手工帧。
	# E2 source validator 必须走纯 validate_original_context，不能进入此消费口。
	func _authenticate_frame() -> Dictionary:
		var frame:Dictionary = AtomicDomain.current_frame()
		var domain:Variant = _domain.get_ref()
		if frame.status != "COMPLETED" or domain == null or not is_same(frame.domain, domain) or not is_same(frame.original_context, original_context) or not is_same(frame.plan_identity, _plan):
			return {"ok":false, "reason":&"private_frame_mismatch"}
		var associated:Dictionary = AtomicPlan.validate_execution_binding(_association, original_context)
		if associated.status != "COMPLETED" or associated.binding_kind != "ASSOCIATION" or not is_same(associated.plan_identity, _plan) or not is_same(associated.domain_identity, domain.identity()):
			return {"ok":false, "reason":&"private_association_rejected"}
		if not is_same(_frame_marker, frame.marker):
			# PREPARE/RESUME 显式 exact marker；null 绝不用于捕获执行帧。
			var issued:Dictionary = AtomicPlan.execution_binding(domain.identity(), original_context, frame.marker)
			if issued.status != "COMPLETED" or issued.binding_kind != "FRAME":
				return {"ok":false, "reason":&"private_core_frame_rejected"}
			_frame_binding = issued.binding
			_frame_marker = frame.marker
		var checked:Dictionary = AtomicPlan.validate_execution_binding(_frame_binding, original_context, frame.marker)
		if checked.status != "COMPLETED" or checked.binding_kind != "FRAME" or not is_same(checked.plan_identity, _plan) or not is_same(checked.domain_identity, domain.identity()) or not is_same(checked.frame_marker, frame.marker):
			return {"ok":false, "reason":&"private_core_frame_rejected"}
		return {"ok":true, "reason":&"current"}
	func attach_current_plan() -> Dictionary:
		return source_status(original_context)
	func begin_reset(lifecycle:StringName, source:Variant) -> Dictionary:
		if _resetting: return {"ok":false, "reason":&"private_reset_busy"}
		var attached:Dictionary = attach_current_plan()
		if not attached.ok: return attached
		if lifecycle not in [&"begin", &"invalidate"] or (source != null and (lifecycle == &"invalidate" or not is_same(source, original_context))):
			return {"ok":false, "reason":&"unbound_origin"}
		_steps.append(&"authenticate_original")
		if source == null:
			_revoked = true
			_revoked_epochs.append(_epoch)
			_steps.append(&"revoke_private_epoch")
			_epoch = RefCounted.new() if lifecycle == &"begin" else null
			_steps.append(&"allocate_private_epoch" if lifecycle == &"begin" else &"invalidate_private_epoch")
		# 清值没有 callback/await；此窄权限仅覆盖原 reset 的同步清值区段。
		_reset_marker = _frame_marker
		_resetting = true
		return {"ok":true, "reason":&"current", "context":original_context}
	func finish_reset(cleared:bool) -> void:
		if not _resetting or not source_status(original_context).ok: return
		_steps.append(&"clear_progress_values" if cleared else &"clear_progress_failed")
		_resetting = false
		_reset_marker = null
		if _revoked and _plan != null:
			_steps.append(&"abort_old_plan")
			preload("res://scripts/system/atomic_action_plan.gd").abort(_plan, "private_generation_revoked")
	func invalidate_live_source() -> void:
		_revoked = true
		_resetting = false
		_reset_marker = null
		if _plan != null:
			preload("res://scripts/system/atomic_action_plan.gd").abort(_plan, "live_generation_revoked")
	func diagnostic_status() -> Dictionary:
		return {"original_context":original_context, "revoked":_revoked, "revoked_epochs":_revoked_epochs.size(), "steps":_steps.duplicate()}

static var _private_services:Array = []

# 受信 open 阶段接缝；只绑定私有服务，不登记生产能力，不授予任意代码执行权限。
static func open_private_lifecycle(domain:Variant, original_context:Variant) -> Dictionary:
	if preload("res://scripts/system/atomic_execution_domain.gd").current_frame().status == "COMPLETED" or preload("res://scripts/system/atomic_execution_domain.gd").publication_is_open():
		return {"status":"UNSUPPORTED", "reason":"private_open_closed"}
	var valid:Dictionary = validate_original_context(original_context)
	if not valid.ok: return {"status":"REJECTED", "reason":str(valid.reason)}
	if not (domain is AtomicDomain):
		return {"status":"UNSUPPORTED", "reason":"invalid_private_domain"}
	# OPEN 仅存真实归属；不以 ASSOCIATION 授执行，也不在消费口创建来源。
	var associated:Dictionary = AtomicPlan.execution_binding(domain.identity(), original_context)
	if associated.status != "COMPLETED": return {"status":associated.status, "reason":associated.reason}
	if associated.binding_kind != "ASSOCIATION" or associated.phase != "OPEN":
		return {"status":"REJECTED", "reason":"private_association_not_open"}
	var checked:Dictionary = AtomicPlan.validate_execution_binding(associated.binding, original_context)
	if checked.status != "COMPLETED": return {"status":checked.status, "reason":checked.reason}
	var service := PrivateLifecycle.new(domain, original_context, checked)
	var bound:Dictionary = domain.bind_root(&"session_generation", service)
	if bound.status != "COMPLETED": return bound
	_private_services.append(weakref(service))
	return {"status":"COMPLETED", "reason":"", "service":service}

static func private_lifecycle() -> Dictionary:
	var root:Dictionary = preload("res://scripts/system/atomic_execution_domain.gd").resolve_root(&"session_generation")
	if root.status != "COMPLETED" or not root.value is PrivateLifecycle:
		return {"status":"UNSUPPORTED", "reason":"missing_private_lifecycle"}
	var registered:bool = false
	for reference:WeakRef in _private_services:
		if is_same(reference.get_ref(), root.value): registered = true
	if not registered: return {"status":"UNSUPPORTED", "reason":"unregistered_private_lifecycle"}
	return {"status":"COMPLETED", "reason":"", "service":root.value}

static func in_private_frame() -> bool:
	return preload("res://scripts/system/atomic_execution_domain.gd").current_frame().status == "COMPLETED"

static func lifecycle_diagnostics() -> Dictionary:
	# 只读数量/identity 旁带；不暴露发行表，也不是准入证明。
	var result:Dictionary = {"token":_current, "bindings":_bindings.size(), "contexts":_contexts.size(), "issued_tokens":_issued_tokens.size()}
	result.make_read_only()
	return result

static func _invalidate_private_plans() -> void:
	for reference:WeakRef in _private_services:
		var service = reference.get_ref()
		if service != null: service.invalidate_live_source()

# 原 provenance 认证永远按 L 发行表 is_same；私有 reset 不改这个身份。
static func validate_original_context(context:Variant) -> Dictionary:
	var candidate:Object = _resolve_object(context)
	if not candidate is SessionContext: return {"ok":false, "reason":&"unbound_origin"}
	var record:Dictionary = _context_record(candidate)
	if record.is_empty(): return {"ok":false, "reason":&"unbound_origin"}
	if not is_same(candidate.token(), record.token) or candidate.origin() != record.origin:
		return {"ok":false, "reason":&"invalid_token"}
	if not _was_issued(record.token) or _current == null or not is_same(record.token, _current):
		return {"ok":false, "reason":&"stale_session"}
	return {"ok":true, "reason":&"current"}
