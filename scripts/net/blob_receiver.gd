class_name MatchBlobReceiver
extends RefCounted

## expect_blob 只能由本地确认后的清单调用，不能由未认证的分块消息隐式创建。
signal completed(sender: int, key: String)
var cache = preload("res://scripts/net/content_cache.gd").new()
var max_pending_bytes: int = 128 * 1024 * 1024
var max_transfers: int = 32
var max_chunk_bytes: int = 64 * 1024
var error: String = ""
var _pending: Dictionary = {}
var _reserved: int = 0

func expect_blob(sender: int, key: String, size: int) -> bool:
	if sender <= 0 or not cache.valid_key(key) or size <= 0 or size > cache.max_file_bytes:
		return _reject("文件声明无效")
	var id := _id(sender, key)
	if _pending.has(id):
		return _pending[id].size == size
	if _pending.size() >= max_transfers or size > max_pending_bytes - _reserved:
		return _reject("接收预算不足")
	_pending[id] = {"sender": sender, "size": size, "bytes": PackedByteArray()}
	_reserved += size
	return true

func offset_for(sender: int, key: String) -> int:
	var id := _id(sender, key)
	return _pending[id].bytes.size() if _pending.has(id) else -1

func accept(sender: int, key: String, offset: int, bytes: PackedByteArray) -> bool:
	var id := _id(sender, key)
	if not _pending.has(id):
		return _reject("未批准该来源的文件")
	var transfer: Dictionary = _pending[id]
	if bytes.is_empty() or bytes.size() > max_chunk_bytes or offset != transfer.bytes.size() or bytes.size() > transfer.size - offset:
		return _reject("分块长度或偏移无效")
	var buffer: PackedByteArray = transfer.bytes
	buffer.append_array(bytes)
	transfer.bytes = buffer
	if buffer.size() == transfer.size:
		_release(id)
		if not cache.store(key, buffer):
			return _reject(cache.error)
		completed.emit(sender, key)
	return true

func cancel_peer(sender: int) -> void:
	for id in _pending.keys():
		if _pending[id].sender == sender:
			_release(id)

func cancel_blob(sender: int, key: String) -> void:
	var id := _id(sender, key)
	if _pending.has(id):
		_release(id)

func pending_bytes() -> int:
	return _reserved

func _release(id: String) -> void:
	_reserved -= int(_pending[id].size)
	_pending.erase(id)

static func _id(sender: int, key: String) -> String:
	return str(sender) + ":" + key

func _reject(reason: String) -> bool:
	error = reason
	return false
