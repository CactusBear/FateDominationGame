extends Node

var _signaling
var _signals

static func process_arguments(arguments:PackedStringArray) -> PackedStringArray:
	if not OS.has_feature("fate_server"): return arguments
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
			if not selected.is_empty():
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
	var configuration:Variant
	if args[1].get_extension().to_lower() == "cfg":
		var file := ConfigFile.new()
		if file.load(args[1]) != OK or not file.has_section("server"):
			_signal_fail("信令配置不可读")
			return
		configuration = {}
		for key in file.get_section_keys("server"): configuration[key] = file.get_value("server",key)
		configuration["relay"] = {}
		if file.has_section("relay"):
			for key in file.get_section_keys("relay"): configuration.relay[key] = file.get_value("relay",key)
	else:
		configuration = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	if not configuration is Dictionary or configuration.get("roles") != ["relay"] or not configuration.get("bind_address", "*") is String or not configuration.get("relay", {}) is Dictionary:
		_signal_fail("纯信令入口需显式 roles=[relay]，不能启动权威规则")
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
	_signals = load("res://scripts/net/server_process_signals.gd").create()
	if _signals == null or not _signals.enable():
		_signal_fail("信令进程信号保护不可用")
		return
	_signaling = load("res://scripts/net/p2p_signal_server.gd").new()
	_signaling.max_clients = int(clients)
	_signaling.max_rooms = int(rooms)
	if not _signaling.configure(configuration.get("relay",{})) or _signaling.listen(int(port),configuration.get("bind_address","*")) != OK:
		_signal_fail("信令监听失败：" + _signaling.error)
		return
	print("SERVER_SIGNALING_READY ",JSON.stringify({"ok":true,"pid":OS.get_process_id(),"port":int(port),"roles":["relay"],"rules_authority_started":false}))

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
