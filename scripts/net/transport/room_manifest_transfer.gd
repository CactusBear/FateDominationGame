class_name RoomManifestTransfer
extends RefCounted

## 仅传输批准文件清单；数据下载、安装与确认仍由原有链路负责。
var validator = preload("res://scripts/net/content/room_data_assembler.gd").new()
var max_manifest_bytes:int = 16 * 1024 * 1024
var timeout_seconds:float = 30.0
var error:String = ""
var pending_revision:int = 0
var _files:Array = []
var _total:int = 0
var _received_bytes:int = 0
var _last_progress:int = 0

func encode(files:Array, revision:int, packet_bytes:int, max_file_bytes:int) -> Array:
	error = ""
	if revision <= 0 or packet_bytes <= 0 or max_manifest_bytes <= 0 or not validator.validate(files, max_file_bytes):
		error = validator.error if not validator.error.is_empty() else "清单传输预算或版本无效"
		return []
	if var_to_bytes(files).size() > max_manifest_bytes:
		error = "文件清单超过累计传输预算"
		return []
	var full := {"kind":"room_files", "revision":revision, "files":files}
	if var_to_bytes(full).size() <= packet_bytes:
		return [full]
	var parts:Array = []
	var offset:int = 0
	while offset < files.size():
		var lower:int = 1
		var upper:int = files.size() - offset
		var accepted:int = 0
		while lower <= upper:
			var count:int = lower + ((upper - lower) >> 1)
			if var_to_bytes(_part(files, revision, offset, count)).size() <= packet_bytes:
				accepted = count
				lower = count + 1
			else:
				upper = count - 1
		if accepted == 0:
			error = "单个文件清单条目超过消息预算"
			return []
		parts.append(_part(files, revision, offset, accepted))
		offset += accepted
	return parts

func _part(files:Array, revision:int, offset:int, count:int) -> Dictionary:
	return {"kind":"room_files_part", "revision":revision, "offset":offset, "total":files.size(), "files":files.slice(offset, offset + count)}

## 返回空字典表示尚未收齐或旧版本；error 非空表示本次已拒绝。
func accept(message:Dictionary, current_revision:int, max_file_bytes:int, packet_bytes:int) -> Dictionary:
	error = ""
	if not message.get("revision") is int:
		return _reject("文件清单分片版本无效")
	if message.revision <= current_revision or (pending_revision > 0 and message.revision < pending_revision):
		return {}
	if message.get("kind") != "room_files_part" or not message.get("offset") is int or not message.get("total") is int or not message.get("files") is Array:
		return _reject("文件清单分片字段无效")
	if message.total <= 0 or message.total > validator.max_files or message.offset < 0 or message.offset >= message.total or message.files.is_empty() or message.files.size() > message.total - message.offset:
		return _reject("文件清单分片数量或偏移无效")
	if var_to_bytes(message).size() > packet_bytes or not is_finite(timeout_seconds) or timeout_seconds <= 0:
		return _reject("文件清单分片超过消息预算或超时配置无效")
	if message.offset == 0 and message.revision > pending_revision:
		reset()
		pending_revision = message.revision
		_total = message.total
	if pending_revision != message.revision or _total != message.total or message.offset != _files.size():
		return _reject("文件清单分片乱序、重复或版本不一致")
	if not validator.validate(message.files, max_file_bytes):
		return _reject(validator.error)
	# 累计条目编码长度，分片数量不能绕过总接收预算。
	var bytes:int = var_to_bytes(message.files).size() - var_to_bytes([]).size()
	if bytes > max_manifest_bytes - _received_bytes - var_to_bytes([]).size():
		return _reject("文件清单超过累计传输预算")
	_received_bytes += bytes
	_files.append_array(message.files.duplicate(true))
	_last_progress = Time.get_ticks_msec()
	if _files.size() < _total:
		return {}
	if not validator.validate(_files, max_file_bytes):
		return _reject(validator.error)
	var complete := {"revision":pending_revision, "files":_files}
	reset()
	return complete

func expire() -> bool:
	if pending_revision == 0 or Time.get_ticks_msec() - _last_progress < timeout_seconds * 1000.0:
		return false
	_reject("文件清单分片接收超时")
	return true

func pending_count() -> int:
	return _files.size()

func reset() -> void:
	pending_revision = 0
	_files = []
	_total = 0
	_received_bytes = 0
	_last_progress = 0

func _reject(reason:String) -> Dictionary:
	error = reason
	reset()
	return {}
