class_name RoomDataAssembler
extends RefCounted

const Catalog = preload("res://scripts/net/content/data_catalog.gd")
const Cache = preload("res://scripts/net/content/content_cache.gd")
## 显式工程预算：递增退避合计 700ms，额外等待小于 1 秒；不是实测最佳参数。
## 调用方可覆盖整张表；表长就是重试上限，空表禁用重试。
const DEFAULT_PUBLISH_RETRY_DELAYS_MSEC: Array[int] = [100, 200, 400]
var publish_retry_delays_msec: Array[int] = DEFAULT_PUBLISH_RETRY_DELAYS_MSEC.duplicate()
var _publish_retry_delays_msec: Array[int] = []
var _publish_retry_index: int = 0
var _publish_retry_started_msec: int = 0
var max_total_bytes: int = 2 * 1024 * 1024 * 1024
var max_files: int = 20000
var error: String = ""
## 失败观测仅保留标量与存在性；不暴露绝对路径、字节或凭据。
var diagnostic:Dictionary = {}

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
	while running:
		poll(2)
		if running and _publish_retry_index > 0:
			var remaining: int = _publish_retry_delays_msec[_publish_retry_index - 1] - (Time.get_ticks_msec() - _publish_retry_started_msec)
			if remaining > 0: OS.delay_msec(remaining)
	return complete

## destination 仅由本机分配；全部缓存预校验结束前不创建 staging。
func start(destination: String, files: Array, cache) -> bool:
	if _polling:
		diagnostic = {"phase":_phase,"index":_index,"reason":"组装正在执行，不接受重入"}
		return false
	cancel()
	error = ""
	diagnostic.clear()
	if DirAccess.dir_exists_absolute(destination) or FileAccess.file_exists(destination):
		return _reject("会话目录已存在，不覆盖")
	for delay in publish_retry_delays_msec:
		if delay <= 0: return _reject("发布重试退避必须为正毫秒数")
	_publish_retry_delays_msec = publish_retry_delays_msec.duplicate()
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
			if _publish_retry_index > 0 and Time.get_ticks_msec() - _publish_retry_started_msec < _publish_retry_delays_msec[_publish_retry_index - 1]: return
			var destination_directory_exists:bool = DirAccess.dir_exists_absolute(_destination)
			var destination_file_exists:bool = FileAccess.file_exists(_destination)
			var rename_attempted:bool = not destination_directory_exists and not destination_file_exists
			var rename_error:Error = DirAccess.rename_absolute(_staging, _destination) if rename_attempted else ERR_ALREADY_EXISTS
			if rename_error != OK:
				var details: Dictionary = {"destination_directory_exists":destination_directory_exists,"destination_file_exists":destination_file_exists,"staging_exists":DirAccess.dir_exists_absolute(_staging),"destination_length":_destination.length(),"staging_length":_staging.length(),"rename_attempted":rename_attempted,"rename_error":int(rename_error),"destination_parent_exists":DirAccess.dir_exists_absolute(_destination.get_base_dir())}
				if _publish_retry_index == 0:
					diagnostic = details.duplicate()
					diagnostic.merge({"phase":_phase,"index":_index,"files":_files.size(),"reason":"无法发布完整会话目录"})
					print("ROOM_DATA_ASSEMBLY_REJECT ", JSON.stringify(diagnostic))
				# Godot FAILED 折叠系统错误；这里只判定有界候选，不声称已识别 ACCESS_DENIED。
				var retryable: bool = rename_attempted and rename_error == FAILED and details.staging_exists and details.destination_parent_exists
				if retryable and _publish_retry_index < _publish_retry_delays_msec.size():
					_publish_retry_started_msec = Time.get_ticks_msec()
					_publish_retry_index += 1
					print("ROOM_DATA_ASSEMBLY_PUBLISH_RETRY ", JSON.stringify({"retry":_publish_retry_index,"delay_msec":_publish_retry_delays_msec[_publish_retry_index - 1]}))
					return
				print("ROOM_DATA_ASSEMBLY_PUBLISH_STOP ", JSON.stringify({"retries":_publish_retry_index,"final_rename_error":int(rename_error)}))
				_abort("无法发布完整会话目录", diagnostic)
				return
			if not diagnostic.is_empty(): print("ROOM_DATA_ASSEMBLY_PUBLISH_RECOVERED ", JSON.stringify({"retries":_publish_retry_index}))
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
	_publish_retry_delays_msec.clear()
	_publish_retry_index = 0
	_publish_retry_started_msec = 0

func _abort(reason: String, details:Dictionary = {}) -> void:
	diagnostic = details.duplicate()
	diagnostic.merge({"phase":_phase,"index":_index,"files":_files.size(),"reason":reason})
	# 在 cleanup 前记录原失败现场，不以另一次成功组装代替这次错误。
	print("ROOM_DATA_ASSEMBLY_REJECT ",JSON.stringify(diagnostic))
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
