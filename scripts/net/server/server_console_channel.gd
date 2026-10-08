extends RefCounted

## 本机管理通道，只接收白名单命令；不注册到网络消息入口。
var directory:String = ""
var max_request_bytes:int = 4096
var requests_per_poll:int = 4
var max_room_requests:int = 128
var gateway
var signaling
var commands:Dictionary = {}
var instance_id:String = ""
## 包括单房间 close；直到最终拒绝或成功回执+真实退出才移除。
var _closing_requests:Dictionary = {}

func configure(root:String,game,relay) -> Error:
	directory = root
	gateway = game
	signaling = relay
	commands = {
		"help":{"arguments":0,"handler":_help},
		"status":{"arguments":0,"handler":_status},
		"rooms":{"arguments":0,"handler":_rooms},
		"list":{"arguments":0,"handler":_list_clients},
		"say":{"arguments":1,"handler":_say},
		"kick":{"arguments":1,"handler":_kick},
		"players":{"arguments":0,"handler":_players},
		"op":{"arguments":1,"handler":_identity_permission.bind("admin",true)},
		"deop":{"arguments":1,"handler":_identity_permission.bind("admin",false)},
		"ban":{"arguments":1,"handler":_identity_permission.bind("banned",true)},
		"pardon":{"arguments":1,"handler":_identity_permission.bind("banned",false)},
		"whitelist on":{"arguments":0,"handler":_whitelist_switch.bind(true)},
		"whitelist off":{"arguments":0,"handler":_whitelist_switch.bind(false)},
		"whitelist add":{"arguments":1,"handler":_identity_permission.bind("whitelisted",true)},
		"whitelist remove":{"arguments":1,"handler":_identity_permission.bind("whitelisted",false)},
		"whitelist list":{"arguments":0,"handler":_whitelist_list},
		"room info":{"arguments":1,"handler":_room_info},
		"room create":{"arguments":2,"handler":_room_create},
		"room save":{"arguments":1,"handler":_room_save},
		"room seed":{"arguments":1,"handler":_room_seed},
		"room close":{"arguments":1,"handler":_room_close},
		"room pause":{"arguments":1,"handler":_room_pause},
		"room resume":{"arguments":1,"handler":_room_resume},
		"room kick":{"arguments":2,"handler":_room_kick},
		"room result":{"arguments":2,"handler":_room_result},
		"room forget":{"arguments":2,"handler":_room_forget},
		"room legacy-approve":{"arguments":5,"handler":_room_legacy_approve},
		"room legacy-reject":{"arguments":3,"handler":_room_legacy_reject},
		"relay status":{"arguments":0,"handler":_relay_status},
		"relay close":{"arguments":1,"handler":_relay_close},
		"relay limit":{"arguments":2,"handler":_relay_limit}
	}
	if directory.is_empty(): return OK
	var result:Error = DirAccess.make_dir_recursive_absolute(directory)
	if result != OK: return result
	var control_path:String = directory.path_join("control.json")
	if FileAccess.file_exists(control_path):
		var parser := JSON.new()
		if parser.parse(FileAccess.get_file_as_string(control_path)) != OK or not parser.data is Dictionary: return ERR_FILE_CORRUPT
		if int(parser.data.get("pid",0)) > 0 and OS.is_process_running(int(parser.data.pid)): return ERR_ALREADY_IN_USE
	instance_id = Crypto.new().generate_random_bytes(16).hex_encode()
	return write_json(control_path,{"instance":instance_id,"pid":OS.get_process_id()})

func execute(line:String, trusted_local:bool = true) -> Dictionary:
	if line.to_utf8_buffer().size() > max_request_bytes: return {"ok":false,"error":"命令超过长度预算"}
	var parsed:Dictionary = preload("res://scripts/net/server/server_command_line.gd").parse(line)
	if not parsed.ok: return parsed
	var parts:PackedStringArray = parsed.tokens
	if parts.is_empty(): return {"ok":false,"error":"命令为空"}
	var command:String = parts[0]
	var offset:int = 1
	if command in ["relay","whitelist"] and parts.size() > 1:
		command += " " + parts[1]
		offset = 2
	elif command == "room" and parts.size() > 1 and parts[1] == "create":
		command += " create"
		offset = 2
	elif command == "room" and parts.size() > 2:
		command += " " + parts[2]
		parts = PackedStringArray([parts[0],parts[2],parts[1]]) + parts.slice(3)
		offset = 2
	if not commands.has(command): return {"ok":false,"error":"未知命令，请输入 help"}
	if command in ["room legacy-approve","room legacy-reject"] and not trusted_local:
		return {"ok":false,"error":"旧档迁移仅允许可信本机控制台"}
	var arguments:PackedStringArray = parts.slice(offset)
	if arguments.size() != commands[command].arguments: return {"ok":false,"error":"命令参数数量无效"}
	var response:Dictionary = commands[command].handler.call(arguments)
	print("SERVER_CONSOLE ",command," ok=",response.get("ok",false))
	return response

func _players(_args:PackedStringArray) -> Dictionary:
	var result:Array = []
	for id in gateway.identity_registry.users:
		var record:Dictionary = gateway.identity_registry.users[id].duplicate(true)
		record.identity = id
		result.append(record)
	return {"ok":true,"result":result}

func _identity_permission(args:PackedStringArray,permission:String,enabled:bool) -> Dictionary:
	return gateway.identity_registry.set_permission(args[0],permission,enabled)

func _whitelist_list(_args:PackedStringArray) -> Dictionary:
	return {"ok":true,"result":{"enabled":gateway.identity_registry.whitelist_enabled,"players":_players(PackedStringArray()).result.filter(func(record): return record.get("whitelisted",false))}}

func _whitelist_switch(_args:PackedStringArray,enabled:bool) -> Dictionary:
	return gateway.identity_registry.set_whitelist(enabled)

func poll() -> void:
	_poll_room_closes()
	if directory.is_empty(): return
	var count:int = 0
	for filename in DirAccess.get_files_at(directory):
		if count >= requests_per_poll: break
		if not filename.ends_with(".request.json"): continue
		var id:String = filename.trim_suffix(".request.json")
		if not valid_id(id): continue
		count += 1
		var path:String = directory.path_join(filename)
		var file := FileAccess.open(path,FileAccess.READ)
		var response:Dictionary = {"ok":false,"error":"本机命令请求无效"}
		if file != null and file.get_length() <= max_request_bytes:
			var parser := JSON.new()
			if parser.parse(file.get_as_text()) == OK and parser.data is Dictionary and parser.data.size() == 2 and parser.data.get("instance") == instance_id and parser.data.get("command") is String:
				response = execute(parser.data.command)
		if file != null: file.close()
		if write_json(directory.path_join(id+".response.json"),response) == OK:
			DirAccess.remove_absolute(path)

static func valid_id(id:String) -> bool:
	if id.length() != 32: return false
	for character in id:
		if character not in "0123456789abcdef": return false
	return true

static func write_json(path:String,value:Dictionary) -> Error:
	var temporary:String = path+".tmp"
	var file := FileAccess.open(temporary,FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(value))
	file.flush()
	var result:Error = file.get_error()
	file.close()
	if result != OK: return result
	return DirAccess.rename_absolute(temporary,path)

func _help(_args:PackedStringArray) -> Dictionary:
	var usage:PackedStringArray = []
	for command in commands:
		var line:String = command
		if command == "room create": line += " <name> <settings_json>"
		elif command.begins_with("room "):
			line = "room <id> " + command.trim_prefix("room ")
			if command in ["room result","room forget"]: line += " <request_id>"
			elif command == "room kick": line += " <connection_id>"
			elif command == "room legacy-approve": line += " <pid> <instance_id> legacy_approved '<member_to_connection_json>'"
			elif command == "room legacy-reject": line += " <pid> <instance_id>"
		elif command == "relay close": line += " <room_code>"
		elif command == "relay limit": line += " <key> <number>"
		elif command == "say": line += " \"<text>\""
		elif command == "kick": line += " <connection_id>"
		usage.append(line)
	return {"ok":true,"result":Array(usage)}

func _status(_args:PackedStringArray) -> Dictionary:
	return {"ok":true,"result":{"game_port":gateway.transport.bound_port,"rooms":gateway.manager.rooms.size(),"attached_clients":gateway.routes.size(),"pending_clients":gateway._pending.size(),"relay_port":signaling.port,"server_name":gateway.server_name,"motd":gateway.motd}}

func _rooms(_args:PackedStringArray) -> Dictionary:
	var result:Array = []
	for room in gateway.manager.rooms.values():
		result.append({"id":room.id,"name":room.name,"ready":room.ready,"error":room.error,"pid":room.pid})
	return {"ok":true,"result":result}

func _list_clients(_args:PackedStringArray) -> Dictionary:
	var result:Array = []
	for peer in gateway.routes:
		var route:Dictionary = gateway.routes[peer]
		result.append({"connection":peer,"room":route.room,"attached":route.attached})
	for peer in gateway._pending:
		result.append({"connection":peer,"room":gateway._pending[peer],"attached":false})
	return {"ok":true,"result":result}

func _say(args:PackedStringArray) -> Dictionary:
	return gateway.broadcast_notice(args[0])

func _kick(args:PackedStringArray) -> Dictionary:
	if not args[0].is_valid_int() or args[0].to_int() <= 1 or args[0].to_int() > 2147483647: return {"ok":false,"error":"连接编号必须是有效整数"}
	return gateway.kick_connection(args[0].to_int())

func _room_create(args:PackedStringArray) -> Dictionary:
	if not gateway.accepting_rooms: return {"ok":false,"error":"服务端正在关闭，不再创建房间"}
	if not gateway.transport.is_connected_to_host(): return {"ok":false,"error":"游戏服务未启动，不能创建房间"}
	var parser := JSON.new()
	if parser.parse(args[1]) != OK or not parser.data is Dictionary: return {"ok":false,"error":"房间设置必须是 JSON 对象"}
	var decoded:Dictionary = preload("res://scripts/net/session/room_state.gd").decode_json_settings(parser.data)
	if not decoded.ok: return decoded
	var id:String = gateway.manager.create_room(args[0],decoded.settings,gateway.data_root)
	if id.is_empty(): return {"ok":false,"error":gateway.manager.error}
	return {"ok":true,"result":{"id":id,"status":"pending","ready":false}}

func _room_info(args:PackedStringArray) -> Dictionary:
	if not gateway.manager.rooms.has(args[0]): return {"ok":false,"error":"房间不存在"}
	var room:Dictionary = gateway.manager.rooms[args[0]]
	return {"ok":true,"result":{"id":room.id,"name":room.name,"ready":room.ready,"error":room.error,"pid":room.pid,"internal_port":room.port}}

func _room_kick(args:PackedStringArray) -> Dictionary:
	if not gateway.manager.rooms.has(args[0]): return {"ok":false,"error":"房间不存在"}
	if not args[1].is_valid_int(): return {"ok":false,"error":"连接编号必须是有效整数"}
	var connection:int = args[1].to_int()
	if gateway.routes.get(connection,{}).get("room","") != args[0]: return {"ok":false,"error":"连接不属于指定房间"}
	return _kick(PackedStringArray([args[1]]))

func _relay_status(_args:PackedStringArray) -> Dictionary:
	var registrations:Array = []
	for code in signaling._rooms:
		var waiting:int = 0
		var answered:int = 0
		for client in signaling._clients.values():
			if client.room != code or client.host: continue
			if client.answered: answered += 1
			else: waiting += 1
		var expires:int = int(signaling._rooms[code].expires)
		registrations.append({"code":code,"pending_handshakes":waiting,"answered_handshakes":answered,"expires_in_msec":maxi(0,expires-Time.get_ticks_msec()) if expires > 0 else null})
	return {"ok":true,"result":{"port":signaling.port,"clients":signaling._clients.size(),"rooms":signaling._rooms.size(),"registrations":registrations,"signal_rate_limit":signaling.max_messages_per_second,"rooms_per_ip":signaling.rooms_per_ip}}

func _room_legacy_approve(args:PackedStringArray) -> Dictionary:
	if not args[1].is_valid_int() or str(args[1].to_int()) != args[1]: return {"ok":false,"error":"PID 格式无效"}
	var parsed:Dictionary = preload("res://scripts/net/identity/legacy_identity_migration.gd").parse_approval(args[3],args[4])
	if not parsed.ok: return parsed
	return gateway.console_legacy_migration(args[0],args[1].to_int(),args[2],true,parsed.selected)

func _room_legacy_reject(args:PackedStringArray) -> Dictionary:
	if not args[1].is_valid_int() or str(args[1].to_int()) != args[1]: return {"ok":false,"error":"PID 格式无效"}
	return gateway.console_legacy_migration(args[0],args[1].to_int(),args[2],false,{})

func _room_save(args:PackedStringArray) -> Dictionary:
	return _room_request(args[0],"save")

func _room_seed(args:PackedStringArray) -> Dictionary:
	return _room_request(args[0],"seed")

func _room_close(args:PackedStringArray) -> Dictionary:
	return _room_request(args[0],"close")

func _room_pause(args:PackedStringArray) -> Dictionary:
	return _room_request(args[0],"pause")

func _room_resume(args:PackedStringArray) -> Dictionary:
	return _room_request(args[0],"resume")

## 常规 console 泵送承担单房间 close 的生命周期，不依赖 server_shutdown。
func _poll_room_closes() -> void:
	for room_id in _closing_requests.keys():
		var request:Dictionary = _closing_requests[room_id]
		var response:Dictionary = _room_result(PackedStringArray([room_id,request.request_id]))
		# 本地读错、pending、错实例都不是 worker 的最终拒绝。
		if response.get("room") != request.binding.room or response.get("pid") != request.binding.pid or response.get("instance") != request.binding.instance_id or response.get("authority_host_mode") != request.binding.authority_host_mode or response.get("request_id") != request.request_id:
			if gateway.manager.process_state_for_binding(request.binding) == 0 and gateway.manager.retire_unconfirmed_close(request.binding,request.request_id): _closing_requests.erase(room_id)
			continue
		if response.get("ok") == false:
			if gateway.manager.cancel_process_supervision(request.binding,request.request_id): _closing_requests.erase(room_id)
			continue
		if response.get("ok") != true or not response.get("result",{}).get("closing",false): continue
		if gateway.manager.closed_binding_for_request(room_id,request.request_id) == request.binding.merged({"request_id":request.request_id}):
			_closing_requests.erase(room_id)
		elif gateway.manager.process_state_for_binding(request.binding) == 0 and gateway.manager.release_process_for_binding(request.binding,request.request_id):
			_closing_requests.erase(room_id)

func _room_request(room_id:String,action:String) -> Dictionary:
	if action == "close":
		_poll_room_closes()
		if _closing_requests.has(room_id): return {"ok":true,"result":{"status":"pending","request_id":_closing_requests[room_id].request_id}}
	if not gateway.manager.rooms.has(room_id) or not gateway.manager.is_ready(room_id): return {"ok":false,"error":"房间不存在或未就绪"}
	var room:Dictionary = gateway.manager.rooms[room_id]
	var parser := JSON.new()
	var ready_path:String = str(room.directory).path_join("ready.json")
	if not FileAccess.file_exists(ready_path) or parser.parse(FileAccess.get_file_as_string(ready_path)) != OK or not parser.data is Dictionary:
		return {"ok":false,"error":"房间就绪报告不可读"}
	if parser.data.get("id") != room_id or parser.data.get("pid") != room.pid or not valid_id(str(parser.data.get("instance",""))):
		return {"ok":false,"error":"房间实例不匹配，不提交管理请求"}
	var instance:String = parser.data.instance
	var root:String = str(room.directory).path_join("control")
	if DirAccess.make_dir_recursive_absolute(root) != OK: return {"ok":false,"error":"无法建立房间管理目录"}
	var requests:Dictionary = {}
	for filename in DirAccess.get_files_at(root):
		for suffix in [".request.json",".response.json"]:
			if filename.ends_with(suffix):
				var existing:String = filename.trim_suffix(suffix)
				if valid_id(existing): requests[existing] = true
	if requests.size() >= max_room_requests: return {"ok":false,"error":"房间管理请求已达预算，请先清理已完成回执"}
	var id:String = Crypto.new().generate_random_bytes(16).hex_encode()
	var binding:Dictionary = gateway.manager.instance_binding(room_id)
	if action == "close" and not gateway.manager.hold_process_supervision(room_id,id): return {"ok":false,"error":"无法持有关闭监督；未提交关闭请求"}
	if write_json(root.path_join(id+".request.json"),{"room":room_id,"pid":room.pid,"instance":instance,"authority_host_mode":room.get("authority_host_mode",""),"action":action}) != OK:
		if action == "close": gateway.manager.cancel_process_supervision(binding,id)
		return {"ok":false,"error":"无法提交房间管理请求"}
	if action == "close": _closing_requests[room_id] = {"binding":binding,"request_id":id}
	var result:Dictionary = {"status":"pending","request_id":id}
	if action == "save": result["saved"] = false
	return {"ok":true,"result":result}

func _room_result(args:PackedStringArray) -> Dictionary:
	if not gateway.manager.rooms.has(args[0]) or not valid_id(args[1]): return {"ok":false,"error":"房间或请求编号无效"}
	var room:Dictionary = gateway.manager.rooms[args[0]]
	var root:String = str(room.directory).path_join("control")
	var path:String = root.path_join(args[1]+".response.json")
	if not FileAccess.file_exists(path):
		var process_state:int = gateway.manager.process_state_for_binding(gateway.manager.instance_binding(args[0]))
		if process_state != 1: return {"ok":false,"error":"原生句柄不可用或房间已退出，未确认操作成功"}
		return {"ok":true,"result":{"status":"pending"}} if FileAccess.file_exists(root.path_join(args[1]+".request.json")) else {"ok":false,"error":"房间管理请求不存在"}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary or parser.data.get("request_id") != args[1]: return {"ok":false,"error":"房间保存回执无效"}
	var response:Dictionary = parser.data
	var binding:Dictionary = gateway.manager.instance_binding(args[0])
	var retired:Dictionary = gateway.manager.retired_binding_for_request(args[0],args[1])
	if not retired.is_empty(): binding = retired
	var closed:Dictionary = gateway.manager.closed_binding_for_request(args[0],args[1])
	if not closed.is_empty():
		if response.get("ok") != true or not response.get("result",{}).get("closing",false): return {"ok":false,"error":"最终关闭回执无效"}
		binding = closed
	if response.get("room") != args[0] or response.get("pid") != binding.get("pid") or response.get("instance") != binding.get("instance_id") or response.get("authority_host_mode") != binding.get("authority_host_mode"): return {"ok":false,"error":"房间保存回执的进程实例不匹配"}
	var request_path:String = root.path_join(args[1]+".request.json")
	if FileAccess.file_exists(request_path):
		var request_parser := JSON.new()
		if request_parser.parse(FileAccess.get_file_as_string(request_path)) != OK or not request_parser.data is Dictionary: return {"ok":false,"error":"房间管理请求无效"}
		var request:Dictionary = request_parser.data
		if request.get("room") != args[0] or request.get("pid") != binding.get("pid") or request.get("instance") != binding.get("instance_id") or request.get("authority_host_mode") != binding.get("authority_host_mode"): return {"ok":false,"error":"房间管理请求的进程实例不匹配"}
	return response

func _room_forget(args:PackedStringArray) -> Dictionary:
	if not gateway.manager.rooms.has(args[0]) or not valid_id(args[1]): return {"ok":false,"error":"房间或请求编号无效"}
	var root:String = str(gateway.manager.rooms[args[0]].directory).path_join("control")
	if FileAccess.file_exists(root.path_join(args[1]+".request.json")): return {"ok":false,"error":"请求尚未清理完成，不能删除回执"}
	var response_path:String = root.path_join(args[1]+".response.json")
	if not FileAccess.file_exists(response_path): return {"ok":false,"error":"已完成回执不存在"}
	if DirAccess.remove_absolute(response_path) != OK: return {"ok":false,"error":"回执删除失败"}
	gateway.manager._retired_close_bindings.erase(args[1])
	return {"ok":true,"result":"已清理管理回执，对局存档未删除"}

func _relay_close(args:PackedStringArray) -> Dictionary:
	if not signaling.close_room(args[0]): return {"ok":false,"error":"信令房间不存在"}
	return {"ok":true,"result":"已关闭信令登记，既有游戏直连不受影响"}

func _relay_limit(args:PackedStringArray) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(args[1]) != OK: return {"ok":false,"error":"限制值必须是合法数值"}
	if not signaling.configure({args[0]:parser.data}): return {"ok":false,"error":signaling.error}
	return {"ok":true,"result":"运行时限制已更新，配置文件未改写"}
