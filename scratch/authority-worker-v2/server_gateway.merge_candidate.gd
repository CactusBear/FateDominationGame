class_name ScratchServerGatewayMergeCandidate
extends RefCounted

var transport = preload("res://scripts/net/enet_transport.gd").new()
var manager = preload("res://scripts/net/server_room_manager.gd").new()
var routes: Dictionary = {}
var error: String = ""
## 本地诊断只含固定阶段和错误码，绝不包含消息载荷。
signal send_failed(diagnostic: Dictionary)
var last_send_failure: Dictionary = {}
var max_clients: int = 96
var accepting_rooms:bool = true
var data_root: String = ""
var server_name:String = ""
var motd:String = ""
var identity_registry = preload("res://scripts/net/player_registry.gd").new()
var authenticated_identities:Dictionary = {}
var _identity_challenges:Dictionary = {}
var identity_timeout_seconds:float = 30.0
var identity_attempts_per_second:int = 16
var identity_profile_max_bytes:int = 16384
var _identity_window_msec:int = 0
var _identity_attempts:int = 0
var admin_console
var _admin_sequences:Dictionary = {}
var _identity_admin_flags:Dictionary = {}
var _pending: Dictionary = {}
var _pending_instances:Dictionary = {}
var _creators: Dictionary = {}
var _creator_instances:Dictionary = {}
var _disconnected_routes: Array[int] = []

func _init() -> void:
	transport.message_received.connect(_receive)
	transport.peer_disconnected.connect(_detach)

func listen(port: int, address: String, root: String) -> Error:
	close()
	if not DirAccess.dir_exists_absolute(root):
		error = "服务端本机数据目录不存在"
		return ERR_INVALID_PARAMETER
	data_root = root
	return transport.listen(port, address, max_clients)

func poll() -> void:
	transport.poll()
	for peer in authenticated_identities.keys():
		var id:String = authenticated_identities[peer]
		var admin:bool = identity_registry.users.get(id,{}).get("admin",false) and identity_registry.can_access(id)
		if _identity_admin_flags.get(peer) != admin:
			_identity_admin_flags[peer] = admin
			transport.send(peer,{"kind":"server_identity_permissions","admin":admin})
		if (routes.has(peer) or _pending.has(peer)) and not identity_registry.can_access(id): kick_connection(peer)
	for peer in _identity_challenges.keys():
		if Time.get_ticks_msec() > _identity_challenges[peer].deadline:
			_identity_challenges.erase(peer)
			_fail(peer,"身份认证超时")
	manager.poll()
	for peer in _pending.keys():
		var id: String = _pending[peer]
		var expected:Dictionary = _pending_instances.get(peer,{})
		if not manager.rooms.has(id) or not manager.matches_instance(manager.rooms[id], int(expected.get("pid",-2)), str(expected.get("instance_id",""))) or not manager.rooms[id].error.is_empty():
			_fail(peer, "所选房间启动失败")
			_pending.erase(peer); _pending_instances.erase(peer)
		elif manager.is_ready(id):
			_attach(peer, id)
			_pending.erase(peer); _pending_instances.erase(peer)
	for peer in routes.keys():
		if not routes.has(peer):
			continue
		var route: Dictionary = routes[peer]
		if not manager.is_ready(route.room) or not manager.matches_instance(manager.rooms[route.room], route.pid, route.instance_id):
			_fail(peer, "所选房间已经停止")
			_detach(peer, false)
			continue
		route.link.poll()
		if not route.attached and route.link.is_connected_to_host():
			if _send_client(peer, {"kind": "server_attached", "room": route.room, "peer_id": route.link.peer_id()}, 0, "attach_notice") == OK:
				route.attached = true
			else:
				_fail(peer, "房间绑定通知发送失败，请重新连接")
				if not _disconnected_routes.has(peer): _disconnected_routes.append(peer)
		elif not route.attached and Time.get_ticks_msec() > route.deadline:
			_fail(peer, "内部房间连接超时")
			_detach(peer, false)
	for peer in _disconnected_routes:
		_detach(peer, false)
	_disconnected_routes.clear()

func _receive(peer: int, message: Dictionary) -> void:
	var kind = message.get("kind")
	if kind in ["server_identity_begin","server_identity_proof"]:
		_receive_identity(peer,message)
		return
	if not identity_registry.path.is_empty() and kind != "server_list" and not authenticated_identities.has(peer):
		_fail(peer,"请先完成密钥身份认证")
		return
	if not identity_registry.path.is_empty() and kind != "server_list" and not identity_registry.can_access(authenticated_identities.get(peer,"")):
		_fail(peer,"该密钥身份已被封禁或未获白名单授权")
		return
	if not kind is String:
		_fail(peer, "服务端请求格式无效")
		return
	if kind == "server_admin_command":
		_receive_admin_command(peer,message)
		return
	if kind not in ["server_list", "server_create", "server_join"]:
		if routes.has(peer) and routes[peer].attached:
			if kind == "join":
				message = _room_join_message(peer,message)
				if message.is_empty(): return
			var channel:int = _channel(kind)
			var result:Error = routes[peer].link.send(1, message, channel)
			if result != OK:
				_record_send_failure(peer, channel, "room_request", result)
				_fail(peer, "请求未能完整入队到权威房间；执行状态未确认，请先刷新状态")
		else:
			_fail(peer, "尚未加入服务器房间")
		return
	if message.get("v") != 1 or not message.get("args") is Dictionary:
		_fail(peer, "服务端管理请求格式无效")
		return
	var args: Dictionary = message.args
	if kind == "server_list":
		var visible: Array = []
		for room in manager.rooms.values():
			visible.append({"id": room.id, "name": room.name, "ready": room.ready, "failed": not room.error.is_empty()})
		if _send_client(peer, {"kind": "server_rooms", "rooms": visible, "server_name":server_name, "motd":motd}, 0, "room_list") != OK:
			_fail(peer, "房间列表发送失败")
		return
	if routes.has(peer) or _pending.has(peer):
		_fail(peer, "连接已经绑定房间")
		return
	if kind == "server_create":
		if not accepting_rooms:
			_fail(peer,"服务端正在关闭，不再创建房间")
			return
		if not args.get("name") is String or args.name.length() > 64 or not args.get("settings") is Dictionary:
			_fail(peer, "房间创建参数无效")
			return
		# 内部策略由网关覆盖，不能接受创建者自报的认证开关。
		var settings:Dictionary = args.settings.duplicate(true)
		settings["_gateway_identity_required"] = not identity_registry.path.is_empty()
		var id: String = manager.create_room(args.name, settings, data_root)
		if id.is_empty():
			_fail(peer, manager.error)
		else:
			_creators[id] = peer
			_creator_instances[id] = {"pid":manager.rooms[id].pid,"instance_id":manager.rooms[id].instance_id}
			_queue_room(peer,id)
	elif kind == "server_join":
		if not accepting_rooms:
			_fail(peer,"服务端正在关闭，不再接受加入")
			return
		manager.poll()
		if not args.get("room") is String or not manager.rooms.has(args.room):
			_fail(peer, "所选房间不存在或尚未就绪")
			return
		if _creators.has(args.room):
			_fail(peer, "房间创建者尚未完成连接")
			return
		if not manager.is_ready(args.room):
			if not _valid_room_resume(args.room, args.get("resume"),peer):
				_fail(peer, "未就绪房间只能由原成员凭据恢复")
				return
			if (int(manager.rooms[args.room].pid) <= 0 or not OS.is_process_running(int(manager.rooms[args.room].pid))) and not manager.recover_room(args.room, int(manager.rooms[args.room].pid), str(manager.rooms[args.room].instance_id)):
				_fail(peer, manager.error)
				return
			_queue_room(peer,args.room)
		else:
			_attach(peer, args.room)
	else:
		_fail(peer, "未知服务端请求")

func _valid_room_resume(id:String, ticket:Variant, peer:int = 0) -> bool:
	if not manager.rooms.has(id): return false
	if not ticket is Dictionary or not ticket.get("member") is int or ticket.member <= 0 or not ticket.get("token") is String or ticket.token.length() != 64: return false
	for character in ticket.token:
		if character not in "0123456789abcdef": return false
	var path:String = str(manager.rooms[id].directory).path_join("recovery.json")
	if not FileAccess.file_exists(path): return false
	var state = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not state is Dictionary or not state.get("resume_hashes") is Dictionary or not state.get("resume_previous", {}) is Dictionary: return false
	var member:String = str(ticket.member)
	if not preload("res://scripts/net/member_identity_bindings.gd").valid_state(state,not identity_registry.path.is_empty()): return false
	if not identity_registry.path.is_empty() or state.get("identity_binding_required",false):
		var identity:String = authenticated_identities.get(peer,"")
		if identity_registry.path.is_empty() or not identity_registry.can_access(identity) or not state.get("member_identities") is Dictionary or state.member_identities.get(member) != identity: return false
	var proof:String = ticket.token.sha256_text()
	return proof == state.resume_hashes.get(member, "") or proof == state.get("resume_previous", {}).get(member, "")

func _queue_room(peer:int, id:String) -> void:
	_pending[peer] = id
	_pending_instances[peer] = {"pid":manager.rooms[id].pid,"instance_id":manager.rooms[id].instance_id}

func _attach(peer: int, id: String) -> void:
	# 创建/恢复等待期间权限可能被撤销，实际建立回环路由前再次验证。
	if not identity_registry.path.is_empty() and not identity_registry.can_access(authenticated_identities.get(peer,"")):
		_fail(peer,"该密钥身份已被封禁或未获白名单授权")
		return
	var link = preload("res://scripts/net/enet_transport.gd").new()
	link.message_received.connect(func(sender: int, message: Dictionary):
		if sender == 1 and routes.has(peer):
			if message.get("kind") == "room" and _creators.get(id) == peer and not message.get("state", {}).get("members", []).is_empty():
				_creators.erase(id); _creator_instances.erase(id)
			if _send_client(peer, message, _channel(str(message.get("kind", ""))), "room_response") != OK:
				_fail(peer, "权威房间回复发送失败；执行状态未确认，请先刷新状态"))
	link.peer_disconnected.connect(func(_id: int):
		_fail(peer, "房间连接已断开")
		if not _disconnected_routes.has(peer): _disconnected_routes.append(peer))
	if link.connect_to("127.0.0.1", manager.rooms[id].port) != OK:
		_fail(peer, "无法连接内部房间")
		return
	routes[peer] = {"room": id, "pid":manager.rooms[id].pid, "instance_id":manager.rooms[id].instance_id, "link": link, "attached": false, "deadline": Time.get_ticks_msec() + 10000}

func _detach(peer: int, stop_owned_room: bool = true) -> void:
	_identity_admin_flags.erase(peer)
	_admin_sequences.erase(peer)
	_identity_challenges.erase(peer)
	authenticated_identities.erase(peer)
	_pending.erase(peer); _pending_instances.erase(peer)
	if routes.has(peer):
		routes[peer].link.close()
		routes.erase(peer)
	for id in _creators.keys():
		if _creators[id] == peer:
			if not stop_owned_room: _creators.erase(id); _creator_instances.erase(id); continue
			var expected:Dictionary = _creator_instances.get(id,{})
			if manager.rooms.has(id): manager.stop_room(id,int(expected.get("pid",-2)),str(expected.get("instance_id","")))
			_creators.erase(id); _creator_instances.erase(id)

## OK 仅证明本机发送入队；不证明客机收到或业务执行完成。
func _send_client(peer:int, message:Dictionary, channel:int = 0, stage:String = "client_response") -> Error:
	var result:Error = transport.send(peer, message, channel)
	if result != OK: _record_send_failure(peer, channel, stage, result)
	return result

func _record_send_failure(peer:int, channel:int, stage:String, result:Error) -> void:
	last_send_failure = {"connection":peer,"channel":channel,"stage":stage,"error_code":int(result),"queued":false}
	send_failed.emit(last_send_failure.duplicate(true))

func _fail(peer: int, reason: String) -> void:
	# 错误回执失败不可递归产生新的错误回执。
	_send_client(peer, {"kind": "error", "reason": reason}, 0, "error_receipt")

func kick_connection(peer:int) -> Dictionary:
	if not transport._connected_peers.has(peer): return {"ok":false,"error":"连接不存在"}
	var notice_result:Error = _send_client(peer,{"kind":"server_notice","text":"管理员已断开你的服务端连接"},0,"kick_notice")
	_detach(peer,false)
	transport.disconnect_peer(peer)
	return {"ok":true,"result":{"connection":peer,"disconnect_requested":true,"notice_queued":notice_result == OK,"notice_error_code":int(notice_result)}}

func broadcast_notice(text:String) -> Dictionary:
	var message:Dictionary = {"kind":"server_notice","text":text}
	if text.strip_edges().is_empty() or var_to_bytes(message).size() > transport.max_packet_bytes:
		return {"ok":false,"error":"通知为空或超过消息预算"}
	var queued:int = 0
	var failed:int = 0
	for peer in transport._connected_peers:
		if _send_client(peer,message,0,"broadcast_notice") == OK: queued += 1
		else: failed += 1
	return {"ok":failed == 0,"result":{"queued":queued,"failed":failed}}

func _channel(kind: String) -> int:
	return 2 if kind in ["room_files", "room_files_part", "blob_request", "blob_chunk", "blob_error", "provider_blob_request", "provider_blob_error", "server_data_catalog", "server_data_catalog_part", "server_data_status"] else 0

func close() -> void:
	admin_console = null
	_identity_admin_flags.clear()
	_admin_sequences.clear()
	_identity_challenges.clear()
	_identity_window_msec = 0
	_identity_attempts = 0
	authenticated_identities.clear()
	for peer in routes.keys():
		_detach(peer)
	_pending.clear(); _pending_instances.clear()
	_creators.clear(); _creator_instances.clear()
	transport.close()
	manager.close()

func _receive_identity(peer:int,message:Dictionary) -> void:
	if identity_registry.path.is_empty() or message.get("v") != 1 or not message.get("args") is Dictionary:
		_fail(peer,"身份认证配置或请求无效")
		return
	var args:Dictionary = message.args
	if message.kind == "server_identity_begin":
		if _identity_challenges.has(peer):
			_fail(peer,"身份认证正在进行")
			return
		if args.size() != 3 or not args.get("public_key") is String or not args.get("username") is String or not args.get("nickname") is String:
			_fail(peer,"身份登记字段无效")
			return
		var reason:String = preload("res://scripts/net/player_name_rules.gd").username_error(args.username)
		if not reason.is_empty(): _fail(peer,reason);return
		if args.public_key.to_utf8_buffer().size() > 4096 or var_to_bytes(args).size() > mini(identity_profile_max_bytes,transport.max_packet_bytes):
			_fail(peer,"身份登记超过消息预算")
			return
		var now:int = Time.get_ticks_msec()
		if now - _identity_window_msec >= 1000:
			_identity_window_msec = now
			_identity_attempts = 0
		if _identity_attempts >= identity_attempts_per_second:
			_fail(peer,"身份认证请求超过速率预算，请稍后重试")
			return
		_identity_attempts += 1
		var challenge:PackedByteArray = Crypto.new().generate_random_bytes(32)
		if challenge.size() != 32: _fail(peer,"无法创建认证挑战");return
		_identity_challenges[peer] = {"challenge":challenge,"profile":args.duplicate(true),"deadline":Time.get_ticks_msec()+int(identity_timeout_seconds*1000)}
		transport.send(peer,{"kind":"server_identity_challenge","challenge":challenge})
		return
	if not _identity_challenges.has(peer) or not args.get("signature") is PackedByteArray:
		_fail(peer,"没有可用的身份挑战")
		return
	var pending:Dictionary = _identity_challenges[peer]
	_identity_challenges.erase(peer)
	var profile:Dictionary = pending.profile
	var context:String = JSON.stringify([profile.public_key,profile.username,profile.nickname])
	var identity = preload("res://scripts/net/player_identity.gd")
	if Time.get_ticks_msec() > pending.deadline or not identity.verify_challenge(profile.public_key,pending.challenge,args.signature,context):
		_fail(peer,"密钥身份认证失败")
		return
	var id:String = identity.fingerprint(profile.public_key)
	if authenticated_identities.has(peer) and authenticated_identities[peer] != id:
		_fail(peer,"连接不能替换已有密钥身份")
		return
	var result:Dictionary = identity_registry.register_authenticated(id,profile.username,profile.nickname)
	if not result.ok: _fail(peer,result.error);return
	authenticated_identities[peer] = id
	transport.send(peer,{"kind":"server_identity_ready","identity":id,"username":profile.username,"nickname":profile.nickname})

## 唯一身份注入点；普通客户端的同名字段始终被覆盖。
func _room_join_message(peer:int,message:Dictionary) -> Dictionary:
	if not message.get("args") is Dictionary:
		_fail(peer,"房间加入参数无效")
		return {}
	var result:Dictionary = message.duplicate(true)
	var required:bool = not identity_registry.path.is_empty()
	var identity:String = authenticated_identities.get(peer,"") if required else ""
	if required and not identity_registry.can_access(identity):
		_fail(peer,"该密钥身份已被封禁或未获白名单授权")
		return {}
	result.args["gateway_identity"] = {"required":required,"key":identity}
	if required: result.args.name = identity_registry.users[identity].nickname
	return result

func _receive_admin_command(peer:int,message:Dictionary) -> void:
	var id:String = authenticated_identities.get(peer,"")
	if identity_registry.path.is_empty() or not identity_registry.can_access(id) or not identity_registry.users.get(id,{}).get("admin",false):
		_fail(peer,"当前密钥身份没有管理员权限")
		return
	if admin_console == null or message.get("v") != 1 or not message.get("seq") is int or message.seq <= int(_admin_sequences.get(peer,0)) or not message.get("args") is Dictionary or not message.args.get("command") is String:
		_fail(peer,"管理员命令无效或重复")
		return
	_admin_sequences[peer] = message.seq
	var response:Dictionary = admin_console.execute(message.args.command)
	if _send_client(peer,{"kind":"server_admin_result","request_seq":message.seq,"response":response},0,"admin_result") != OK:
		# 命令已经执行过，不能因回执失败重执行；保留原请求序号供客户端关联。
		_send_client(peer,{"kind":"server_admin_result","request_seq":message.seq,"response":{"ok":false,"error":"管理员命令已返回，但完整结果发送失败；请查询实际状态，不要重复提交写命令","result":{"execution_returned":true,"result_available":false}}},0,"admin_result_fallback")
