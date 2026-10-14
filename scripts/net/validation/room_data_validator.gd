class_name RoomDataValidator
extends RefCounted

var errors: Array = []
var max_json_depth: int = 128
var max_file_bytes: int = 64 * 1024 * 1024
## 本机执行预算；只并行独立文件I/O、哈希及纯JSON解析。
var file_worker_count:int = 20
## 可选本机观测；累计文件 CPU/I/O 时间不等于并行墙钟，不保存内容。
var profile_enabled:bool = false
var performance:Dictionary = {}

## JSON 只定义一种数字类型；只转换已经证明为预算内整数的大小字段。
func parse_manifest(text: String):
	var parsed := JSON.new()
	if parsed.parse(text) != OK or not parsed.data is Array:
		return null
	for item in parsed.data:
		if not item is Dictionary:
			return null
		var size = item.get("size")
		if not (size is int or size is float) or not is_finite(float(size)) or size < 0 or size > max_file_bytes or floor(float(size)) != float(size):
			return null
		item.size = int(size)
	return parsed.data

func validate(directory: String, files: Array) -> bool:
	errors.clear()
	performance.clear()
	var started_usec:int = Time.get_ticks_usec() if profile_enabled else 0
	if file_worker_count <= 0:
		errors.append("文件校验线程预算必须大于零")
		return false
	var assembler = preload("res://scripts/net/content/room_data_assembler.gd").new()
	if not assembler.validate(files, max_file_bytes):
		errors.append(assembler.error)
		return false
	var selected:Array = files.duplicate(true)
	var results:Array = []
	results.resize(selected.size())
	if file_worker_count == 1 or selected.size() <= 1:
		for index in range(selected.size()): results[index] = _read_file_result(directory, selected[index])
	else:
		var lock := Mutex.new()
		var task:int = WorkerThreadPool.add_group_task(_read_group_file.bind(directory, selected, results, lock), selected.size(), mini(file_worker_count, selected.size()), false, "Room file validation")
		if task < 0:
			errors.append("无法创建文件校验任务")
			return false
		WorkerThreadPool.wait_for_group_task_completion(task)
	# 线程任务不访问全局规则对象；引用检查与错误汇总保持原顺序。
	var references_usec:int = Time.get_ticks_usec() if profile_enabled else 0
	if profile_enabled:
		performance = {"file_phase_wall_usec":references_usec-started_usec,"read_sum_usec":0,"hash_sum_usec":0,"json_sum_usec":0}
	for index in range(selected.size()):
		var result:Dictionary = results[index]
		if profile_enabled:
			for key in ["read_sum_usec","hash_sum_usec","json_sum_usec"]: performance[key] += result.get(key,0)
		if not result.error.is_empty(): errors.append(result.error)
		elif result.document != null: check_value(result.document, selected[index].path)
	if profile_enabled: performance.references_wall_usec = Time.get_ticks_usec() - references_usec
	return errors.is_empty()

func _read_group_file(index:int, directory:String, files:Array, results:Array, lock:Mutex) -> void:
	var result:Dictionary = _read_file_result(directory, files[index])
	lock.lock()
	results[index] = result
	lock.unlock()

func _read_file_result(directory:String, item:Dictionary) -> Dictionary:
	var rejected:Dictionary = {"error":"批准文件校验失败：" + item.path, "document":null}
	var started_usec:int = Time.get_ticks_usec() if profile_enabled else 0
	var file := FileAccess.open(directory.path_join(item.path), FileAccess.READ)
	if file == null: return rejected
	if file.get_length() != item.size:
		file.close()
		return rejected
	var content:PackedByteArray = file.get_buffer(item.size)
	var read_error:Error = file.get_error()
	file.close()
	var hash_usec:int = Time.get_ticks_usec() if profile_enabled else 0
	if read_error != OK or content.size() != item.size or preload("res://scripts/net/content/content_cache.gd").digest(content) != item.hash: return rejected
	var json_usec:int = Time.get_ticks_usec() if profile_enabled else 0
	var result:Dictionary = {"error":"", "document":null}
	if profile_enabled:
		result.read_sum_usec = hash_usec - started_usec
		result.hash_sum_usec = json_usec - hash_usec
		result.json_sum_usec = 0
	if item.path.get_extension().to_lower() != "json": return result
	var parsed := JSON.new()
	if parsed.parse(content.get_string_from_utf8()) != OK:
		return {"error":"JSON 解析失败：%s:%d %s" % [item.path, parsed.get_error_line(), parsed.get_error_message()], "document":null}
	if not (parsed.data is Dictionary or parsed.data is Array):
		return {"error":"JSON 根节点不是对象或数组：" + item.path, "document":null}
	result.document = parsed.data
	if profile_enabled: result.json_sum_usec = Time.get_ticks_usec() - json_usec
	return result

## 只检验可执行操作引用，不把普通字符串或角色名字推断为依赖。
func check_value(value, source: String, depth: int = 0, query_scope: bool = false) -> bool:
	if depth > max_json_depth:
		errors.append("JSON 嵌套超过校验预算：" + source)
		return false
	var valid := true
	if value is Dictionary:
		if value.has("func_name"):
			var supported: bool = value.func_name is String
			if supported:
				supported = BoardPowerQuery.supports_descriptor(value.func_name) if query_scope else AllOperations.TABLE.has(value.func_name)
			if not supported:
				errors.append("未登记的操作：%s %s" % [source, str(value.func_name)])
				valid = false
		for key in value:
			if not check_value(value[key], source, depth + 1, query_scope or key == "power_query"):
				valid = false
	elif value is Array:
		for item in value:
			if not check_value(item, source, depth + 1, query_scope):
				valid = false
	return valid
