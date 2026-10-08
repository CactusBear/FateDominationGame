class_name MatchEnetTransport
extends RefCounted

## 只处理连接和基础类型消息，不执行收到的代码，不自行授予座位或管理权限。
signal message_received(sender: int, message: Dictionary)
signal peer_connected(id: int)
signal peer_disconnected(id: int)
signal packet_rejected(sender: int, reason: String)
## 拒包没有可信业务信封，序号始终未知；只公开固定代码和通道。
var last_packet_rejection: Dictionary = {}

func _reject_packet(sender:int, channel:int, code:String, reason:String) -> void:
	last_packet_rejection = {"connection":sender,"channel":channel,"code":code,"request_seq":-1}
	packet_rejected.emit(sender, reason)

var max_packet_bytes: int = 1024 * 1024
# webrtc-native 1.2.2 的数据通道声明 16384；底层预算显式配置。
var max_webrtc_frame_bytes:int = 16384
const PACKET_FRAGMENTS = preload("res://scripts/net/transport/packet_fragments.gd")
## 只允许分帧器声明的固定原因进入诊断，未知原因一律归类而不透传。
const FRAGMENT_REJECTION_CODES = {
	"底层消息分帧字段无效":"fragment_fields",
	"底层消息分帧长度或预算无效":"fragment_length_budget",
	"底层消息分帧重复或序号回退":"fragment_replay",
	"底层消息接收预算不足":"fragment_receive_budget",
	"底层消息缺少首帧":"fragment_missing_start",
	"底层消息分帧乱序或不一致":"fragment_order",
}
var _fragments = PACKET_FRAGMENTS.new()
var max_packets_per_poll: int = 128
var _native_poll_busy:bool = false
var _peer: MultiplayerPeer
var bound_port: int = 0
var _connected_peers: Dictionary = {}
var _recovery_probe = preload("res://scripts/net/transport/recovery_net_probe.gd").new()

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
	_recovery_probe.sample(self,"peer_connected",id)
	peer_connected.emit(id)

func _on_disconnected(id: int) -> void:
	_recovery_probe.sample(self,"peer_disconnected",id)
	_connected_peers.erase(id)
	_fragments.cancel_peer(id)
	peer_disconnected.emit(id)

# 仅服务原生网络；不取包、不解码、不发 message_received，不运行业务或规则。
# peer 连接事件仍按原路径分发；会话用修订/取消守卫观察它们。
func keep_alive() -> bool:
	if _native_poll_busy or _peer == null or _peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED: return false
	_native_poll_busy = true
	var peer:MultiplayerPeer = _peer
	var diagnostic_poll_start:int = Time.get_ticks_usec() if _recovery_probe.enabled() else 0
	peer.poll()
	_recovery_probe.native_poll_elapsed(diagnostic_poll_start)
	_native_poll_busy = false
	return _peer == peer and peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED

func poll() -> void:
	_recovery_probe.poll_enter()
	_recovery_probe.sample(self,"poll")
	if _peer == null or _peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return
	for sender in _fragments.expire():
		_reject_packet(sender, -1, "fragment_timeout", "底层消息分帧接收超时")
	if not keep_alive(): return
	_recovery_probe.sample(self,"poll_after")
	if _peer == null or _peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return
	var count := 0
	while _peer != null and _peer.get_available_packet_count() > 0 and count < max_packets_per_poll:
		count += 1
		var sender := _peer.get_packet_peer()
		var channel:int = _peer.get_packet_channel()
		var bytes := _peer.get_packet()
		var frame_budget:int = mini(max_packet_bytes, max_webrtc_frame_bytes) if _peer is WebRTCMultiplayerPeer else max_packet_bytes
		if channel < 0 or channel >= 3 or bytes.is_empty() or bytes.size() > frame_budget:
			_fragments.cancel_channel(sender, channel)
			var code:String = "invalid_channel" if channel < 0 or channel >= 3 else ("empty_frame" if bytes.is_empty() else "frame_budget")
			_reject_packet(sender, channel, code, "消息通道无效" if code == "invalid_channel" else ("消息为空" if code == "empty_frame" else "消息过大"))
			continue
		# bytes_to_var 不允许实例化 Object；不能改成 bytes_to_var_with_objects。
		var value = bytes_to_var(bytes)
		if not value is Dictionary or not _plain(value):
			_fragments.cancel_channel(sender, channel)
			_reject_packet(sender, channel, "invalid_format", "消息格式无效")
			continue
		if value.has(PACKET_FRAGMENTS.MARKER):
			var assembled:PackedByteArray = _fragments.accept(sender, channel, value, max_packet_bytes)
			if not _fragments.error.is_empty():
				_reject_packet(sender, channel, FRAGMENT_REJECTION_CODES.get(_fragments.error,"fragment_invalid"), _fragments.error if FRAGMENT_REJECTION_CODES.has(_fragments.error) else "底层消息分帧无效")
			if assembled.is_empty(): continue
			value = bytes_to_var(assembled)
			if not value is Dictionary or value.has(PACKET_FRAGMENTS.MARKER) or not _plain(value):
				_reject_packet(sender, channel, "assembled_invalid", "分帧消息内容格式无效")
				continue
		else:
			# 可靠通道后续整包已到，先前未收齐的消息不可再续接。
			_fragments.cancel_channel(sender, channel)
		message_received.emit(sender, value)

func send(target: int, message: Dictionary, channel: int = 0) -> Error:
	if not is_connected_to_host():
		return ERR_UNCONFIGURED
	if target <= 0 or channel < 0 or channel >= 3 or message.has(PACKET_FRAGMENTS.MARKER) or not _plain(message):
		return ERR_INVALID_PARAMETER
	if not _connected_peers.has(target):
		return ERR_UNAVAILABLE
	if _peer is ENetMultiplayerPeer:
		var remote: ENetPacketPeer = (_peer as ENetMultiplayerPeer).get_peer(target)
		if remote == null or remote.get_state() != ENetPacketPeer.STATE_CONNECTED:
			return ERR_UNAVAILABLE
	elif _peer is WebRTCMultiplayerPeer:
		var rtc:WebRTCMultiplayerPeer = _peer
		if not rtc.has_peer(target): return ERR_UNAVAILABLE
		var remote:Dictionary = rtc.get_peer(target)
		var channels:Array = remote.get("channels",[])
		# Godot 的 0 号可靠发送使用保留通道；非零编号排在三个保留通道后。
		var index:int = 0 if channel == 0 else channel + 2
		if not remote.get("connected",false) or index >= channels.size() or channels[index].get_ready_state() != WebRTCDataChannel.STATE_OPEN:
			return ERR_UNAVAILABLE
	var bytes := var_to_bytes(message)
	if bytes.size() > max_packet_bytes:
		return ERR_OUT_OF_MEMORY
	_peer.set_target_peer(target)
	_peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
	_peer.transfer_channel = channel
	var frame_bytes:int = mini(max_packet_bytes, max_webrtc_frame_bytes) if _peer is WebRTCMultiplayerPeer else max_packet_bytes
	var frames:Array = _fragments.encode(bytes, frame_bytes, max_packet_bytes)
	if frames.is_empty(): return ERR_INVALID_PARAMETER
	for frame in frames:
		var result:Error = _peer.put_packet(frame)
		if result != OK: return result
	return OK

func peer_id() -> int:
	return _peer.get_unique_id() if is_connected_to_host() else 0

func is_connected_to_host() -> bool:
	return _peer != null and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func is_connecting() -> bool:
	return _peer != null and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING

func disconnect_peer(id: int) -> void:
	if peer_id() == MultiplayerPeer.TARGET_PEER_SERVER and id > MultiplayerPeer.TARGET_PEER_SERVER:
		if _peer is WebRTCMultiplayerPeer:
			(_peer as WebRTCMultiplayerPeer).remove_peer(id)
		else:
			_peer.disconnect_peer(id)

func close() -> void:
	_recovery_probe.sample(self,"close_requested")
	if _peer != null:
		_peer.peer_connected.disconnect(_on_connected)
		_peer.peer_disconnected.disconnect(_on_disconnected)
		_peer.close()
	_peer = null
	_fragments.reset()
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
