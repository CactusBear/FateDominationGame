extends RefCounted

## 仅在同一权威进程中恢复原对象，不编码/执行网络对象或 Callable。
const Ids = preload("res://scripts/match/net_ids.gd")
const Generation = preload("res://scripts/system/session_generation.gd")
const Token = preload("res://scripts/system/session_token.gd")
const Context = preload("res://scripts/system/session_context.gd")
var _captured_context:Variant = null
var error:String = ""
var ready:bool = false
var limits = Ids.new()
var _objects:Dictionary = {}
var _collections:Array = []

var _pending:Array = []
var _comparisons:int = 0
var _excluded:Dictionary = {}
var _node_roots:Dictionary = {}
var max_capture_objects:int = 100000
var max_capture_values:int = 1000000
var _values:int = 0
var _collection_groups:Dictionary = {}
var _identity_index:Object = null

## 不透明预算资格；构造同类型对象不授资格，原父发行表才是权威。
class BudgetLease:
	extends RefCounted

## 主线程进程内元信息，不是实例规则字段，restore 不得回滚消费/失效。
## weak owner 防止延长检查点寿命；强持有发行票直到关闭，防身份复用。
static var _budget_sessions:Dictionary = {}
const BUDGET_DIMENSIONS = ["collections", "comparisons", "values", "objects"]

func _retire_budget_session() -> void:
	_budget_sessions.erase(get_instance_id())
	for id in _budget_sessions.keys():
		if _budget_sessions[id].owner.get_ref() == null:
			_budget_sessions.erase(id)

func _open_budget_session() -> void:
	var remaining:Dictionary = {
		"collections":limits.max_capture_collections - _collections.size(),
		"comparisons":limits.max_capture_comparisons - _comparisons,
		"values":max_capture_values - _values,
		"objects":max_capture_objects - _objects.size()}
	for key in BUDGET_DIMENSIONS:
		if remaining[key] < 0: return
	_budget_sessions[get_instance_id()] = {
		"owner":weakref(self), "context":_captured_context,
		"remaining":remaining, "leases":{}}
	# One COLD original-source authentication. Never create provenance in a consumer.
	# WeakRef/private sources keep their legacy behaviour but get no bounded cache.
	if Thread.is_main_thread() and not Generation.in_private_frame() and _captured_context is Context and is_same(_captured_context.get_script(), Context) and Generation.validate_original_context(_captured_context).ok:
		_budget_sessions[get_instance_id()]["authenticated_source"] = {
			"context":_captured_context, "token":_captured_context.token(), "origin":_captured_context.origin()}

func _budget_session(context:Variant) -> Dictionary:
	var session:Dictionary = _budget_sessions.get(get_instance_id(), {})
	if session.is_empty() or not is_same(session.owner.get_ref(), self): return {}
	if not ready or not is_same(context, session.context): return {}
	if not Generation.validate_context(context).ok: return {}
	return session

## Fixed public qualification envelope; not a second meter/allowance.
## Standalone validate is bounded bootstrap; reserve charges this with work atomically.
const BOUNDED_AUTH_COSTS = {"collections":32, "comparisons":96, "values":1024, "objects":0}

func _bounded_budget_session(context:Variant) -> Dictionary:
	# The original Source factory issues this exact Context Script. Reject script
	# replacement BEFORE public getters, whose fixed definitions are the bound.
	if not context is Context or not is_same(context.get_script(), Context): return {}
	if not Thread.is_main_thread() or Generation.in_private_frame(): return {}
	var session:Dictionary = _budget_sessions.get(get_instance_id(), {})
	if session.is_empty() or not is_same(session.owner.get_ref(), self): return {}
	if not ready or not is_same(context, session.context): return {}
	var authenticated:Dictionary = session.get("authenticated_source", {})
	if authenticated.is_empty() or not is_same(context, authenticated.context): return {}
	# Only compare the previously authenticated token to current to revoke it.
	# Current NEVER signs a missing/new context, token, cache or lease.
	var current:Dictionary = Generation.current_token()
	if not current.ok or not is_same(authenticated.token, current.token): return {}
	if not is_same(context.token(), authenticated.token) or context.origin() != authenticated.origin: return {}
	return session

func _bounded_budget_qualification(lease:Variant, context:Variant) -> Dictionary:
	if not Thread.is_main_thread(): return _budget_rejected("budget_main_thread_required")
	if Generation.in_private_frame(): return _budget_rejected("budget_private_frame_unsupported")
	var session:Dictionary = _bounded_budget_session(context)
	if session.is_empty(): return _budget_rejected("budget_session_invalid")
	if not lease is BudgetLease or not session.leases.has(lease): return _budget_rejected("budget_lease_invalid")
	# This record is internal to the original parent; never expose it in receipts.
	return {"status":"COMPLETED", "session":session}

func validate_budget_lease_bounded(lease:Variant, original_context:Variant) -> Dictionary:
	var qualified:Dictionary = _bounded_budget_qualification(lease, original_context)
	if qualified.status != "COMPLETED": return qualified
	return {"status":"COMPLETED", "reason":"", "remaining":qualified.session.remaining.duplicate()}

## No Source history scan and no duplicate session validation. The fixed protocol
## envelope + caller's work are ONE original atomic reservation; no refund.
func reserve_budget_bounded(lease:Variant, costs:Variant, original_context:Variant) -> Dictionary:
	var qualified:Dictionary = _bounded_budget_qualification(lease, original_context)
	if qualified.status != "COMPLETED": return qualified
	if not costs is Dictionary: return _budget_rejected("budget_costs_type")
	if costs.size() > 4: return _budget_rejected("budget_costs_key")
	for key in costs:
		if typeof(key) != TYPE_STRING or key not in BUDGET_DIMENSIONS: return _budget_rejected("budget_costs_key")
		if typeof(costs[key]) != TYPE_INT or costs[key] < 0: return _budget_rejected("budget_costs_value")
	var total:Dictionary = {}
	for key in BUDGET_DIMENSIONS:
		var work:int = costs.get(key, 0)
		if work > 9223372036854775807 - BOUNDED_AUTH_COSTS[key]: return _budget_rejected("budget_costs_value")
		total[key] = work + BOUNDED_AUTH_COSTS[key]
	var paid:Dictionary = _reserve_budget_costs(qualified.session, total)
	if paid.status == "COMPLETED":
		paid["reservation"] = total
	return paid

func _budget_rejected(reason:String) -> Dictionary:
	return {"status":"REJECTED", "reason":reason}

## 返回独立只读数据，不泄漏可写账本；不授 C/写者闭包/commit 权限。
func budget_remaining(original_context:Variant) -> Dictionary:
	var session:Dictionary = _budget_session(original_context)
	if session.is_empty(): return _budget_rejected("budget_session_invalid")
	return {"status":"COMPLETED", "reason":"", "remaining":session.remaining.duplicate()}

func issue_budget_lease(original_context:Variant) -> Dictionary:
	var session:Dictionary = _budget_session(original_context)
	if session.is_empty(): return _budget_rejected("budget_session_invalid")
	# 每张新票/登记槽自身收费；嵌套发票只共用原剩余，不开另一满额账。
	var reserved:Dictionary = _reserve_budget_costs(session, {"objects":1, "values":1})
	if reserved.status != "COMPLETED": return reserved
	var lease:BudgetLease = BudgetLease.new()
	session.leases[lease] = true
	reserved["lease"] = lease
	return reserved

func validate_budget_lease(lease:Variant, original_context:Variant) -> Dictionary:
	var session:Dictionary = _budget_session(original_context)
	if session.is_empty(): return _budget_rejected("budget_session_invalid")
	if not lease is BudgetLease or not session.leases.has(lease):
		return _budget_rejected("budget_lease_invalid")
	return {"status":"COMPLETED", "reason":"", "remaining":session.remaining.duplicate()}

## 调用者必须先消费成功回执，再复制旧槽/新壳或执行首次规则写。
## 不 invoke callback；空 costs 合法，restore/release 不退款。
func reserve_budget(lease:Variant, costs:Variant, original_context:Variant) -> Dictionary:
	var valid:Dictionary = validate_budget_lease(lease, original_context)
	if valid.status != "COMPLETED": return valid
	return _reserve_budget_costs(_budget_session(original_context), costs)

func _reserve_budget_costs(session:Dictionary, costs:Variant) -> Dictionary:
	if not costs is Dictionary: return _budget_rejected("budget_costs_type")
	# 先检查全组：严格 int（不收 bool/float），不求和避免 int64 溢出。
	for key in costs:
		if typeof(key) != TYPE_STRING or key not in BUDGET_DIMENSIONS:
			return _budget_rejected("budget_costs_key")
		if typeof(costs[key]) != TYPE_INT or costs[key] < 0:
			return _budget_rejected("budget_costs_value")
	for key in BUDGET_DIMENSIONS:
		if costs.get(key, 0) > session.remaining[key]:
			return _budget_rejected("budget_exhausted_" + key)
	# 整组资格已通过才单调扣减；任何一维不足均零账写、零调用方写。
	for key in BUDGET_DIMENSIONS:
		session.remaining[key] -= costs.get(key, 0)
	return {"status":"COMPLETED", "reason":"", "remaining":session.remaining.duplicate()}

## 只关闭预算资格；不消耗/退款原规则快照，不改变原 restore 语义。
func close_budget(original_context:Variant) -> Dictionary:
	if _budget_session(original_context).is_empty(): return _budget_rejected("budget_session_invalid")
	_retire_budget_session()
	return {"status":"COMPLETED", "reason":""}

## 来源必须由捕获调用者显式传入；不为旧对象补 current 票。
func capture(roots:Array, excluded:Dictionary = {}, context:Variant = null) -> bool:
	# 先撤旧票；新capture的任何失败都不能保活上一会话。
	_retire_budget_session()
	ready = false
	error = ""
	_captured_context = null
	var source:Dictionary = Generation.validate_context(context)
	if not source.ok:
		error = "回滚捕获来源无效: " + str(source.reason)
		return false
	_captured_context = context
	_objects.clear()
	_collections.clear()
	_collection_groups.clear()
	_pending = []
	for root in roots:
		_pending.append({"value":root, "path":[]})
	_comparisons = 0
	_values = 0
	_excluded = excluded
	_node_roots.clear()
	# 身份候选键只限当前进程；缺少目标ABI能力时失败关闭，不退回平方扫描。
	if not ClassDB.class_exists("FateCollectionIdentity"):
		error = "当前进程缺少集合身份索引扩展"
		_pending.clear()
		return false
	_identity_index = ClassDB.instantiate("FateCollectionIdentity")
	if _identity_index == null or not _identity_index.has_method("is_supported") or not _identity_index.has_method("candidate_key"):
		error = "集合身份索引扩展接口不完整"
		_pending.clear()
		return false
	if not _identity_index.call("is_supported", str(Engine.get_version_info().get("hash", ""))):
		error = "当前引擎集合身份索引ABI未验证"
		_pending.clear()
		return false
	for root in roots:
		if root is Node:
			_node_roots[root] = true
	while not _pending.is_empty() and error.is_empty():
		var task:Dictionary = _pending.pop_back()
		_collect(task.value, task.path)
	_pending.clear()
	ready = error.is_empty()
	if ready: _open_budget_session()
	return ready

func _queue(values:Array, path:Array) -> void:
	for value in values:
		if _pending.size() + _values >= max_capture_values:
			error = "回滚检查点超出待采集值预算"
			return
		_pending.append({"value":value, "path":path})

func _collect(value, path:Array) -> void:
	_values += 1
	if _values > max_capture_values:
		error = "回滚检查点超出值访问预算"
		return
	# 句柄与服务身份是图外资格；覆盖属性、Callable 参数和 WeakRef 路线。
	if value is Token or value is Context or value is Generation or value is BudgetLease:
		return
	if value is Array or value is Dictionary:
		if value.is_read_only():
			error = "规则集合没有原地恢复写入资格"
			return
		# 引用句柄候选键不依赖内容、长度或类型元数据；最终仍由is_same核验。
		var identity_key:int = _identity_index.call("candidate_key", value)
		if identity_key == 0:
			error = "集合身份索引没有有效引用句柄"
			return
		var group_key:String = "%s:%s" % [typeof(value), identity_key]
		var candidates:Array = _collection_groups.get(group_key, [])
		for record in candidates:
			_comparisons += 1
			if _comparisons > limits.max_capture_comparisons:
				error = "回滚检查点超出集合身份比较预算"
				return
			if is_same(record.target, value):
				return
		if _collections.size() >= limits.max_capture_collections:
			error = "回滚检查点超出集合预算"
			return
		var record:Dictionary = {"target":value, "items":value.duplicate()}
		_collections.append(record)
		candidates.append(record)
		_collection_groups[group_key] = candidates
		var next_path:Array = path.duplicate()
		next_path.append(value)
		if value is Dictionary:
			_queue(value.keys(), next_path)
			_queue(value.values(), next_path)
		else:
			_queue(value, next_path)
	elif value is Callable:
		# 延迟绑定 BaseFunc 的空句柄是完整可恢复的字面前态。
		if value.is_null(): return
		if not value.is_valid():
			error = "回滚调用目标已失效"
			return
		_queue(value.get_bound_arguments(), path)
		var target = value.get_object()
		# 规则 Callable 显式声明其脚本目标；只保留当前进程原句柄。
		if target is Node and target.get_script() != null: _node_roots[target] = true
		_pending.append({"value":target, "path":path})
	elif value is WeakRef:
		_pending.append({"value":value.get_ref(), "path":path})
	elif value is Object:
		if not is_instance_valid(value):
			error = "回滚对象已失效"
			return
		if _objects.has(value):
			return
		# 脚本代码与卡图仅作为不变引用保留，不属于可改写规则对象。
		if value is Script or value is Texture2D:
			return
		if value is Node and not _node_roots.has(value):
			error = "规则状态引用未声明的 Node"
			return
		if _objects.size() >= max_capture_objects:
			error = "回滚检查点超出对象预算"
			return
		if value is RandomNumberGenerator:
			_objects[value] = {"fields":{"seed":value.seed, "state":value.state}, "connections":{}}
			return
		if value.get_script() == null:
			error = "规则状态包含不可采集的内建对象"
			return
		var fields:Dictionary = Ids.script_fields(value, _excluded.get(value, []))
		var connections:Dictionary = {}
		for declaration in value.get_script().get_script_signal_list():
			var signal_value:Signal = Signal(value, declaration.name)
			connections[declaration.name] = signal_value.get_connections()
		_objects[value] = {"fields":fields, "connections":connections}
		_queue(fields.values(), path)
		_queue(connections.values(), path)
	elif typeof(value) == TYPE_RID:
		error = "规则状态包含不可采集的原生 RID"
	elif typeof(value) >= TYPE_PACKED_BYTE_ARRAY:
		# PackedArray 的别名恢复尚无契约，不能把不完整检查点当成可回滚。
		error = "规则状态包含尚未支持原地恢复的 PackedArray"

func restore() -> bool:
	if not ready:
		return false
	# 来源前门必须先于集合、对象、RNG、连接和派生恢复器的任何规则写。
	var source:Dictionary = Generation.validate_context(_captured_context)
	if not source.ok:
		error = "回滚来源无效: " + str(source.reason)
		return false
	# 在任何写入前验证全部目标；已释放对象不能靠新建同名对象替代。
	for object in _objects:
		if not is_instance_valid(object):
			error = "回滚对象已失效"
			return false
	for object in _objects:
		for connections in _objects[object].connections.values():
			for connection in connections:
				if not connection.callable.is_valid():
					error = "回滚信号连接目标已失效"
					return false
	for record in _collections:
		if record.target.is_read_only():
			error = "回滚集合不可原地写入"
			return false
	for record in _collections:
		record.target.clear()
		if record.target is Array:
			record.target.append_array(record.items)
		else:
			record.target.merge(record.items)
	for object in _objects:
		var record:Dictionary = _objects[object]
		for field in record.fields:
			object.set(field, record.fields[field])
		for name in record.connections:
			var signal_value:Signal = Signal(object, name)
			for connection in signal_value.get_connections():
				signal_value.disconnect(connection.callable)
			for connection in record.connections[name]:
				signal_value.connect(connection.callable, int(connection.flags))
	return true
