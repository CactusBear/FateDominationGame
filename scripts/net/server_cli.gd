extends Node

var gateway = preload("res://scripts/net/server_gateway.gd").new()
var signaling = preload("res://scripts/net/p2p_signal_server.gd").new()
var _status_file: String = ""

func _ready() -> void:
	var arguments := OS.get_cmdline_user_args()
	arguments.erase("--server-gateway")
	if arguments.size() != 2 or arguments[0] != "--config":
		_fail("启动方式：--server-gateway --config 本机配置.json")
		return
	var configuration = JSON.parse_string(FileAccess.get_file_as_string(arguments[1]))
	if not configuration is Dictionary:
		_fail("服务端配置不是 JSON 对象")
		return
	var allowed := ["port", "bind_address", "data_root", "storage_root", "max_rooms", "max_clients", "internal_port_base", "startup_seconds", "status_file", "p2p_signaling"]
	for key in configuration:
		if key not in allowed:
			_fail("未识别的服务端配置字段：" + str(key))
			return
	for key in ["port", "max_rooms", "max_clients", "internal_port_base"]:
		if configuration.has(key):
			var number = configuration[key]
			if not number is float or not is_finite(number) or number < 1 or number > 65535 or floor(number) != number:
				_fail("服务端端口或预算必须是正整数：" + key)
				return
	if not configuration.has("port") or not configuration.get("data_root") is String or not configuration.get("storage_root") is String or not configuration.get("bind_address", "*") is String:
		_fail("必须显式声明 port、data_root、storage_root")
		return
	if configuration.has("startup_seconds") and (not configuration.startup_seconds is float or not is_finite(configuration.startup_seconds) or configuration.startup_seconds <= 0):
		_fail("房间启动时限无效")
		return
	if not configuration.get("p2p_signaling", false) is bool:
		_fail("p2p_signaling 必须是显式布尔开关")
		return
	gateway.manager.storage_root = configuration.storage_root
	gateway.manager.max_rooms = int(configuration.get("max_rooms", 16))
	gateway.manager.internal_port_base = int(configuration.get("internal_port_base", 52000))
	gateway.manager.startup_seconds = float(configuration.get("startup_seconds", 30.0))
	gateway.max_clients = int(configuration.get("max_clients", 96))
	if gateway.manager.internal_port_base + gateway.manager.max_rooms > 65536:
		_fail("内部端口范围超过预算")
		return
	if gateway.listen(int(configuration.port), configuration.get("bind_address", "*"), configuration.data_root) != OK:
		_fail("服务端外部入口监听失败")
		return
	if configuration.get("p2p_signaling", false):
		signaling.max_clients = gateway.max_clients
		signaling.max_rooms = gateway.manager.max_rooms
		if signaling.listen(int(configuration.port), configuration.get("bind_address", "*")) != OK:
			_fail("同端口 TCP 信令入口监听失败")
			return
	_status_file = str(configuration.get("status_file", ""))
	var report := {"ok": true, "pid": OS.get_process_id(), "port": gateway.transport.bound_port, "p2p_signaling": signaling.port > 0}
	if not _status_file.is_empty():
		if DirAccess.make_dir_recursive_absolute(_status_file.get_base_dir()) != OK:
			_fail("无法建立状态报告目录")
			return
		var file := FileAccess.open(_status_file, FileAccess.WRITE)
		if file == null:
			_fail("无法写入状态报告")
			return
		file.store_string(JSON.stringify(report))
		file.close()
	print("SERVER_GATEWAY_READY ", JSON.stringify(report))

func _process(_delta: float) -> void:
	gateway.poll()
	signaling.poll()

func _fail(reason: String) -> void:
	push_error(reason)
	signaling.close()
	gateway.close()
	get_tree().quit(1)

func _exit_tree() -> void:
	signaling.close()
	gateway.close()
	if not _status_file.is_empty():
		DirAccess.remove_absolute(_status_file)
