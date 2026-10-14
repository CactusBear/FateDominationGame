extends RefCounted

## 只选择明确声明的临时单文件；调用方必须提供可信部署配置和当前生命周期台账。
const Paths = preload("res://scripts/net/server/recovery_path_safety.gd")

static func configuration_error(config:Dictionary, now:int) -> String:
	if now < 0: return "invalid_clock"
	for key in ["retention_seconds", "max_files", "max_bytes"]:
		if not config.get(key) is int or config[key] < 0: return "missing_or_invalid_config:" + key
	for key in ["approved_roots", "protected_paths", "current_instances"]:
		if not config.get(key) is Array: return "missing_or_invalid_config:" + key
	if config.approved_roots.is_empty(): return "no_approved_root"
	for root in config.approved_roots:
		if not root is String or not Paths.checked(root, root): return "unsafe_approved_root"
	for path in config.protected_paths:
		if not path is String or Paths.absolute(path).is_empty(): return "invalid_protected_path"
	for instance in config.current_instances:
		if not instance is String or instance.is_empty(): return "invalid_current_instance"
	return ""

static func record_error(record:Dictionary, config:Dictionary, now:int) -> String:
	for key in ["artifact_id", "source", "instance_id", "consumption_receipt_id", "exit_receipt_id", "path", "sha256"]:
		if not record.get(key) is String or record[key].is_empty(): return "missing_declaration:" + key
	if record.get("artifact_kind") != "temporary_file": return "not_declared_temporary_file"
	if record.get("save_status") != "confirmed": return "save_unconfirmed"
	for key in ["consumed", "recyclable", "instance_exited"]:
		if record.get(key) != true or not record.get(key) is bool: return "not_confirmed:" + key
	if record.instance_id in config.current_instances: return "current_instance"
	for key in ["consumed_at", "bytes"]:
		if not record.get(key) is int or record[key] < 0: return "missing_declaration:" + key
	if record.consumed_at > now or now - record.consumed_at < config.retention_seconds: return "retention_not_elapsed"
	var path:String = record.path
	for protected in config.protected_paths:
		if Paths.contained(protected, path): return "protected_path"
	var approved:bool = false
	for root in config.approved_roots:
		if not Paths.same(root, path) and Paths.checked(root, path):
			approved = true
			break
	if not approved: return "unsafe_or_outside_path"
	if not FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path): return "not_regular_file"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return "unreadable_file"
	var length:int = file.get_length()
	file.close()
	if length != record.bytes or FileAccess.get_sha256(path) != record.sha256: return "artifact_changed"
	return ""

static func select(records:Array, config:Dictionary, now:int) -> Dictionary:
	var result:Dictionary = {"candidates":[], "rejected":[], "planned_files":0, "planned_bytes":0, "config_error":configuration_error(config, now)}
	if not result.config_error.is_empty(): return result
	var ids:Dictionary = {}
	var paths:Dictionary = {}
	# 重复身份/路径全部拒绝，不让输入顺序挑中互相矛盾的声明。
	for record in records:
		if not record is Dictionary: continue
		var id = record.get("artifact_id")
		var path = record.get("path")
		if id is String: ids[id] = int(ids.get(id, 0)) + 1
		if path is String:
			var canonical:String = Paths.absolute(path)
			if OS.get_name() == "Windows": canonical = canonical.to_lower()
			paths[canonical] = int(paths.get(canonical, 0)) + 1
	for record in records:
		if not record is Dictionary:
			result.rejected.append({"artifact_id":"", "reason":"invalid_record"})
			continue
		var reason:String = record_error(record, config, now)
		var canonical:String = Paths.absolute(str(record.get("path", "")))
		if OS.get_name() == "Windows": canonical = canonical.to_lower()
		if reason.is_empty() and (ids.get(record.artifact_id, 0) != 1 or paths.get(canonical, 0) != 1): reason = "duplicate_identity_or_path"
		if reason.is_empty() and (result.planned_files >= config.max_files or record.bytes > config.max_bytes - result.planned_bytes): reason = "budget_exhausted"
		if not reason.is_empty():
			result.rejected.append({"artifact_id":record.get("artifact_id", ""), "reason":reason})
			continue
		result.candidates.append(record.duplicate(true))
		result.planned_files += 1
		result.planned_bytes += record.bytes
	return result