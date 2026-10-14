extends RefCounted
## 可选原生单文件删除能力；不生成批准/身份，不枚举、不提供生命周期证明。
## caller 先持久化意图，提供历史批准证据并保持完整登记与部署排他门。
const Paths = preload("res://scripts/net/server/recovery_path_safety.gd")

static func remove_verified(request:Dictionary) -> Dictionary:
	var reason:String = evidence_error(request)
	if not reason.is_empty(): return _blocked(reason)
	if not ClassDB.class_exists("FateAtomicFileReplace"):
		return _blocked("native_extension_unavailable")
	var backend := ClassDB.instantiate("FateAtomicFileReplace") as RefCounted
	if backend == null or not backend.has_method("remove_verified"):
		return _blocked("native_interface_unavailable")
	# 先严格校验 caller 原始路径，再做 OS 分隔符表示转换；不 simplify/resolve。
	# native core 的 root pin 比较使用 Windows preferred path，不能混用 / 与 \\。
	var root:String = request.approved_root
	var path:String = request.path
	if OS.get_name() == "Windows":
		root = root.replace("/", "\\")
		path = path.replace("/", "\\")
	var raw:Variant = backend.call("remove_verified", root, path,
		request.approved_root_identity, request.parent_identity, request.file_identity,
		request.bytes, request.sha256)
	# 调用后未知回执可能已经提交 disposition，不能把未知当作已保留。
	if not raw is Dictionary: return _uncertain("invalid_native_result")
	for key in ["ok", "recovery_required"]:
		if not raw.get(key) is bool: return _uncertain("invalid_native_result")
	if not raw.get("stage") is String or not raw.get("native_error") is int or not raw.get("removed_bytes") is int:
		return _uncertain("invalid_native_result")
	var result:Dictionary = raw.duplicate(true)
	result.blocked = not result.ok
	if result.ok and (result.stage != "deleted_absence_confirmed" or result.removed_bytes != request.bytes or result.recovery_required):
		return _uncertain("invalid_native_success")
	return result

static func evidence_error(request:Dictionary) -> String:
	if not request.get("artifact_kind") is String or request.artifact_kind != "temporary_file": return "not_explicit_temporary_file"
	for key in ["approved_root", "path"]:
		if not request.get(key) is String: return "unsafe_path"
		var path:String = request[key]
		if path.begins_with("res://") or path.begins_with("user://") or Paths.absolute(path) != path: return "unsafe_path"
	if Paths.same(request.approved_root, request.path) or not Paths.contained(request.approved_root, request.path):
		return "outside_approved_root"
	for key in ["approved_root_identity", "parent_identity", "file_identity"]:
		var identity:Variant = request.get(key)
		if not identity is Dictionary or not identity.get("volume") is int or not identity.get("file_index") is int:
			return "missing_identity"
		if identity.volume < 0 or identity.volume > 4294967295 or identity.file_index <= 0: return "missing_identity"
	if not request.get("bytes") is int or request.bytes < 0: return "invalid_size"
	if not request.get("sha256") is String or request.sha256.length() != 64: return "invalid_sha256"
	for character in request.sha256:
		if character not in "0123456789abcdef": return "invalid_sha256"
	return ""

static func _blocked(stage:String) -> Dictionary:
	return {"ok":false, "blocked":true, "stage":stage, "native_error":0, "removed_bytes":0, "recovery_required":false}

static func _uncertain(stage:String) -> Dictionary:
	var result:Dictionary = _blocked(stage)
	result.recovery_required = true
	return result
