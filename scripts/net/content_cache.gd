class_name MatchContentCache
extends RefCounted

## 只存已校验的内容块；不解释 JSON、不解压、不执行文件。
var root: String = "user://net_cache/blobs"
var max_file_bytes: int = 64 * 1024 * 1024
var _pins: Dictionary = {}
var error: String = ""

static func digest(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()

static func valid_key(key: String) -> bool:
	if key.length() != 64:
		return false
	for character in key:
		if character not in "0123456789abcdef":
			return false
	return true

func store(key: String, bytes: PackedByteArray) -> bool:
	error = ""
	if not valid_key(key) or bytes.size() > max_file_bytes or digest(bytes) != key:
		error = "缓存大小或校验值无效"
		return false
	if DirAccess.make_dir_recursive_absolute(root) != OK:
		error = "无法创建缓存目录"
		return false
	var destination := root.path_join(key)
	if FileAccess.file_exists(destination) and fetch(key) == bytes:
		return true
	var temporary := destination + ".part"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		error = "无法写入缓存"
		return false
	file.store_buffer(bytes)
	file.flush()
	var result := file.get_error()
	file.close()
	if result != OK:
		error = "缓存写入失败"
		return false
	if FileAccess.file_exists(destination):
		DirAccess.remove_absolute(destination)
	if DirAccess.rename_absolute(temporary, destination) != OK:
		error = "缓存落盘失败"
		return false
	return true

func fetch(key: String) -> PackedByteArray:
	if not valid_key(key):
		return PackedByteArray()
	var path := root.path_join(key)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > max_file_bytes:
		return PackedByteArray()
	var bytes := file.get_buffer(file.get_length())
	file.close()
	return bytes if digest(bytes) == key else PackedByteArray()

func pin(key: String) -> void:
	if valid_key(key):
		_pins[key] = int(_pins.get(key, 0)) + 1

func unpin(key: String) -> void:
	if not _pins.has(key):
		return
	_pins[key] -= 1
	if _pins[key] <= 0:
		_pins.erase(key)

func clear_unused() -> int:
	var dir := DirAccess.open(root)
	if dir == null:
		return 0
	var removed := 0
	for key in dir.get_files():
		if valid_key(key) and not _pins.has(key) and not dir.is_link(key):
			if dir.remove(key) == OK:
				removed += 1
	return removed

func usage() -> Dictionary:
	var result := {"files": 0, "bytes": 0, "pinned": _pins.size()}
	var dir := DirAccess.open(root)
	if dir != null:
		for key in dir.get_files():
			if valid_key(key) and not dir.is_link(key):
				var file := FileAccess.open(root.path_join(key), FileAccess.READ)
				if file != null:
					result.files += 1
					result.bytes += file.get_length()
	return result
