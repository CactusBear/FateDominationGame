extends Node

const Manager = preload("res://scripts/net/server/server_room_manager.gd")
const Channel = preload("res://scripts/net/server/server_console_channel.gd")
const PREFIX:String = "SERVER_ROOM_STARTUP stage="
const STAGES:Array = ["signal_protection", "launch_arguments", "configuration", "settings", "selection_mode", "catalog_scan", "data_plan", "cache_policy", "cache_population", "data_assembly", "data_validation", "fixed_source_registration", "process_content", "content_environment", "rules_reload", "roster", "host", "recovery_binding", "selection_configuration", "blob_publication", "room_asset_installation", "startup_pin_release", "identity_bridge", "data_approval", "transaction_audit", "ready_publication"]
const SENTINEL:String = "STARTUP_PRIVATE_CONTENT_SENTINEL"
var checks:int = 0
var failures:Array = []
var manager = Manager.new()

func check(value:bool, label:String) -> bool:
	checks += 1
	print("CHECK ", label, " ", value)
	if not value: failures.append(label)
	return value

func _ready() -> void:
	var root:String = OS.get_environment("FATE_TEST_SCRATCH_ROOT")
	var invalid:bool = OS.get_environment("ROUND74_STAGE_CASE") == "invalid"
	manager.storage_root = root.path_join("startup-rooms")
	manager.approved_data_root = LoadHelper.get_data_dir()
	if not check(root.begins_with("E:/") and manager.startup_seconds == 30.0, "物理E输出且原启动期限不变"):
		finish(); return
	if invalid:
		# 仅隔离副本；真实catalog/base/assembler接收此JSON，原validator拒绝标量根。
		var path:String = manager.approved_data_root.path_join("card_backs/startup_invalid.json")
		var file := FileAccess.open(path,FileAccess.WRITE)
		if not check(file != null,"独立冻结副本显式无效数据夹具"):
			finish(); return
		file.store_string(JSON.stringify(SENTINEL))
		file.close()
	var probe := PacketPeerUDP.new()
	if not check(probe.bind(0,"127.0.0.1") == OK,"系统分配单个内部端口"):
		finish(); return
	manager.internal_port_base = probe.get_local_port()
	manager.internal_port_count = 1
	probe.close()
	var modes:Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manager.approved_data_root.path_join("selection_modes.json")))
	var id:String = manager.create_room("阶段标记",{"capacity":4,"minimum":1,"ai_count":0,"selection_mode":modes.default_mode,"spectator_limit":2},manager.approved_data_root)
	if not check(not id.is_empty(),"真实产品manager/native worker启动"):
		finish(); return
	var room:Dictionary = manager.rooms[id]
	var binding:Dictionary = manager.instance_binding(id).duplicate(true)
	var deadline:int = Time.get_ticks_msec()+40000
	while not manager.is_ready(id) and room.error.is_empty() and Time.get_ticks_msec()<deadline:
		manager.poll()
		await get_tree().process_frame
	var ready:bool = manager.is_ready(id)
	if invalid:
		check(not ready and not room.get("ever_ready",false) and room.error.contains("worker_exit_before_ready"),"显式无效数据拒绝且不发布READY")
	else:
		var report = JSON.parse_string(FileAccess.get_file_as_string(str(room.directory).path_join("ready.json"))) if ready else null
		check(ready and manager.process_identity_verified(binding) and Manager.valid_ready_report(room,report),"真实空大厅通过原绑定READY门")
	# 只释放本次自有空大厅；不是保存/恢复/正常关停验收。退出后读日志以免扰动组装发布。
	manager.close()
	check(manager.rooms.is_empty(),"只释放本次自有worker")
	var text:String = FileAccess.get_file_as_string(room.log_file)
	var markers:Array = []
	var syntax_ok:bool = true
	var regex := RegEx.new()
	regex.compile("^SERVER_ROOM_STARTUP stage=([a-z_]+) result=(-1|0|1)$")
	for line in text.split("\n"):
		if not line.begins_with(PREFIX): continue
		var matched = regex.search(line.strip_edges())
		if matched == null:
			syntax_ok = false
		else:
			var stage:String = matched.get_string(1)
			syntax_ok = syntax_ok and stage in STAGES
			markers.append([stage,int(matched.get_string(2))])
	check(syntax_ok and not markers.is_empty(),"标记只有有限固定阶段名与结果码")
	var expected:Array = []
	for stage in STAGES:
		if stage in ["content_environment","rules_reload"]: continue
		expected.append([stage,1])
		if invalid and stage == "data_validation":
			expected.append([stage,-1]); break
		if stage == "process_content":
			for child in ["content_environment","rules_reload"]:
				expected.append([child,1]); expected.append([child,0])
		expected.append([stage,0])
	check(markers == expected,"真实调用进入完成顺序及拒绝点精确匹配")
	var safe:bool = not text.contains(SENTINEL)
	for line in text.split("\n"):
		if not line.begins_with(PREFIX): continue
		for forbidden in [root,manager.approved_data_root,str(binding.pid),str(binding.instance_id),str(binding.room),"token", "ticket", "settings", "data_root", "directory", "port=", "pid=", "instance="]:
			# settings本身是固定阶段名，不作为载荷字段。
			if forbidden == "settings": continue
			safe = safe and not line.contains(forbidden)
	check(safe,"新增阶段标记不含路径身份配置票据内容且数据哨兵不出日志")
	if invalid:
		check(text.contains("JSON 根节点不是对象或数组：card_backs/startup_invalid.json") and not text.contains("SERVER_ROOM_READY ") and not text.contains("SCRIPT ERROR"),"原校验器首拒绝保留且无后续成功标记")
	else:
		check(text.contains("SERVER_ROOM_READY ") and not text.contains("ERROR:") and not text.contains("SCRIPT ERROR"),"原READY日志保留且无引擎错误")
	Channel.write_json(root.path_join("stage-evidence.json"),{"checks":checks,"failures":failures,"invalid":invalid,"markers":markers,"historical_cause":"UNKNOWN"})
	finish()

func finish() -> void:
	manager.close()
	print("RESULT round74_worker_startup_stages checks=",checks," failures=",JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
