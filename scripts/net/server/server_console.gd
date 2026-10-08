extends Node

const Channel = preload("res://scripts/net/server/server_console_channel.gd")
const SharedOutput = preload("res://scripts/net/server/server_console_shared_output.gd")
var max_line_bytes:int = 2048
var response_seconds:float = 5.0

func _ready() -> void:
	var args:PackedStringArray = OS.get_cmdline_user_args()
	args.erase("--server-console")
	# 显式共享模式只投影 stdout；默认本机原始身份管理能力不变。
	var shared_log: bool = args.has("--shared-log")
	args.erase("--shared-log")
	if args.size() != 1:
		push_error("控制台启动方式：--server-console 本机控制目录")
		get_tree().quit(2)
		return
	var directory:String = ProjectSettings.globalize_path(args[0])
	if not DirAccess.dir_exists_absolute(directory):
		push_error("本机控制目录不存在，请先启动服务端")
		get_tree().quit(2)
		return
	var parser := JSON.new()
	var control_path:String = directory.path_join("control.json")
	if not FileAccess.file_exists(control_path) or parser.parse(FileAccess.get_file_as_string(control_path)) != OK or not parser.data is Dictionary or not Channel.valid_id(str(parser.data.get("instance",""))):
		push_error("控制目录缺少有效服务实例，请先启动服务端")
		get_tree().quit(2)
		return
	var instance_id:String = parser.data.instance
	print("CONSOLE_READY 输入 help 查看命令；exit 只退出控制台，不停止服务端")
	var line:PackedByteArray = []
	var overflow:bool = false
	while true:
		var bytes:PackedByteArray = OS.read_buffer_from_stdin(1)
		if bytes.is_empty(): break
		if bytes[0] != 10:
			if line.size() < max_line_bytes: line.append_array(bytes)
			else: overflow = true
			continue
		var command:String = line.get_string_from_utf8().strip_edges()
		line.clear()
		if overflow:
			print("CONSOLE_ERROR 命令超过长度预算")
			overflow = false
			continue
		if command == "exit": break
		if command.is_empty(): continue
		var id:String = Crypto.new().generate_random_bytes(16).hex_encode()
		var request_path:String = directory.path_join(id+".request.json")
		var response_path:String = directory.path_join(id+".response.json")
		if Channel.write_json(request_path,{"command":command,"instance":instance_id}) != OK:
			print("CONSOLE_ERROR 无法提交本机命令")
			continue
		var deadline:int = Time.get_ticks_msec()+int(response_seconds*1000)
		while not FileAccess.file_exists(response_path) and Time.get_ticks_msec() < deadline: OS.delay_msec(10)
		if FileAccess.file_exists(response_path):
			print("CONSOLE_RESULT ",SharedOutput.render(FileAccess.get_file_as_string(response_path), shared_log))
			DirAccess.remove_absolute(response_path)
		else:
			DirAccess.remove_absolute(request_path)
			print("CONSOLE_ERROR 服务端响应超时，未认定命令成功")
	get_tree().quit(0)
