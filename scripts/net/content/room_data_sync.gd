class_name RoomDataSync
extends RefCounted

## 调用方提供已批准的完整文件清单；本组件不授予数据来源信任。
var timeout_seconds: float = 30.0
var running: bool = false
var complete: bool = false
var error: String = ""
var completed_files: int = 0
## 仅由本机调用方提供，网络清单不能指定读取根。
var local_roots:Array = []
var max_local_files:int = 20000
var _local_candidates:Array = []
var _local_index:int = 0
var _required_hashes:Dictionary = {}
var _required_sizes:Dictionary = {}
var assembler = preload("res://scripts/net/content/room_data_assembler.gd").new()
var _session
var _files: Array = []
var _destination: String = ""
var _index: int = 0
var _active_hash: String = ""
var _last_offset: int = -1
var _last_progress: int = 0
var _pinned: Array = []
var _receiver
var _cache
var _cache_root:String = ""

func begin(session, files: Array, destination: String) -> bool:
	cancel()
	complete = false
	error = ""
	completed_files = 0
	if not is_finite(timeout_seconds) or timeout_seconds <= 0:
		return _fail("文件同步超时预算无效")
	if DirAccess.dir_exists_absolute(destination) or FileAccess.file_exists(destination):
		return _fail("目标会话目录已存在")
	if not assembler.validate(files, session.blobs.cache.max_file_bytes):
		return _fail(assembler.error)
	_session = session
	_receiver = session.blobs
	_cache = _receiver.cache
	_cache_root = _cache.root
	_files = files.duplicate(true)
	_destination = destination
	_index = 0
	_local_index = 0
	_local_candidates.clear()
	_required_hashes.clear()
	_required_sizes.clear()
	for item in _files:
		_required_hashes[item.hash] = item.size
		_required_sizes[item.size] = true
	_collect_local_candidates()
	for item in _files:
		if not _pinned.any(func(pin): return pin.key == item.hash):
			_pinned.append({"key":item.hash,"token":_cache.pin(item.hash)})
	running = true
	return true

func poll() -> void:
	if not running:
		return
	if not is_finite(timeout_seconds) or timeout_seconds <= 0:
		_fail("文件同步超时预算无效")
		return
	if _session.blobs != _receiver or _receiver.cache != _cache or _cache.root != _cache_root:
		_fail("同步过程中缓存实例或目录已改变")
		return
	if not _session.transport.is_connected_to_host():
		_fail("同步过程中连接中断")
		return
	if _local_index < _local_candidates.size():
		_precheck_local_file(_local_candidates[_local_index])
		_local_index += 1
		return
	if _index >= _files.size():
		var result: bool = assembler.assemble(_destination, _files, _session.blobs.cache)
		if not result:
			_fail(assembler.error)
			return
		complete = true
		running = false
		_release_pins()
		return
	var item: Dictionary = _files[_index]
	if not _active_hash.is_empty():
		var pending_offset:int = _receiver.offset_for(1, _active_hash)
		if pending_offset >= 0:
			if pending_offset != _last_offset:
				_last_offset = pending_offset
				_last_progress = Time.get_ticks_msec()
			if Time.get_ticks_msec() - _last_progress > timeout_seconds * 1000.0:
				_fail("文件同步超时：" + item.path)
			return
	var bytes: PackedByteArray = _cache.fetch(item.hash)
	if bytes.size() == item.size:
		_index += 1
		completed_files = _index
		_active_hash = ""
		return
	if _active_hash.is_empty():
		if not _session.download_blob(item.hash, item.size):
			_fail("无法请求所需文件：" + item.path)
			return
		_active_hash = item.hash
		_last_offset = 0
		_last_progress = Time.get_ticks_msec()
		return
	_fail("主机拒绝或文件校验失败：" + item.path)

func cancel() -> void:
	if _receiver != null and not _active_hash.is_empty():
		_receiver.cancel_blob(1, _active_hash)
	_release_pins()
	_active_hash = ""
	_session = null
	_receiver = null
	_cache = null
	_cache_root = ""
	running = false
	_local_candidates.clear()
	_required_hashes.clear()
	_required_sizes.clear()

func _collect_local_candidates() -> void:
	var paths = preload("res://scripts/net/server/recovery_path_safety.gd")
	if max_local_files <= 0: return
	for declared in local_roots:
		if not declared is String: continue
		var root:String = paths.absolute(declared)
		if root.is_empty() or not paths.checked(root, root): continue
		var pending:Array[String] = [root]
		var visited:int = 0
		while not pending.is_empty() and visited < max_local_files and _local_candidates.size() < max_local_files:
			var directory:String = pending.pop_back()
			visited += 1
			if not paths.checked(root, directory): continue
			var dir := DirAccess.open(directory)
			if dir == null: continue
			for folder in dir.get_directories():
				if not dir.is_link(folder) and not folder.begins_with(".") and pending.size() < max_local_files:
					pending.append(directory.path_join(folder))
			for name in dir.get_files():
				if dir.is_link(name) or _local_candidates.size() >= max_local_files: continue
				var path:String = directory.path_join(name)
				if not paths.checked(root, path): continue
				var file := FileAccess.open(path, FileAccess.READ)
				if file != null and _required_sizes.has(file.get_length()):
					_local_candidates.append({"root":root, "path":path})

func _precheck_local_file(candidate:Dictionary) -> void:
	var paths = preload("res://scripts/net/server/recovery_path_safety.gd")
	if not paths.checked(candidate.root, candidate.path): return
	var file := FileAccess.open(candidate.path, FileAccess.READ)
	if file == null or not _required_sizes.has(file.get_length()) or file.get_length() > _session.blobs.cache.max_file_bytes: return
	var bytes:PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	if not paths.checked(candidate.root, candidate.path): return
	var hash:String = _session.blobs.cache.digest(bytes)
	if _required_hashes.get(hash, -1) != bytes.size(): return
	# store 再验哈希和安全发布；本机损坏或不可用时仍走正常下载。
	if _session.blobs.cache.fetch(hash).size() == bytes.size() or _session.blobs.cache.store(hash, bytes):
		_required_hashes.erase(hash)

func _release_pins() -> void:
	if _cache != null:
		for pin in _pinned:
			_cache.unpin(pin.key, pin.token)
	_pinned.clear()

func _fail(reason: String) -> bool:
	error = reason
	complete = false
	cancel()
	return false
