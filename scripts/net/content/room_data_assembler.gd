class_name RoomDataAssembler
extends RefCounted

const Catalog = preload("res://scripts/net/content/data_catalog.gd")
const Cache = preload("res://scripts/net/content/content_cache.gd")
var max_total_bytes: int = 2 * 1024 * 1024 * 1024
var max_files: int = 20000
var error: String = ""

var running: bool = false
var complete: bool = false
var _destination: String = ""
var _staging: String = ""
var _files: Array = []
var _cache
var _created: Array = []
var _index: int = 0
var _phase: String = "idle"
var _generation: int = 0
var _polling: bool = false

## 同步调用兼容；联机准备使用 start/poll，批次之间返回原主循环。
func assemble(destination: String, files: Array, cache) -> bool:
	if not start(destination, files, cache): return false
	while running: poll(2)
	return complete

## destination 仅由本机分配；全部缓存预校验结束前不创建 staging。
func start(destination: String, files: Array, cache) -> bool:
	if _polling: return false
	cancel()
	error = ""
	if DirAccess.dir_exists_absolute(destination) or FileAccess.file_exists(destination):
		return _reject("会话目录已存在，不覆盖")
	if not validate(files, cache.max_file_bytes): return false
	_destination = destination
	_files = files.duplicate(true)
	_cache = cache
	_index = 0
	_phase = "check"
	running = true
	return true

func poll(files_per_poll: int = 2) -> void:
	if _polling or not running: return
	if files_per_poll <= 0:
		_abort("组装批次预算无效")
		return
	_polling = true
	_step(files_per_poll, _generation)
	_polling = false

func _step(budget: int, generation: int) -> void:
	for _unused in range(budget):
		if not running or generation != _generation: return
		if _index == _files.size():
			if _phase == "check":
				_staging = _destination + ".building-" + str(Time.get_ticks_usec())
				if DirAccess.make_dir_recursive_absolute(_staging) != OK:
					_abort("无法创建会话临时目录")
					return
				_phase = "write"
				_index = 0
				return
			# 独立的发布步骤：取消或失败时永远不发布半成品。
			if DirAccess.dir_exists_absolute(_destination) or FileAccess.file_exists(_destination) or DirAccess.rename_absolute(_staging, _destination) != OK:
				_abort("无法发布完整会话目录")
				return
			_staging = ""
			_created.clear()
			running = false
			complete = true
			return
		var item: Dictionary = _files[_index]
		var bytes: PackedByteArray = _cache.fetch(item.hash)
		if not running or generation != _generation: return
		if bytes.size() != item.size or Cache.digest(bytes) != item.hash:
			_abort("缓存缺失或组装期间缓存失效：" + item.path)
			return
		if _phase == "write":
			var target: String = _staging.path_join(item.path)
			# 先登记拥有的路径，创建目录后 open 失败也可清理空目录。
			_created.append(item.path)
			if DirAccess.make_dir_recursive_absolute(target.get_base_dir()) != OK:
				_abort("无法创建数据子目录")
				return
			var file := FileAccess.open(target, FileAccess.WRITE)
			if file == null:
				_abort("无法写入数据文件")
				return
			file.store_buffer(bytes)
			file.flush()
			var result := file.get_error()
			file.close()
			if result != OK or FileAccess.get_sha256(target) != item.hash:
				_abort("会话文件写入校验失败")
				return
		_index += 1

func cancel() -> void:
	_generation += 1
	running = false
	complete = false
	if not _staging.is_empty(): _cleanup(_staging, _created)
	_staging = ""
	_created.clear()
	_files.clear()
	_cache = null
	_phase = "idle"

func _abort(reason: String) -> void:
	cancel()
	error = reason

func validate(files: Array, max_file_bytes: int) -> bool:
	error = ""
	if files.is_empty() or files.size() > max_files:
		return _reject("文件清单数量无效")
	var paths: Dictionary = {}
	var total: int = 0
	for item in files:
		if not item is Dictionary or not item.get("path") is String or not item.get("hash") is String or not item.get("size") is int:
			return _reject("文件清单字段无效")
		if not _portable_path(item.path) or not Cache.valid_key(item.hash):
			return _reject("文件路径或校验值无效")
		if item.size < 0 or item.size > max_file_bytes or item.size > max_total_bytes - total:
			return _reject("文件大小超过接收预算")
		var key: String = item.path.to_lower()
		if paths.has(key):
			return _reject("文件路径重复或大小写冲突")
		paths[key] = true
		total += item.size
	for path in paths:
		var parent: String = path.get_base_dir()
		while not parent.is_empty():
			if paths.has(parent):
				return _reject("文件与目录路径冲突")
			parent = parent.get_base_dir()
	return true

static func _portable_path(path: String) -> bool:
	if not Catalog.safe_path(path) or path.get_extension().to_lower() not in Catalog.EXTENSIONS:
		return false
	for part in path.split("/"):
		if part.ends_with(".") or part.ends_with(" "):
			return false
		for character in part:
			if character.unicode_at(0) < 32 or character in "<>\"|?*":
				return false
		var stem: String = part.split(".")[0].to_upper()
		if stem in ["CON", "PRN", "AUX", "NUL"] or (stem.length() == 4 and (stem.begins_with("COM") or stem.begins_with("LPT")) and stem[3] in "123456789"):
			return false
	return true

func _cleanup(staging: String, created: Array) -> void:
	# 只删除本次建立的目录，不遍历外部链接或原始 data。
	var directories: Array = []
	for relative in created:
		DirAccess.remove_absolute(staging.path_join(relative))
		var parent: String = relative.get_base_dir()
		while not parent.is_empty():
			if not directories.has(parent):
				directories.append(parent)
			parent = parent.get_base_dir()
	directories.sort_custom(func(a, b): return a.length() > b.length())
	for relative in directories:
		DirAccess.remove_absolute(staging.path_join(relative))
	DirAccess.remove_absolute(staging)

func _reject(reason: String) -> bool:
	error = reason
	return false
