class_name ServerGateway
extends RefCounted

var transport = preload("res://scripts/net/enet_transport.gd").new()
var manager = preload("res://scripts/net/server_room_manager.gd").new()
var routes: Dictionary = {}
var error: String = ""
var max_clients: int = 96
var data_root: String = ""
var _pending: Dictionary = {}
var _creators: Dictionary = {}

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
	manager.poll()
	for peer in _pending.keys():
		var id: String = _pending[peer]
		if not manager.rooms.has(id) or not manager.rooms[id].error.is_empty():
			_fail(peer, "所选房间启动失败")
			_pending.erase(peer)
		elif manager.is_ready(id):
			_attach(peer, id)
			_pending.erase(peer)
	for peer in routes.keys():
		if not routes.has(peer):
			continue
		var route: Dictionary = routes[peer]
		if not manager.is_ready(route.room):
			_fail(peer, "所选房间已经停止")
			_detach(peer)
			continue
		route.link.poll()
		if not route.attached and route.link.is_connected_to_host():
			route.attached = true
			transport.send(peer, {"kind": "server_attached", "room": route.room, "peer_id": route.link.peer_id()})
		elif not route.attached and Time.get_ticks_msec() > route.deadline:
			_fail(peer, "内部房间连接超时")
			_detach(peer)

func _receive(peer: int, message: Dictionary) -> void:
	var kind = message.get("kind")
	if not kind is String:
		_fail(peer, "服务端请求格式无效")
		return
	if not kind.begins_with("server_"):
		if routes.has(peer) and routes[peer].attached:
			routes[peer].link.send(1, message, _channel(kind))
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
		transport.send(peer, {"kind": "server_rooms", "rooms": visible})
		return
	if routes.has(peer) or _pending.has(peer):
		_fail(peer, "连接已经绑定房间")
		return
	if kind == "server_create":
		if not args.get("name") is String or args.name.length() > 64 or not args.get("settings") is Dictionary:
			_fail(peer, "房间创建参数无效")
			return
		var id: String = manager.create_room(args.name, args.settings, data_root)
		if id.is_empty():
			_fail(peer, manager.error)
		else:
			_creators[id] = peer
			_pending[peer] = id
	elif kind == "server_join":
		if not args.get("room") is String or not manager.is_ready(args.room):
			_fail(peer, "所选房间不存在或尚未就绪")
			return
		if _creators.has(args.room):
			_fail(peer, "房间创建者尚未完成连接")
			return
		_attach(peer, args.room)
	else:
		_fail(peer, "未知服务端请求")

func _attach(peer: int, id: String) -> void:
	var link = preload("res://scripts/net/enet_transport.gd").new()
	link.message_received.connect(func(sender: int, message: Dictionary):
		if sender == 1 and routes.has(peer):
			if message.get("kind") == "room" and _creators.get(id) == peer and not message.get("state", {}).get("members", []).is_empty():
				_creators.erase(id)
			transport.send(peer, message, _channel(str(message.get("kind", "")))))
	link.peer_disconnected.connect(func(_id: int):
		_fail(peer, "房间连接已断开")
		_detach(peer))
	if link.connect_to("127.0.0.1", manager.rooms[id].port) != OK:
		_fail(peer, "无法连接内部房间")
		return
	routes[peer] = {"room": id, "link": link, "attached": false, "deadline": Time.get_ticks_msec() + 10000}

func _detach(peer: int) -> void:
	_pending.erase(peer)
	if routes.has(peer):
		routes[peer].link.close()
		routes.erase(peer)
	for id in _creators.keys():
		if _creators[id] == peer:
			manager.stop_room(id)
			_creators.erase(id)

func _fail(peer: int, reason: String) -> void:
	transport.send(peer, {"kind": "error", "reason": reason})

func _channel(kind: String) -> int:
	return 2 if kind in ["blob_request", "blob_chunk", "blob_error", "provider_blob_request", "provider_blob_error"] else 0

func close() -> void:
	for peer in routes.keys():
		_detach(peer)
	_pending.clear()
	_creators.clear()
	transport.close()
	manager.close()
