class_name NetIds
extends RefCounted

## ID 只在当前会话有效，弱引用不延长游戏对象生命周期；不按名字猜对象。
var error: String = ""
var data_root: String = ""
var _by_instance: Dictionary = {}
var _objects: Array = [null]
var _visited: Dictionary = {}
var _definitions: Array = []
var _capturing: bool = false
var _prefixes: Array = []
var max_capture_collections: int = 100000
var max_capture_comparisons: int = 1000000
var _capture_comparisons: int = 0
var _capture_collections: bool = false
var _collection_groups: Dictionary = {}
var _collections: Array = []
static var _field_names: Dictionary = {}

func id_for(object: Object) -> int:
	var instance: int = object.get_instance_id()
	if _by_instance.has(instance):
		return int(_by_instance[instance])
	var id := _objects.size()
	_by_instance[instance] = id
	_objects.append(weakref(object))
	return id

func object_for(id: int):
	if id <= 0 or id >= _objects.size():
		error = "存档引用未知对象 ID: %d" % id
		return null
	var object = _objects[id].get_ref()
	if object == null:
		error = "存档引用已释放对象 ID: %d" % id
	return object

func encode(value, depth: int = 0):
	if _capture_collections and not error.is_empty():
		return null
	if depth > 128:
		error = "存档数据嵌套过深"
		return null
	if value is WeakRef:
		return encode(value.get_ref(), depth + 1)
	if value is Object:
		var id := id_for(value)
		if _capturing and not _visited.has(id):
			_visited[id] = true
			var definition := {"id": id, "script": str(value.get_script().resource_path) if value.get_script() else value.get_class(), "fields": null}
			_definitions.append(definition)
			definition.fields = encode(script_fields(value), depth + 1)
		return ["ref", id]
	if value is Array:
		if _capture_collections:
			return _encode_collection(value, depth)
		var items: Array = []
		for item in value:
			items.append(encode(item, depth + 1))
		return ["array", items]
	if value is Dictionary:
		if _capture_collections:
			return _encode_collection(value, depth)
		var pairs: Array = []
		for key in value:
			pairs.append([encode(key, depth + 1), encode(value[key], depth + 1)])
		return ["dict", pairs]
	if value is Callable:
		# Callable 不反序列化执行。定义校验只保存绑定目标与方法，恢复由原代码重新构造。
		return ["callable", str(value.get_method()), encode(value.get_object(), depth + 1), encode(value.get_bound_arguments(), depth + 1)]
	if value is Signal:
		return ["signal", str(value.get_name())]
	if typeof(value) in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING]:
		if _capturing and value is String and not data_root.is_empty():
			for prefix in _prefixes:
				if value.begins_with(prefix + "/"):
					return ["value", "<session-data>/" + value.substr(prefix.length() + 1)]
		return ["value", value]
	if value is StringName or value is NodePath:
		return ["value", str(value)]
	error = "存档不支持的类型: %s" % type_string(typeof(value))
	return null

func decode(value, depth: int = 0):
	if depth > 128 or not value is Array or value.size() != 2:
		error = "存档参数编码无效"
		return null
	match value[0]:
		"value":
			if typeof(value[1]) not in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING]:
				error = "存档字面量类型无效"
				return null
			return value[1]
		"ref":
			if not value[1] is int:
				error = "存档对象 ID 类型无效"
				return null
			return object_for(int(value[1]))
		"array":
			if not value[1] is Array:
				error = "存档数组类型无效"
				return null
			var items: Array = []
			for item in value[1]:
				items.append(decode(item, depth + 1))
			return items if error.is_empty() else null
		"dict":
			if not value[1] is Array:
				error = "存档字典类型无效"
				return null
			var result: Dictionary = {}
			for pair in value[1]:
				if not pair is Array or pair.size() != 2:
					error = "存档字典条目无效"
					return null
				var key = decode(pair[0], depth + 1)
				result[key] = decode(pair[1], depth + 1)
			return result if error.is_empty() else null
	error = "存档参数不能包含可执行类型"
	return null

func snapshot(roots: Dictionary) -> Dictionary:
	return _snapshot(roots, false)

## 仅供单向状态检查；集合引用不交给 decode 还原为可执行输入。
func snapshot_graph(roots: Dictionary) -> Dictionary:
	return _snapshot(roots, true)

func _snapshot(roots: Dictionary, collections: bool) -> Dictionary:
	error = ""
	_prefixes = [data_root, ProjectSettings.globalize_path(data_root)] if not data_root.is_empty() else []
	_visited.clear()
	_definitions = []
	_collection_groups.clear()
	_collections = []
	_capture_comparisons = 0
	_capture_collections = collections
	_capturing = true
	var state = encode(roots)
	_capturing = false
	_capture_collections = false
	var result := {"roots": state, "objects": _definitions.duplicate()}
	if collections:
		result["collections"] = _collections.duplicate()
	# 引用只在本次遍历期间保活，不让状态检查延长原始集合的生命周期。
	_collection_groups.clear()
	_collections.clear()
	return result

func _encode_collection(value, depth: int):
	# 不能用值相等或内容哈希替代引用比较；循环集合也不能先递归求哈希。
	var group_key := "%s:%s" % [typeof(value), value.size()]
	var candidates: Array = _collection_groups.get(group_key, [])
	for candidate in candidates:
		_capture_comparisons += 1
		if max_capture_comparisons <= 0 or _capture_comparisons > max_capture_comparisons:
			error = "状态采集超出集合身份比较预算"
			return null
		if is_same(candidate.value, value):
			return ["collection_ref", candidate.id]
	if max_capture_collections <= 0 or _collections.size() >= max_capture_collections:
		error = "状态采集超出集合预算"
		return null
	var id := _collections.size() + 1
	candidates.append({"value": value, "id": id})
	_collection_groups[group_key] = candidates
	var definition := {"id": id, "kind": "array" if value is Array else "dict", "items": []}
	var declaration = value.duplicate()
	declaration.clear()
	definition["declaration"] = var_to_bytes(declaration).hex_encode()
	_collections.append(definition)
	if value is Array:
		for item in value:
			definition.items.append(encode(item, depth + 1))
	else:
		for key in value:
			definition.items.append([encode(key, depth + 1), encode(value[key], depth + 1)])
	return ["collection_ref", id]

static func script_fields(object: Object, excluded: Array = []) -> Dictionary:
	var fields: Dictionary = {}
	var script = object.get_script()
	if not _field_names.has(script):
		var keys: Array = []
		for property in object.get_property_list():
			if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
				keys.append(str(property.name))
		keys.sort()
		_field_names[script] = keys
	for key in _field_names[script]:
		if not excluded.has(key):
			fields[key] = object.get(key)
	return fields
