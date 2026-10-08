extends RefCounted

## 仅在同一权威进程中恢复原对象，不编码/执行网络对象或 Callable。
const Ids = preload("res://scripts/match/net_ids.gd")
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

func capture(roots:Array, excluded:Dictionary = {}) -> bool:
	ready = false
	error = ""
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
	elif typeof(value) == TYPE_RID:
		error = "规则状态包含不可采集的原生 RID"
	elif typeof(value) >= TYPE_PACKED_BYTE_ARRAY:
		# PackedArray 的别名恢复尚无契约，不能把不完整检查点当成可回滚。
		error = "规则状态包含尚未支持原地恢复的 PackedArray"

func restore() -> bool:
	if not ready:
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
