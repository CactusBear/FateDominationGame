extends Node

var _system_signals

# 配置角色通过检查之后才构造游戏网关；relay-only 不进入游戏组件链。
var gateway
var signaling = preload("res://scripts/net/p2p/p2p_signal_server.gd").new()
var _status_file: String = ""
var console = preload("res://scripts/net/server/server_console_channel.gd").new()
var _configuration_path:String = ""
var _configuration_snapshot:Dictionary = {}
var shutdown = preload("res://scripts/net/server/server_shutdown.gd").new()

func _ready() -> void:
	var arguments := OS.get_cmdline_user_args()
	arguments.erase("--server-gateway")
	if arguments.size() != 2 or arguments[0] != "--config":
		_fail("启动方式：--server-gateway --config 本机配置.json 或 server.cfg")
		return
	if not FileAccess.file_exists(arguments[1]) and arguments[1].get_extension().to_lower() == "cfg":
		var result:Error = create_configuration(arguments[1])
		if result != OK:
			_fail("无法生成服务端配置：" + error_string(result))
			return
		print("SERVER_CONFIG_CREATED ", arguments[1], "；请检查配置后再次启动，当前未开放监听")
		get_tree().quit(0)
		return
	_configuration_path = arguments[1]
	var configuration = read_configuration(_configuration_path)
	if not configuration is Dictionary:
		_fail("服务端配置无效，CFG 只接受 server、data 与 relay 段")
		return
	var configuration_error:String = preload("res://scripts/net/server/server_bootstrap.gd").configuration_error(configuration)
	if not configuration_error.is_empty():
		_fail(configuration_error)
		return
	for key in ["port", "max_rooms", "max_clients", "internal_port_base", "internal_port_count"]:
		if configuration.has(key):
			var number = configuration[key]
			if typeof(number) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(number)) or number < 1 or number > 65535 or floor(float(number)) != number:
				_fail("服务端端口或预算必须是正整数：" + key)
				return
	var roles:Array = configured_roles(configuration)
	if roles.is_empty():
		_fail("roles 必须是不重复的 game、relay 列表，且不能与 p2p_signaling 冲突")
		return
	if not roles.has("game"):
		_fail("纯 relay 必须使用无 autoload 的独立信令项目；游戏项目不能提供规则隔离")
		return
	gateway = load("res://scripts/net/server/server_gateway.gd").new()
	if not configuration.has("port") or not configuration.get("bind_address", "*") is String or (roles.has("game") and (not configuration.get("data_root") is String or not configuration.get("storage_root") is String)):
		_fail("必须显式声明 port；游戏服务还需 data_root、storage_root")
		return
	if configuration.has("startup_seconds") and (typeof(configuration.startup_seconds) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(configuration.startup_seconds)) or configuration.startup_seconds <= 0 or configuration.startup_seconds >= float((9223372036854775807-Time.get_ticks_msec())/1000)):
		_fail("房间启动时限无效")
		return
	if not configuration.get("p2p_signaling", false) is bool:
		_fail("p2p_signaling 必须是显式布尔开关")
		return
	var data = configuration.get("data", {})
	if not data is Dictionary or data.keys().any(func(key): return key not in ["random_sim_enabled", "random_sim_budget_sec"]) or not preload("res://scripts/net/session/room_state.gd").valid_simulation_settings(data):
		_fail("服务端 data 段必须合法声明随机模拟开关和时间")
		return
	if not configuration.get("server_name", "") is String or not configuration.get("motd", "") is String:
		_fail("服务器名称和公告必须是文本")
		return
	gateway.server_name = configuration.get("server_name", "")
	gateway.motd = configuration.get("motd", "")
	if var_to_bytes({"kind":"server_rooms","rooms":[],"server_name":gateway.server_name,"motd":gateway.motd}).size() > gateway.transport.max_packet_bytes:
		_fail("服务器信息超过单消息预算")
		return
	gateway.manager.data_settings = data.duplicate(true)
	if not configuration.get("relay",{}) is Dictionary or not signaling.configure(configuration.get("relay",{})):
		_fail("信令配置无效：" + signaling.error)
		return
	if roles.has("game"): gateway.manager.storage_root = configuration.storage_root
	if not configuration.get("record_matches", true) is bool:
		_fail("record_matches 必须是显式布尔开关")
		return
	gateway.manager.record_matches = configuration.get("record_matches", true)
	gateway.manager.max_rooms = int(configuration.get("max_rooms", 16))
	gateway.manager.internal_port_base = int(configuration.get("internal_port_base", 52000))
	gateway.manager.internal_port_count = int(configuration.get("internal_port_count", gateway.manager.internal_port_count))
	gateway.manager.startup_seconds = float(configuration.get("startup_seconds", 30.0))
	gateway.max_clients = int(configuration.get("max_clients", 96))
	if gateway.manager.internal_port_count > 65536 - gateway.manager.internal_port_base:
		_fail("内部端口范围超过预算")
		return
	# 所有身份与策略声明在开放外部监听之前验证，避免部分配置先产生副作用。
	var policy_result:Dictionary = preload("res://scripts/net/server/server_policy_config.gd").validate(configuration,gateway.transport.max_packet_bytes)
	if not policy_result.ok:
		_fail(policy_result.error)
		return
	if roles.has("game"):
		if not gateway.manager.has_method("configure_server_policy"):
			_fail("房间管理器尚未接入服务端策略，拒绝启动未声明的权威/审计/恢复行为")
			return
		if not gateway.manager.configure_server_policy(policy_result.policy):
			_fail("服务端策略应用失败："+gateway.manager.error)
			return
	if not configuration.get("status_file", "") is String:
		_fail("status_file 必须是本机状态报告路径文本")
		return
	if not configuration.get("identity_registry","") is String:
		_fail("identity_registry 必须是本机登记库路径")
		return
	var identity_attempts = configuration.get("identity_attempts_per_second", gateway.identity_attempts_per_second)
	if typeof(identity_attempts) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(identity_attempts)) or identity_attempts < 1 or identity_attempts > 2147483647 or floor(float(identity_attempts)) != identity_attempts:
		_fail("identity_attempts_per_second 必须是有效正整数")
		return
	var identity_profile_bytes = configuration.get("identity_profile_max_bytes", gateway.identity_profile_max_bytes)
	if typeof(identity_profile_bytes) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(identity_profile_bytes)) or identity_profile_bytes < 1 or identity_profile_bytes > gateway.transport.max_packet_bytes or floor(float(identity_profile_bytes)) != identity_profile_bytes:
		_fail("identity_profile_max_bytes 必须是有效正整数且不超过单消息预算")
		return
	gateway.identity_attempts_per_second = int(identity_attempts)
	gateway.identity_profile_max_bytes = int(identity_profile_bytes)
	if roles.has("game") and not configuration.get("identity_registry","").is_empty():
		var identity_path:String = LoadHelper.resolve_path(configuration.identity_registry)
		if DirAccess.make_dir_recursive_absolute(identity_path.get_base_dir()) != OK or not gateway.identity_registry.open(identity_path):
			_fail("身份登记库读取失败："+gateway.identity_registry.error)
			return
	gateway.manager.identity_binding_required = roles.has("game") and not configuration.get("identity_registry","").is_empty()
	if roles.has("game") and gateway.listen(int(configuration.port), configuration.get("bind_address", "*"), LoadHelper.resolve_path(configuration.data_root)) != OK:
		_fail("服务端外部入口监听失败")
		return
	if roles.has("relay"):
		signaling.max_clients = gateway.max_clients
		signaling.max_rooms = gateway.manager.max_rooms
		if signaling.listen(int(configuration.port), configuration.get("bind_address", "*")) != OK:
			_fail("同端口 TCP 信令入口监听失败")
			return
	if roles.has("game"):
		var discovery:Dictionary = gateway.manager.discover_rooms()
		print("SERVER_ROOM_DISCOVERY ",JSON.stringify(discovery))
	_status_file = str(configuration.get("status_file", ""))
	var control_limit = configuration.get("max_room_control_requests",console.max_room_requests)
	if typeof(control_limit) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(control_limit)) or control_limit < 1 or control_limit > 2147483647 or floor(float(control_limit)) != control_limit:
		_fail("max_room_control_requests 必须是有效正整数")
		return
	console.max_room_requests = int(control_limit)
	var shutdown_seconds = configuration.get("shutdown_seconds",30.0)
	if typeof(shutdown_seconds) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(shutdown_seconds)) or shutdown_seconds <= 0 or shutdown_seconds >= float((9223372036854775807-Time.get_ticks_msec())/1000):
		_fail("shutdown_seconds 必须是有效正数")
		return
	shutdown.timeout_seconds = float(shutdown_seconds)
	if not configuration.get("console_dir", "") is String:
		_fail("console_dir 必须是本机目录文本")
		return
	var console_directory:String = configuration.get("console_dir", "")
	if console.configure(LoadHelper.resolve_path(console_directory) if not console_directory.is_empty() else "",gateway,signaling) != OK:
		_fail("无法建立本机控制目录")
		return
	_configuration_snapshot = configuration.duplicate(true)
	gateway.admin_console = console
	console.commands["reload"] = {"arguments":0,"handler":_reload_configuration}
	shutdown.gateway = gateway
	shutdown.signaling = signaling
	shutdown.console = console
	shutdown.completed.connect(func(): get_tree().quit(0))
	console.commands["stop"] = {"arguments":0,"handler":shutdown.start}
	console.commands["stop-status"] = {"arguments":0,"handler":shutdown.status}
	_system_signals = preload("res://scripts/net/server/server_process_signals.gd").create()
	if _system_signals == null:
		_fail("系统信号适配器不可用，拒绝启动未经保护的服务端")
		return
	if not _system_signals.enable():
		_fail("系统信号接管失败")
		return
	var report := {"ok": true, "pid": OS.get_process_id(), "port": gateway.transport.bound_port if roles.has("game") else signaling.port, "p2p_signaling": signaling.port > 0, "roles":roles}
	if not _status_file.is_empty():
		if DirAccess.make_dir_recursive_absolute(_status_file.get_base_dir()) != OK:
			_fail("无法建立状态报告目录")
			return
		var temporary:String = _status_file + ".%d.tmp" % OS.get_process_id()
		var file := FileAccess.open(temporary, FileAccess.WRITE)
		if file == null:
			_fail("无法写入状态报告")
			return
		file.store_string(JSON.stringify(report))
		file.flush()
		var result:Error = file.get_error()
		file.close()
		if result != OK or DirAccess.rename_absolute(temporary,_status_file) != OK:
			DirAccess.remove_absolute(temporary)
			_fail("无法完整发布状态报告")
			return
	print("SERVER_GATEWAY_READY ", JSON.stringify(report))

func _reload_configuration(_args:PackedStringArray) -> Dictionary:
	var candidate = read_configuration(_configuration_path)
	if not candidate is Dictionary: return {"ok":false,"error":"配置读取失败，保留当前配置"}
	var fixed:Dictionary = candidate.duplicate(true)
	var previous:Dictionary = _configuration_snapshot.duplicate(true)
	for key in ["server_name","motd","relay"]:
		fixed.erase(key)
		previous.erase(key)
	if fixed != previous: return {"ok":false,"error":"包含需重启的配置变更，本次未应用"}
	var name_value = candidate.get("server_name", "")
	var motd_value = candidate.get("motd", "")
	if not name_value is String or not motd_value is String or not candidate.get("relay",{}) is Dictionary:
		return {"ok":false,"error":"名称、公告或信令配置类型无效，保留当前配置"}
	if var_to_bytes({"kind":"server_rooms","rooms":[],"server_name":name_value,"motd":motd_value}).size() > gateway.transport.max_packet_bytes:
		return {"ok":false,"error":"服务器信息超过消息预算，保留当前配置"}
	# 缺省值按新的完整文件重新计算，避免删除配置项后悄悄保留旧运行值。
	var defaults = preload("res://scripts/net/p2p/p2p_signal_server.gd").new()
	if not defaults.configure(candidate.get("relay",{})): return {"ok":false,"error":defaults.error}
	var relay:Dictionary = {"signal_rate_limit":defaults.max_messages_per_second,"max_packet_bytes":defaults.max_packet_bytes,"ice_timeout_sec":defaults.handshake_seconds,"rooms_per_ip":defaults.rooms_per_ip,"room_code_ttl_sec":defaults.room_code_ttl_sec,"room_code_length":defaults.room_code_length}
	if not signaling.configure(relay): return {"ok":false,"error":signaling.error}
	gateway.server_name = name_value
	gateway.motd = motd_value
	_configuration_snapshot = candidate.duplicate(true)
	return {"ok":true,"result":"名称、公告和信令配置已重载；当前对局数据未改变"}

static func configured_roles(configuration:Dictionary) -> Array:
	return preload("res://scripts/net/server/server_bootstrap.gd").configured_roles(configuration)

static func create_configuration(path:String) -> Error:
	if FileAccess.file_exists(path): return ERR_ALREADY_EXISTS
	var source := FileAccess.open("res://assets/config/server.cfg",FileAccess.READ)
	if source == null: return FileAccess.get_open_error()
	var content:String = source.get_as_text()
	if content.is_empty(): return ERR_FILE_CORRUPT
	var parent:String = path.get_base_dir()
	if not parent.is_empty():
		var result:Error = DirAccess.make_dir_recursive_absolute(parent)
		if result != OK: return result
	var target := FileAccess.open(path,FileAccess.WRITE)
	if target == null: return FileAccess.get_open_error()
	target.store_string(content)
	target.flush()
	var result:Error = target.get_error()
	target.close()
	return result

static func read_configuration(path:String) -> Variant:
	return preload("res://scripts/net/server/server_bootstrap.gd").read_configuration(path)

func _process(_delta: float) -> void:
	if _system_signals != null:
		var request:int = _system_signals.take_request()
		if request != 0:
			print("SERVER_SYSTEM_STOP_REQUEST ",request)
			var response:Dictionary = shutdown.start(PackedStringArray())
			if not response.get("ok",false): print("SERVER_STOP_FAILED ",response.get("error","关闭请求被拒绝"))
	if gateway != null: gateway.poll()
	signaling.poll()
	console.poll()
	shutdown.poll()

func _fail(reason: String) -> void:
	push_error(reason)
	signaling.close()
	if gateway != null: gateway.close()
	get_tree().quit(1)

func _exit_tree() -> void:
	if _system_signals != null:
		_system_signals.disable()
		_system_signals = null
	signaling.close()
	if gateway != null: gateway.close()
	if not _status_file.is_empty():
		DirAccess.remove_absolute(_status_file)
