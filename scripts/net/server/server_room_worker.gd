extends Node

var _system_signals

var session = preload("res://scripts/net/session/lobby_session.gd").new()
var _data_approval = preload("res://scripts/net/server/server_data_approval.gd").new()
var _control = preload("res://scripts/net/server/server_room_control.gd").new()
var _directory: String = ""
var _room_id: String = ""
var _authority_host_mode:String = ""
var _supervisor_timeout_msec: int = 0
var _supervisor_seen_msec: int = 0
var _supervisor_version: int = -1
var _recovery_attempted: bool = false
var _audit_journal
var _lan_identity_bridge
const RecoveryPaths = preload("res://scripts/net/server/recovery_path_safety.gd")
var _startup_pins:Array = []
var _copy_source_root:String = ""
var recovery_copy_max_bytes:int = 2 * 1024 * 1024 * 1024
var recovery_copy_max_file_bytes:int = 64 * 1024 * 1024
const RECOVERY_COPY_CHUNK_BYTES:int = 64 * 1024


func _ready() -> void:
	_system_signals = preload("res://scripts/net/server/server_process_signals.gd").create()
	if _system_signals == null or not _system_signals.protect_worker():
		_fail("房间子进程信号保护不可用")
		return
	var arguments := OS.get_cmdline_user_args()
	arguments.erase("--server-room-worker")
	if arguments.size() != 3:
		push_error("房间子进程需要本机配置路径")
		get_tree().quit(2)
		return
	# 授权根来自本机主管参数，不信任 config 中自报的批准根。
	if not RecoveryPaths.checked(arguments[2], arguments[0]):
		_fail("房间启动配置不在主管批准目录")
		return
	var config = JSON.parse_string(FileAccess.get_file_as_string(arguments[0]))
	if not config is Dictionary or not config.get("data_root") is String or not config.get("directory") is String or not config.get("settings") is Dictionary or not config.get("id") is String or not _valid_integer(config.get("port"), 1, 65535):
		_fail("房间启动配置无效")
		return
	var recovery_state_path:String = config.directory.path_join("recovery.json")
	var has_recovery_state:bool = FileAccess.file_exists(recovery_state_path)
	var recovery_digest:String = FileAccess.get_sha256(recovery_state_path) if has_recovery_state else ""
	if not preload("res://scripts/net/server/server_room_manager.gd").valid_instance_id(config.id) or not RecoveryPaths.same(config.directory, arguments[2].path_join(config.id)) or not RecoveryPaths.same(arguments[0], config.directory.path_join("config.json")) or not RecoveryPaths.checked(arguments[2], config.directory) or (not has_recovery_state and (not RecoveryPaths.checked(arguments[1], config.data_root) or not RecoveryPaths.tree(arguments[1], config.data_root, [20000]))):
		_fail("房间目录或数据根越过批准范围或包含链接")
		return
	for child in ["control", "cache", "data", "preflight", "matches", "recovery.json", "stored_jsons.dat", "ready.json", "ready.json.tmp"]:
		if not RecoveryPaths.checked(config.directory, config.directory.path_join(child), true):
			_fail("房间内部路径不安全：" + child)
			return
	if config.get("authority_host_mode") not in preload("res://scripts/net/server/server_room_manager.gd").AUTHORITY_HOST_MODES or not preload("res://scripts/net/server/server_room_manager.gd").valid_instance_id(config.get("instance_id")):
		_fail("权威位置或进程实例未显式声明")
		return
	_authority_host_mode = config.authority_host_mode
	if not config.get("transaction_log", true) is bool or config.get("recovery_key_mismatch", "reject") != "reject" or config.get("recovery_inheritance", "host_select") != "host_select":
		_fail("房间恢复或事务审计策略无效")
		return
	var transaction_log_enabled:bool = config.get("transaction_log", true)
	# 复用管理通道的随机实例，不另建一套管理凭据。
	_control.instance_id = config.instance_id
	_control.room_id = config.id
	_control.authority_host_mode = config.authority_host_mode
	session.authority_host_mode = config.authority_host_mode
	# 本机配置中的专用策略由网关覆盖写入，不进入公开房间设置。
	var identity_required = config.settings.get("_gateway_identity_required",false)
	if not identity_required is bool:
		_fail("房间身份策略无效")
		return
	# LAN/P2P 永不接受无密钥绑定旧档或身份策略降级。
	if _authority_host_mode in ["lan", "p2p"]: identity_required = true
	config.settings.erase("_gateway_identity_required")
	var decoded:Dictionary = preload("res://scripts/net/session/room_state.gd").decode_json_settings(config.settings)
	if not decoded.ok:
		_fail(decoded.error)
		return
	config.settings = decoded.settings
	var root: String = config.data_root
	if typeof(config.get("supervisor_timeout_seconds")) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(config.supervisor_timeout_seconds)) or config.supervisor_timeout_seconds <= 1:
		_fail("主管心跳预算无效")
		return
	_directory = config.directory
	_control.directory = _directory.path_join("control")
	_control.session = session
	_control.restore_snapshot = _prepare_manual_restore_snapshot
	_control.restore_transaction = _restore_manual_match
	_control.shutdown_ready.connect(_shutdown_after_control)
	if not config.get("record_matches", false) is bool:
		_fail("存档开关必须显式声明为布尔值")
		return
	session.record_matches = config.get("record_matches", false)
	session.archive_root = config.directory.path_join("matches")
	# 先以强制认证策略读取旧档；既有 schema/身份/固定数据检查失败即关闭。
	# recovery_state_path 在 host() 前清空，禁止空大厅覆盖旧档。
	var isolated: String = config.directory.path_join("data")
	if has_recovery_state:
		session._identity_binding_required = identity_required
		if not session.load_recovery_state(recovery_state_path):
			_fail("恢复文件无效，原档保留：" + session.error)
			return
		root = isolated
		config.settings = session.room.settings.duplicate(true)
		# 读取模式或加载规则之前，固定副本必须通过完整树和逐文件校验。
		if not RecoveryPaths.tree(_directory, isolated, [20000]) or not preload("res://scripts/net/validation/room_data_validator.gd").new().validate(isolated, session.room_files):
			_fail("恢复固定数据副本缺失或校验失败")
			return
	_room_id = config.id
	_supervisor_timeout_msec = int(config.supervisor_timeout_seconds * 1000.0)
	var modes = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("selection_modes.json")))
	if not modes is Dictionary or not modes.get("modes") is Array:
		_fail("服务端本机选人配置无效")
		return
	var mode: Dictionary = {}
	for candidate in modes.modes:
		if candidate is Dictionary and candidate.get("id") == config.settings.get("selection_mode"):
			mode = candidate
	if mode.is_empty():
		_fail("服务端未声明所选选人模式")
		return
	var entries: Array = []
	var base: Array = []
	var plan: Dictionary = {}
	if has_recovery_state:
		# load_recovery_state 已完成 schema、整数、身份和座位校验。
		plan = {"ok":true, "files":session.room_files.duplicate(true), "sources":[]}
	else:
		var catalog = preload("res://scripts/net/content/data_catalog.gd").new()
		var scanned_entries: Array = catalog.scan(root, "server").filter(func(entry): return entry.category != "command_spells")
		if not catalog.errors.is_empty():
			_fail("\n".join(catalog.errors))
			return
		entries = scanned_entries
		for path in catalog._files(root, "card_backs") + catalog._files(root, "command_spells") + ["selection_modes.json"]:
			if path.get_extension() not in catalog.EXTENSIONS: continue
			base.append({"provider": "server", "path": path, "hash": FileAccess.get_sha256(root.path_join(path)), "size": FileAccess.get_file_as_bytes(root.path_join(path)).size()})
		plan = preload("res://scripts/net/content/room_data_plan.gd").new().build(entries, base)
		if not plan.ok:
			_fail(plan.error)
			return
	session.blobs.cache.root = config.directory.path_join("cache")
	for index in range(plan.files.size()):
		if has_recovery_state: continue
		# store 自身可能触发预算淘汰，先 pin；失败出口统一释放。
		session.blobs.cache.pin(plan.files[index].hash)
		_startup_pins.append(plan.files[index].hash)
		if not RecoveryPaths.checked(root, root.path_join(plan.sources[index].path)):
			_fail("批准数据源路径在读取前失效")
			return
		var bytes := FileAccess.get_file_as_bytes(root.path_join(plan.sources[index].path))
		if not session.blobs.cache.store(plan.files[index].hash, bytes):
			_fail(session.blobs.cache.error)
			return
	var assembler = preload("res://scripts/net/content/room_data_assembler.gd").new()
	var validator = preload("res://scripts/net/validation/room_data_validator.gd").new()
	if DirAccess.dir_exists_absolute(isolated):
		# 重启只复用逐文件校验仍完整的目录；不覆盖或删除未知残留。
		if not RecoveryPaths.tree(_directory, isolated, [20000]) or not validator.validate(isolated, plan.files):
			_fail("房间已有数据目录不完整，拒绝覆盖恢复：" + "\n".join(validator.errors))
			return
	elif has_recovery_state:
		_fail("固定主机数据副本缺失，拒绝从候选 provider 重建")
		return
	else:
		if not assembler.assemble(isolated, plan.files, session.blobs.cache):
			_fail(assembler.error)
			return
	if not RecoveryPaths.tree(_directory, isolated, [20000]) or not validator.validate(isolated, plan.files):
		_fail("\n".join(validator.errors))
		return
	LoadHelper.session_data_dir = isolated
	LoadGame.stored_jsons_path = config.directory.path_join("stored_jsons.dat")
	LoadGame.reload_game()
	var masters: Array = GameStart.get_masters_can_use()
	var servants: Array = GameStart.get_servants_can_use()
	if masters.is_empty() or servants.is_empty():
		_fail("房间数据缺少可用阵容")
		return
	var settings: Dictionary = config.settings.duplicate(true)
	settings.capacity = load(mode.script).new().capacity(masters, servants, mode)
	session.recovery_state_path = ""
	if session.host(int(config.port), "服务端", settings, "127.0.0.1") != OK:
		_fail(session.error)
		return
	session.dedicated = true
	session._identity_binding_required = identity_required
	var recovered_state:bool = has_recovery_state and session.load_recovery_state(recovery_state_path)
	if has_recovery_state and not recovered_state:
		_fail("房间恢复文件无效，拒绝覆盖既有状态")
		return
	if recovered_state and (session.room_files != plan.files or FileAccess.get_sha256(recovery_state_path) != recovery_digest):
		_fail("恢复文件在启动校验期间变化，拒绝发布")
		return
	if not recovered_state: session.recovery_state_path = recovery_state_path
	session.dedicated = true
	session.selection_modes = modes.modes.duplicate(true)
	if not recovered_state:
		session.room.members.erase(1)
		session.room.owner = 0
	session.configure_selection(mode, masters, servants)
	for file in plan.files:
		var fixed_bytes:PackedByteArray = FileAccess.get_file_as_bytes(isolated.path_join(file.path)) if has_recovery_state else session.blobs.cache.fetch(file.hash)
		if session.publish_blob(fixed_bytes) != file.hash:
			_fail("无法发布批准内容")
			return
	# 显式启用预检配置的房间，初始目录仅作为候选；恢复也不能绕过批准。
	if has_recovery_state:
		if not session.install_room_assets(isolated):
			_fail(session.error)
			return
	elif not session.room.settings.has("random_sim_enabled"):
		if not session.set_room_files(plan.files) or not session.install_room_assets(isolated):
			_fail(session.error)
			return
	session.require_room_data = true
	_release_startup_pins()
	if _authority_host_mode in ["lan","p2p"]:
		_lan_identity_bridge = preload("res://scripts/net/server/lan_worker_identity_bridge.gd").new()
		if not _lan_identity_bridge.configure(_control,session):
			_fail("LAN 认证连接观察通道不可用")
			return
	session._rules_revision = session.data_revision
	# config.directory 是启动时已校验的本机房间目录，不由批准网络请求提供。
	_data_approval.configure(session, root, entries, base, config.directory.path_join("preflight"))
	# 对局录制和事务审计不是同一个开关。关闭对局录制仍保存完整事务审计。
	# 开启录制时由 MatchReplay 创建/恢复其 transactions.log，不重复占用全局写入器。
	if transaction_log_enabled and not session.record_matches and session.room.phase != "restoring":
		_audit_journal = preload("res://scripts/match/match_journal.gd").begin_audit(_directory.path_join("transactions.%s.log" % _control.instance_id))
		if _audit_journal == null:
			_fail("权威事务审计文件建立失败")
			return
	var report := FileAccess.open(config.directory.path_join("ready.json.tmp"), FileAccess.WRITE)
	if report == null:
		_fail("无法写出房间就绪报告")
		return
	report.store_string(JSON.stringify({"ok": true, "id": config.id, "room_id":config.id, "pid": OS.get_process_id(), "port": int(config.port), "instance":_control.instance_id, "instance_id":_control.instance_id, "authority_host_mode":_authority_host_mode, "capabilities":_capabilities()}))
	report.flush()
	var report_error:Error = report.get_error()
	report.close()
	if report_error != OK or DirAccess.rename_absolute(config.directory.path_join("ready.json.tmp"), config.directory.path_join("ready.json")) != OK:
		_fail("无法发布房间就绪报告")
		return
	print("SERVER_ROOM_READY ", config.id)
	_supervisor_seen_msec = Time.get_ticks_msec()

func _process(delta: float) -> void:
	if not _directory.is_empty() and _supervisor_seen_msec > 0:
		var path := _directory.path_join("supervisor.json")
		var parser := JSON.new()
		var pulse = null
		if FileAccess.file_exists(path) and parser.parse(FileAccess.get_file_as_string(path)) == OK: pulse = parser.data
		if pulse is Dictionary and pulse.get("id") == _room_id and pulse.get("pid") == OS.get_process_id() and pulse.get("instance_id") == _control.instance_id and _valid_integer(pulse.get("version"), 0, 9007199254740991) and pulse.version > _supervisor_version:
			_supervisor_version = int(pulse.version)
			_supervisor_seen_msec = Time.get_ticks_msec()
		if Time.get_ticks_msec() - _supervisor_seen_msec > _supervisor_timeout_msec:
			print("SERVER_ROOM_SUPERVISOR_LOST ", _room_id)
			get_tree().quit(0)
			return
	if session.transport.is_connected_to_host():
		session.poll(delta)
		_data_approval.poll()
	_control.poll()
	if _lan_identity_bridge != null: _lan_identity_bridge.poll()
	if not _recovery_attempted and session.room.phase == "restoring" and not session.match_authority.started:
		_try_restore_match()

func _try_restore_match() -> void:
	_recovery_attempted = true
	# 模式禁令由真实连接认证守卫替代，不信任恢复票据自报或 connected 标志。
	if _authority_host_mode in ["lan", "p2p"] and not _authenticated_recovery_ready():
		_recovery_attempted = false
		return
	for player_id in session._recovery_bindings:
		var member_id:int = int(session._recovery_bindings[player_id])
		if member_id > 0 and (not session.room.members.has(member_id) or not session.room.members[member_id].connected):
			_recovery_attempted = false
			return
	if not RecoveryPaths.same(session.archive_root, _directory.path_join("matches")) or not RecoveryPaths.checked(_directory, session.archive_root):
		push_error("恢复存档根越过房间边界或包含链接；原档保留")
		return
	# 同步准备也可能触发 transport 回调；复用业务守卫，不运行 session.poll。
	if session._restore_in_progress or session._restore_failed_closed: return
	session._restore_in_progress = true
	var snapshot:String = _prepare_recovery_snapshot()
	session._restore_in_progress = false
	if snapshot.is_empty(): return
	if OS.get_environment("FD_RECOVERY_DIAGNOSTICS") == "1": print("RECOVERY_STAGE replay_begin ", Time.get_ticks_msec())
	var ok:bool = await session.restore_crashed_match(snapshot)
	if OS.get_environment("FD_RECOVERY_DIAGNOSTICS") == "1": print("RECOVERY_STAGE replay_return ", Time.get_ticks_msec(), " ", ok)
	if not ok:
		if session._restore_failed_closed:
			_fail("存档恢复失败关闭：" + session.error)
		else:
			push_error("存档恢复失败：" + session.error)

func _authenticated_recovery_ready() -> bool:
	return _lan_identity_bridge != null and session.authenticated_crash_recovery_ready()

func _prepare_recovery_snapshot() -> String:
	var folders:Array = []
	_maintain_copy_transport()
	for folder in DirAccess.get_directories_at(session.archive_root):
		_maintain_copy_transport()
		var candidate:String = session.archive_root.path_join(folder)
		if FileAccess.file_exists(candidate + ".restore-pending") or DirAccess.dir_exists_absolute(candidate + ".restore-pending"):
			continue
		if not RecoveryPaths.component(folder) or not RecoveryPaths.tree(_directory, candidate, [20000], 0, _maintain_copy_transport):
			push_error("恢复存档包含不安全路径；原档保留")
			return ""
		if RecoveryPaths.checked(candidate, candidate.path_join("match.log")):
			folders.append(folder)
	if folders.is_empty():
		push_error("存档恢复缺少可读对局日志")
		return ""
	folders.sort()
	var source:String = session.archive_root.path_join(folders.back())
	# replay 的恢复/续写只接触本实例副本，不得截断或追加原始崩溃档。
	var snapshot:String = _directory.path_join("restore-" + _control.instance_id)
	if OS.get_environment("FD_RECOVERY_DIAGNOSTICS") == "1": print("RECOVERY_STAGE copy_begin ", Time.get_ticks_msec())
	if not _copy_recovery_tree(source, snapshot, [0, 0]):
		push_error("恢复副本建立失败；原档保留")
		return ""
	if not RecoveryPaths.tree(_directory, snapshot, [20000], 0, _maintain_copy_transport):
		push_error("恢复副本路径校验失败；原档保留")
		return ""
	return snapshot

func _prepare_manual_restore_snapshot(source:String, archive_id:String) -> String:
	if not session._restore_in_progress or not preload("res://scripts/net/server/server_console_channel.gd").valid_id(archive_id): return ""
	if not RecoveryPaths.tree(source.get_base_dir(),source,[20000],0,_maintain_copy_transport): return ""
	_copy_source_root = source
	var snapshot:String = _directory.path_join("restore-"+_control.instance_id+"-"+archive_id)
	var ok:bool = _copy_recovery_tree(source,snapshot,[0,0])
	_copy_source_root = ""
	if not ok or not RecoveryPaths.tree(_directory,snapshot,[20000],0,_maintain_copy_transport): return ""
	return snapshot

func _restore_manual_match(snapshot:String) -> bool:
	# 大厅独立审计器必须让出全局 writer；不关闭真人连接、不修改旧审计日志。
	var detached:bool = _audit_journal != null
	if detached:
		if not _audit_journal.flush():
			session.error = "大厅审计刷新失败，未进入规则恢复；旧档保留"
			return false
		preload("res://scripts/match/match_journal.gd").end_audit(_audit_journal)
		_audit_journal = null
	var ok:bool = await session.restore_local_match(snapshot)
	if not ok and not session._restore_failed_closed and detached:
		var suffix:String = Crypto.new().generate_random_bytes(16).hex_encode()
		_audit_journal = preload("res://scripts/match/match_journal.gd").begin_audit(_directory.path_join("transactions.restore-rejected."+suffix+".log"))
		if _audit_journal == null:
			session._restore_failed_closed = true
			session.error = "恢复被拒且大厅审计重启失败，必须退出权威；旧档保留"
	return ok

func _copy_source_checked(path:String) -> bool:
	return RecoveryPaths.checked(_directory,path) if _copy_source_root.is_empty() else RecoveryPaths.checked(_copy_source_root,path)

func _maintain_copy_transport() -> void:
	if not session._restore_in_progress or session._restore_failed_closed: return
	# 仅底层 ENet/传输保活；_send/_receive 的恢复守卫拒绝业务。
	session.transport.poll()

func _copy_recovery_tree(source:String, destination:String, budget:Array, depth:int = 0) -> bool:
	_maintain_copy_transport()
	if depth > 128 or not _copy_source_checked(source) or not RecoveryPaths.checked(_directory, destination, true) or DirAccess.dir_exists_absolute(destination) or FileAccess.file_exists(destination): return false
	if DirAccess.make_dir_absolute(destination) != OK: return false
	var dir := DirAccess.open(source)
	if dir == null: return false
	dir.include_hidden = true
	dir.include_navigational = false
	if dir.list_dir_begin() != OK: return false
	var name:String = dir.get_next()
	while not name.is_empty():
		_maintain_copy_transport()
		budget[0] += 1
		var original:String = source.path_join(name)
		var target:String = destination.path_join(name)
		if budget[0] > 20000 or not RecoveryPaths.component(name) or dir.is_link(name) or not _copy_source_checked(original) or not RecoveryPaths.checked(_directory, target, true):
			dir.list_dir_end()
			return false
		if dir.current_is_dir():
			if not _copy_recovery_tree(original, target, budget, depth + 1):
				dir.list_dir_end()
				return false
		else:
			if not _copy_recovery_file(original, target, budget):
				dir.list_dir_end()
				return false
		name = dir.get_next()
	dir.list_dir_end()
	return _copy_source_checked(source) and RecoveryPaths.checked(_directory, destination)

func _copy_recovery_file(original:String, target:String, budget:Array) -> bool:
	var input := FileAccess.open(original, FileAccess.READ)
	if input == null: return false
	var length:int = input.get_length()
	if length > recovery_copy_max_file_bytes or length > recovery_copy_max_bytes - budget[1]:
		input.close()
		return false
	if not RecoveryPaths.checked(_directory, target, true):
		input.close()
		return false
	var output := FileAccess.open(target, FileAccess.WRITE)
	if output == null:
		input.close()
		return false
	var hash := HashingContext.new()
	var ok:bool = hash.start(HashingContext.HASH_SHA256) == OK
	var copied:int = 0
	while ok and copied < length:
		_maintain_copy_transport()
		var requested:int = mini(RECOVERY_COPY_CHUNK_BYTES, length - copied)
		var bytes:PackedByteArray = input.get_buffer(requested)
		ok = bytes.size() == requested and input.get_error() == OK and hash.update(bytes) == OK
		if not ok: break
		output.store_buffer(bytes)
		ok = output.get_error() == OK
		copied += bytes.size()
	ok = ok and input.get_length() == length
	input.close()
	output.flush()
	ok = ok and output.get_error() == OK
	output.close()
	if not ok: return false
	var digest:String = hash.finish().hex_encode()
	# 独立重读源与目标，保持旧的双向 SHA256 校验；哈希阶段同样分块保活。
	if _recovery_file_digest(original, length) != digest or _recovery_file_digest(target, length) != digest: return false
	budget[1] += length
	return true

func _recovery_file_digest(path:String, length:int) -> String:
	_maintain_copy_transport()
	if not RecoveryPaths.checked(_directory, path) and not _copy_source_checked(path): return ""
	var input := FileAccess.open(path, FileAccess.READ)
	if input == null: return ""
	var hash := HashingContext.new()
	var ok:bool = input.get_length() == length and hash.start(HashingContext.HASH_SHA256) == OK
	var read:int = 0
	while ok and read < length:
		_maintain_copy_transport()
		var requested:int = mini(RECOVERY_COPY_CHUNK_BYTES, length - read)
		var bytes:PackedByteArray = input.get_buffer(requested)
		ok = bytes.size() == requested and input.get_error() == OK and hash.update(bytes) == OK
		read += bytes.size()
	ok = ok and input.get_length() == length
	input.close()
	if not ok or (not RecoveryPaths.checked(_directory, path) and not _copy_source_checked(path)): return ""
	return hash.finish().hex_encode()

func _release_startup_pins() -> void:
	for key in _startup_pins: session.blobs.cache.unpin(key)
	_startup_pins.clear()

func _shutdown_after_control() -> void:
	set_process(false)
	get_tree().quit(0)

static func _valid_integer(value:Variant, minimum:int, maximum:int) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) and floor(float(value)) == value and value >= minimum and value <= maximum

func _capabilities() -> Dictionary:
	# 接口能力不等于当前存在完整检查点，ready 不伪造某次跳过/恢复成功。
	return {"root_transaction_rollback":EffectManager.has_method("runtime_guard_root_effect") and EffectManager.has_method("skip_runtime_guard"),
		"can_rollback_now":EffectManager.can_rollback_runtime_guard(),
		"execution_trace":_script_has_method(preload("res://scripts/system/global/game_log.gd"), "all_func_calls"),
		"root_transaction_audit":_script_has_method(preload("res://scripts/match/match_journal.gd"), "audit_event"),
		"transaction_audit_persistence_enabled":session.record_matches or _audit_journal != null,
		"match_recording_enabled":session.record_matches,
		"process_restart_is_rollback":false}

static func _script_has_method(script:GDScript, method_name:String) -> bool:
	for method in script.get_script_method_list():
		if method.get("name") == method_name: return true
	return false

func _fail(reason: String) -> void:
	push_error(reason)
	_release_startup_pins()
	_data_approval.close()
	session.close()
	get_tree().quit(1)

func _exit_tree() -> void:
	_release_startup_pins()
	preload("res://scripts/match/match_journal.gd").end_audit(_audit_journal)
	_audit_journal = null
	if _system_signals != null:
		_system_signals.disable()
		_system_signals = null
	_data_approval.close()
	session.close()
	if not _directory.is_empty():
		# 只移除本实例报告；旧进程晚退出不能删掉新进程的 ready。
		var path:String = _directory.path_join("ready.json")
		var report = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		if report is Dictionary and report.get("pid") == OS.get_process_id() and report.get("instance_id") == _control.instance_id:
			DirAccess.remove_absolute(path)
