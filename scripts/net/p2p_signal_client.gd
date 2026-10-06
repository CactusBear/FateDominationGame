extends RefCounted

signal room_created(code: String)
signal rejected(reason: String)

var invite = preload("res://scripts/net/p2p_invite.gd").new()
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

func host(url: String, session: RefCounted, name: String, settings: Dictionary, configuration: Dictionary) -> Error:
	session.close()
	close()
	var result: Error = invite.link.open(1, configuration)
	if result == OK:
		result = session.host_peer(invite.link.peer, name, settings)
	if result == OK:
		result = _open(url, session, "host", "", configuration)
	if result != OK:
		session.close()
		close()
	return result

func join(url: String, code: String, session: RefCounted, name: String, spectator: bool, configuration: Dictionary) -> Error:
	session.close()
	close()
	var pattern := RegEx.new()
	pattern.compile("^[0-9a-f]{32}$")
	if pattern.search(code) == null:
		return ERR_INVALID_PARAMETER
	_name = name
	_spectator = spectator
	return _open(url, session, "guest", code, configuration)

func _open(url: String, session: RefCounted, role: String, code: String, configuration: Dictionary) -> Error:
	if not (url.begins_with("ws://") or url.begins_with("wss://")) or not is_finite(handshake_seconds) or handshake_seconds <= 0 or max_packet_bytes <= 0:
		return ERR_INVALID_PARAMETER
	_socket = WebSocketPeer.new()
	_socket.inbound_buffer_size = max_packet_bytes
	_socket.outbound_buffer_size = max_packet_bytes
	var result := _socket.connect_to_url(url)
	if result != OK:
		return result
	_session = weakref(session)
	_role = role
	room_code = code
	_configuration = configuration.duplicate(true)
	_deadline = Time.get_ticks_msec() + int(handshake_seconds * 1000)
	session.connection_driver = self
	return OK

func poll() -> void:
	invite.poll()
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
		if error.is_empty():
			_warn("信令已断开，已建立的对局直连不受影响")
		return
	if _deadline > 0 and Time.get_ticks_msec() >= _deadline:
		_warn("信令或直连握手超时，未使用转发兜底")
		_socket.close()
		if _role == "guest" and not session.transport.is_connected_to_host():
			session.transport.close()
			invite.close()
		return
	if _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	if not _sent_request:
		_send({"kind": "create"} if _role == "host" else {"kind": "join", "room": room_code})
		_sent_request = true
	while _socket.get_available_packet_count() > 0:
		var bytes := _socket.get_packet()
		var parser := JSON.new()
		if not _socket.was_string_packet() or bytes.size() > max_packet_bytes or parser.parse(bytes.get_string_from_utf8()) != OK or not parser.data is Dictionary:
			_warn("信令服务返回无效消息")
			_socket.close()
			return
		_receive(parser.data, session)
	for client in _pending.keys():
		var pending: Dictionary = _pending[client]
		if Time.get_ticks_msec() >= pending.deadline:
			invite.cancel_offer(pending.peer_id)
			_pending.erase(client)
			_warn("一个客机的直连握手超时")
		elif not pending.sent:
			var code: String = invite.export_code(pending.peer_id)
			if not code.is_empty():
				_send({"kind": "offer", "client": client, "code": code})
				pending.sent = true
	if _role == "guest" and invite.link.peer != null and not _sent_answer:
		var code: String = invite.export_code(1)
		if not code.is_empty():
			_send({"kind": "answer", "code": code})
			_sent_answer = true

func _receive(message: Dictionary, session: RefCounted) -> void:
	match message.get("kind"):
		"created":
			var pattern := RegEx.new()
			pattern.compile("^[0-9a-f]{32}$")
			if _role != "host" or not message.get("room") is String or pattern.search(message.room) == null:
				_warn("信令房间码无效")
				return
			room_code = message.room
			_deadline = 0
			room_created.emit(room_code)
		"join_request":
			if _role != "host" or not invite._id(message.get("client")) or _pending.has(int(message.client)):
				return
			var id: int = invite.offer()
			if id > 1:
				_pending[int(message.client)] = {"peer_id": id, "sent": false, "deadline": Time.get_ticks_msec() + int(handshake_seconds * 1000)}
			else:
				_warn("客机连接超过直连预算")
		"offer":
			if _role != "guest" or not message.get("code") is String or not invite.accept_offer(message.code, _configuration):
				_warn("信令邀请或直连配置无效")
				return
			session.connection_driver = null
			var result: Error = session.join_peer(invite.link.peer, _name, _spectator)
			session.connection_driver = self
			if result != OK:
				_warn("无法接入直连会话")
		"answer":
			if _role != "host" or not invite._id(message.get("client")) or not _pending.has(int(message.client)) or not message.get("code") is String:
				return
			var data: Dictionary = invite._read(message.code)
			if not data.is_empty() and data.from == _pending[int(message.client)].peer_id and invite.accept_answer(message.code):
				_pending.erase(int(message.client))
			else:
				_warn("客机直连应答无效")
		"error", "room_closed":
			_warn(str(message.get("reason", "信令房间已关闭，已建立的直连不受影响")))
		_:
			_warn("信令服务返回未知消息")

func _send(message: Dictionary) -> void:
	if _socket != null and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_socket.send_text(JSON.stringify(message))

func _warn(reason: String) -> void:
	error = reason
	rejected.emit(reason)

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
	_sent_answer = false
	_deadline = 0
