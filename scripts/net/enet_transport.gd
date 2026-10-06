class_name MatchEnetTransport
extends RefCounted

## 只处理连接和基础类型消息，不执行收到的代码，不自行授予座位或管理权限。
signal message_received(sender: int, message: Dictionary)
signal peer_connected(id: int)
signal peer_disconnected(id: int)
signal packet_rejected(sender: int, reason: String)

var max_packet_bytes: int = 1024 * 1024
var max_packets_per_poll: int = 128
var _peer: MultiplayerPeer
var bound_port: int = 0
var _connected_peers: Dictionary = {}

func listen(port: int, bind_address: String = "*", max_clients: int = 32) -> Error:
	close()
	if port < 1 or port > 65535 or max_clients < 1:
		return ERR_INVALID_PARAMETER
	_create_peer()
	var enet := _peer as ENetMultiplayerPeer
	enet.set_bind_ip(bind_address)
	var result := enet.create_server(port, max_clients, 3)
	if result != OK:
		close()
		return result
	bound_port = port
	return OK

func connect_to(address: String, port: int) -> Error:
	close()
	if address.is_empty() or port < 1 or port > 65535:
		return ERR_INVALID_PARAMETER
	_create_peer()
	var result := (_peer as ENetMultiplayerPeer).create_client(address, port, 3)
	if result != OK:
		close()
	return result

func _create_peer() -> void:
	_peer = ENetMultiplayerPeer.new()
	_peer.peer_connected.connect(_on_connected)
	_peer.peer_disconnected.connect(_on_disconnected)

## 在握手开始前接管，保留后续 peer_connected 的真实连接身份。
func attach_peer(peer: MultiplayerPeer) -> Error:
	if peer == null or not (peer is ENetMultiplayerPeer or peer is WebRTCMultiplayerPeer):
		return ERR_INVALID_PARAMETER
	close()
	_peer = peer
	_peer.peer_connected.connect(_on_connected)
	_peer.peer_disconnected.connect(_on_disconnected)
	return OK

func _on_connected(id: int) -> void:
	_connected_peers[id] = true
	peer_connected.emit(id)

func _on_disconnected(id: int) -> void:
	_connected_peers.erase(id)
	peer_disconnected.emit(id)

func poll() -> void:
	if _peer == null or _peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return
	_peer.poll()
	if _peer == null or _peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return
	var count := 0
	while _peer != null and _peer.get_available_packet_count() > 0 and count < max_packets_per_poll:
		count += 1
		var sender := _peer.get_packet_peer()
		var bytes := _peer.get_packet()
		if bytes.size() > max_packet_bytes:
			packet_rejected.emit(sender, "消息过大")
			continue
		# bytes_to_var 不允许实例化 Object；不能改成 bytes_to_var_with_objects。
		var value = bytes_to_var(bytes)
		if not value is Dictionary or not _plain(value):
			packet_rejected.emit(sender, "消息格式无效")
			continue
		message_received.emit(sender, value)

func send(target: int, message: Dictionary, channel: int = 0) -> Error:
	if not is_connected_to_host():
		return ERR_UNCONFIGURED
	if target <= 0 or channel < 0 or channel >= 3 or not _plain(message):
		return ERR_INVALID_PARAMETER
	if not _connected_peers.has(target):
		return ERR_UNAVAILABLE
	if _peer is ENetMultiplayerPeer:
		var remote: ENetPacketPeer = (_peer as ENetMultiplayerPeer).get_peer(target)
		if remote == null or remote.get_state() != ENetPacketPeer.STATE_CONNECTED:
			return ERR_UNAVAILABLE
	var bytes := var_to_bytes(message)
	if bytes.size() > max_packet_bytes:
		return ERR_OUT_OF_MEMORY
	_peer.set_target_peer(target)
	_peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
	_peer.transfer_channel = channel
	return _peer.put_packet(bytes)

func peer_id() -> int:
	return _peer.get_unique_id() if is_connected_to_host() else 0

func is_connected_to_host() -> bool:
	return _peer != null and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func disconnect_peer(id: int) -> void:
	if peer_id() == MultiplayerPeer.TARGET_PEER_SERVER and id > MultiplayerPeer.TARGET_PEER_SERVER:
		if _peer is WebRTCMultiplayerPeer:
			(_peer as WebRTCMultiplayerPeer).remove_peer(id)
		else:
			_peer.disconnect_peer(id)

func close() -> void:
	if _peer != null:
		_peer.peer_connected.disconnect(_on_connected)
		_peer.peer_disconnected.disconnect(_on_disconnected)
		_peer.close()
	_peer = null
	bound_port = 0
	_connected_peers.clear()

static func _plain(value, depth: int = 0) -> bool:
	if depth > 32:
		return false
	if value is Array:
		for item in value:
			if not _plain(item, depth + 1):
				return false
		return true
	if value is Dictionary:
		for key in value:
			if (not key is String and not key is StringName) or not _plain(value[key], depth + 1):
				return false
		return true
	return typeof(value) in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_PACKED_BYTE_ARRAY]
