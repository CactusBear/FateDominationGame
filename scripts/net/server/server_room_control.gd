extends RefCounted

const Channel = preload("res://scripts/net/server/server_console_channel.gd")
var directory:String = ""
var session
var room_id:String = ""
var authority_host_mode:String = ""
var instance_id:String = Crypto.new().generate_random_bytes(16).hex_encode()
var max_request_bytes:int = 4096
var requests_per_poll:int = 4
signal shutdown_ready
var _identity_ledger
var _identity_setup:bool = false
var identity_receipt_sequence:int = 0
var restore_snapshot:Callable
var restore_transaction:Callable
var _archive_restore = preload("res://scripts/net/server/lan_archive_restore.gd").new()

func poll() -> void:
	if _archive_restore.busy: return
	if directory.is_empty() or not DirAccess.dir_exists_absolute(directory): return
	var count:int = 0
	for filename in DirAccess.get_files_at(directory):
		if count >= requests_per_poll: break
		if not filename.ends_with(".request.json"): continue
		var id:String = filename.trim_suffix(".request.json")
		if not Channel.valid_id(id): continue
		count += 1
		var path:String = directory.path_join(filename)
		var response_path:String = directory.path_join(id+".response.json")
		if FileAccess.file_exists(response_path):
			DirAccess.remove_absolute(path)
			continue
		var request:Dictionary = {}
		var file := FileAccess.open(path,FileAccess.READ)
		if file != null:
			if file.get_length() <= max_request_bytes:
				var parser := JSON.new()
				if parser.parse(file.get_as_text()) == OK and parser.data is Dictionary: request = parser.data
			file.close()
		var response:Dictionary = {"ok":false,"error":"房间管理请求无效或进程已更换"}
		# 恢复只解析本机登记的 archive_id；身份来自当前活连接账本，路径不来自 IPC 请求。
		if request.get("action") == "identity_context":
			var ledger = identity_context()
			response = ledger.install(request) if ledger != null else {"ok":false,"code":"identity_ledger_unavailable","executed":false}
		elif request.get("action") == "restore":
			response = await _archive_restore.execute(self,request)
		elif request.size() == 5 and request.get("room") == room_id and request.get("pid") == OS.get_process_id() and request.get("instance") == instance_id and request.get("authority_host_mode") == authority_host_mode and request.get("action") in ["save","seed","close","pause","resume"]:
			if session.room.phase == "restoring" or session.match_authority._archive_pulse_running: continue
			match request.action:
				"save": response = save()
				"seed": response = seed_value()
				"close": response = prepare_close()
				"pause": response = set_paused(true)
				"resume": response = set_paused(false)
		response["pid"] = OS.get_process_id()
		response["instance"] = instance_id
		response["room"] = room_id
		response["authority_host_mode"] = authority_host_mode
		response["request_id"] = id
		if Channel.write_json(response_path,response) == OK:
			if request.get("action") == "identity_context" and response.get("ok") == true and response.get("result",{}).get("identity_context_installed") == true:
				identity_receipt_sequence = int(response.result.request_seq)
			DirAccess.remove_absolute(path)
			if request.get("action") == "restore" and session._restore_failed_closed:
				shutdown_ready.emit()
				return
			if request.get("action") == "close" and response.get("ok",false):
				shutdown_ready.emit()
				return

func set_paused(value:bool) -> Dictionary:
	if not session.match_authority.confirm_audit(): return {"ok":false,"error":session.match_authority.error}
	if not session.match_authority.started or session.room.phase != "playing": return {"ok":false,"error":"当前没有可暂停或恢复的对局"}
	var previous:bool = session.management_paused
	session.management_paused = value
	if not session._persist_recovery_state():
		session.management_paused = previous
		return {"ok":false,"error":"暂停状态保存失败，原状态未改变"}
	if not session.match_authority.confirm_audit(): return {"ok":false,"error":session.match_authority.error}
	session._publish_match()
	return {"ok":true,"result":{"management_paused":value}}

func prepare_close() -> Dictionary:
	if not session.match_authority.confirm_audit(): return {"ok":false,"error":session.match_authority.error}
	var result:Dictionary
	if session.match_authority.started:
		result = save()
		if not result.ok: return result
	elif not session._persist_recovery_state():
		return {"ok":false,"error":"房间状态写入失败，未关闭"}
	else:
		result = {"ok":true,"result":{"saved":false,"room_state_saved":true}}
	if not session.match_authority.confirm_audit(): return {"ok":false,"error":session.match_authority.error}
	if not session.match_authority.close_archive(): return {"ok":false,"error":"对局日志关闭未确认"}
	result.result["closing"] = true
	return result

func seed_value() -> Dictionary:
	if not session.match_authority.started or session.match_authority._restart_seed == null: return {"ok":false,"error":"当前房间没有运行中的对局种子"}
	return {"ok":true,"result":{"seed":str(session.match_authority._restart_seed)}}

func save() -> Dictionary:
	var authority = session.match_authority
	if not authority.confirm_audit(): return {"ok":false,"error":authority.error}
	if not authority.started or authority.recorder == null: return {"ok":false,"error":"当前对局未启用录制，不能声明存档成功"}
	var recorder = authority.recorder
	if not recorder.error.is_empty(): return {"ok":false,"error":recorder.error}
	if recorder.state_hash() != recorder._last_hash: return {"ok":false,"error":"存在尚未记入存档的状态，未保存"}
	if not recorder.journal.flush(): return {"ok":false,"error":"对局日志刷新失败"}
	if not session._persist_recovery_state(): return {"ok":false,"error":"房间恢复状态写入失败"}
	if not authority.confirm_audit(): return {"ok":false,"error":authority.error}
	return {"ok":true,"result":{"state_hash":recorder._last_hash,"records":recorder.journal._sequence,"saved":true}}

## 内部握手适配器调用此方法取得账本；只管理可信上下文，不解除恢复门禁。
func identity_context():
	if not _identity_setup:
		_identity_setup = true
		var path:String = directory.path_join("identity-context.%s.json" % instance_id)
		var paths = preload("res://scripts/net/server/recovery_path_safety.gd")
		if not paths.checked(directory,path,true) or not paths.checked(directory,path+".tmp",true): return null
		var candidate = preload("res://scripts/net/server/worker_identity_ipc.gd").new()
		if not candidate.configure({"room":room_id,"pid":OS.get_process_id(),"instance":instance_id,"authority_host_mode":authority_host_mode},path): return null
		_identity_ledger = candidate
	return _identity_ledger
