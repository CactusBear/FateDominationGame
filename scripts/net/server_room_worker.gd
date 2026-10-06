extends Node

var session = preload("res://scripts/net/lobby_session.gd").new()
var _directory: String = ""
var _room_id: String = ""
var _supervisor_timeout_msec: int = 0
var _supervisor_seen_msec: int = 0
var _supervisor_version: int = -1


func _ready() -> void:
	var arguments := OS.get_cmdline_user_args()
	arguments.erase("--server-room-worker")
	if arguments.size() != 1:
		push_error("房间子进程需要本机配置路径")
		get_tree().quit(2)
		return
	var config = JSON.parse_string(FileAccess.get_file_as_string(arguments[0]))
	if not config is Dictionary or not config.get("data_root") is String or not config.get("directory") is String or not config.get("settings") is Dictionary or not config.get("id") is String or not config.get("port") is float:
		_fail("房间启动配置无效")
		return
	for key in ["capacity", "minimum", "ai_count", "spectator_limit"]:
		if config.settings.has(key):
			var number = config.settings[key]
			if not number is float or not is_finite(number) or number < 0 or number > 2147483647 or floor(number) != number:
				_fail("房间数值配置无效")
				return
			config.settings[key] = int(number)
	if config.settings.has("runtime_guard"):
		if not config.settings.runtime_guard is Dictionary:
			_fail("规则执行预算编码无效")
			return
		var budget:Dictionary = preload("res://scripts/match/rule_budget.gd").decode_json_config(config.settings.runtime_guard)
		if budget.is_empty() or not preload("res://scripts/match/rule_budget.gd").new().configure(budget):
			_fail("规则执行预算编码无效")
			return
		config.settings.runtime_guard = budget
	var root: String = config.data_root
	if not config.get("supervisor_timeout_seconds") is float or not is_finite(config.supervisor_timeout_seconds) or config.supervisor_timeout_seconds <= 1:
		_fail("主管心跳预算无效")
		return
	_directory = config.directory
	_room_id = config.id
	_supervisor_timeout_msec = int(config.supervisor_timeout_seconds * 1000.0)
	var modes = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("selection_modes.json")))
	if not modes is Dictionary or not modes.get("modes") is Array:
		_fail("服务端本机选人配置无效")
		return
	var mode: Dictionary = {}
	for candidate in modes.modes:
		if candidate.get("id") == config.settings.get("selection_mode"):
			mode = candidate
	if mode.is_empty():
		_fail("服务端未声明所选选人模式")
		return
	var catalog = preload("res://scripts/net/data_catalog.gd").new()
	var entries: Array = catalog.scan(root, "server").filter(func(entry): return entry.category != "command_spells")
	if not catalog.errors.is_empty():
		_fail("\n".join(catalog.errors))
		return
	var base: Array = []
	for path in catalog._files(root, "card_backs") + catalog._files(root, "command_spells") + ["selection_modes.json"]:
		if path.get_extension() not in catalog.EXTENSIONS:
			continue
		base.append({"provider": "server", "path": path, "hash": FileAccess.get_sha256(root.path_join(path)), "size": FileAccess.get_file_as_bytes(root.path_join(path)).size()})
	var plan: Dictionary = preload("res://scripts/net/room_data_plan.gd").new().build(entries, base)
	if not plan.ok:
		_fail(plan.error)
		return
	session.blobs.cache.root = config.directory.path_join("cache")
	for index in range(plan.files.size()):
		var bytes := FileAccess.get_file_as_bytes(root.path_join(plan.sources[index].path))
		if not session.blobs.cache.store(plan.files[index].hash, bytes):
			_fail(session.blobs.cache.error)
			return
	var isolated: String = config.directory.path_join("data")
	var assembler = preload("res://scripts/net/room_data_assembler.gd").new()
	if not assembler.assemble(isolated, plan.files, session.blobs.cache):
		_fail(assembler.error)
		return
	var validator = preload("res://scripts/net/room_data_validator.gd").new()
	if not validator.validate(isolated, plan.files):
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
	if session.host(int(config.port), "服务端", settings, "127.0.0.1") != OK:
		_fail(session.error)
		return
	session.dedicated = true
	session.room.members.erase(1)
	session.room.owner = 0
	session.configure_selection(mode, masters, servants)
	for file in plan.files:
		if session.publish_blob(session.blobs.cache.fetch(file.hash)) != file.hash:
			_fail("无法发布批准内容")
			return
	if not session.set_room_files(plan.files) or not session.install_room_assets(isolated):
		_fail(session.error)
		return
	session.require_room_data = true
	session._rules_revision = session.data_revision
	var report := FileAccess.open(config.directory.path_join("ready.json.tmp"), FileAccess.WRITE)
	if report == null:
		_fail("无法写出房间就绪报告")
		return
	report.store_string(JSON.stringify({"ok": true, "id": config.id, "pid": OS.get_process_id(), "port": int(config.port)}))
	report.close()
	if DirAccess.rename_absolute(config.directory.path_join("ready.json.tmp"), config.directory.path_join("ready.json")) != OK:
		_fail("无法发布房间就绪报告")
		return
	print("SERVER_ROOM_READY ", config.id)
	_supervisor_seen_msec = Time.get_ticks_msec()

func _process(delta: float) -> void:
	if not _directory.is_empty() and _supervisor_seen_msec > 0:
		var path := _directory.path_join("supervisor.json")
		var pulse = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		if pulse is Dictionary and pulse.get("id") == _room_id and pulse.get("version") is float and pulse.version > _supervisor_version:
			_supervisor_version = int(pulse.version)
			_supervisor_seen_msec = Time.get_ticks_msec()
		if Time.get_ticks_msec() - _supervisor_seen_msec > _supervisor_timeout_msec:
			print("SERVER_ROOM_SUPERVISOR_LOST ", _room_id)
			get_tree().quit(0)
			return
	if session.transport.is_connected_to_host():
		session.poll(delta)

func _fail(reason: String) -> void:
	push_error(reason)
	session.close()
	get_tree().quit(1)

func _exit_tree() -> void:
	session.close()
	if not _directory.is_empty():
		DirAccess.remove_absolute(_directory.path_join("ready.json"))
