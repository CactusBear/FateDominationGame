class_name RoomDataValidator
extends RefCounted

var errors: Array = []
var max_json_depth: int = 128
var max_file_bytes: int = 64 * 1024 * 1024

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
	var assembler = preload("res://scripts/net/room_data_assembler.gd").new()
	if not assembler.validate(files, max_file_bytes):
		errors.append(assembler.error)
		return false
	for item in files:
		var path: String = directory.path_join(item.path)
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null or file.get_length() != item.size or FileAccess.get_sha256(path) != item.hash:
			errors.append("批准文件校验失败：" + item.path)
			continue
		if item.path.get_extension().to_lower() != "json":
			continue
		var parsed := JSON.new()
		if parsed.parse(file.get_as_text()) != OK:
			errors.append("JSON 解析失败：%s:%d %s" % [item.path, parsed.get_error_line(), parsed.get_error_message()])
			continue
		if not (parsed.data is Dictionary or parsed.data is Array):
			errors.append("JSON 根节点不是对象或数组：" + item.path)
			continue
		check_value(parsed.data, item.path)
	return errors.is_empty()

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
