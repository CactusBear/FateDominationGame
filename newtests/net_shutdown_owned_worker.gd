extends Node

# 只用于所有权/控制协议测试：没有网络、身份认证或规则模拟。
# 子进程使用真实 RoomControl 与 LobbySession，文件门只控制处理/自然退出时序。
const Channel = preload("res://scripts/net/server/server_console_channel.gd")
var session
var control
var directory:String = ""
var close_prepared:bool = false
var started_msec:int = 0

func _ready() -> void:
	call_deferred("boot")

func boot() -> void:
	var args:PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 5:
		get_tree().quit(2)
		return
	directory = args[0]
	started_msec = Time.get_ticks_msec()
	session = preload("res://scripts/net/session/lobby_session.gd").new()
	session._host = true
	session.recovery_state_path = directory.path_join("recovery.json")
	if args[3] == "unsaved": session.match_authority.started = true
	elif args[3] == "persist_fail":
		# 已存在的目录占住临时文件位置，实际 FileAccess.open 必然失败。
		DirAccess.make_dir_recursive_absolute(session.recovery_state_path+".%d.tmp" % OS.get_process_id())
	control = preload("res://scripts/net/server/server_room_control.gd").new()
	control.session = session
	control.room_id = args[1]
	control.instance_id = args[2]
	control.authority_host_mode = args[4]
	control.directory = directory.path_join("control")
	DirAccess.make_dir_recursive_absolute(control.directory)
	control.shutdown_ready.connect(func():
		close_prepared = true
		Channel.write_json(directory.path_join("prepared.json"),{"pid":OS.get_process_id(),"instance":control.instance_id})
	)
	Channel.write_json(directory.path_join("ready.json"),{"id":control.room_id,"room_id":control.room_id,"pid":OS.get_process_id(),"instance":control.instance_id,"instance_id":control.instance_id,"authority_host_mode":control.authority_host_mode})

func _process(_delta:float) -> void:
	if control == null: return
	if FileAccess.file_exists(directory.path_join("exit.allow")):
		# 退出门故意独立于 shutdown_ready，覆盖“先退出却无回执”反例。
		session.match_authority.started = false
		session.close()
		get_tree().quit(0)
		return
	if FileAccess.file_exists(directory.path_join("poll.allow")): control.poll()
	if Time.get_ticks_msec()-started_msec > 600000:
		# 自然自退而非由父测试强杀；超时不得被算作关闭成功。
		session.match_authority.started = false
		session.close()
		get_tree().quit(3)
