extends RefCounted

var max_clients: int = 96
var max_rooms: int = 16
var max_packet_bytes: int = 256 * 1024
var max_messages_per_second: int = 32
var handshake_seconds: float = 30.0
var port: int = 0
var error: String = ""
var _listener := TCPServer.new()
var _clients: Dictionary = {}
var _rooms: Dictionary = {}
var _next_client: int = 0
var _codec = preload("res://scripts/net/p2p_invite.gd").new()

func listen(requested_port: int, address: String = "127.0.0.1") -> Error:
	close()
	if requested_port < 0 or requested_port > 65535 or max_clients <= 0 or max_rooms <= 0 or max_packet_bytes <= 0 or max_messages_per_second <= 0 or not is_finite(handshake_seconds) or handshake_seconds <= 0:
		return ERR_INVALID_PARAMETER
	var result := _listener.listen(requested_port, address)
	if result == OK:
		port = _listener.get_local_port()
	return result

func poll() -> void:
	while _listener.is_connection_available():
		var stream := _listener.take_connection()
		if _clients.size() >= max_clients:
			stream.disconnect_from_host()
			continue
		var peer := WebSocketPeer.new()
		peer.inbound_buffer_size = max_packet_bytes
		peer.outbound_buffer_size = max_packet_bytes
		if peer.accept_stream(stream) != OK:
			stream.disconnect_from_host()
			continue
		_next_client += 1
		_clients[_next_client] = {"peer": peer, "room": "", "host": false, "expires": Time.get_ticks_msec() + int(handshake_seconds * 1000), "second": 0, "messages": 0, "expected": {}, "answered": false}
	for id in _clients.keys():
		if not _clients.has(id):
			continue
		var client: Dictionary = _clients[id]
		var peer: WebSocketPeer = client.peer
		peer.poll()
		if peer.get_ready_state() == WebSocketPeer.STATE_CLOSED or client.expires > 0 and Time.get_ticks_msec() >= client.expires:
			_remove(id)
			continue
		var processed := 0
		while peer.get_available_packet_count() > 0 and processed < max_messages_per_second:
			processed += 1
			var bytes := peer.get_packet()
			var second: int = Time.get_ticks_msec() / 1000
			if second != client.second:
				client.second = second
				client.messages = 0
			client.messages += 1
			if not peer.was_string_packet() or bytes.size() > max_packet_bytes or client.messages > max_messages_per_second:
				_remove(id)
				break
			var parser := JSON.new()
			if parser.parse(bytes.get_string_from_utf8()) != OK or not parser.data is Dictionary:
				_remove(id)
				break
			_handle(id, parser.data)

func _handle(id: int, message: Dictionary) -> void:
	var client: Dictionary = _clients[id]
	var keys := message.keys()
	keys.sort()
	match message.get("kind"):
		"create":
			if keys != ["kind"] or not client.room.is_empty() or _rooms.size() >= max_rooms:
				_reject(id, "不能创建信令房间")
				return
			var code := Crypto.new().generate_random_bytes(16).hex_encode()
			while _rooms.has(code):
				code = Crypto.new().generate_random_bytes(16).hex_encode()
			_rooms[code] = {"host": id, "peer_ids": {}}
			client.room = code
			client.host = true
			client.expires = 0
			_send(id, {"kind": "created", "room": code})
		"join":
			if keys != ["kind", "room"] or not message.room is String or message.room.length() != 32 or not client.room.is_empty() or not _rooms.has(message.room):
				_reject(id, "信令房间不存在或连接已加入房间")
				return
			client.room = message.room
			client.expires = Time.get_ticks_msec() + int(handshake_seconds * 1000)
			_send(_rooms[client.room].host, {"kind": "join_request", "client": id})
		"offer":
			if keys != ["client", "code", "kind"] or not client.host or not _codec._id(message.get("client")) or not message.code is String:
				_reject(id, "无权发送握手邀请")
				return
			var target := int(message.client)
			if not _clients.has(target) or _clients[target].room != client.room or _clients[target].host or not _clients[target].expected.is_empty() or _clients[target].answered:
				_reject(id, "握手目标不属于该房间或已有邀请")
				return
			var data: Dictionary = _codec._read(message.code)
			if data.is_empty() or data.type != "offer" or data.from != 1 or _rooms[client.room].peer_ids.has(int(data.to)):
				_reject(id, "无效或重复的直连邀请")
				return
			_rooms[client.room].peer_ids[int(data.to)] = target
			_clients[target].expected = {"peer_id": int(data.to), "nonce": data.nonce}
			_send(target, {"kind": "offer", "code": message.code})
		"answer":
			if keys != ["code", "kind"] or client.host or client.expected.is_empty() or client.answered or not message.code is String or not _rooms.has(client.room):
				_reject(id, "没有待答握手或应答已经使用")
				return
			var data: Dictionary = _codec._read(message.code)
			if data.is_empty() or data.type != "answer" or data.to != 1 or data.from != client.expected.peer_id or data.nonce != client.expected.nonce:
				_reject(id, "应答与该次握手不匹配")
				return
			client.answered = true
			client.expires = 0
			_send(_rooms[client.room].host, {"kind": "answer", "client": id, "code": message.code})
		_:
			_reject(id, "信令服务不接受此消息")

func _send(id: int, message: Dictionary) -> void:
	if _clients.has(id) and _clients[id].peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_clients[id].peer.send_text(JSON.stringify(message))

func _reject(id: int, reason: String) -> void:
	_send(id, {"kind": "error", "reason": reason})

func _remove(id: int) -> void:
	if not _clients.has(id):
		return
	var client: Dictionary = _clients[id]
	if client.host and _rooms.has(client.room):
		_rooms.erase(client.room)
		for other in _clients:
			if other != id and _clients[other].room == client.room:
				_send(other, {"kind": "room_closed"})
				_clients[other].room = ""
				_clients[other].expected = {}
				_clients[other].expires = Time.get_ticks_msec() + int(handshake_seconds * 1000)
	elif _rooms.has(client.room):
		var peers: Dictionary = _rooms[client.room].peer_ids
		for peer_id in peers.keys():
			if peers[peer_id] == id:
				peers.erase(peer_id)
	client.peer.close()
	_clients.erase(id)

func close() -> void:
	for client in _clients.values():
		client.peer.close()
	_clients.clear()
	_rooms.clear()
	_listener.stop()
	port = 0
	error = ""
