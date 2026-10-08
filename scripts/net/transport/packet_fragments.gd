class_name MatchPacketFragments
extends RefCounted

## 可靠通道内部消息分帧；不解码或执行规则、对象及文件。
const MARKER:String = "_fate_transport_part"
var max_pending_bytes:int = 16 * 1024 * 1024
var max_transfers:int = 64
var timeout_seconds:float = 30.0
var error:String = ""
var _serial:int = 0
var _pending:Dictionary = {}
var _reserved:int = 0

func encode(bytes:PackedByteArray, frame_bytes:int, message_bytes:int) -> Array:
	error = ""
	if bytes.is_empty() or bytes.size() > message_bytes or frame_bytes <= 0:
		error = "消息或底层分帧预算无效"
		return []
	if bytes.size() <= frame_bytes:
		return [bytes]
	if _serial == 9223372036854775807:
		error = "分帧序号已耗尽，请重新连接"
		return []
	_serial += 1
	# 为 offset 与 total 预留同一编码宽度，再按实际编码校验各帧。
	var header:Dictionary = _frame(_serial, bytes.size(), bytes.size(), PackedByteArray())
	# Variant 的 PackedByteArray 编码按四字节补齐。
	var payload_bytes:int = ((frame_bytes - var_to_bytes(header).size()) >> 2) << 2
	if payload_bytes <= 0:
		error = "底层预算不足以容纳分帧头"
		return []
	var frames:Array = []
	var offset:int = 0
	while offset < bytes.size():
		var end:int = mini(offset + payload_bytes, bytes.size())
		var frame:PackedByteArray = var_to_bytes(_frame(_serial, offset, bytes.size(), bytes.slice(offset, end)))
		if frame.size() > frame_bytes:
			error = "分帧实际编码超过底层预算"
			return []
		frames.append(frame)
		offset = end
	return frames

func _frame(serial:int, offset:int, total:int, bytes:PackedByteArray) -> Dictionary:
	return {MARKER:1, "serial":serial, "offset":offset, "total":total, "bytes":bytes}

## 一条可靠通道同一时刻只拼装一份消息，跨来源与通道不共享缓冲。
func accept(sender:int, channel:int, frame:Dictionary, message_bytes:int) -> PackedByteArray:
	error = ""
	var key := Vector2i(sender, channel)
	if sender <= 0 or channel < 0 or not frame.get(MARKER) is int or frame[MARKER] != 1 or not frame.get("serial") is int or not frame.get("offset") is int or not frame.get("total") is int or not frame.get("bytes") is PackedByteArray:
		return _reject(key, "底层消息分帧字段无效")
	if frame.serial <= 0 or frame.total <= 0 or frame.total > message_bytes or frame.offset < 0 or frame.offset >= frame.total or frame.bytes.is_empty() or frame.bytes.size() > frame.total - frame.offset or not is_finite(timeout_seconds) or timeout_seconds <= 0:
		return _reject(key, "底层消息分帧长度或预算无效")
	if frame.offset == 0:
		if _pending.has(key) and frame.serial <= _pending[key].serial:
			return _reject(key, "底层消息分帧重复或序号回退")
		_release(key)
		if _pending.size() >= max_transfers or frame.total > max_pending_bytes - _reserved:
			return _reject(key, "底层消息接收预算不足")
		_pending[key] = {"serial":frame.serial, "total":frame.total, "bytes":PackedByteArray(), "touched":Time.get_ticks_msec()}
		_reserved += frame.total
	if not _pending.has(key):
		return _reject(key, "底层消息缺少首帧")
	var state:Dictionary = _pending[key]
	if state.serial != frame.serial or state.total != frame.total or state.bytes.size() != frame.offset:
		return _reject(key, "底层消息分帧乱序或不一致")
	var bytes:PackedByteArray = state.bytes
	bytes.append_array(frame.bytes)
	state.bytes = bytes
	state.touched = Time.get_ticks_msec()
	if bytes.size() < state.total:
		return PackedByteArray()
	_release(key)
	return bytes

func expire() -> Array:
	var senders:Array = []
	var now:int = Time.get_ticks_msec()
	for key in _pending.keys():
		if now - _pending[key].touched >= timeout_seconds * 1000.0:
			if key.x not in senders: senders.append(key.x)
			_release(key)
	return senders

func cancel_peer(sender:int) -> void:
	for key in _pending.keys():
		if key.x == sender: _release(key)

func cancel_channel(sender:int, channel:int) -> void:
	_release(Vector2i(sender, channel))

func pending_bytes() -> int:
	return _reserved

func reset() -> void:
	_pending.clear()
	_reserved = 0
	_serial = 0
	error = ""

func _release(key:Vector2i) -> void:
	if _pending.has(key):
		_reserved -= int(_pending[key].total)
		_pending.erase(key)

func _reject(key:Vector2i, reason:String) -> PackedByteArray:
	error = reason
	_release(key)
	return PackedByteArray()
