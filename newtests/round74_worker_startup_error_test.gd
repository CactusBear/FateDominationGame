extends Node

const Manager = preload("res://scripts/net/server/server_room_manager.gd")
const Bootstrap = preload("res://scripts/net/server/server_bootstrap.gd")
const Channel = preload("res://scripts/net/server/server_console_channel.gd")
class DeadlineManager extends Manager:
	var test_now:int = -1
	func _startup_now_msec() -> int:
		return Time.get_ticks_msec() if test_now < 0 else test_now

var checks:int = 0
var failures:Array = []
var manager = DeadlineManager.new()
var evidence:Dictionary = {}

func check(value:bool,label:String) -> bool:
	checks += 1
	print("CHECK ",label," ",value)
	if not value: failures.append(label)
	return value

func _ready() -> void:
	var root:String = OS.get_environment("FATE_TEST_SCRATCH_ROOT")
	manager.storage_root = root.path_join("startup-rooms")
	manager.approved_data_root = LoadHelper.get_data_dir()
	if not check(root.begins_with("E:/") and manager.startup_seconds == 30.0,"独占物理 E 输出且生产30秒未改"):
		finish(); return
	var probe := PacketPeerUDP.new()
	if not check(probe.bind(0,"127.0.0.1") == OK,"系统分配单个内部端口"):
		finish(); return
	manager.internal_port_base = probe.get_local_port()
	manager.internal_port_count = 1
	probe.close()
	var modes:Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manager.approved_data_root.path_join("selection_modes.json")))
	var id:String = manager.create_room("启动诊断",{"capacity":4,"minimum":1,"ai_count":0,"selection_mode":modes.default_mode,"spectator_limit":2},manager.approved_data_root)
	if not check(not id.is_empty(),"正式 manager 单 worker native spawn"):
		print("SETUP_ERROR ",manager.error)
		finish(); return
	var binding:Dictionary = manager.instance_binding(id).duplicate(true)
	evidence.binding = binding
	evidence.deadline = manager.rooms[id].deadline
	if OS.get_environment("ROUND74_STARTUP_CASE") == "diagnostic":
		# 只推进夹具时钟，实际期限值保持不变；未READY的本次自有worker由原失败分支清理。
		manager.test_now = manager.rooms[id].deadline
		manager.poll()
		var diagnostic:String = manager.error
		evidence.diagnostic = diagnostic
		check(not manager.is_ready(id) and manager.rooms[id].deadline == evidence.deadline,"截止失败不fake READY或改原deadline")
		check(diagnostic.contains("stage=startup_deadline") and diagnostic.contains("ready_report=missing"),"现manager.error提供精确截止阶段与未发布原因")
		check(diagnostic.contains("pid="+str(binding.pid)) and diagnostic.contains(binding.instance_id) and diagnostic.contains(binding.room) and not diagnostic.contains(str(manager.rooms[id].get("process_token",""))),"失败保留创建PID与实例绑定且不泄漏token")
		var channel = Channel.new()
		channel.gateway = {"manager":manager}
		var info:Dictionary = channel._room_info(PackedStringArray([id]))
		check(info.result.error == diagnostic and manager.rooms[id].error == diagnostic,"现产品room info错误路径消费同一诊断")
		manager.poll()
		check(manager.rooms[id].pid == -1 and manager.error == diagnostic and manager.rooms[id].error == diagnostic,"原EXITED release后保留首错与原绑定")
	else:
		var deadline:int = Time.get_ticks_msec()+40000
		while not manager.is_ready(id) and manager.rooms[id].error.is_empty() and Time.get_ticks_msec()<deadline:
			manager.poll()
			await get_tree().process_frame
		var ready:bool = manager.is_ready(id)
		evidence.diagnostic = manager.error
		if check(ready,"正式默认期限内真实句柄与READY"):
			var path:String = str(manager.rooms[id].directory).path_join("ready.json")
			var report = JSON.parse_string(FileAccess.get_file_as_string(path))
			evidence.ready = report
			check(manager.process_state_for_binding(binding) == 1 and manager.process_identity_verified(binding) and Manager.valid_ready_report(manager.rooms[id],report),"真实native RUNNING与完整报告同绑定")
			actual_argv(id)
		else:
			print("STARTUP_ERROR ",manager.error," room_error=",manager.rooms[id].error)
	finish()

func actual_argv(id:String) -> void:
	var room:Dictionary = manager.rooms[id]
	var expected:PackedStringArray = Bootstrap.role_scene_arguments("--server-room-worker",PackedStringArray(["--headless","--audio-driver","Dummy","--path",ProjectSettings.globalize_path("res://"),"--log-file",ProjectSettings.globalize_path(room.log_file)]),PackedStringArray([ProjectSettings.globalize_path(str(room.directory).path_join("config.json")),ProjectSettings.globalize_path(manager.approved_data_root),ProjectSettings.globalize_path(manager.storage_root)]))
	var output:Array = []
	var command:String = "Get-CimInstance Win32_Process -Filter 'ProcessId = %d' | Select-Object ProcessId,ParentProcessId,ExecutablePath,CommandLine | ConvertTo-Json -Compress" % room.pid
	var code:int = OS.execute("powershell.exe",PackedStringArray(["-NoProfile","-Command",command]),output)
	var actual = JSON.parse_string("".join(output)) if code == 0 else null
	var quoted:PackedStringArray = PackedStringArray(["\""+OS.get_executable_path()+"\""])
	for arg in expected: quoted.append("\""+arg+"\"")
	check(actual is Dictionary and actual.CommandLine == " ".join(quoted) and actual.ParentProcessId == OS.get_process_id(),"OS实际worker argv角色路径和父PID匹配")
	evidence.argv = Array(expected)
	evidence.actual = actual

func finish() -> void:
	# 仅夹具自有空大厅的显式清理，不作为正常保存/关停验收。
	manager.close()
	check(manager.rooms.is_empty(),"只释放本次自有进程")
	var root:String = OS.get_environment("FATE_TEST_SCRATCH_ROOT")
	Channel.write_json(root.path_join("startup-evidence.json"),{"checks":checks,"failures":failures,"evidence":evidence})
	print("RESULT round74_worker_startup_error checks=",checks," failures=",JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
