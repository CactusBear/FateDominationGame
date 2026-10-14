extends "res://newtests/net_server_shutdown_failure_test.gd"

func run() -> void:
	gateway = preload("res://scripts/net/server/server_gateway.gd").new()
	relay = preload("res://scripts/net/p2p/p2p_signal_server.gd").new()
	console = Channel.new()
	root = OS.get_environment("HERMES_SHUTDOWN_TEST_ROOT")
	if root.is_empty() or not root.is_absolute_path():
		check(false,"explicit E scratch root required")
		finish()
		return
	root = root.path_join("emergency-%d" % Time.get_ticks_usec())
	check(console.configure(root.path_join("console"),gateway,relay) == OK,"configure real local console")
	if not gateway.manager.process_ownership_available():
		check(false,"native ownership required")
		finish()
		return
	_watchdog()
	var room:Dictionary = await _spawn("unsaved")
	if room.is_empty():
		await _cleanup()
		finish()
		return
	var prefix:String = "room %s emergency-stop %d %s " % [room.id,room.pid,room.instance_id]
	check(not console.execute(prefix+"--confirm-unsaved-risk 'administrator test'",false).ok and _alive(room),"remote administrator cannot invoke local emergency command")
	check(not console.execute(prefix+"no-confirm 'administrator test'").ok and _alive(room),"missing explicit risk confirmation cannot kill")
	check(not console.execute(prefix+"--confirm-unsaved-risk").ok and _alive(room),"missing reason cannot kill")
	check(not console.execute(prefix+"--confirm-unsaved-risk '   '").ok and _alive(room),"blank reason cannot kill")
	var console_root:String = console.directory
	console.directory = ""
	check(not console.execute(prefix+"--confirm-unsaved-risk 'administrator test'").ok and _alive(room),"unconfigured audit directory cannot kill")
	console.directory = console_root
	var token:String = room.process_token
	room.process_token = "invalid-token"
	var unknown:Dictionary = console.execute(prefix+"--confirm-unsaved-risk 'administrator test'")
	room.process_token = token
	check(not unknown.ok and _alive(room),"unverified native ownership cannot kill")
	var help:Dictionary = console.execute("help")
	check(help.ok and str(help.result).contains("--confirm-unsaved-risk") and str(help.result).contains("可能丢失未保存进度"),"help documents explicit risk confirmation")
	check(not console.execute("room %s emergency-stop %d %s --confirm-unsaved-risk 'stale'" % [room.id,room.pid+1,room.instance_id]).ok and _alive(room),"stale PID cannot kill")
	check(not console.execute("room %s emergency-stop %d %s --confirm-unsaved-risk 'stale'" % [room.id,room.pid,"0".repeat(32)]).ok and _alive(room),"stale instance cannot kill")
	var close:Dictionary = console.execute("room %s close" % room.id)
	check(close.ok,"normal close request accepted")
	var request_id:String = close.result.request_id
	_allow(room,"poll")
	await _wait_file(str(room.directory).path_join("control").path_join(request_id+".response.json"))
	var refused:Dictionary = console._room_result(PackedStringArray([room.id,request_id]))
	check(not refused.ok and not Channel.saved_close_receipt(refused) and _alive(room),"real unsaved match rejects close and stays alive")
	var old_receipt:String = FileAccess.get_sha256(str(room.directory).path_join("control").path_join(request_id+".response.json"))
	var binding:Dictionary = gateway.manager.instance_binding(room.id)
	# 走生产本机命令文件通道；未投递命令的 poll 不会自动升级正常保存拒绝。
	console.poll()
	check(_alive(room),"failed normal close never automatically invokes emergency stop")
	var command_id:String = Crypto.new().generate_random_bytes(16).hex_encode()
	var command_path:String = console.directory.path_join(command_id+".request.json")
	check(Channel.write_json(command_path,{"instance":console.instance_id,"command":prefix+"--confirm-unsaved-risk 'administrator test'"}) == OK,"submit explicit command via real local CLI transport")
	console.poll()
	var response_path:String = console.directory.path_join(command_id+".response.json")
	var stopped = JSON.parse_string(FileAccess.get_file_as_string(response_path))
	if not stopped is Dictionary:
		check(false,"local CLI response required")
		await _cleanup()
		finish()
		return
	check(stopped.ok,"explicit administrator emergency stop executes")
	check(gateway.manager.process_state_for_binding(binding) == 0,"real native handle confirms EXITED")
	if stopped.get("result") is Dictionary:
		check(stopped.result.get("process_exited") == true and stopped.result.get("saved") == false and stopped.result.get("save_confirmed") == false and str(stopped.result.get("warning","")).contains("未确认"),"emergency exit never implies successful save")
		var intent = JSON.parse_string(FileAccess.get_file_as_string(str(stopped.result.get("intent_path",""))))
		var audit = JSON.parse_string(FileAccess.get_file_as_string(str(stopped.result.get("audit_path",""))))
		check(intent is Dictionary and intent.get("stage") == "intent" and intent.get("binding",{}).get("pid") == binding.pid and intent.get("confirmed_unsaved_risk") == true and intent.get("reason") == "administrator test","durable intent binds administrator confirmation reason and process")
		check(audit is Dictionary and audit.get("process_exited") == true and audit.get("saved") == false and audit.get("audit_id") == intent.get("audit_id"),"durable outcome audit can be read back")
	else:
		check(false,"emergency result required")
	check(FileAccess.get_sha256(str(room.directory).path_join("control").path_join(request_id+".response.json")) == old_receipt,"normal failed-save receipt remains byte-identical")
	check(gateway.manager.rooms.has(room.id) and not FileAccess.file_exists(str(room.directory).path_join("recovery.json")),"registration retained and no fake saved recovery file")
	# 同一命令文件重放只读已有回执，不再次执行强停。
	var audit_root:String = console.directory.path_join("emergency-stop")
	var audit_count:int = DirAccess.get_files_at(audit_root).size()
	check(Channel.write_json(command_path,{"instance":console.instance_id,"command":prefix+"--confirm-unsaved-risk 'administrator test'"}) == OK,"replay local command envelope")
	console.poll()
	check(DirAccess.get_files_at(audit_root).size() == audit_count and not FileAccess.file_exists(command_path),"existing CLI receipt suppresses duplicate emergency side effects")
	await _cleanup()
	# 确认新增紧急入口不改变正常成功保存链。
	var healthy:Dictionary = await _spawn("idle")
	if not healthy.is_empty():
		var normal:Dictionary = console.execute("room %s close" % healthy.id)
		check(normal.ok,"healthy normal close still submits")
		_allow(healthy,"poll")
		await _wait_file(str(healthy.directory).path_join("control").path_join(normal.result.request_id+".response.json"))
		await _wait_file(str(healthy.directory).path_join("prepared.json"))
		var saved:Dictionary = console._room_result(PackedStringArray([healthy.id,normal.result.request_id]))
		check(Channel.saved_close_receipt(saved) and FileAccess.file_exists(str(healthy.directory).path_join("recovery.json")) and _alive(healthy),"normal close has real saved receipt and file before exit")
		_allow(healthy,"exit")
		await _wait_exit(healthy)
		console.poll()
		check(not gateway.manager.closed_binding_for_request(healthy.id,normal.result.request_id).is_empty() and healthy.pid == -1,"normal close still confirms save plus exit and releases handle")
	await _cleanup()
	finish()
