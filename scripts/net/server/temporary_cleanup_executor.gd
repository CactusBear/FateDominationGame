extends RefCounted

## 不枚举目录、不升级声明。计划与当前可信台账一致才可执行，并逐文件重验。
const Policy = preload("res://scripts/net/server/temporary_cleanup_policy.gd")

const NativeDelete = preload("res://scripts/io/temporary_cleanup_native_delete.gd")

## 可选注入仅用于持有批准身份与持久化意图的显式 caller；现 ledger 不传入，默认阻断。
## evidence 按 artifact_id 绑定，不从候选/当前文件现采身份生成授权。
static func execute(candidates:Array, current_records:Array, config:Dictionary, now:int, remove_verified:Callable = Callable(), evidence:Dictionary = {}) -> Dictionary:
	var result:Dictionary = {"removed":[], "refused":[], "removed_files":0, "removed_bytes":0, "config_error":"", "recovery_required":false}
	var current:Dictionary = Policy.select(current_records, config, now)
	result.config_error = current.config_error
	if not result.config_error.is_empty(): return result
	var processed:Dictionary = {}
	for candidate in candidates:
		if not candidate is Dictionary:
			result.refused.append({"artifact_id":"", "reason":"invalid_candidate"})
			continue
		var id = candidate.get("artifact_id", "")
		var reason:String = "not_in_current_eligible_ledger"
		for record in current.candidates:
			if record == candidate:
				reason = Policy.record_error(record, config, now)
				break
		if processed.has(id): reason = "duplicate_candidate"
		processed[id] = true
		if reason.is_empty() and (result.removed_files >= config.max_files or candidate.bytes > config.max_bytes - result.removed_bytes): reason = "budget_exhausted"
		if reason.is_empty() and not remove_verified.is_valid(): reason = "native_delete_adapter_missing"
		var request:Variant = evidence.get(id)
		if reason.is_empty():
			if not request is Dictionary:
				reason = "native_delete_evidence_missing"
			else:
				reason = NativeDelete.evidence_error(request)
				if reason.is_empty() and (request.path != candidate.path or request.bytes != candidate.bytes or request.sha256 != candidate.sha256 or request.artifact_kind != candidate.artifact_kind):
					reason = "native_delete_evidence_mismatch"
				if reason.is_empty() and request.approved_root not in config.approved_roots:
					reason = "native_delete_root_not_approved"
		if not reason.is_empty():
			result.refused.append({"artifact_id":id, "reason":reason})
			continue
		var receipt:Variant = remove_verified.call(request.duplicate(true))
		# 注入能力的回执必须明确；提交后不确定时停止本批，并交还未解决意图。
		var valid:bool = receipt is Dictionary
		if valid:
			valid = receipt.get("ok") is bool and receipt.get("recovery_required") is bool and receipt.get("stage") is String and receipt.get("removed_bytes") is int
		if not valid:
			result.refused.append({"artifact_id":id, "reason":"invalid_delete_receipt"})
			result.recovery_required = true
			return result
		if not receipt.ok or receipt.recovery_required:
			result.refused.append({"artifact_id":id, "reason":receipt.stage, "native_receipt":receipt.duplicate(true)})
			if receipt.recovery_required:
				result.recovery_required = true
				return result
			continue
		# 除原生 pinned readback 外再次精确读回；缺文件不追认失败回执成功。
		if receipt.stage != "deleted_absence_confirmed" or receipt.removed_bytes != candidate.bytes or FileAccess.file_exists(candidate.path) or DirAccess.dir_exists_absolute(candidate.path):
			result.refused.append({"artifact_id":id, "reason":"delete_not_confirmed", "native_receipt":receipt.duplicate(true)})
			result.recovery_required = true
			return result
		result.removed.append({"artifact_id":id, "path":candidate.path, "bytes":candidate.bytes, "instance_id":candidate.instance_id})
		result.removed_files += 1
		result.removed_bytes += candidate.bytes
	return result