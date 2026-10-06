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

func capture(roots:Array, excluded:Dictionary = {}) -> bool:
	ready = false
	error = ""
	_objects.clear()
	_collections.clear()
	_pending = []
	for root in roots:
		_pending.append({"value":root, "path":[]})
	_comparisons = 0
	_excluded = excluded
	_node_roots.clear()
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
		_pending.append({"value":value, "path":path})

func _collect(value, path:Array) -> void:
	if value is Array or value is Dictionary:
		for ancestor in path:
			_comparisons += 1
			if _comparisons > limits.max_capture_comparisons:
				error = "回滚检查点超出集合身份比较预算"
				return
			if is_same(ancestor, value):
				return
		if _collections.size() >= limits.max_capture_collections:
			error = "回滚检查点超出集合预算"
			return
		var record:Dictionary = {"target":value, "items":value.duplicate()}
		_collections.append(record)
		var next_path:Array = path.duplicate()
		next_path.append(value)
		if value is Dictionary:
			_queue(value.keys(), next_path)
			_queue(value.values(), next_path)
		else:
			_queue(value, next_path)
	elif value is Callable:
		_queue(value.get_bound_arguments(), path)
	elif value is WeakRef:
		_pending.append({"value":value.get_ref(), "path":path})
	elif value is Object:
		if not is_instance_valid(value):
			error = "回滚对象已失效"
			return
		if _objects.has(value) or (value is Node and not _node_roots.has(value)) or value.get_script() == null:
			return
		var fields:Dictionary = Ids.script_fields(value, _excluded.get(value, []))
		var connections:Dictionary = {}
		for declaration in value.get_script().get_script_signal_list():
			var signal_value:Signal = Signal(value, declaration.name)
			connections[declaration.name] = signal_value.get_connections()
		_objects[value] = {"fields":fields, "connections":connections}
		_queue(fields.values(), path)
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
