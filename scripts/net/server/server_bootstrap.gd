extends Node

var _signaling
var _signals

# 两种入口共用字段、角色与 CFG 展平规则；不依赖任何游戏脚本。
const CONFIGURATION_FIELDS:Array = ["port", "bind_address", "data_root", "storage_root", "max_rooms", "max_clients", "internal_port_base", "internal_port_count", "startup_seconds", "status_file", "p2p_signaling", "record_matches", "data", "server_name", "motd", "relay", "roles", "console_dir", "max_room_control_requests", "shutdown_seconds", "identity_registry", "identity_attempts_per_second", "identity_profile_max_bytes", "authority_host_mode", "transaction_log", "recovery_key_mismatch", "recovery_inheritance"]
const SIGNALING_FIELDS:Array = ["port", "bind_address", "max_rooms", "max_clients", "p2p_signaling", "relay", "roles"]

static func configuration_error(configuration:Dictionary, signaling_only:bool = false) -> String:
	for key in configuration:
		if key not in CONFIGURATION_FIELDS:
			return "未识别的服务端配置字段：" + str(key)
		if signaling_only and key not in SIGNALING_FIELDS:
			return "纯信令入口不接受游戏或管理配置字段：" + str(key)
	var roles:Array = configured_roles(configuration)
	if roles.is_empty(): return "roles 无效或与 p2p_signaling 冲突"
	if signaling_only and (not configuration.has("roles") or roles != ["relay"]):
		return "纯信令入口需显式 roles=[relay]"
	return ""

static func configured_roles(configuration:Dictionary) -> Array:
	if not configuration.get("p2p_signaling",false) is bool: return []
	if not configuration.has("roles"):
		return ["game","relay"] if configuration.get("p2p_signaling",false) else ["game"]
	if not configuration.roles is Array or configuration.roles.is_empty(): return []
	var roles:Array = []
	for role in configuration.roles:
		if role not in ["game","relay"] or roles.has(role): return []
		roles.append(role)
	if configuration.has("p2p_signaling") and configuration.p2p_signaling != roles.has("relay"): return []
	return roles

static func read_configuration(path:String) -> Variant:
	if path.get_extension().to_lower() != "cfg": return JSON.parse_string(FileAccess.get_file_as_string(path))
	var file := ConfigFile.new()
	if file.load(path) != OK or not file.has_section("server"): return null
	var configuration:Dictionary = {}
	for section in file.get_sections():
		if section not in ["server", "data", "relay"]: return null
		if section in ["data", "relay"]:
			var data:Dictionary = {}
			for key in file.get_section_keys(section): data[key] = file.get_value(section,key)
			configuration[section] = data
		else:
			for key in file.get_section_keys(section):
				if key in ["data","relay"]: return null
				configuration[key] = file.get_value(section,key)
	return configuration

static func has_project_autoloads() -> bool:
	for property in ProjectSettings.get_property_list():
		if str(property.name).begins_with("autoload/"): return true
	return false

static func process_arguments(arguments:PackedStringArray) -> PackedStringArray:
	if OS.has_feature("editor") and not OS.has_feature("fate_server"): return arguments
	var result:PackedStringArray = []
	var index:int = 0
	while index < arguments.size():
		if arguments[index] == "--":
			result.append_array(arguments.slice(index))
			break
		if arguments[index] in ["--path","--scene"]:
			index += 2
			continue
		result.append(arguments[index])
		index += 1
	return result

## Release 导出统一入口；子进程身份由本机启动参数显式声明。
func _ready() -> void:
	var args:PackedStringArray = OS.get_cmdline_user_args()
	var routes:Dictionary = {
		"--server-signaling":"signaling-only",
		"--server-console":"res://assets/scenes/main_menu/server_console.tscn",
		"--server-room-worker":"res://assets/scenes/main_menu/server_room_worker.tscn",
		"--room-data-validation-worker":"res://assets/scenes/main_menu/room_data_validation_worker.tscn",
		"--server-gateway":"res://assets/scenes/main_menu/server_cli.tscn"
	}
	var selected:String = ""
	for flag in routes:
		if args.has(flag):
			if args.count(flag) != 1 or not selected.is_empty():
				push_error("服务端进程只能声明一种职责")
				get_tree().quit(2)
				return
			selected = routes[flag]
	if selected.is_empty(): selected = routes["--server-gateway"]
	if selected == "signaling-only":
		_start_signaling(args)
		return
	get_tree().change_scene_to_file.call_deferred(selected)

## 独立信令职责：不实例化 gateway、room manager、session 或规则 authority。
## 配置兼容 server.cfg，但 roles 必须仅 relay；此入口不提供游戏/房间管理。
func _start_signaling(args:PackedStringArray) -> void:
	args = args.duplicate()
	args.erase("--server-signaling")
	if args.size() != 2 or args[0] != "--config":
		_signal_fail("信令启动方式：--server-signaling --config 本机配置")
		return
	if has_project_autoloads():
		_signal_fail("纯信令必须运行于无 autoload 的独立项目；此项目已加载游戏规则，拒绝冒充隔离")
		return
	var configuration:Variant = read_configuration(args[1])
	if not configuration is Dictionary:
		_signal_fail("信令配置不可读或包含未知 CFG 段/嵌套覆盖")
		return
	var reason:String = configuration_error(configuration,true)
	if not reason.is_empty():
		_signal_fail(reason)
		return
	if not configuration.get("bind_address", "*") is String or not configuration.get("relay", {}) is Dictionary:
		_signal_fail("信令地址或 relay 配置类型无效")
		return
	var port = configuration.get("port")
	var clients = configuration.get("max_clients",96)
	var rooms = configuration.get("max_rooms",16)
	if configuration.has("p2p_signaling") and configuration.p2p_signaling != true:
		_signal_fail("纯信令入口不能声明 p2p_signaling=false")
		return
	if not _positive_integer(port,65535) or not _positive_integer(clients,2147483647) or not _positive_integer(rooms,2147483647):
		_signal_fail("信令端口或连接预算无效")
		return
	_signals = load("res://scripts/net/server/server_process_signals.gd").create()
	if _signals == null or not _signals.enable():
		_signal_fail("信令进程信号保护不可用")
		return
	_signaling = load("res://scripts/net/p2p/p2p_signal_server.gd").new()
	_signaling.max_clients = int(clients)
	_signaling.max_rooms = int(rooms)
	if not _signaling.configure(configuration.get("relay",{})) or _signaling.listen(int(port),configuration.get("bind_address","*")) != OK:
		_signal_fail("信令监听失败：" + _signaling.error)
		return
	print("SERVER_SIGNALING_READY ",JSON.stringify({"ok":true,"pid":OS.get_process_id(),"port":int(port),"roles":["relay"]}))

static func _positive_integer(value:Variant, maximum:int) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) and floor(float(value)) == value and value >= 1 and value <= maximum

func _signal_fail(reason:String) -> void:
	push_error(reason)
	get_tree().quit(2)

func _process(_delta:float) -> void:
	if _signaling == null: return
	if _signals != null and _signals.take_request() != 0:
		get_tree().quit(0)
		return
	_signaling.poll()

func _exit_tree() -> void:
	if _signaling != null: _signaling.close()
	if _signals != null: _signals.disable()
