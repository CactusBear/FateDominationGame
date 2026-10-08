class_name RoomDataSync
extends RefCounted

## 调用方提供已批准的完整文件清单；本组件不授予数据来源信任。
var timeout_seconds: float = 30.0
var running: bool = false
var complete: bool = false
var error: String = ""
var completed_files: int = 0
var assembler = preload("res://scripts/net/content/room_data_assembler.gd").new()
var _session
var _files: Array = []
var _destination: String = ""
var _index: int = 0
var _active_hash: String = ""
var _last_offset: int = -1
var _last_progress: int = 0
var _pinned: Array = []

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
	_files = files.duplicate(true)
	_destination = destination
	_index = 0
	for item in _files:
		if not _pinned.has(item.hash):
			_session.blobs.cache.pin(item.hash)
			_pinned.append(item.hash)
	running = true
	return true

func poll() -> void:
	if not running:
		return
	if not is_finite(timeout_seconds) or timeout_seconds <= 0:
		_fail("文件同步超时预算无效")
		return
	if not _session.transport.is_connected_to_host():
		_fail("同步过程中连接中断")
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
	var bytes: PackedByteArray = _session.blobs.cache.fetch(item.hash)
	if bytes.size() == item.size and _session.blobs.cache.digest(bytes) == item.hash:
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
	var offset: int = _session.blobs.offset_for(1, _active_hash)
	if offset < 0:
		_fail("主机拒绝或文件校验失败：" + item.path)
		return
	if offset != _last_offset:
		_last_offset = offset
		_last_progress = Time.get_ticks_msec()
	if Time.get_ticks_msec() - _last_progress > timeout_seconds * 1000.0:
		_fail("文件同步超时：" + item.path)

func cancel() -> void:
	if _session != null and not _active_hash.is_empty():
		_session.blobs.cancel_blob(1, _active_hash)
	_release_pins()
	_active_hash = ""
	_session = null
	running = false

func _release_pins() -> void:
	if _session != null:
		for key in _pinned:
			_session.blobs.cache.unpin(key)
	_pinned.clear()

func _fail(reason: String) -> bool:
	error = reason
	complete = false
	cancel()
	return false
