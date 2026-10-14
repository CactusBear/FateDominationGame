extends RefCounted

## 仅接受本机可信 producer/consumer；磁盘不是认证来源，部署须独占这些文件。
const Paths = preload("res://scripts/net/server/recovery_path_safety.gd")
const Atomic = preload("res://scripts/io/atomic_file_replace.gd")
const Content = preload("res://scripts/io/validated_file_content.gd")
const Policy = preload("res://scripts/net/server/temporary_cleanup_policy.gd")
const ProofCollector = preload("res://scripts/net/server/temporary_cleanup_proof_collector.gd")
var path:String = ""
## 同一进程多个台账对象也共享锁；跨进程独占仍由 lifecycle proof 的提供者保证。
static var _mutex := Mutex.new()

func configure(target:String) -> bool:
	_mutex.lock()
	path = target
	var ok:bool = Paths.checked(path.get_base_dir(), path, true)
	if ok and not FileAccess.file_exists(path): ok = _persist({"version":1,"entries":{},"runs":[]})
	if ok: ok = _read().get("ok", false)
	_mutex.unlock()
	return ok

static func binding_valid(binding:Dictionary) -> bool:
	for key in ["room","instance_id","authority_host_mode"]:
		if not binding.get(key) is String or binding[key].is_empty(): return false
	return binding.get("pid") is int and binding.pid > 0

func register_close(request_id:String, binding:Dictionary, root:String) -> Dictionary:
	_mutex.lock()
	var result:Dictionary = _register(request_id, binding, root)
	_mutex.unlock()
	return result

func _register(id:String, binding:Dictionary, root:String) -> Dictionary:
	if not preload("res://scripts/net/server/server_console_channel.gd").valid_id(id) or not binding_valid(binding): return _error("invalid_binding")
	var loaded:Dictionary = _read()
	if not loaded.ok: return loaded
	if loaded.data.entries.has(id): return _error("already_registered")
	var request_path:String = root.path_join(id + ".request.json")
	if not Paths.checked(root, request_path): return _error("unsafe_request")
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(request_path)) != OK or not parser.data is Dictionary: return _error("invalid_request")
	if not _matches(parser.data, binding) or parser.data.get("action") not in ["close", "close_empty"]: return _error("not_registered_close")
	loaded.data.entries[id] = {"source":"server_console_channel.close","binding":binding.duplicate(true),"root":root,"request_sha256":FileAccess.get_sha256(request_path),"state":"registered","records":[]}
	return {"ok":true} if _persist(loaded.data) else _error("ledger_write_failed")

## 调用方必须已通过现有回执读取，并以同绑定 closed history 证明 EXITED+release。
func consume_close(id:String, response:Dictionary, released:Dictionary, consumed_at:int) -> Dictionary:
	_mutex.lock()
	var result:Dictionary = _consume(id, response, released, consumed_at)
	_mutex.unlock()
	return result

func _consume(id:String, response:Dictionary, released:Dictionary, consumed_at:int) -> Dictionary:
	if consumed_at < 0: return _error("invalid_clock")
	var loaded:Dictionary = _read()
	if not loaded.ok: return loaded
	if not loaded.data.entries.has(id): return _error("unknown_producer")
	var entry:Dictionary = loaded.data.entries[id]
	if released != entry.binding.merged({"request_id":id}) or not _matches(response, entry.binding) or response.get("request_id") != id: return _error("release_binding_mismatch")
	if not preload("res://scripts/net/server/server_console_channel.gd").saved_close_receipt(response): return _error("save_unconfirmed")
	var response_path:String = entry.root.path_join(id + ".response.json")
	if not Paths.checked(entry.root, response_path): return _error("unsafe_response")
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(response_path)) != OK or not parser.data is Dictionary: return _error("response_changed")
	var delivered:Dictionary = response.duplicate(true)
	if not _integers(parser.data) or not _integers(delivered) or parser.data != delivered: return _error("response_changed")
	var digest:String = FileAccess.get_sha256(response_path)
	if entry.state == "consumed":
		return {"ok":true,"duplicate":true,"consumed_at":entry.consumed_at} if entry.response_sha256 == digest else _error("consumed_response_changed")
	if entry.state != "registered": return _error("unresolved_cleanup_intent")
	var records:Array = []
	for kind in ["request", "response"]:
		var artifact_path:String = entry.root.path_join(id + "." + kind + ".json")
		if not FileAccess.file_exists(artifact_path): continue
		if not Paths.checked(entry.root, artifact_path): return _error("unsafe_artifact")
		if kind == "request" and FileAccess.get_sha256(artifact_path) != entry.request_sha256: return _error("request_changed")
		var file := FileAccess.open(artifact_path, FileAccess.READ)
		if file == null: return _error("artifact_unreadable")
		var length:int = file.get_length()
		file.close()
		records.append({"artifact_id":id+":"+kind,"source":entry.source+":"+kind,"instance_id":entry.binding.instance_id,"path":artifact_path,"sha256":FileAccess.get_sha256(artifact_path),"bytes":length,"artifact_kind":"temporary_file","save_status":"confirmed","consumed":true,"recyclable":true,"instance_exited":true,"consumed_at":consumed_at,"consumption_receipt_id":id,"exit_receipt_id":id,"save_exit_binding":released.duplicate(true)})
	entry.state = "consumed"
	entry.consumed_at = consumed_at
	entry.response_sha256 = digest
	entry.save_exit_binding = released.duplicate(true)
	entry.records = records
	return {"ok":true,"duplicate":false,"consumed_at":consumed_at} if _persist(loaded.data) else _error("ledger_write_failed")

## snapshot 在锁内调用，必须由可信生命周期拥有者提供完整集合和文件互斥证明。
## 只读候选诊断：observed_instances 不是完整性证明，不得把此结果送入执行器。
func preview(config:Dictionary, now:int, observed_instances:Array) -> Dictionary:
	_mutex.lock()
	var result:Dictionary = _preview(config,now,observed_instances)
	_mutex.unlock()
	return result

func _preview(config:Dictionary, now:int, observed_instances:Array) -> Dictionary:
	var explicit:Dictionary = config.duplicate(true)
	explicit.current_instances = observed_instances.duplicate()
	var reason:String = Policy.configuration_error(explicit,now)
	if not reason.is_empty(): return _error(reason)
	var loaded:Dictionary = _read()
	if not loaded.ok: return loaded
	var records:Array = []
	for entry in loaded.data.entries.values():
		if entry.state == "cleanup_intent": return _error("unresolved_cleanup_intent")
		if entry.state == "consumed": records.append_array(entry.records)
	var plan:Dictionary = Policy.select(records,explicit,now)
	plan.ok = true
	plan.diagnostic_only = true
	return plan

## 显式对象能力的只读候选入口。生产未提供能力时失败关闭，不将诊断升级为执行。
func preview_proven(config:Dictionary, now:int, capability:Object, lease:Object, deployment_id:String) -> Dictionary:
	_mutex.lock()
	var result:Dictionary = _preview_proven(config,now,capability,lease,deployment_id)
	_mutex.unlock()
	return result

func _preview_proven(config:Dictionary, now:int, capability:Object, lease:Object, deployment_id:String) -> Dictionary:
	var explicit:Dictionary = config.duplicate(true)
	explicit.current_instances = []
	var reason:String = Policy.configuration_error(explicit,now)
	if not reason.is_empty(): return _error(reason)
	var scope:Dictionary = {"deployment_id":deployment_id,"approved_roots":explicit.approved_roots.duplicate(),"protected_paths":explicit.protected_paths.duplicate()}
	var proof:Dictionary = ProofCollector.collect(capability,lease,scope)
	if not proof.ok: return proof
	if path.is_empty() or not Paths.checked(path.get_base_dir(),path): return _error("ledger_unavailable")
	var digest:String = FileAccess.get_sha256(path)
	var loaded:Dictionary = _read()
	if not loaded.ok: return loaded
	var records:Array = []
	for entry in loaded.data.entries.values():
		if entry.state == "cleanup_intent": return _error("unresolved_cleanup_intent")
		if entry.state == "consumed": records.append_array(entry.records)
	explicit.current_instances = proof.current_instances.duplicate()
	var plan:Dictionary = Policy.select(records,explicit,now)
	var rechecked:Dictionary = ProofCollector.revalidate(proof,capability,lease,scope)
	if not rechecked.ok: return rechecked
	if FileAccess.get_sha256(path) != digest: return _error("ledger_changed_during_preview")
	plan.ok = true
	plan.diagnostic_only = true
	plan.blocked = true
	plan.removed_files = 0
	plan.lifecycle_proof = rechecked
	plan.execution_blocker = "cleanup_execution_lease_unwired"
	return plan

## 保留旧 Callable 入口，但撤销 v1 两个 bool 的删除许可；磁盘台账仍为 version=1。
## v2 仅供只读 proof collector，执行器尚未持有全程部署租约，明确拒绝而非降级删除。
func cleanup(config:Dictionary, now:int, snapshot:Callable) -> Dictionary:
	_mutex.lock()
	var result:Dictionary = _cleanup(config, now, snapshot)
	_mutex.unlock()
	return result

func _cleanup(_config:Dictionary, _now:int, snapshot:Callable) -> Dictionary:
	if not snapshot.is_valid(): return _error("missing_lifecycle_proof")
	var proof:Variant = snapshot.call()
	if not proof is Dictionary: return _error("invalid_lifecycle_proof")
	if not proof.has("proof_version"): return _error("lifecycle_proof_upgrade_required")
	if not proof.proof_version is int or proof.proof_version != 2: return _error("unsupported_lifecycle_proof_version")
	return _error("cleanup_execution_lease_unwired")

func _read() -> Dictionary:
	if path.is_empty() or not Paths.checked(path.get_base_dir(), path): return _error("ledger_unavailable")
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary: return _error("ledger_corrupt")
	var data:Dictionary = parser.data
	if data.get("version") != 1 or not data.get("entries") is Dictionary or not data.get("runs") is Array: return _error("ledger_schema")
	# JSON 数值只允许精确非负整数字段，绝不把分数截断为许可。
	if not _integers(data): return _error("ledger_numeric_field")
	for id in data.entries:
		var entry:Variant = data.entries[id]
		if not entry is Dictionary or not entry.get("binding") is Dictionary or not binding_valid(entry.binding) or not entry.get("records") is Array or entry.get("state") not in ["registered","consumed","cleanup_intent"] or entry.get("source") != "server_console_channel.close" or not entry.get("root") is String: return _error("ledger_entry_schema")
		if not preload("res://scripts/net/server/server_console_channel.gd").valid_id(str(id)) or not entry.get("request_sha256") is String or entry.request_sha256.length() != 64: return _error("ledger_producer_schema")
		if entry.state == "registered":
			if not entry.records.is_empty(): return _error("unconsumed_records")
			continue
		if not entry.get("consumed_at") is int or not entry.get("response_sha256") is String or entry.response_sha256.length() != 64 or entry.get("save_exit_binding") != entry.binding.merged({"request_id":id}): return _error("ledger_consumption_schema")
		var seen:Dictionary = {}
		for record in entry.records:
			if not record is Dictionary: return _error("ledger_record_schema")
			var kind:String = str(record.get("artifact_id", "")).trim_prefix(str(id)+":")
			if kind not in ["request","response"] or record.get("artifact_id") != str(id)+":"+kind or seen.has(kind): return _error("ledger_artifact_identity")
			seen[kind] = true
			if record.get("path") != entry.root.path_join(str(id)+"."+kind+".json") or record.get("source") != entry.source+":"+kind or record.get("instance_id") != entry.binding.instance_id or record.get("artifact_kind") != "temporary_file": return _error("ledger_artifact_scope")
			if record.get("consumption_receipt_id") != id or record.get("exit_receipt_id") != id or record.get("consumed_at") != entry.consumed_at or record.get("save_exit_binding") != entry.save_exit_binding or record.get("save_status") != "confirmed": return _error("ledger_artifact_proof")
			for flag in ["consumed","recyclable","instance_exited"]:
				if not record.get(flag) is bool or record[flag] != true: return _error("ledger_artifact_flag")
			if not record.get("bytes") is int or record.get("sha256") != (entry.request_sha256 if kind == "request" else entry.response_sha256): return _error("ledger_artifact_digest")
	return {"ok":true,"data":data}

static func _integers(value:Variant) -> bool:
	if value is Dictionary:
		for key in value:
			if key in ["version","pid","consumed_at","bytes","at","removed_files","removed_bytes"]:
				var number:Variant = value[key]
				if not (number is int or number is float): return false
				if number < 0 or number > 9007199254740991 or not is_finite(float(number)) or float(number) != floor(float(number)): return false
				value[key] = int(number)
			elif not _integers(value[key]): return false
	elif value is Array:
		for item in value:
			if not _integers(item): return false
	return true

func _persist(data:Dictionary) -> bool:
	if not Paths.checked(path.get_base_dir(), path, true): return false
	var temporary:String = path + "." + Crypto.new().generate_random_bytes(16).hex_encode() + ".tmp"
	var encoded:PackedByteArray = JSON.stringify(data).to_utf8_buffer()
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return false
	file.store_buffer(encoded)
	file.flush()
	var error:Error = file.get_error()
	file.close()
	if error != OK or not Paths.checked(path.get_base_dir(), temporary) or not Content.matches_bytes(temporary, encoded): return false
	var committed:bool = false
	if FileAccess.file_exists(path): committed = Atomic.replace_validated_file(temporary, path, encoded.size()).get("ok", false) == true
	elif not DirAccess.dir_exists_absolute(path): committed = DirAccess.rename_absolute(temporary, path) == OK
	return committed and Content.matches_bytes(path, encoded)

static func _matches(value:Dictionary, binding:Dictionary) -> bool:
	return value.get("room") == binding.room and value.get("pid") == binding.pid and value.get("instance") == binding.instance_id and value.get("authority_host_mode") == binding.authority_host_mode

static func _error(reason:String) -> Dictionary:
	return {"ok":false,"error":reason}
