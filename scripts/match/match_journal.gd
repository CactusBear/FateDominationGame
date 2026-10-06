class_name MatchJournal
extends RefCounted

## 仅保存基础 Variant 的带长度帧日志。哈希用于检测损坏，不是身份认证。
const MAGIC := "FATEJNL1"
const MAX_FRAME_BYTES := 16 * 1024 * 1024
var error: String = ""
var _file: FileAccess
var _sequence: int = 0
var _previous: PackedByteArray = PackedByteArray()

func create(path: String, header: Dictionary) -> bool:
	close()
	error = ""
	if FileAccess.file_exists(path):
		error = "存档已存在，不覆盖"
		return false
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
		error = "无法创建存档目录"
		return false
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		error = "无法创建存档"
		return false
	_file.store_buffer(MAGIC.to_ascii_buffer())
	_sequence = 0
	_previous = PackedByteArray()
	return append(header)

func append(record: Dictionary) -> bool:
	if _file == null or not error.is_empty():
		return false
	if not _plain(record):
		error = "存档不接受可执行对象或调用句柄"
		return false
	var body := var_to_bytes({"sequence": _sequence, "record": record})
	if body.size() > MAX_FRAME_BYTES:
		error = "存档记录超出大小上限"
		return false
	var digest := _digest(_previous + body)
	_file.store_32(body.size())
	_file.store_buffer(digest)
	_file.store_buffer(body)
	_file.flush()
	if _file.get_error() != OK:
		error = "存档写入失败"
		return false
	_previous = digest
	_sequence += 1
	return true

func close() -> void:
	if _file != null:
		_file.close()
	_file = null

func resume(path: String) -> bool:
	close()
	error = ""
	var parsed := read_all(path)
	if not parsed.ok or parsed.truncated:
		error = "不能续写损坏或截断的存档"
		return false
	_previous = PackedByteArray()
	_sequence = 0
	for record in parsed.records:
		var body := var_to_bytes({"sequence": _sequence, "record": record})
		_previous = _digest(_previous + body)
		_sequence += 1
	_file = FileAccess.open(path, FileAccess.READ_WRITE)
	if _file == null:
		error = "无法打开存档续写"
		return false
	_file.seek_end()
	return true

func read_all(path: String) -> Dictionary:
	var result := {"ok": false, "records": [], "truncated": false, "error": "", "error_index": -1}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		result.error = "无法读取存档"
		return result
	if file.get_buffer(MAGIC.length()).get_string_from_ascii() != MAGIC:
		result.error = "存档格式不兼容"
		return result
	var previous := PackedByteArray()
	while file.get_position() < file.get_length():
		var index: int = result.records.size()
		if file.get_length() - file.get_position() < 36:
			result.truncated = true
			break
		var length := file.get_32()
		if length <= 0 or length > MAX_FRAME_BYTES:
			result.error = "记录长度无效"
			result.error_index = index
			return result
		var digest := file.get_buffer(32)
		if file.get_length() - file.get_position() < length:
			result.truncated = true
			break
		var body := file.get_buffer(length)
		if _digest(previous + body) != digest:
			result.error = "记录校验失败"
			result.error_index = index
			return result
		var frame = bytes_to_var(body)
		if not frame is Dictionary or frame.get("sequence") != index or not frame.get("record") is Dictionary or not _plain(frame):
			result.error = "记录序号或内容无效"
			result.error_index = index
			return result
		result.records.append(frame.record)
		previous = digest
	result.ok = not result.records.is_empty()
	if not result.ok:
		result.error = "存档缺少完整文件头"
	return result

static func _digest(bytes: PackedByteArray) -> PackedByteArray:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish()

static func _plain(value, depth: int = 0) -> bool:
	if depth > 128:
		return false
	if value is Array:
		for item in value:
			if not _plain(item, depth + 1):
				return false
		return true
	if value is Dictionary:
		for key in value:
			if not _plain(key, depth + 1) or not _plain(value[key], depth + 1):
				return false
		return true
	return typeof(value) in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_PACKED_BYTE_ARRAY]
