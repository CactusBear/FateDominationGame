class_name MatchP2PInvite
extends RefCounted

const PREFIX := "FATEP2P1:"
var link = preload("res://scripts/net/webrtc_link.gd").new()
var max_invite_bytes: int = 128 * 1024
var error: String = ""
var _pending: Dictionary = {}

func _init() -> void:
	_bind()

func _bind() -> void:
	if not link.connection_removed.is_connected(_connection_removed):
		link.connection_removed.connect(_connection_removed)
	if not link.description_created.is_connected(_description):
		link.description_created.connect(_description)
	if not link.candidate_created.is_connected(_candidate):
		link.candidate_created.connect(_candidate)

func offer() -> int:
	_bind()
	if link.peer == null or link.peer.get_unique_id() != 1:
		return 0
	var crypto := Crypto.new()
	var id: int = 2 + crypto.generate_random_bytes(4).decode_u32(0) % 2147483646
	while _pending.has(id):
		id = 2 + crypto.generate_random_bytes(4).decode_u32(0) % 2147483646
	_pending[id] = {"nonce": crypto.generate_random_bytes(16).hex_encode(), "candidates": [], "type": "", "sdp": "", "consumed": false}
	if link.offer(id) != OK:
		_pending.erase(id)
		return 0
	return id

func _description(id: int, type: String, sdp: String) -> void:
	if _pending.has(id):
		_pending[id].type = type
		_pending[id].sdp = sdp

func _connection_removed(id: int) -> void:
	_pending.erase(id)

func _candidate(id: int, media: String, index: int, sdp: String) -> void:
	if not _pending.has(id):
		return
	if _pending[id].candidates.size() >= link.max_candidates_per_peer:
		error = "邀请码候选地址超过预算"
		return
	_pending[id].candidates.append({"media": media, "index": index, "sdp": sdp})

func export_code(id: int) -> String:
	if not _pending.has(id) or _pending[id].sdp.is_empty() or not link.gathering_complete(id) or not error.is_empty():
		return ""
	var item: Dictionary = _pending[id]
	var content := JSON.stringify({"v": 1, "nonce": item.nonce, "from": link.peer.get_unique_id(), "to": id, "type": item.type, "sdp": item.sdp, "candidates": item.candidates})
	var code := PREFIX + Marshalls.utf8_to_base64(content)
	if code.length() > max_invite_bytes:
		error = "邀请码超过长度预算"
		return ""
	return code

static func _id(value) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value == floor(float(value)) and value >= 1 and value <= 2147483647

func _read(code: String) -> Dictionary:
	if code.length() > max_invite_bytes or not code.begins_with(PREFIX):
		return {}
	var encoded := code.substr(PREFIX.length())
	var valid := RegEx.new()
	valid.compile("^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$")
	if encoded.is_empty() or valid.search(encoded) == null:
		return {}
	var bytes := Marshalls.base64_to_raw(encoded)
	# 此协议只携带 ASCII SDP 与地址，避免损坏 UTF-8 进入引擎解码器。
	for byte in bytes:
		if byte > 127:
			return {}
	var parser := JSON.new()
	if parser.parse(bytes.get_string_from_ascii()) != OK or not parser.data is Dictionary:
		return {}
	var data: Dictionary = parser.data
	var keys := data.keys()
	keys.sort()
	if keys != ["candidates", "from", "nonce", "sdp", "to", "type", "v"] or data.v != 1 or not _id(data.from) or not _id(data.to) or data.from == data.to:
		return {}
	if not data.nonce is String or not data.sdp is String or not data.type is String or data.type not in ["offer", "answer"]:
		return {}
	valid.compile("^[0-9a-f]{32}$")
	if valid.search(data.nonce) == null or data.sdp.is_empty() or data.sdp.length() > link.max_description_bytes or "typ relay" in data.sdp:
		return {}
	if not data.candidates is Array or data.candidates.size() > link.max_candidates_per_peer:
		return {}
	for item in data.candidates:
		if not item is Dictionary or item.size() != 3 or not item.get("media") is String or not item.get("sdp") is String:
			return {}
		var index = item.get("index")
		if not (index is int or index is float) or index < 0 or index >= 2147483647:
			return {}
		if item.media.length() > 128 or not _id(index + 1) or not link._direct_candidate(item.sdp):
			return {}
	return data

func accept_offer(code: String, configuration: Dictionary) -> bool:
	var data := _read(code)
	if data.is_empty() or data.type != "offer" or data.from != 1 or data.to <= 1 or link.peer != null:
		return false
	if link.open(int(data.to), configuration) != OK:
		return false
	_bind()
	_pending[1] = {"nonce": data.nonce, "candidates": [], "type": "", "sdp": "", "consumed": false}
	if not _accept(data):
		close()
		return false
	return true

func accept_answer(code: String) -> bool:
	var data := _read(code)
	if data.is_empty() or data.type != "answer" or data.to != 1 or not _pending.has(int(data.from)):
		return false
	var item: Dictionary = _pending[int(data.from)]
	if item.nonce != data.nonce or item.consumed:
		return false
	if not _accept(data):
		return false
	item.consumed = true
	return true

func _accept(data: Dictionary) -> bool:
	var id := int(data.from)
	if link.accept_description(id, data.type, data.sdp) != OK:
		return false
	for item in data.candidates:
		if link.accept_candidate(id, item.media, int(item.index), item.sdp) != OK:
			return false
	return true

func close() -> void:
	link.close()
	if link.connection_removed.is_connected(_connection_removed):
		link.connection_removed.disconnect(_connection_removed)
	if link.description_created.is_connected(_description):
		link.description_created.disconnect(_description)
	if link.candidate_created.is_connected(_candidate):
		link.candidate_created.disconnect(_candidate)
	_pending.clear()
	error = ""

func poll() -> void:
	link.poll()

func cancel_offer(id: int) -> bool:
	if link.peer == null or link.peer.get_unique_id() != 1 or not _pending.has(id) or _pending[id].consumed:
		return false
	link.remove_peer(id)
	_pending.erase(id)
	return true
