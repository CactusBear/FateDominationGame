extends RefCounted

signal room_created(code: String)
signal rejected(reason: String)

var invite = preload("res://scripts/net/p2p/p2p_invite.gd").new()
var room_code: String = ""
var error: String = ""
var handshake_seconds: float = 30.0
var max_packet_bytes: int = 256 * 1024
var _socket: WebSocketPeer
var _session: WeakRef
var _role: String = ""
var _name: String = ""
var _spectator: bool = false
var _configuration: Dictionary = {}
var _sent_request: bool = false
var _sent_answer: bool = false
var _deadline: int = 0
var _pending: Dictionary = {}
var _joined_clients: Dictionary = {}
var _url:String = ""
var _resuming:bool = false
var _received_offer:bool = false
# 期望的权威机器，不代表已启动隔离规则子进程；relay 永不承载规则。
const AUTHORITY_HOST_MODE:String = "p2p_host_machine"

func diagnostics() -> Dictionary:
	var session = _session.get_ref() if _session != null else null
	return {
		"authority_host_mode": AUTHORITY_HOST_MODE,
		"game_forwarding": false,
		"signaling_open": _socket != null and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN,
		"socket_state": _socket.get_ready_state() if _socket != null else -1,
		"request_sent": _sent_request,
		"room_registered": not room_code.is_empty() and _socket != null and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN,
		"direct_transport_connected": session != null and session.transport.is_connected_to_host(),
		"pending_handshakes": _pending.size(),
		"nat_type": "unknown_not_measured",
		"selected_candidate_pair": "not_observed",
		"public_network_acceptance": "unverified",
		"error": error,
	}

func can_reconnect_session(session) -> bool:
	return _role == "guest" and not _url.is_empty() and not room_code.is_empty() and session.has_resume_identity() and not (_resuming and error.is_empty() and _deadline > 0)

func reconnect(session) -> Error:
	if not can_reconnect_session(session) or session.transport.is_connected_to_host(): return ERR_UNAVAILABLE
	var url:String = _url
	var code:String = room_code
	var config:Dictionary = _configuration.duplicate(true)
	close()
	session._prepare_reconnect()
	_resuming = true
	var result:Error = _open(url,session,"guest",code,config)
	if result != OK:
		_url = url
		room_code = code
		_role = "guest"
		_configuration = config
		session._resume_inflight = false
		_warn("无法重新连接信令服务")
	return result

func host(url: String, session: RefCounted, name: String, settings: Dictionary, configuration: Dictionary) -> Error:
	session.close()
	close()
	var result: Error = invite.link.open(1, configuration)
	if result == OK:
		result = session.host_authority_peer(invite.link.peer, name, settings)
	if result == OK:
		result = _open(url, session, "host", "", configuration)
	if result != OK:
		session.close()
		close()
	return result

func join(url: String, code: String, session: RefCounted, name: String, spectator: bool, configuration: Dictionary) -> Error:
	session.close()
	close()
	if not _valid_room_code(code):
		return ERR_INVALID_PARAMETER
	_name = name
	_spectator = spectator
	return _open(url, session, "guest", code, configuration)

func _open(url: String, session: RefCounted, role: String, code: String, configuration: Dictionary) -> Error:
	if not (url.begins_with("ws://") or url.begins_with("wss://")) or not is_finite(handshake_seconds) or handshake_seconds <= 0 or max_packet_bytes <= 0:
		return ERR_INVALID_PARAMETER
	if not invite.link._direct_configuration(configuration) or handshake_seconds >= float((9223372036854775807 - Time.get_ticks_msec()) / 1000):
		return ERR_INVALID_PARAMETER
	if not invite.configure_timeout(handshake_seconds):
		return ERR_INVALID_PARAMETER
	_socket = WebSocketPeer.new()
	_socket.inbound_buffer_size = max_packet_bytes
	_socket.outbound_buffer_size = max_packet_bytes
	var result := _socket.connect_to_url(url)
	if result != OK:
		return result
	_session = weakref(session)
	_url = url
	_role = role
	room_code = code
	_configuration = configuration.duplicate(true)
	_deadline = Time.get_ticks_msec() + int(handshake_seconds * 1000)
	session.connection_driver = self
	return OK

func poll() -> void:
	invite.poll()
	for client in _joined_clients.keys():
		if not invite.link._connections.has(_joined_clients[client]):
			_joined_clients.erase(client)
	if _socket == null:
		return
	_socket.poll()
	var session = _session.get_ref() if _session != null else null
	if session == null:
		close()
		return
	if _role == "guest" and session.transport.is_connected_to_host():
		_deadline = 0
	if _socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		_fail_signaling("信令已断开，已建立的对局直连不受影响" if session.transport.is_connected_to_host() else "信令服务不可用，无法建立或恢复直连；未使用转发兜底")
		return
	if _deadline > 0 and Time.get_ticks_msec() >= _deadline:
		_fail_signaling("信令或直连握手超时，未使用转发兜底")
		return
	if _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	if not _sent_request:
		if _send({"kind": "create"} if _role == "host" else {"kind": "join", "room": room_code}) != OK:
			_fail_signaling("信令请求发送失败，未建立房间或加入握手")
			return
		_sent_request = true
	while _socket.get_available_packet_count() > 0:
		var bytes := _socket.get_packet()
		var parser := JSON.new()
		if not _socket.was_string_packet() or bytes.size() > max_packet_bytes or parser.parse(bytes.get_string_from_utf8()) != OK or not parser.data is Dictionary:
			_fail_signaling("信令服务返回无效消息")
			return
		_receive(parser.data, session)
		if _socket == null:
			return
	for client in _pending.keys():
		var pending: Dictionary = _pending[client]
		if invite.is_peer_connected(pending.peer_id):
			_joined_clients[client] = pending.peer_id
			_pending.erase(client)
		elif Time.get_ticks_msec() >= pending.deadline:
			invite.cancel_offer(pending.peer_id)
			_pending.erase(client)
			_warn("一个客机的直连握手超时")
		elif not pending.sent:
			var code: String = invite.export_code(pending.peer_id)
			if not code.is_empty():
				if _send({"kind": "offer", "client": client, "code": code}) == OK:
					pending.sent = true
				else:
					_fail_signaling("直连邀请发送失败")
					return
	if _role == "guest" and invite.link.peer != null and not _sent_answer:
		var code: String = invite.export_code(1)
		if not code.is_empty():
			if _send({"kind": "answer", "code": code}) == OK:
				_sent_answer = true
			else:
				_fail_signaling("直连应答发送失败")
				return

func _receive(message: Dictionary, session: RefCounted) -> void:
	if not _valid_signal_reply(message):
		_fail_signaling("信令服务返回无效字段或游戏消息；信令不转发游戏流量")
		return
	match message.get("kind"):
		"created":
			if _role != "host" or not room_code.is_empty() or not _valid_room_code(message.get("room")):
				_warn("信令房间码无效")
				return
			room_code = message.room
			_deadline = 0
			room_created.emit(room_code)
		"join_request":
			if _role != "host" or not invite._id(message.get("client")) or _pending.has(int(message.client)) or _joined_clients.has(int(message.client)):
				return
			var id: int = invite.offer()
			if id > 1:
				_pending[int(message.client)] = {"peer_id": id, "sent": false, "answered": false, "deadline": Time.get_ticks_msec() + int(handshake_seconds * 1000)}
			else:
				_warn("客机连接超过直连预算")
		"offer":
			if _role != "guest" or _received_offer:
				return
			if not invite.accept_offer(message.code, _configuration):
				_fail_signaling("信令邀请或直连配置无效")
				return
			session.connection_driver = null
			var result: Error = session.resume_peer(invite.link.peer) if _resuming else session.join_peer(invite.link.peer, _name, _spectator)
			session.connection_driver = self
			if result != OK:
				_fail_signaling("无法接入直连会话")
			else:
				_received_offer = true
		"answer":
			if _role != "host" or not invite._id(message.get("client")) or not _pending.has(int(message.client)) or not message.get("code") is String:
				return
			if _pending[int(message.client)].answered:
				return
			var data: Dictionary = invite._read(message.code)
			if not data.is_empty() and data.from == _pending[int(message.client)].peer_id and invite.accept_answer(message.code):
				_pending[int(message.client)].answered = true
			else:
				_warn("客机直连应答无效")
		"error", "room_closed":
			_fail_signaling(str(message.get("reason", "信令房间已关闭，已建立的直连不受影响")))
		_:
			_warn("信令服务返回未知消息")

func _valid_signal_reply(message: Dictionary) -> bool:
	var keys := message.keys()
	keys.sort()
	match message.get("kind"):
		"created": return keys == ["kind", "room"] and _valid_room_code(message.room)
		"join_request": return keys == ["client", "kind"] and invite._id(message.client)
		"offer": return keys == ["code", "kind"] and message.code is String
		"answer": return keys == ["client", "code", "kind"] and invite._id(message.client) and message.code is String
		"error": return keys == ["kind", "reason"] and message.reason is String
		"room_closed": return keys == ["kind"]
	return false

func _send(message: Dictionary) -> Error:
	if _socket == null or _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return ERR_UNAVAILABLE
	var text:String = JSON.stringify(message)
	if text.to_utf8_buffer().size() > max_packet_bytes:
		_warn("信令消息超过发送预算")
		return ERR_OUT_OF_MEMORY
	var result:Error = _socket.send_text(text)
	if result != OK:
		_warn("信令发送失败：" + error_string(result))
	return result

func _fail_signaling(reason: String) -> void:
	# 不调用 close()：它会关闭房主所有链路，误杀已连通对局。
	if _socket != null:
		_socket.close()
	_socket = null
	_deadline = 0
	for pending in _pending.values():
		invite.cancel_offer(pending.peer_id)
	_pending.clear()
	var session = _session.get_ref() if _session != null else null
	if _role == "guest" and session != null and not session.transport.is_connected_to_host():
		session.transport.close()
		invite.close()
		if _resuming:
			session.fail_reconnect(reason)
	_warn(reason)

func _warn(reason: String) -> void:
	error = reason
	rejected.emit(reason)

func _valid_room_code(code:Variant) -> bool:
	if not code is String or code.is_empty(): return false
	if JSON.stringify({"kind":"join","room":code}).to_utf8_buffer().size() > max_packet_bytes: return false
	for character in code:
		if character not in "0123456789abcdef": return false
	return true

func close() -> void:
	if _socket != null:
		_socket.close()
	_socket = null
	invite.close()
	_session = null
	room_code = ""
	error = ""
	_role = ""
	_pending.clear()
	_sent_request = false
	_joined_clients.clear()
	_sent_answer = false
	_received_offer = false
	_deadline = 0
	_url = ""
	_resuming = false
