extends RefCounted

## 仅准备并隔离校验显式选择的数据；是否批准、何时采用由调用方决定。
var session
var source_root:String = ""
## 可选本机隔离根；服务端使用已校验的房间目录，客户端保留 user 默认。
var workspace_root:String = ""
var source_provider:String = "host"
var files_per_poll:int = 2
var plan:Dictionary = {}
var preparing:bool = false
var status:String = ""
var error:String = ""
var validation = preload("res://scripts/net/validation/room_validation_task.gd").new()
var _assembled:String = ""
var _index:int = 0
var _seconds:float = 0.0
var _simulation:Dictionary = {}
var _download_provider:int = -1
var _download_key:String = ""
var _download_progress:int = 0
var _download_offset:int = -1
var _phase:String = "idle"
var _entry_index:int = 0
var _entry_file_index:int = 0
var _polling:bool = false
var _generation:int = 0
var _catalog = preload("res://scripts/net/content/data_catalog.gd").new()
var _assembler = preload("res://scripts/net/content/room_data_assembler.gd").new()

func start(selected:Array, base:Array, seconds:float) -> bool:
	if _polling: return false
	cancel()
	error = ""
	if session == null or not is_finite(seconds) or seconds <= 0 or seconds >= 9223372036854775.0 or files_per_poll <= 0:
		error = "数据准备会话或时间预算无效"
		return false
	plan = preload("res://scripts/net/content/room_data_plan.gd").new().build(selected, base)
	if not plan.ok:
		error = plan.error + "\n" + JSON.stringify(plan.conflicts if not plan.conflicts.is_empty() else plan.dependencies)
		return false
	_seconds = seconds
	_simulation = preload("res://scripts/net/validation/rule_random_simulation.gd").room_options(session.room.settings, session.room._humans())
	_index = 0
	var preparation_root:String = "user://net_session" if workspace_root.is_empty() else workspace_root
	_assembled = preparation_root.path_join("%d-%d/data" % [OS.get_process_id(), Time.get_ticks_usec()])
	validation.workspace_root = "user://room_validation" if workspace_root.is_empty() else workspace_root.path_join("room_validation")
	_phase = "copy"
	_entry_index = 0
	_entry_file_index = 0
	preparing = true
	status = "正在准备批准数据"
	return true

func poll() -> void:
	if _polling: return
	_polling = true
	_poll_work(_generation)
	_polling = false

func _poll_work(generation:int) -> void:
	if (preparing or validation.running) and not simulation_is_current():
		_fail("预检策略已变化，请重新校验")
		return
	if preparing and _phase == "verify":
		_verify_step(generation)
		return
	if preparing and _phase == "assemble":
		_assembler.poll(files_per_poll)
		if generation != _generation: return
		if not _assembler.error.is_empty():
			_fail(_assembler.error)
		elif _assembler.complete:
			_phase = "validate"
			preparing = false
			if not validation.start(_assembled, plan.files, _seconds, _simulation): _fail(validation.error)
		return
	if preparing:
		for _step in range(files_per_poll):
			if not preparing or generation != _generation: return
			if _index >= plan.files.size(): break
			var file:Dictionary = plan.files[_index]
			var source:Dictionary = plan.sources[_index]
			var content:PackedByteArray
			if source.provider == source_provider:
				var input := FileAccess.open(source_root.path_join(source.path), FileAccess.READ)
				if input == null:
					_fail("无法读取所选文件：" + source.path)
					return
				if input.get_length() != file.size or file.size > session.blobs.cache.max_file_bytes:
					input.close()
					_fail("所选文件大小已变化：" + source.path)
					return
				content = input.get_buffer(file.size)
				input.close()
			else:
				content = session.blobs.cache.fetch(file.hash)
				if not preparing or generation != _generation: return
				if content.size() != file.size or content.is_empty():
					if _download_key != file.hash:
						_download_provider = int(source.provider)
						_download_key = file.hash
						_download_offset = -1
						_download_progress = Time.get_ticks_msec()
						if not session.download_provider_blob(_download_provider, file.hash, file.size):
							_fail("无法从所选提供者获取文件：" + source.path)
							return
					var offset:int = session.blobs.offset_for(_download_provider, file.hash)
					if offset > _download_offset:
						_download_offset = offset
						_download_progress = Time.get_ticks_msec()
					if offset < 0 or Time.get_ticks_msec() - _download_progress >= _seconds * 1000.0:
						_fail("提供者下载失败或超时：" + source.path)
						return
					break
				_download_key = ""
				_download_provider = -1
			var stored:bool = content.size() == file.size and session.blobs.cache.store(file.hash, content)
			if not preparing or generation != _generation: return
			var published:bool = stored and session.publish_blob(content) == file.hash
			if not preparing or generation != _generation: return
			if not published:
				_fail("所选文件已变化或无法发布：" + source.path)
				return
			if not preparing or generation != _generation: return
			_index += 1
		status = "正在准备批准数据：%d / %d" % [_index, plan.files.size()]
		if _index == plan.files.size():
			_phase = "verify"
			_catalog.errors.clear()
		return
	if validation.running:
		validation.poll()
		status = "正在独立进程中校验所选数据"
		if not validation.running and not validation.complete:
			_fail(validation.error)

## 每次只访问固定数量文件；条目身份校验也占一个步骤。
func _verify_step(generation:int) -> void:
	for _unused in range(files_per_poll):
		if not preparing or generation != _generation: return
		if _entry_index == plan.entries.size():
			if not _assembler.start(_assembled, plan.files, session.blobs.cache):
				_fail(_assembler.error)
			else:
				_phase = "assemble"
				status = "正在分步组装批准数据"
			return
		var entry:Dictionary = plan.entries[_entry_index]
		var ok:bool
		if _entry_file_index < entry.files.size():
			ok = _catalog.verify_content_file(entry.files[_entry_file_index], session.blobs.cache)
			if generation != _generation: return
			_entry_file_index += 1
		else:
			ok = _catalog.verify_content_identity(entry, session.blobs.cache)
			if generation != _generation: return
			_entry_index += 1
			_entry_file_index = 0
		if not ok:
			_fail("\n".join(_catalog.errors))
			return
	status = "正在逐文件核验批准数据：%d / %d" % [_entry_index, plan.entries.size()]

func simulation_is_current() -> bool:
	if session == null: return false
	var original:Dictionary = _simulation.duplicate(true)
	var current:Dictionary = preload("res://scripts/net/validation/rule_random_simulation.gd").room_options(session.room.settings, session.room._humans())
	# 随机采样人数不是数据来源资质；已收齐校验的候补不因提供者掉线而失效。
	original.erase("player_ids")
	current.erase("player_ids")
	return original == current

func _fail(reason:String) -> void:
	cancel()
	error = reason

func cancel() -> void:
	_generation += 1
	_phase = "idle"
	_assembler.cancel()
	preparing = false
	if session != null and _download_provider >= 0 and not _download_key.is_empty():
		session.blobs.cancel_blob(_download_provider, _download_key)
	_download_provider = -1
	_download_key = ""
	validation.cancel()
