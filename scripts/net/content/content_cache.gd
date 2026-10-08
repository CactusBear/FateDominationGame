class_name MatchContentCache
extends RefCounted

const AtomicReplace = preload("res://scripts/io/atomic_file_replace.gd")
const Paths = preload("res://scripts/net/server/recovery_path_safety.gd")

## 只存已校验的内容块；不解释 JSON、不解压、不执行文件。
var root: String = "user://net_cache/blobs"
var max_file_bytes: int = 64 * 1024 * 1024
# 本实例只解除自己持有的引用；清理入口共用规范路径的全局引用表。
var _pins: Dictionary = {}
static var _shared_pins: Dictionary = {}
static var _lifecycle_lock: Mutex = Mutex.new()
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
	_lifecycle_lock.lock()
	var result := _store_locked(key, bytes)
	_lifecycle_lock.unlock()
	return result

func _store_locked(key: String, bytes: PackedByteArray) -> bool:
	error = ""
	# 网络接收协议要求正长度，缓存拒绝空字节，避免同时表示命中和未命中。
	if not valid_key(key) or bytes.is_empty() or bytes.size() > max_file_bytes or digest(bytes) != key:
		error = "缓存大小或校验值无效"
		return false
	var ancestor: String = Paths.absolute(root)
	if ancestor.is_empty():
		error = "缓存路径无效"
		return false
	while not DirAccess.dir_exists_absolute(ancestor):
		var parent := ancestor.get_base_dir()
		if parent.length() == 2 and parent[1] == ":": parent += "/"
		if parent == ancestor or parent.is_empty():
			error = "缓存路径无效"
			return false
		ancestor = parent
	# 已存在目录不需要创建；目标检查仍在任何缓存读取/写入前逐层检查所有祖先。
	# 不保存安全批准：每次调用和发布前仍使用原 Paths.checked。
	if ancestor != Paths.absolute(root):
		if not Paths.checked(ancestor, root, true):
			error = "缓存路径不安全"
			return false
		if DirAccess.make_dir_recursive_absolute(root) != OK:
			error = "无法创建缓存目录"
			return false
	var destination := root.path_join(key)
	if not Paths.checked(root, destination, true):
		error = "缓存目标路径不安全"
		return false
	if FileAccess.file_exists(destination) and _fetch_locked(key, false) == bytes:
		return true

	var nonce := Crypto.new().generate_random_bytes(16)
	if nonce.size() != 16:
		error = "无法生成专属缓存临时路径"
		return false
	var temporary := destination + "." + nonce.hex_encode() + ".part"
	if not Paths.checked(root, temporary, true) or FileAccess.file_exists(temporary) or DirAccess.dir_exists_absolute(temporary):
		error = "缓存临时路径已被占用"
		return false
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		error = "无法写入缓存"
		return false
	file.store_buffer(bytes)
	var write_error := file.get_error()
	file.flush()
	var flush_error := file.get_error()
	file.close()
	if write_error != OK or flush_error != OK or not _temporary_matches(temporary, key, bytes.size()):
		if Paths.checked(root, temporary): DirAccess.remove_absolute(temporary)
		error = "缓存写入或读回校验失败"
		return false
	var published: bool = false
	if Paths.checked(root, temporary) and Paths.checked(root, destination, true):
		if FileAccess.file_exists(destination):
			published = AtomicReplace.replace_validated_file(temporary, destination, bytes.size()).get("ok", false) == true
		elif not DirAccess.dir_exists_absolute(destination):
			published = DirAccess.rename_absolute(temporary, destination) == OK
	if not published:
		if Paths.checked(root, temporary): DirAccess.remove_absolute(temporary)
		error = "缓存落盘失败，已保留旧目标"
		return false
	return true

func _temporary_matches(path: String, key: String, size: int) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	if file.get_length() != size:
		file.close()
		return false
	var bytes := file.get_buffer(size)
	var result := file.get_error()
	file.close()
	return result == OK and bytes.size() == size and digest(bytes) == key

func fetch(key: String) -> PackedByteArray:
	_lifecycle_lock.lock()
	var bytes := _fetch_locked(key)
	_lifecycle_lock.unlock()
	return bytes

func _fetch_locked(key: String, clean_corrupt: bool = true) -> PackedByteArray:
	if not valid_key(key):
		return PackedByteArray()
	var path := root.path_join(key)
	var dir := DirAccess.open(root)
	# 不跟随显式链接；这不是同权限攻击者下的无竞态文件操作。
	if dir == null or dir.is_link(key):
		return PackedByteArray()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	var size := file.get_length()
	if size <= 0 or size > max_file_bytes:
		file.close()
		if clean_corrupt:
			_remove_corrupt_locked(key)
		return PackedByteArray()
	var bytes := file.get_buffer(size)
	var result := file.get_error()
	file.close()
	if result != OK or bytes.size() != size or digest(bytes) != key:
		if clean_corrupt:
			_remove_corrupt_locked(key)
		return PackedByteArray()
	return bytes

func _remove_corrupt_locked(key: String) -> void:
	# 在途/组装持有者的路径不能被清理；稍后 fetch 或 clear 可重试。
	if _shared_pins.has(_identity(key)):
		return
	var dir := DirAccess.open(root)
	if dir != null and not dir.is_link(key) and key in dir.get_files():
		dir.remove(key)

func _identity(key: String) -> String:
	var path := ProjectSettings.globalize_path(root).replace("\\", "/").simplify_path().path_join(key)
	return path.to_lower() if OS.get_name() == "Windows" else path

func pin(key: String) -> String:
	if not valid_key(key):
		return ""
	_lifecycle_lock.lock()
	var path := _identity(key)
	_pins[path] = int(_pins.get(path, 0)) + 1
	_shared_pins[path] = int(_shared_pins.get(path, 0)) + 1
	_lifecycle_lock.unlock()
	return path

func unpin(key: String, pinned_path: String = "") -> void:
	if not valid_key(key):
		return
	_lifecycle_lock.lock()
	var path := _identity(key) if pinned_path.is_empty() else pinned_path
	# 显式 token 只可解除本实例、该 key 原来持有的路径。
	if path.get_file() == key and _pins.has(path):
		_release_pin_locked(path, 1)
	_lifecycle_lock.unlock()

func _release_pin_locked(path: String, count: int) -> void:
	_pins[path] -= count
	_shared_pins[path] -= count
	if _pins[path] <= 0:
		_pins.erase(path)
	if _shared_pins[path] <= 0:
		_shared_pins.erase(path)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_lifecycle_lock.lock()
		for path in _pins.keys():
			_release_pin_locked(path, int(_pins[path]))
		_lifecycle_lock.unlock()

func clear_unused() -> int:
	_lifecycle_lock.lock()
	var removed := _clear_unused_locked()
	_lifecycle_lock.unlock()
	return removed

func _clear_unused_locked() -> int:
	var dir := DirAccess.open(root)
	if dir == null:
		return 0
	var removed := 0
	for key in dir.get_files():
		if dir.is_link(key):
			continue
		var blob_key := key if valid_key(key) else _part_key(key)
		if not blob_key.is_empty() and not _shared_pins.has(_identity(blob_key)):
			if dir.remove(key) == OK:
				removed += 1
	return removed

static func _part_key(name: String) -> String:
	# 仅识别本组件的 <sha256>.<32位随机hex>.part，不泛删 *.part。
	var parts := name.split(".")
	if parts.size() != 3 or parts[2] != "part" or not valid_key(parts[0]):
		return ""
	if parts[1].length() != 32 or not valid_key(parts[1] + parts[1]):
		return ""
	return parts[0]

func usage() -> Dictionary:
	_lifecycle_lock.lock()
	var result := {"files": 0, "bytes": 0, "pinned": 0}
	var dir := DirAccess.open(root)
	if dir != null:
		for key in dir.get_files():
			if valid_key(key) and not dir.is_link(key):
				var file := FileAccess.open(root.path_join(key), FileAccess.READ)
				if file != null:
					result.files += 1
					result.bytes += file.get_length()
					file.close()
				if _shared_pins.has(_identity(key)):
					result.pinned += 1
	_lifecycle_lock.unlock()
	return result
