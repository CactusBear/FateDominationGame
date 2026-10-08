class_name ServerGateway
extends RefCounted

var transport = preload("res://scripts/net/transport/enet_transport.gd").new()
var manager = preload("res://scripts/net/server/server_room_manager.gd").new()
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
var identity_registry = preload("res://scripts/net/identity/player_registry.gd").new()
var authenticated_identities:Dictionary = {}
var _identity_challenges:Dictionary = {}
## 仅房主直连适配器设置；dedicated 保持 null。
var lan_identity:RefCounted
var identity_timeout_seconds:float = 30.0
var identity_attempts_per_second:int = 16
var identity_profile_max_bytes:int = 16384
var _identity_window_msec:int = 0
var _identity_attempts:int = 0
var admin_console
var _admin_sequences:Dictionary = {}
var _identity_admin_flags:Dictionary = {}
var _pending: Dictionary = {}
var _creators: Dictionary = {}
var _disconnected_routes: Array[Dictionary] = []
var _deferred_peer_detaches: Array[int] = []

func _init() -> void:
	transport.message_received.connect(_receive)
	transport.peer_disconnected.connect(_queue_peer_detach)
	transport.packet_rejected.connect(_client_packet_rejected)
	send_failed.connect(_log_transport_diagnostic)

func listen(port: int, address: String, root: String) -> Error:
	close()
	if not DirAccess.dir_exists_absolute(root):
		error = "服务端本机数据目录不存在"
		return ERR_INVALID_PARAMETER
	data_root = root
	return transport.listen(port, address, max_clients)

func poll() -> void:
	transport.poll()
	var peer_detaches:Array[int] = _deferred_peer_detaches.duplicate()
	_deferred_peer_detaches.clear()
	for peer in peer_detaches:
		_detach(peer)
	for peer in authenticated_identities.keys():
		var id:String = authenticated_identities[peer]
		var admin:bool = identity_registry.users.get(id,{}).get("admin",false) and identity_registry.can_access(id)
		if _identity_admin_flags.get(peer) != admin:
			if _send_client(peer,{"kind":"server_identity_permissions","admin":admin},0,"identity_permissions") == OK:
				_identity_admin_flags[peer] = admin
			else:
				_identity_admin_flags.erase(peer)
		if (routes.has(peer) or _pending.has(peer)) and not identity_registry.can_access(id): kick_connection(peer)
	for peer in _identity_challenges.keys():
		if Time.get_ticks_msec() > _identity_challenges[peer].deadline:
			_identity_challenges.erase(peer)
			_fail(peer,"身份认证超时")
	manager.poll()
	for peer in _pending.keys():
		var binding:Dictionary = _pending[peer]
		if not manager.binding_matches(binding) or not manager.rooms[binding.room].error.is_empty():
			_fail(peer, "所选房间实例已停止或更换，请重新连接")
			_pending.erase(peer)
			_release_creator(peer,binding)
		elif manager.rooms[binding.room].ready and not manager.process_identity_verified(binding):
			_fail(peer,"房间缺少可信 OS 进程句柄验证，拒绝连接")
			_pending.erase(peer)
			_release_creator(peer,binding)
		elif manager.binding_matches(binding,true):
			_attach(peer, binding.room, binding)
			_pending.erase(peer)
			if not routes.has(peer): _release_creator(peer,binding)
	for peer in routes.keys():
		if not routes.has(peer):
			continue
		var route: Dictionary = routes[peer]
		if not _route_is_current(peer,route):
			_fail(peer, "所选房间已经停止或实例校验失败")
			_detach_route(peer,route)
			continue
		_recovery_route_sample(peer,route,"route_poll")
		route.link.poll()
		# poll 可能同步触发旧回调或清理；后续不得再操作失效路由。
		if not _route_is_current(peer,route): continue
		if not route.attached and route.link.is_connected_to_host():
			if _send_client(peer, {"kind": "server_attached", "room": route.room, "peer_id": route.link.peer_id()}, 0, "attach_notice") == OK:
				route.attached = true
			else:
				_fail(peer, "房间绑定通知发送失败，请重新连接")
				_queue_route_disconnect(peer,route)
		elif not route.attached and Time.get_ticks_msec() > route.deadline:
			_fail(peer, "内部房间连接超时")
			_detach_route(peer,route)
	var disconnected:Array[Dictionary] = _disconnected_routes.duplicate()
	_disconnected_routes.clear()
	for callback in disconnected:
		if not _same_route(callback.peer,callback.route): continue
		if callback.get("notify",false):
			_fail(callback.peer,"房间连接已断开")
		_detach_route(callback.peer,callback.route)

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
		# 仅协议信封允许的字段可转发；可信上下文只能在下方由网关添加。
		message = _public_room_request(message)
		if message.is_empty():
			_fail(peer, "房间请求字段无效")
			return
		if kind in ["identity_candidates","identity_inherit"] and lan_identity == null:
			message["gateway_inheritance"] = _room_inheritance_context(peer)
			if message.gateway_inheritance.is_empty():
				_fail(peer,"身份继承要求已认证房间连接")
				return
		if routes.has(peer) and routes[peer].attached and _route_is_current(peer,routes[peer]):
			if kind == "join":
				message = _room_join_message(peer,message)
				if message.is_empty(): return
			var channel:int = _channel(kind)
			var result:Error = routes[peer].link.send(1, message, channel)
			if result != OK:
				_record_send_failure(peer, channel, "room_request", result, message)
				_fail(peer, "请求未能完整入队到权威房间；执行状态未确认，请先刷新状态", message, last_send_failure)
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
			visible.append({"id": room.id, "name": room.name, "ready": manager.is_ready(room.id), "failed": not room.error.is_empty()})
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
			# 本机管理员日志保留失败原因；公开响应仍不泄漏路径或内部策略。
			print("SERVER_ROOM_CREATE_FAILED ", JSON.stringify({"error":manager.error}))
			_fail(peer, "服务端房间操作失败，请联系管理员检查房间状态", message)
		else:
			var binding:Dictionary = manager.instance_binding(id)
			var creator:Dictionary = binding.duplicate(true)
			creator["peer"] = peer
			_creators[id] = creator
			_pending[peer] = binding
	elif kind == "server_join":
		if not accepting_rooms:
			_fail(peer,"服务端正在关闭，不再接受加入")
			return
		manager.poll()
		if not args.get("room") is String or not manager.rooms.has(args.room):
			_fail(peer, "所选房间不存在或尚未就绪")
			return
		if _creators.has(args.room) and not manager.binding_matches(_creators[args.room]):
			_creators.erase(args.room)
		if _creators.has(args.room):
			_fail(peer, "房间创建者尚未完成连接")
			return
		var binding:Dictionary = manager.instance_binding(args.room)
		if binding.is_empty():
			_fail(peer,"房间实例绑定无效")
			return
		if not manager.binding_matches(binding,true):
			if not _valid_room_resume(args.room, args.get("resume"),peer):
				_fail(peer, "未就绪房间只能由原成员凭据恢复")
				return
			# 生命周期 poll 负责确认退出并登记 pid=-1，不能靠裸 PID 存活决定恢复。
			var native:MultiplayerPeer = transport._peer
			var identity:String = authenticated_identities.get(peer,"")
			var identity_required:bool = not identity_registry.path.is_empty()
			var maintenance:Callable = _recovery_maintenance.bind(peer,native,identity,identity_required)
			if binding.pid <= 0 and not manager.recover_room(args.room,binding.pid,binding.instance_id,maintenance):
				_fail(peer, "服务端房间操作失败，请联系管理员检查房间状态", message)
				return
			# A disconnect callback only queues detach; reject before restoring old authorization.
			if not maintenance.call(): return
			_pending[peer] = manager.instance_binding(args.room)
		else:
			_attach(peer, args.room,binding)
	else:
		_fail(peer, "未知服务端请求")

## Native service only: no packet decoding, gateway.poll or route/session poll here.
## Queued disconnect is a sticky epoch barrier even if the same numeric peer reconnects.
func _recovery_maintenance(peer:int, native:MultiplayerPeer, identity:String, identity_required:bool) -> bool:
	if not is_same(transport._peer,native): return false
	if not transport.keep_alive(): return false
	if not is_same(transport._peer,native) or not accepting_rooms or _deferred_peer_detaches.has(peer) or not transport._connected_peers.has(peer): return false
	if identity_required != (not identity_registry.path.is_empty()): return false
	return not identity_required or (authenticated_identities.get(peer,"") == identity and identity_registry.can_access(identity))

## 客户端信封白名单；args 仍由各业务入口验证，join 的认证字段不透传。
static func _public_room_request(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var kind = source.get("kind")
	if not kind is String: return {}
	var fields: Array = ["v", "kind", "seq", "args"]
	if kind in ["catalog_part", "server_data_catalog_part"]:
		fields = ["kind", "bytes"]
	elif kind == "blob_chunk":
		fields = ["kind", "key", "offset", "bytes"]
	elif kind == "provider_blob_error":
		fields = ["kind", "key"]
	for field in fields:
		if source.has(field): result[field] = source[field]
	result = result.duplicate(true)
	if fields.has("args"):
		if not source.get("args") is Dictionary: return {}
		var allowed_args: Array = []
		match kind:
			"join": allowed_args = ["name", "spectator", "password", "resume"]
			"identity_inherit": allowed_args = ["target_member", "successor_member", "revision"]
			"room_password": allowed_args = ["password"]
			"identity_ack": allowed_args = ["token"]
			"catalog": allowed_args = ["entries"]
			"data_ack": allowed_args = ["revision"]
			"preview_group": allowed_args = ["request_id", "view_seq", "cards", "hidden"]
			"match_command": allowed_args = ["view_seq", "command", "params"]
			"guard_continue", "guard_skip", "guard_restart", "guard_lobby": allowed_args = ["view_seq"]
			"blob_request": allowed_args = ["key", "offset"]
			"ready": allowed_args = ["ready"]
			"settings": allowed_args = ["changes"]
			"choose_master": allowed_args = ["seat", "name"]
			"transfer", "kick": allowed_args = ["target"]
			"server_data_prepare": allowed_args = ["catalog_revision", "selected"]
			"server_data_commit", "server_data_cancel": allowed_args = ["request_id"]
			"identity_candidates", "server_data_catalog", "begin_match", "start": pass
			_: return {}
		result["args"] = {}
		for field in allowed_args:
			if source.args.has(field): result.args[field] = source.args[field]
	return result.duplicate(true)

func _room_inheritance_context(peer:int) -> Dictionary:
	if identity_registry.path.is_empty() or not routes.has(peer) or not routes[peer].attached or not _route_is_current(peer,routes[peer]):
		return {}
	var actor_key:String = authenticated_identities.get(peer,"")
	if not identity_registry.can_access(actor_key):
		return {}
	var profiles:Dictionary = {}
	for connection in routes:
		if routes[connection].room != routes[peer].room or not routes[connection].attached or not _route_is_current(connection,routes[connection]):
			continue
		var key:String = authenticated_identities.get(connection,"")
		if not identity_registry.can_access(key):
			continue
		var record:Dictionary = identity_registry.users[key]
		profiles[key] = {"username":record.username,"nickname":record.nickname}
	return {"actor_key":actor_key,"profiles":profiles}

func _valid_room_resume(id:String,ticket:Variant,peer:int = 0) -> bool:
	if not manager.rooms.has(id): return false
	if not ticket is Dictionary or not ticket.get("member") is int or ticket.member <= 0 or not ticket.get("token") is String or ticket.token.length() != 64: return false
	for character in ticket.token:
		if character not in "0123456789abcdef": return false
	var path:String = str(manager.rooms[id].directory).path_join("recovery.json")
	if not FileAccess.file_exists(path): return false
	var state = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not state is Dictionary or not state.get("resume_hashes") is Dictionary or not state.get("resume_previous", {}) is Dictionary: return false
	var member:String = str(ticket.member)
	if not preload("res://scripts/net/identity/member_identity_bindings.gd").valid_state(state,not identity_registry.path.is_empty()): return false
	if not identity_registry.path.is_empty() or state.get("identity_binding_required",false):
		var identity:String = authenticated_identities.get(peer,"")
		if identity_registry.path.is_empty() or not identity_registry.can_access(identity) or not state.get("member_identities") is Dictionary or state.member_identities.get(member) != identity: return false
	var proof:String = ticket.token.sha256_text()
	return proof == state.resume_hashes.get(member, "") or proof == state.get("resume_previous", {}).get(member, "")

func _attach(peer: int, id: String, binding:Dictionary = {}) -> void:
	# 创建/恢复等待期间权限可能被撤销，实际建立回环路由前再次验证。
	if not identity_registry.path.is_empty() and not identity_registry.can_access(authenticated_identities.get(peer,"")):
		_fail(peer,"该密钥身份已被封禁或未获白名单授权")
		return
	if binding.is_empty(): binding = manager.instance_binding(id)
	if binding.get("room") != id or not manager.binding_matches(binding,true):
		_fail(peer,"房间实例已更换或缺少可信进程句柄验证")
		return
	var link = preload("res://scripts/net/transport/enet_transport.gd").new()
	var route:Dictionary = binding.duplicate(true)
	route.merge({"link":link,"attached":false,"deadline":Time.get_ticks_msec()+10000})
	link.message_received.connect(func(sender: int, message: Dictionary):
		_room_response(peer,route,sender,message))
	link.packet_rejected.connect(func(sender:int, _reason:String):
		_room_packet_rejected(peer,route,sender))
	link.peer_disconnected.connect(func(_id: int):
		_room_disconnected(peer,route))
	if link.connect_to("127.0.0.1", manager.rooms[id].port) != OK:
		_fail(peer, "无法连接内部房间")
		_close_route_link(link)
		return
	if not manager.binding_matches(binding,true):
		_close_route_link(link)
		_fail(peer,"连接期间房间实例已更换")
		return
	routes[peer] = route
	_recovery_route_sample(peer,route,"route_created")

func _same_route(peer:int,route:Dictionary) -> bool:
	if not routes.has(peer) or not route.has("link"): return false
	var current:Dictionary = routes[peer]
	return is_same(current.get("link"),route.link) and current.get("room") == route.get("room") and current.get("pid") == route.get("pid") and current.get("instance_id") == route.get("instance_id") and current.get("authority_host_mode") == route.get("authority_host_mode")

func _route_is_current(peer:int,route:Dictionary) -> bool:
	return _same_route(peer,route) and manager.binding_matches(route,true)

func _room_response(peer:int,route:Dictionary,sender:int,message:Dictionary) -> void:
	if sender != 1 or not _route_is_current(peer,route): return
	var creator:Dictionary = _creators.get(route.room,{})
	if message.get("kind") == "room" and creator.get("peer") == peer and manager.binding_matches(creator,true) and not message.get("state",{}).get("members",[]).is_empty():
		_creators.erase(route.room)
	if _send_client(peer,message,_channel(str(message.get("kind",""))),"room_response") != OK:
		_fail(peer,"权威房间回复发送失败；执行状态未确认，请先刷新状态",message,last_send_failure)

func _room_disconnected(peer:int,route:Dictionary) -> void:
	_recovery_route_sample(peer,route,"route_disconnect_callback")
	if not _route_is_current(peer,route): return
	_queue_route_disconnect(peer,route,true)

func _queue_route_disconnect(peer:int,route:Dictionary,notify:bool = false) -> void:
	if not _same_route(peer,route): return
	for callback in _disconnected_routes:
		if callback.peer == peer and is_same(callback.route.link,route.link):
			callback.notify = callback.get("notify",false) or notify
			return
	_disconnected_routes.append({"peer":peer,"route":route.duplicate(),"notify":notify})

func _queue_peer_detach(peer:int) -> void:
	transport._recovery_probe.sample(transport,"external_disconnect",peer)
	if not _deferred_peer_detaches.has(peer):
		_deferred_peer_detaches.append(peer)

func _release_creator(peer:int,binding:Dictionary) -> void:
	var id:String = binding.get("room","")
	var creator:Dictionary = _creators.get(id,{})
	if creator.get("peer") == peer and creator.get("pid") == binding.get("pid") and creator.get("instance_id") == binding.get("instance_id") and creator.get("authority_host_mode") == binding.get("authority_host_mode"):
		_creators.erase(id)

func _detach_route(peer:int,route:Dictionary) -> void:
	# 管理器可能已登记新 worker：只撤销旧 link，不停止新实例或清公网认证。
	if not _same_route(peer,route): return
	_recovery_route_sample(peer,route,"route_detach")
	routes.erase(peer)
	_release_creator(peer,route)
	_close_route_link(route.link)

## 内部 route 独占这三个应用层信号；仅在撤销路由后断开捕获 route 的闭包。
## transport.close() 必须保留其他调用方的接线，以支持 session/transport 重连。
func _close_route_link(link) -> void:
	for route_signal in [link.message_received, link.packet_rejected, link.peer_disconnected]:
		for connection in route_signal.get_connections():
			route_signal.disconnect(connection.callable)
	link.close()

func _detach(peer: int, stop_owned_room: bool = true) -> void:
	_identity_admin_flags.erase(peer)
	_admin_sequences.erase(peer)
	_identity_challenges.erase(peer)
	authenticated_identities.erase(peer)
	_pending.erase(peer)
	# 先取创建者再撤销路由，以免同步 close 回调改变清理目标。
	var owned:Array[Dictionary] = []
	for id in _creators.keys():
		if _creators[id].get("peer") == peer:
			owned.append(_creators[id])
			_creators.erase(id)
	if routes.has(peer): _detach_route(peer,routes[peer])
	for binding in owned:
		if stop_owned_room and manager.binding_matches(binding) and manager.process_identity_verified(binding):
			manager.stop_room(binding.room,binding.pid,binding.instance_id)

## OK 仅证明本机发送入队；不证明客机收到或业务执行完成。
func _send_client(peer:int, message:Dictionary, channel:int = 0, stage:String = "client_response") -> Error:
	var result:Error = transport.send(peer, message, channel)
	if result != OK: _record_send_failure(peer, channel, stage, result, message)
	return result

func _record_send_failure(peer:int, channel:int, stage:String, result:Error, message:Dictionary = {}) -> void:
	last_send_failure = _diagnostic_context(peer, message)
	last_send_failure.merge({"channel":channel,"stage":stage,"error_code":int(result),"queued":false,"code":"send_failed"})
	send_failed.emit(last_send_failure.duplicate(true))

## 只读取可信路由标识和整数序号，不复制 kind/args/密钥/票据/牌面。
func _diagnostic_context(peer:int, message:Dictionary = {}, binding:Dictionary = {}) -> Dictionary:
	if binding.is_empty(): binding = routes.get(peer, _pending.get(peer, {}))
	var room:Variant = binding.get("room", "")
	var instance:Variant = binding.get("instance_id", "")
	var sequence:Variant = message.get("request_seq", message.get("seq", -1))
	return {"connection":peer,
		"room":room if manager.valid_instance_id(room) else "",
		"pid":binding.get("pid", -1) if binding.get("pid", -1) is int else -1,
		"instance_id":instance if manager.valid_instance_id(instance) else "",
		"request_seq":sequence if sequence is int and sequence >= 0 else -1}

func _log_transport_diagnostic(diagnostic:Dictionary) -> void:
	# 生产信号消费者；不打印任意 reason、消息或业务返回值。
	print("NET_DIAGNOSTIC ", JSON.stringify(diagnostic))

func _client_packet_rejected(peer:int, _reason:String) -> void:
	_record_packet_rejection(peer, transport.last_packet_rejection, "client_packet")

func _room_packet_rejected(peer:int, route:Dictionary, sender:int) -> void:
	# 旧实例回调不得向新路由报告错误。
	if sender != 1 or not _route_is_current(peer, route): return
	_record_packet_rejection(peer, route.link.last_packet_rejection, "room_packet", route)

func _record_packet_rejection(peer:int, rejection:Dictionary, stage:String, binding:Dictionary = {}) -> void:
	var diagnostic:Dictionary = _diagnostic_context(peer, {}, binding)
	diagnostic.merge({"stage":stage,"channel":rejection.get("channel",-1),"code":rejection.get("code","packet_rejected"),"error_code":int(ERR_INVALID_DATA),"queued":false})
	_log_transport_diagnostic(diagnostic)
	# 无可信 seq 的拒包绝不借用上一条请求序号或重放请求。
	_send_client(peer, {"kind":"error","reason":"网络消息被拒绝；请刷新状态，不要自动重复提交操作","request_seq":-1,"diagnostic":diagnostic}, 0, "error_receipt")

func _fail(peer: int, reason: String, request:Dictionary = {}, diagnostic:Dictionary = {}) -> void:
	# 错误回执失败不可递归产生新的错误回执。
	var context:Dictionary = _diagnostic_context(peer,request) if diagnostic.is_empty() else diagnostic.duplicate(true)
	_send_client(peer, {"kind": "error", "reason": reason,"request_seq":context.request_seq,"diagnostic":context}, 0, "error_receipt")

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
	_pending.clear()
	_creators.clear()
	_disconnected_routes.clear()
	transport.close()
	_deferred_peer_detaches.clear()
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
		var reason:String = preload("res://scripts/net/identity/player_name_rules.gd").username_error(args.username)
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
		if _send_client(peer,{"kind":"server_identity_challenge","challenge":challenge},0,"identity_challenge") != OK:
			_identity_challenges.erase(peer)
			_fail(peer,"认证挑战发送失败，请重新连接")
		return
	if not _identity_challenges.has(peer) or not args.get("signature") is PackedByteArray:
		_fail(peer,"没有可用的身份挑战")
		return
	var pending:Dictionary = _identity_challenges[peer]
	_identity_challenges.erase(peer)
	var profile:Dictionary = pending.profile
	var context:String = JSON.stringify([profile.public_key,profile.username,profile.nickname])
	var identity = preload("res://scripts/net/identity/player_identity.gd")
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
	if _send_client(peer,{"kind":"server_identity_ready","identity":id,"username":profile.username,"nickname":profile.nickname},0,"identity_ready") != OK:
		# 认证事实不回滚、不重执行；断开连接要求重新握手。
		_detach(peer,false)
		transport.disconnect_peer(peer)

## 唯一身份注入点；普通客户端的同名字段始终被覆盖。
func _room_join_message(peer:int,message:Dictionary) -> Dictionary:
	if not message.get("args") is Dictionary:
		_fail(peer,"房间加入参数无效")
		return {}
	var result:Dictionary = message.duplicate(true)
	if lan_identity != null:
		var key:String = lan_identity.authenticated.get(peer, "")
		if key.is_empty() or not lan_identity.profiles.has(key):
			_fail(peer,"LAN 连接缺少密钥认证")
			return {}
		result.args.erase("gateway_identity") # LAN 身份只经私有 IPC，不随对局网络信封授权。
		result.args.name = lan_identity.profiles[key].nickname
		return result
	var required:bool = not identity_registry.path.is_empty()
	var identity:String = authenticated_identities.get(peer,"") if required else ""
	if required and not identity_registry.can_access(identity):
		_fail(peer,"该密钥身份已被封禁或未获白名单授权")
		return {}
	result.args["gateway_identity"] = {"required":required,"key":identity}
	if required: result.args.name = identity_registry.users[identity].nickname
	return result

## 旧档管理区：只由本机白名单命令调用，公网管理员执行路径被显式隔离。
func console_legacy_migration(room_id:String, pid:int, instance_id:String, legacy_approved:bool, selected:Dictionary) -> Dictionary:
	var migration = preload("res://scripts/net/identity/legacy_identity_migration.gd")
	if not manager.rooms.has(room_id): return migration.failure("房间不存在")
	var room:Dictionary = manager.rooms[room_id]
	if not manager.matches_instance(room,pid,instance_id): return migration.failure("房间 PID 或 instance_id 已改变")
	if pid > 0 and OS.is_process_running(pid): return migration.failure("必须先停止房间工作进程，迁移不得并发覆盖")
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(str(room.directory).path_join("config.json"))) != OK or not parser.data is Dictionary:
		return migration.failure("房间配置不可读")
	if parser.data.get("id") != room_id or parser.data.get("instance_id") != instance_id or parser.data.get("authority_host_mode") != room.get("authority_host_mode"):
		return migration.failure("房间磁盘配置与实例登记不一致")
	var path:String = str(room.directory).path_join("recovery.json")
	var loaded:Dictionary = migration.read_legacy(path)
	if not loaded.ok: return loaded
	var members:Array = loaded.state.room.members.keys()
	if not legacy_approved:
		# 拒绝不会改变旧档或启动恢复，审计不含身份或票据。
		print("LEGACY_MIGRATION action=reject operator=local-console members=",members)
		return {"ok":true,"result":{"status":"rejected","members":members,"operator":"local-console"}}
	if identity_registry.path.is_empty() or selected.size() != members.size(): return migration.failure("必须显式绑定全部旧成员并启用认证登记")
	var approved:Dictionary = {}
	var profiles:Dictionary = {}
	var used_connections:Dictionary = {}
	var used_keys:Dictionary = {}
	for member in members:
		var connection = selected.get(member)
		if not connection is int or connection <= 1 or used_connections.has(connection): return migration.failure("旧成员绑定缺失或认证连接重复")
		if routes.has(connection) and routes[connection].room != room_id: return migration.failure("认证连接属于其他房间")
		if _pending.has(connection) and _pending[connection].room != room_id: return migration.failure("认证连接正在加入其他房间")
		var key:String = authenticated_identities.get(connection,"")
		if not identity_registry.can_access(key) or used_keys.has(key): return migration.failure("身份未认证、已禁用或重复绑定")
		approved[member] = key
		profiles[key] = {} # 只需认证资格，不向审计复制档案。
		used_connections[connection] = true
		used_keys[key] = true
	var prepared:Dictionary = migration.prepare(loaded.state,approved,profiles)
	if not prepared.ok: return prepared
	var committed:Dictionary = migration.commit(path,loaded.bytes,prepared.state)
	if not committed.ok: return committed
	print("LEGACY_MIGRATION action=approve operator=local-console members=",members)
	var failed:int = 0
	for member in members:
		var connection:int = selected[member]
		# 落盘后再检查身份，绝不广播或在管理回执中返回票据。
		if authenticated_identities.get(connection) != approved[member] or not identity_registry.can_access(approved[member]):
			failed += 1
		elif _send_client(connection,prepared.private_tickets[member],0,"legacy_ticket") != OK:
			failed += 1
	return {"ok":failed == 0,"result":{"status":"migrated","persisted":true,"members":members,"operator":"local-console","delivery_failed":failed,"delivery_confirmed":false}}

func _receive_admin_command(peer:int,message:Dictionary) -> void:
	var id:String = authenticated_identities.get(peer,"")
	if identity_registry.path.is_empty() or not identity_registry.can_access(id) or not identity_registry.users.get(id,{}).get("admin",false):
		_fail(peer,"当前密钥身份没有管理员权限")
		return
	if admin_console == null or message.get("v") != 1 or not message.get("seq") is int or message.seq <= int(_admin_sequences.get(peer,0)) or not message.get("args") is Dictionary or not message.args.get("command") is String:
		_fail(peer,"管理员命令无效或重复")
		return
	_admin_sequences[peer] = message.seq
	var response:Dictionary = admin_console.execute(message.args.command,false)
	if _send_client(peer,{"kind":"server_admin_result","request_seq":message.seq,"response":response},0,"admin_result") != OK:
		# 命令已经执行过，不能因回执失败重执行；保留原请求序号供客户端关联。
		_send_client(peer,{"kind":"server_admin_result","request_seq":message.seq,"response":{"ok":false,"error":"管理员命令已返回，但完整结果发送失败；请查询实际状态，不要重复提交写命令","result":{"execution_returned":true,"result_available":false}}},0,"admin_result_fallback")

# 只读取现有 route 的身份，不触碰认证数据或消息。
func _recovery_route_sample(peer:int,route:Dictionary,stage:String) -> void:
	if not route.link._recovery_probe.enabled(): return
	var context:Dictionary = {"external_peer":peer,"internal_peer":route.link.peer_id(),
		"room":route.get("room",""),"instance_id":route.get("instance_id",""),
		"worker_pid":route.get("pid",-1),"attached":route.get("attached",false)}
	route.link._recovery_probe.sample(route.link,stage,1,context)
