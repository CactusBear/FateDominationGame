class_name ScratchMatchWebRTCLink
extends RefCounted

## 只建立房主与客机的直连；信令如何送达由调用方决定。
signal description_created(target: int, type: String, sdp: String)
signal candidate_created(target: int, media: String, index: int, sdp: String)
signal connection_removed(target: int)
var peer: WebRTCMultiplayerPeer
var error: String = ""
var max_description_bytes: int = 65536
var max_candidate_bytes: int = 4096
var max_candidates_per_peer: int = 64
var max_peers: int = 32
var _configuration: Dictionary = {}
var _connections: Dictionary = {}
var _remote_description: Dictionary = {}
var _pending_candidates: Dictionary = {}

func open(id: int, configuration: Dictionary) -> Error:
	close()
	if id < 1 or id > 2147483647 or not _direct_configuration(configuration):
		return ERR_INVALID_PARAMETER
	_configuration = configuration.duplicate(true)
	peer = WebRTCMultiplayerPeer.new()
	var channels := [MultiplayerPeer.TRANSFER_MODE_RELIABLE, MultiplayerPeer.TRANSFER_MODE_RELIABLE, MultiplayerPeer.TRANSFER_MODE_RELIABLE]
	var result := peer.create_server(channels) if id == 1 else peer.create_client(id, channels)
	if result != OK:
		close()
	else:
		peer.peer_disconnected.connect(remove_peer)
	return result

static func _direct_configuration(configuration: Dictionary) -> bool:
	if configuration.keys() != ["iceServers"] or not configuration.iceServers is Array:
		return false
	for server in configuration.iceServers:
		if not server is Dictionary or server.keys() != ["urls"]:
			return false
		var urls = [server.urls] if server.urls is String else server.urls
		if not urls is Array or urls.is_empty():
			return false
		for url in urls:
			if not url is String or not url.begins_with("stun:") or url.length() <= 5:
				return false
	return true

func _add_connection(id: int) -> Error:
	if peer == null or id < 1 or id > 2147483647 or id == peer.get_unique_id() or (peer.get_unique_id() != 1 and id != 1):
		return ERR_INVALID_PARAMETER
	if _connections.has(id):
		return OK
	if _connections.size() >= max_peers:
		return ERR_OUT_OF_MEMORY
	var connection := WebRTCPeerConnection.new()
	var result := connection.initialize(_configuration)
	if result != OK:
		return result
	result = peer.add_peer(connection, id)
	if result != OK:
		connection.close()
		return result
	_connections[id] = connection
	connection.session_description_created.connect(_description.bind(id))
	connection.ice_candidate_created.connect(_candidate.bind(id))
	return OK

func offer(id: int) -> Error:
	if peer == null or peer.get_unique_id() != 1 or id <= 1 or _connections.has(id):
		return ERR_INVALID_PARAMETER
	var result := _add_connection(id)
	return _connections[id].create_offer() if result == OK else result

func _description(type: String, sdp: String, id: int) -> void:
	var result: Error = _connections[id].set_local_description(type, sdp)
	if result != OK:
		error = "无法设置 WebRTC 本地握手"
		return
	description_created.emit(id, type, sdp)

func _candidate(media: String, index: int, sdp: String, id: int) -> void:
	if _direct_candidate(sdp):
		candidate_created.emit(id, media, index, sdp)

func accept_description(id: int, type: String, sdp: String) -> Error:
	if peer == null or sdp.to_utf8_buffer().size() > max_description_bytes or sdp.is_empty() or "typ relay" in sdp:
		return ERR_INVALID_PARAMETER
	if (peer.get_unique_id() == 1 and (type != "answer" or not _connections.has(id))) or (peer.get_unique_id() != 1 and (type != "offer" or id != 1)):
		return ERR_INVALID_PARAMETER
	if _remote_description.has(id):
		return ERR_ALREADY_IN_USE
	var result := _add_connection(id)
	if result != OK:
		return result
	result = _connections[id].set_remote_description(type, sdp)
	if result != OK:
		return result
	_remote_description[id] = true
	for item in _pending_candidates.get(id, []):
		_connections[id].add_ice_candidate(item.media, item.index, item.sdp)
	_pending_candidates.erase(id)
	return OK

func _direct_candidate(sdp: String) -> bool:
	if sdp.to_utf8_buffer().size() > max_candidate_bytes:
		return false
	var words := sdp.split(" ", false)
	var type_at := words.find("typ")
	return type_at >= 0 and type_at + 1 < words.size() and words[type_at + 1] in ["host", "srflx", "prflx"]

func accept_candidate(id: int, media: String, index: int, sdp: String) -> Error:
	if not _direct_candidate(sdp) or media.length() > 128 or index < 0 or not _connections.has(id):
		return ERR_INVALID_PARAMETER
	if _remote_description.has(id):
		return _connections[id].add_ice_candidate(media, index, sdp)
	var pending: Array = _pending_candidates.get(id, [])
	if pending.size() >= max_candidates_per_peer:
		return ERR_OUT_OF_MEMORY
	pending.append({"media": media, "index": index, "sdp": sdp})
	_pending_candidates[id] = pending
	return OK

func poll() -> void:
	for connection in _connections.values():
		connection.poll()

func gathering_complete(id: int) -> bool:
	return _connections.has(id) and _connections[id].get_gathering_state() == WebRTCPeerConnection.GATHERING_STATE_COMPLETE

func remove_peer(id: int) -> void:
	if not _connections.has(id):
		return
	var connection = _connections[id]
	_connections.erase(id)
	_remote_description.erase(id)
	_pending_candidates.erase(id)
	if peer != null and peer.has_peer(id):
		peer.remove_peer(id)
	connection.close()
	connection_removed.emit(id)

func close() -> void:
	if peer != null:
		if peer.peer_disconnected.is_connected(remove_peer):
			peer.peer_disconnected.disconnect(remove_peer)
		peer.close()
	for connection in _connections.values():
		connection.close()
	peer = null
	_connections.clear()
	_remote_description.clear()
	_pending_candidates.clear()
	_configuration.clear()
	error = ""
