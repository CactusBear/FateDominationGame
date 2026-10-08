extends RefCounted

var max_clients: int = 96
var accepting_rooms:bool = true
var max_rooms: int = 16
var rooms_per_ip:int = 16
var max_packet_bytes: int = 256 * 1024
var max_messages_per_second: int = 32
var handshake_seconds: float = 30.0
var room_code_ttl_sec:float = 0.0
var room_code_length:int = 32
var port: int = 0
var error: String = ""
var _listener := TCPServer.new()
var _clients: Dictionary = {}
var _rooms: Dictionary = {}
var _next_client: int = 0
var _codec = preload("res://scripts/net/p2p/p2p_invite.gd").new()
# 信令角色不具有规则运算权限，也不启动权威子进程。
const AUTHORITY_HOST_MODE:String = "disabled_on_relay"

func diagnostics() -> Dictionary:
	var waiting:int = 0
	var answered:int = 0
	for client in _clients.values():
		if client.answered: answered += 1
		elif not client.expected.is_empty(): waiting += 1
	return {
		"authority_host_mode": AUTHORITY_HOST_MODE,
		"game_forwarding": false,
		"port": port,
		"signaling_clients": _clients.size(),
		"signaling_rooms": _rooms.size(),
		"pending_answers": waiting,
		"answered_handshakes": answered,
		"nat_type": "unknown_not_measured",
		"public_network_acceptance": "unverified",
		"error": error,
	}

func configure(options:Dictionary) -> bool:
	error = ""
	var fields:Dictionary = {"signal_rate_limit":"max_messages_per_second", "max_packet_bytes":"max_packet_bytes", "ice_timeout_sec":"handshake_seconds", "rooms_per_ip":"rooms_per_ip", "room_code_ttl_sec":"room_code_ttl_sec", "room_code_length":"room_code_length"}
	for key in options:
		if not fields.has(key):
			error = "未知信令配置：" + str(key)
			return false
		var value = options[key]
		if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)) or value < 0 or (value == 0 and key != "room_code_ttl_sec"):
			error = "信令限制必须是有限正数：" + str(key)
			return false
		if key not in ["ice_timeout_sec","room_code_ttl_sec"] and (floor(float(value)) != value or value > 2147483647):
			error = "信令数量限制必须是有效整数：" + str(key)
			return false
		if key in ["ice_timeout_sec","room_code_ttl_sec"] and value >= float((9223372036854775807-Time.get_ticks_msec())/1000):
			error = "信令超时超出可表示范围"
			return false
	var code_bytes:int = int(options.get("room_code_length",room_code_length))
	var packet_bytes:int = int(options.get("max_packet_bytes",max_packet_bytes))
	if code_bytes > packet_bytes - JSON.stringify({"kind":"created","room":""}).to_utf8_buffer().size():
		error = "房间码长度超过信令消息预算"
		return false
	for key in options:
		set(fields[key], float(options[key]) if key in ["ice_timeout_sec","room_code_ttl_sec"] else int(options[key]))
	return true

func listen(requested_port: int, address: String = "127.0.0.1") -> Error:
	close()
	# 同时校验直接设置的码长/TTL；configure 是原子校验入口。
	if not configure({"room_code_length":room_code_length, "room_code_ttl_sec":room_code_ttl_sec, "ice_timeout_sec":handshake_seconds, "max_packet_bytes":max_packet_bytes}):
		return ERR_INVALID_PARAMETER
	if requested_port < 0 or requested_port > 65535 or max_clients <= 0 or max_rooms <= 0 or rooms_per_ip <= 0 or max_packet_bytes <= 0 or max_messages_per_second <= 0 or not is_finite(handshake_seconds) or handshake_seconds <= 0:
		return ERR_INVALID_PARAMETER
	var result := _listener.listen(requested_port, address)
	if result == OK:
		port = _listener.get_local_port()
	return result

func poll() -> void:
	for code in _rooms.keys():
		if _rooms[code].expires > 0 and Time.get_ticks_msec() >= _rooms[code].expires:
			_remove(int(_rooms[code].host))
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
		_clients[_next_client] = {"peer": peer, "address":stream.get_connected_host(), "room": "", "host": false, "expires": Time.get_ticks_msec() + int(handshake_seconds * 1000), "timestamps": [], "expected": {}, "answered": false}
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
			if not peer.was_string_packet() or bytes.size() > max_packet_bytes or not _allow_message(client, Time.get_ticks_msec()):
				_remove(id)
				break
			var parser := JSON.new()
			if parser.parse(bytes.get_string_from_utf8()) != OK or not parser.data is Dictionary:
				_remove(id)
				break
			_handle(id, parser.data)
			if not _clients.has(id):
				break

func _allow_message(client: Dictionary, now: int) -> bool:
	# 任意滚动一秒内最多 N 条，整秒边界不会重新赠送 N 条额度。
	var timestamps: Array = client.timestamps
	var cutoff: int = now - 1000
	while not timestamps.is_empty() and int(timestamps[0]) <= cutoff:
		timestamps.pop_front()
	if timestamps.size() >= max_messages_per_second:
		return false
	timestamps.append(now)
	return true

func _handle(id: int, message: Dictionary) -> void:
	var client: Dictionary = _clients[id]
	if not accepting_rooms and message.get("kind") in ["create","join"]:
		_reject(id,"信令服务正在关闭，不再接受新握手")
		return
	var keys := message.keys()
	keys.sort()
	match message.get("kind"):
		"create":
			if keys != ["kind"] or not client.room.is_empty() or _rooms.size() >= max_rooms:
				_reject(id, "不能创建信令房间")
				return
			var hosted:int = 0
			for other in _clients.values():
				if other.host and other.address == client.address: hosted += 1
			if hosted >= rooms_per_ip:
				_reject(id, "该来源地址的信令房间数量已达上限")
				return
			var code:String = _new_room_code()
			if code.is_empty():
				_reject(id,"房间码空间已用完")
				return
			if _send(id, {"kind": "created", "room": code}) != OK:
				_remove(id)
				return
			_rooms[code] = {"host": id, "peer_ids": {}, "expires":Time.get_ticks_msec()+int(room_code_ttl_sec*1000) if room_code_ttl_sec > 0 else 0}
			client.room = code
			client.host = true
			client.expires = 0

		"join":
			if keys != ["kind", "room"] or not message.room is String or not client.room.is_empty() or not _rooms.has(message.room):
				_reject(id, "信令房间不存在或连接已加入房间")
				return
			if _send(_rooms[message.room].host, {"kind": "join_request", "client": id}) != OK:
				_remove(id)
				return
			client.room = message.room
			client.expires = Time.get_ticks_msec() + int(handshake_seconds * 1000)
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
			if _send(target, {"kind": "offer", "code": message.code}) == OK:
				_rooms[client.room].peer_ids[int(data.to)] = target
				_clients[target].expected = {"peer_id": int(data.to), "nonce": data.nonce}
		"answer":
			if keys != ["code", "kind"] or client.host or client.expected.is_empty() or client.answered or not message.code is String or not _rooms.has(client.room):
				_reject(id, "没有待答握手或应答已经使用")
				return
			var data: Dictionary = _codec._read(message.code)
			if data.is_empty() or data.type != "answer" or data.to != 1 or data.from != client.expected.peer_id or data.nonce != client.expected.nonce:
				_reject(id, "应答与该次握手不匹配")
				return
			if _send(_rooms[client.room].host, {"kind": "answer", "client": id, "code": message.code}) == OK:
				client.answered = true
				client.expires = 0
		_:
			_reject(id, "信令服务不接受此消息")

func _new_room_code() -> String:
	var code:String = Crypto.new().generate_random_bytes((room_code_length+1)/2).hex_encode().left(room_code_length)
	if code.length() != room_code_length: return ""
	# 随机起点后有限探测，最多已有房间数加一次；短码空间耗尽也不会死循环。
	var digits:String = "0123456789abcdef"
	for attempt in range(_rooms.size()+1):
		if not _rooms.has(code): return code
		for index in range(code.length()-1,-1,-1):
			var next:int = (digits.find(code[index])+1)%digits.length()
			code = code.left(index)+digits[next]+code.substr(index+1)
			if next != 0: break
	return ""

func _send(id: int, message: Dictionary) -> Error:
	if not _clients.has(id) or _clients[id].peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		error = "信令目标尚未连接或已断开"
		return ERR_UNAVAILABLE
	var text:String = JSON.stringify(message)
	if text.to_utf8_buffer().size() > max_packet_bytes:
		error = "信令回复超过发送预算"
		return ERR_OUT_OF_MEMORY
	var result:Error = _clients[id].peer.send_text(text)
	if result != OK: error = "信令发送失败：" + error_string(result)
	return result

func close_room(code:String) -> bool:
	if not _rooms.has(code): return false
	_remove(int(_rooms[code].host))
	return true

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
				_clients[other].answered = false
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
