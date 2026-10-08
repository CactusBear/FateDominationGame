extends RefCounted

## 仅为候选目录消息扩展累计预算；分帧、顺序和来源隔离复用既有组件。
const Transport = preload("res://scripts/net/transport/enet_transport.gd")
const Fragments = preload("res://scripts/net/transport/packet_fragments.gd")
const KINDS:Array = ["catalog", "server_data_catalog"]
var max_message_bytes:int = 16 * 1024 * 1024
var fragments = Fragments.new()
var error:String = ""

func encode(message:Dictionary, packet_bytes:int) -> Array:
	error = ""
	if message.get("kind") not in KINDS or not Transport._plain(message):
		error = "仅允许基础类型的候选目录消息"
		return []
	var bytes:PackedByteArray = var_to_bytes(message)
	if packet_bytes <= 0 or max_message_bytes <= 0 or bytes.size() > max_message_bytes:
		error = "候选目录超过累计消息预算"
		return []
	if bytes.size() <= packet_bytes: return [message]
	var part_kind:String = message.kind + "_part"
	var envelope_bytes:int = var_to_bytes({"kind":part_kind, "bytes":PackedByteArray()}).size()
	var frames:Array = fragments.encode(bytes, packet_bytes - envelope_bytes, max_message_bytes)
	if frames.is_empty():
		error = fragments.error
		return []
	var result:Array = []
	for frame in frames:
		var part:Dictionary = {"kind":part_kind, "bytes":frame}
		if var_to_bytes(part).size() > packet_bytes:
			error = "候选目录分片超过单包预算"
			return []
		result.append(part)
	return result

## 接收者先检查房间阶段和连接权限；完整消息再交原有语义校验，不能提前替换目录。
func accept(connection:int, message:Dictionary, packet_bytes:int, expected_kind:String) -> Dictionary:
	error = ""
	var channel:int = 2 if expected_kind == "server_data_catalog" else 0
	if expected_kind not in KINDS or message.get("kind") != expected_kind + "_part" or not message.get("bytes") is PackedByteArray or var_to_bytes(message).size() > packet_bytes:
		return _reject(connection, channel, "候选目录分片字段或预算无效")
	var frame = bytes_to_var(message.bytes)
	if not frame is Dictionary or not Transport._plain(frame):
		return _reject(connection, channel, "候选目录分片内容无效")
	var complete:PackedByteArray = fragments.accept(connection, channel, frame, max_message_bytes)
	if not fragments.error.is_empty():
		error = fragments.error
		return {}
	if complete.is_empty(): return {}
	var decoded = bytes_to_var(complete)
	if not decoded is Dictionary or not Transport._plain(decoded) or decoded.get("kind") != expected_kind:
		return _reject(connection, channel, "候选目录分片不能承载其他操作")
	return decoded

func _reject(connection:int, channel:int, reason:String) -> Dictionary:
	fragments.cancel_channel(connection, channel)
	error = reason
	return {}
