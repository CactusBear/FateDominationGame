class_name MatchJournal
extends RefCounted

## 仅保存基础 Variant 的带长度帧日志。哈希用于检测损坏，不是身份认证。
const MAGIC := "FATEJNL1"
const MAX_FRAME_BYTES := 16 * 1024 * 1024
var error: String = ""
var _file: FileAccess
var _sequence: int = 0
var _previous: PackedByteArray = PackedByteArray()
const FRAME_VERSION:int = 2
# 审计在规则图之外，不被撤销；不透明根身份不携带牌面或凭据。
const AUDIT_VERSION:int = 3
const AUDIT_MAX_TOTAL_BYTES:int = 64 * 1024 * 1024
const AUDIT_MAX_RECORDS:int = 100000
const AUDIT_EVENTS:Array = ["start", "child", "pause", "resume", "rollback_intent", "rollback", "commit", "tail_registered", "tail_consumed", "aborted"]
const AUDIT_REASONS:Array = ["", "host_skip", "player_choice", "step_budget", "time_budget", "checkpoint_unavailable", "redacted"]
var max_total_bytes:int = 0
var max_records:int = 0
var _audit_lease:String = ""
var _append_mutex:Mutex = Mutex.new()
var _append_receipts:Dictionary = {}
var _written_length:int = 0
var _audit_inner_previous:String = ""
static var _audit_mutex:Mutex = Mutex.new()
# Mutex 是递归锁；锁内维护不能借递归调用重置/替换续写拥有者。
static var _audit_resume_active:bool = false
static var _audit_namespace:String = ""
static var _root_names:Dictionary = {}
static var _audit_receipts:Dictionary = {}
static var _audit_phases:Dictionary = {}
static var audit_writer = null
static var audit_error:String = ""
static var audit_replaying:bool = false
static var audit_records:Array = []
static var audit_revision:int = 0
static var _audit_identity:int = 0
static var _audit_previous:String = ""
static var _audit_total_bytes:int = 0
static var _tail_consumptions:Dictionary = {}

static func next_audit_identity() -> int:
	_audit_mutex.lock()
	if _audit_identity == 9223372036854775807:
		audit_error = "事务局部身份空间已满"
		_audit_mutex.unlock()
		return 0
	_audit_identity += 1
	var identity:int = _audit_identity
	_audit_mutex.unlock()
	return identity

static func reset_audit_memory() -> bool:
	_audit_mutex.lock()
	if _audit_resume_active:
		audit_error = "审计续写维护期间拒绝生命周期重入"
		_audit_mutex.unlock()
		return false
	var accepted:bool = _reset_audit_memory()
	_audit_mutex.unlock()
	return accepted

static func _reset_audit_memory() -> bool:
	if audit_writer != null: return false
	audit_error = ""
	audit_records.clear()
	audit_revision = 0
	_audit_identity = 0
	_audit_previous = ""
	_audit_total_bytes = 0
	_tail_consumptions.clear()
	_root_names.clear()
	_audit_receipts.clear()
	_audit_phases.clear()
	_audit_namespace = Crypto.new().generate_random_bytes(32).hex_encode()
	return _audit_namespace.length() == 64

static func audit_chain(records:Array, maintenance:Callable = Callable()) -> Dictionary:
	var result:Dictionary = {"ok":false, "revision":0, "hash":""}
	if records.is_empty() or not records[0] is Dictionary or records[0].get("kind") != "transaction_audit" or records[0].get("format") != AUDIT_VERSION or not _audit_hex(records[0].get("namespace", "")):
		return result
	if records.size() > AUDIT_MAX_RECORDS + 1: return result
	var receipts:Dictionary = {}
	var roots:Dictionary = {}
	for index in range(1, records.size()):
		if maintenance.is_valid() and maintenance.call() == false: return result
		if not records[index] is Dictionary: return result
		var record:Dictionary = records[index].duplicate()
		var hash_value = record.get("hash")
		record.erase("hash")
		if not _valid_audit_record(record) or not _audit_hex(hash_value) or record.get("sequence") != result.revision or record.get("revision_before") != result.revision or record.get("revision_after") != result.revision + 1 or record.get("previous_hash") != result.hash or _digest(var_to_bytes(record)).hex_encode() != hash_value:
			return result
		if receipts.has(record.idempotency_key): return result
		receipts[record.idempotency_key] = true
		var root_id:int = int(record.get("root_id", 0))
		if root_id > 0:
			if roots.has(root_id) and roots[root_id] != record.transaction_id: return result
			roots[root_id] = record.transaction_id
		result.hash = hash_value
		result.revision += 1
	result.ok = true
	return result

static func _audit_payload_digest(record:Dictionary) -> String:
	var safe:Dictionary = {}
	var keys:Array = record.keys()
	keys.sort()
	for key in keys:
		if key in ["root_id", "effect_id", "parent_id", "player_id", "card_id", "ticket_id", "consumption", "reason", "checkpoint_ready"]: safe[key] = record[key]
	return _digest(var_to_bytes(safe)).hex_encode()

static func _audit_hex(value) -> bool:
	if not value is String or value.length() != 64: return false
	for character in value:
		if character not in "0123456789abcdef": return false
	return true

static func _valid_audit_record(record:Dictionary) -> bool:
	for key in record:
		if key not in ["format", "kind", "event", "sequence", "revision_before", "revision_after", "previous_hash", "transaction_id", "idempotency_key", "phase", "root_id", "effect_id", "parent_id", "player_id", "card_id", "ticket_id", "consumption", "reason", "checkpoint_ready"]: return false
	if record.get("format") != AUDIT_VERSION or record.get("kind") != "transaction" or record.get("event") not in AUDIT_EVENTS: return false
	for key in ["sequence", "revision_before", "revision_after", "phase"]:
		if not record.get(key) is int or record[key] < 0: return false
	for key in ["root_id", "effect_id", "parent_id", "player_id", "card_id", "ticket_id", "consumption"]:
		if record.has(key) and (not record[key] is int or (key in ["root_id", "effect_id", "parent_id", "ticket_id", "consumption"] and record[key] < 0)): return false
	if record.has("reason") and record.reason not in AUDIT_REASONS: return false
	if record.has("checkpoint_ready") and not record.checkpoint_ready is bool: return false
	if not record.get("transaction_id") is String or not record.get("idempotency_key") is String: return false
	var identity:PackedStringArray = record.transaction_id.split(":")
	if identity.size() != 2 or not _audit_hex(identity[0]) or identity[1] != str(record.get("root_id", 0)): return false
	var key:String = record.transaction_id + ":" + record.event
	if record.event in ["pause", "resume"]: key += ":" + str(record.phase)
	if record.event == "child": key += ":" + str(record.get("effect_id", 0))
	if record.event in ["tail_registered", "tail_consumed"]: key += ":" + str(record.get("ticket_id", 0))
	return record.idempotency_key == key

static func resume_audit(path:String, expected_revision:int = -1, maintenance:Callable = Callable()):
	_audit_mutex.lock()
	if _audit_resume_active:
		audit_error = "审计续写维护期间拒绝生命周期重入"
		_audit_mutex.unlock()
		return null
	_audit_resume_active = true
	var writer = _resume_audit(path, expected_revision, maintenance)
	_audit_resume_active = false
	_audit_mutex.unlock()
	return writer

static func _resume_audit(path:String, expected_revision:int = -1, maintenance:Callable = Callable()):
	if audit_writer != null: return null
	var writer = MatchJournal.new()
	if not writer._claim_audit_lease(path):
		audit_error = writer.error
		writer.close()
		return null
	var parsed:Dictionary = writer.read_all(path, maintenance)
	if not parsed.ok or parsed.truncated or parsed.records[0].get("kind") != "transaction_audit":
		writer.close()
		audit_error = "事务审计文件损坏或缺失"
		return null
	var chain:Dictionary = audit_chain(parsed.records, maintenance)
	if not chain.ok:
		writer.close()
		audit_error = "事务审计链校验失败"
		return null
	var previous:String = chain.hash
	var revision:int = chain.revision
	if expected_revision >= 0 and revision != expected_revision:
		writer.close()
		audit_error = "事务审计超出最后已记录规则边界，拒绝续写"
		return null
	if not _reset_audit_memory():
		writer.close()
		return null
	for record in parsed.records:
		if maintenance.is_valid() and maintenance.call() == false:
			audit_error = "事务审计续写已取消"
			writer.close()
			return null
		for key in ["root_id", "effect_id", "parent_id", "ticket_id"]:
			_audit_identity = maxi(_audit_identity, int(record.get(key, 0)))
		if record.has("transaction_id") and int(record.get("root_id", 0)) > 0:
			_root_names[record.root_id] = record.transaction_id
		if record.has("idempotency_key"):
			_audit_receipts[record.idempotency_key] = _audit_payload_digest(record)
			_audit_phases[int(record.get("root_id", 0))] = int(record.get("phase", 0))
			_audit_phases["last:" + str(record.get("root_id", 0))] = record.event + ":" + _audit_payload_digest(record)
		if record.get("event") == "tail_consumed":
			_tail_consumptions[record.ticket_id] = record.consumption
	if not writer.resume(path, true, maintenance):
		audit_error = writer.error
		writer.close()
		return null
	audit_writer = writer
	audit_revision = revision
	_audit_previous = previous
	_audit_total_bytes = writer._file.get_length()
	audit_error = ""
	return writer

static func begin_audit(path:String):
	_audit_mutex.lock()
	if _audit_resume_active:
		audit_error = "审计续写维护期间拒绝生命周期重入"
		_audit_mutex.unlock()
		return null
	var writer = _begin_audit(path)
	_audit_mutex.unlock()
	return writer

static func _begin_audit(path:String):
	if audit_writer != null:
		return null
	if not _reset_audit_memory(): return null
	var writer = MatchJournal.new()
	if not writer._claim_audit_lease(path):
		audit_error = writer.error
		writer.close()
		return null
	if not writer.create(path, {"format":AUDIT_VERSION, "kind":"transaction_audit", "namespace":_audit_namespace}, true):
		audit_error = writer.error
		writer.close()
		return null
	audit_writer = writer
	_audit_total_bytes = writer._file.get_length()
	audit_error = ""
	return writer

static func end_audit(writer) -> void:
	_audit_mutex.lock()
	if writer != null and audit_writer == writer:
		writer.close()
		audit_writer = null
	_audit_mutex.unlock()

static func audit_event(event:String, metadata:Dictionary = {}) -> bool:
	_audit_mutex.lock()
	var accepted:bool = _append_audit_event(event, metadata)
	_audit_mutex.unlock()
	return accepted

static func _append_audit_event(event:String, metadata:Dictionary) -> bool:
	if not audit_error.is_empty(): return false
	if event not in AUDIT_EVENTS:
		audit_error = "未知事务审计事件"
		return false
	var safe:Dictionary = {}
	var metadata_keys:Array = metadata.keys()
	for metadata_key in metadata_keys:
		if not metadata_key is String:
			audit_error = "事务审计字段名无效"
			return false
	metadata_keys.sort()
	for key in metadata_keys:
		if key not in ["root_id", "effect_id", "parent_id", "player_id", "card_id", "ticket_id", "consumption", "reason", "checkpoint_ready"]:
			audit_error = "事务审计字段无效"
			return false
		if key.ends_with("_id") or key == "consumption":
			var integer_value = metadata[key]
			if integer_value is float:
				var integer_limit:float = float(9007199254740991)
				if not is_finite(integer_value) or floor(integer_value) != integer_value or abs(integer_value) > integer_limit:
					audit_error = "事务审计身份及次数必须为有效整数"
					return false
				integer_value = int(integer_value)
			if not integer_value is int or (key in ["root_id", "effect_id", "parent_id", "ticket_id", "consumption"] and integer_value < 0):
				audit_error = "事务审计身份及次数必须为有效整数"
				return false
			safe[key] = integer_value
			continue
		if key == "reason" and not metadata[key] is String:
			audit_error = "事务审计原因类型无效"
			return false
		if key == "checkpoint_ready" and not metadata[key] is bool:
			audit_error = "事务审计检查点资格必须为布尔值"
			return false
		safe[key] = metadata[key]
	if safe.has("reason") and safe.reason not in AUDIT_REASONS: safe.reason = "redacted"
	if _audit_namespace.is_empty():
		_audit_namespace = Crypto.new().generate_random_bytes(32).hex_encode()
	if _audit_namespace.length() != 64:
		audit_error = "无法分配事务命名空间"
		return false
	var root_id:int = int(safe.get("root_id", 0))
	if root_id > 0 and not _root_names.has(root_id):
		_root_names[root_id] = _audit_namespace + ":" + str(root_id)
	var transaction_id:String = str(_root_names.get(root_id, _audit_namespace + ":0"))
	var payload_digest:String = _digest(var_to_bytes(safe)).hex_encode()
	var signature:String = event + ":" + payload_digest
	var phase:int = int(_audit_phases.get(root_id, 0))
	# 生命周期暂停/续行只在实际状态交替时生成新阶段；重试保持相同键。
	if event in ["pause", "resume"]:
		var last_event:String = str(_audit_phases.get("last:" + str(root_id), ""))
		if last_event != signature: phase += 1
	var key:String = transaction_id + ":" + event
	if event in ["pause", "resume"]: key += ":" + str(phase)
	if event == "child": key += ":" + str(safe.get("effect_id", 0))
	if event in ["tail_registered", "tail_consumed"]: key += ":" + str(safe.get("ticket_id", 0))
	if _audit_receipts.has(key):
		if _audit_receipts[key] == payload_digest: return true
		audit_error = "事务审计重复键载荷冲突"
		return false
	if _audit_receipts.size() >= AUDIT_MAX_RECORDS:
		audit_error = "事务审计记录容量已满，拒绝追加"
		return false
	var record:Dictionary = {"format":AUDIT_VERSION, "kind":"transaction", "event":event,
		"sequence":audit_revision, "revision_before":audit_revision,
		"revision_after":audit_revision + 1, "previous_hash":_audit_previous,
		"transaction_id":transaction_id, "idempotency_key":key, "phase":phase}
	for name in safe: record[name] = safe[name]
	var hash_value:String = _digest(var_to_bytes(record)).hex_encode()
	record["hash"] = hash_value
	var record_bytes:int = var_to_bytes({"version":FRAME_VERSION, "sequence":audit_revision + 1, "record":record}).size() + 36
	if _audit_total_bytes + record_bytes > AUDIT_MAX_TOTAL_BYTES:
		audit_error = "事务审计总字节容量已满，拒绝追加"
		return false
	if audit_writer != null and not audit_replaying and not audit_writer.append(record):
		audit_error = audit_writer.error
		return false
	_audit_total_bytes += record_bytes
	_audit_receipts[key] = payload_digest
	_audit_phases[root_id] = phase
	_audit_phases["last:" + str(root_id)] = signature
	_audit_previous = hash_value
	audit_revision += 1
	audit_records.append(record)
	if audit_records.size() > 4096: audit_records.pop_front()
	return true

static func consume_tail(ticket_id:int, root_id:int) -> bool:
	_audit_mutex.lock()
	var accepted:bool = false
	# 重试 append 是幂等成功；消费能力则必须拒绝二次执行。
	if not _tail_consumptions.has(ticket_id):
		accepted = _append_audit_event("tail_consumed", {"ticket_id":ticket_id, "root_id":root_id, "consumption":1})
		if accepted: _tail_consumptions[ticket_id] = 1
	_audit_mutex.unlock()
	return accepted

static func flush_audit() -> bool:
	_audit_mutex.lock()
	var accepted:bool = _flush_audit()
	_audit_mutex.unlock()
	return accepted

static func _flush_audit() -> bool:
	if not audit_error.is_empty(): return false
	if audit_writer == null: return true
	if not audit_writer.flush():
		audit_error = audit_writer.error
		return false
	return true

func create(path: String, header: Dictionary, keep_lease:bool = false) -> bool:
	var accepted:bool = _create_file(path, header, keep_lease)
	if not accepted: close()
	return accepted

func _create_file(path:String, header:Dictionary, keep_lease:bool) -> bool:
	if not keep_lease: close()
	if header.get("kind") == "transaction_audit" and _audit_lease.is_empty() and not _claim_audit_lease(path): return false
	error = ""
	if FileAccess.file_exists(path):
		error = "存档已存在，不覆盖"
		return false
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
		error = "无法创建存档目录"
		return false
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		error = "无法创建存档"
		return false
	_file.store_buffer(MAGIC.to_ascii_buffer())
	_sequence = 0
	_previous = PackedByteArray()
	_written_length = _file.get_position()
	_append_receipts.clear()
	_audit_inner_previous = ""
	return append(header)

func append(record: Dictionary) -> bool:
	if self != audit_writer and (not audit_error.is_empty() or (audit_writer != null and not flush_audit())):
		error = audit_error
		return false
	_append_mutex.lock()
	var accepted:bool = _append_record(record)
	_append_mutex.unlock()
	return accepted

func _append_record(record:Dictionary) -> bool:
	if not error.is_empty(): return false
	if _file == null:
		error = "存档未打开或已关闭"
		return false
	if not _plain(record):
		error = "存档不接受可执行对象或调用句柄"
		return false
	var receipt_key:String = ""
	var receipt_digest:String = ""
	if max_total_bytes > 0 and _sequence > 0:
		var unsigned:Dictionary = record.duplicate()
		var record_hash = unsigned.get("hash")
		unsigned.erase("hash")
		if not _valid_audit_record(unsigned) or _digest(var_to_bytes(unsigned)).hex_encode() != record_hash:
			error = "事务审计内容或内链无效"
			return false
		receipt_key = record.idempotency_key
		receipt_digest = _digest(var_to_bytes(record)).hex_encode()
		if _append_receipts.has(receipt_key):
			if _append_receipts[receipt_key] == receipt_digest: return true
			error = "事务审计重复 append 载荷冲突"
			return false
		if record.sequence != _sequence - 1 or record.previous_hash != _audit_inner_previous:
			error = "事务审计内部序号无效"
			return false
	if _file.get_length() != _written_length or _file.get_position() != _written_length:
		error = "日志在写入租约之外被修改"
		return false
	var body := var_to_bytes({"version":FRAME_VERSION, "sequence": _sequence, "record": record})
	if body.size() > MAX_FRAME_BYTES:
		error = "存档记录超出大小上限"
		return false
	if (max_total_bytes > 0 and _file.get_length() + 36 + body.size() > max_total_bytes) or (max_records > 0 and _sequence >= max_records):
		error = "事务审计容量已满，拒绝追加"
		return false
	var digest := _digest(_previous + body)
	_file.store_32(body.size())
	_file.store_buffer(digest)
	_file.store_buffer(body)
	_file.flush()
	if _file.get_error() != OK:
		error = "存档写入失败"
		return false
	_previous = digest
	_written_length = _file.get_position()
	if not receipt_key.is_empty():
		_append_receipts[receipt_key] = receipt_digest
		_audit_inner_previous = record.hash
	_sequence += 1
	return true

func flush() -> bool:
	_append_mutex.lock()
	var accepted:bool = _flush_file()
	_append_mutex.unlock()
	if not accepted: return false
	return flush_audit() if self != audit_writer else true

func _flush_file() -> bool:
	if not error.is_empty(): return false
	if _file == null:
		error = "存档未打开或已关闭"
		return false
	_file.flush()
	if _file.get_error() != OK:
		error = "存档刷新失败"
		return false
	return true

func close() -> void:
	_append_mutex.lock()
	if _file != null:
		_file.close()
	_file = null
	if not _audit_lease.is_empty():
		DirAccess.remove_absolute(_audit_lease)
		_audit_lease = ""
	_append_mutex.unlock()

func _claim_audit_lease(path:String) -> bool:
	var absolute:String = ProjectSettings.globalize_path(path).simplify_path()
	if DirAccess.make_dir_recursive_absolute(absolute.get_base_dir()) != OK:
		error = "无法创建审计目录"
		return false
	var lease:String = absolute + ".writer-lock"
	# mkdir 为跨进程独占操作；崩溃残留必须由管理员确认后清理。
	if DirAccess.make_dir_absolute(lease) != OK:
		error = "事务审计写入租约被占用，拒绝并发写入"
		return false
	_audit_lease = lease
	max_total_bytes = AUDIT_MAX_TOTAL_BYTES
	max_records = AUDIT_MAX_RECORDS + 1
	return true

func resume(path: String, keep_lease:bool = false, maintenance:Callable = Callable()) -> bool:
	var accepted:bool = _resume_file(path, keep_lease, maintenance)
	if not accepted: close()
	return accepted

func _resume_file(path:String, keep_lease:bool, maintenance:Callable) -> bool:
	if not keep_lease: close()
	error = ""
	var parsed := read_all(path, maintenance)
	if not parsed.ok or parsed.truncated:
		error = "不能续写损坏或截断的存档"
		return false
	if parsed.records[0].get("kind") == "transaction_audit":
		if not audit_chain(parsed.records, maintenance).ok:
			error = "事务审计链校验失败"
			return false
		if _audit_lease.is_empty() and not _claim_audit_lease(path): return false
	# 旧帧与新帧编码不同，续写必须沿用读回的真实链头。
	_previous = parsed.chain_head
	_sequence = parsed.records.size()
	_file = FileAccess.open(path, FileAccess.READ_WRITE)
	if _file == null:
		error = "无法打开存档续写"
		return false
	_file.seek_end()
	_written_length = _file.get_length()
	_append_receipts.clear()
	if max_total_bytes > 0:
		var receipt_chain:Dictionary = audit_chain(parsed.records, maintenance)
		if not receipt_chain.ok:
			error = "事务审计回执链校验失败或续写已取消"
			return false
		_audit_inner_previous = receipt_chain.hash
		for record in parsed.records:
			if maintenance.is_valid() and maintenance.call() == false:
				error = "存档续写已取消"
				return false
			if record.has("idempotency_key"):
				_append_receipts[record.idempotency_key] = _digest(var_to_bytes(record)).hex_encode()
	return true

func read_all(path: String, maintenance:Callable = Callable()) -> Dictionary:
	var result := {"ok": false, "records": [], "truncated": false, "error": "", "error_index": -1, "chain_head":PackedByteArray()}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		result.error = "无法读取存档"
		return result
	if file.get_buffer(MAGIC.length()).get_string_from_ascii() != MAGIC:
		result.error = "存档格式不兼容"
		return result
	if max_total_bytes > 0 and file.get_length() > max_total_bytes:
		result.error = "事务审计总字节超限"
		return result
	var read_max_records:int = max_records
	var previous := PackedByteArray()
	while file.get_position() < file.get_length():
		if maintenance.is_valid() and maintenance.call() == false:
			result.error = "维护回调取消日志校验"
			return result
		var index: int = result.records.size()
		if read_max_records > 0 and index >= read_max_records:
			result.error = "事务审计记录数量超限"
			return result
		if file.get_length() - file.get_position() < 36:
			result.truncated = true
			break
		var length := file.get_32()
		if length <= 0 or length > MAX_FRAME_BYTES:
			result.error = "记录长度无效"
			result.error_index = index
			return result
		var digest := file.get_buffer(32)
		if file.get_length() - file.get_position() < length:
			result.truncated = true
			break
		var body := PackedByteArray()
		var context := HashingContext.new()
		context.start(HashingContext.HASH_SHA256)
		if not previous.is_empty(): context.update(previous)
		while body.size() < length:
			var amount:int = mini(256 * 1024, length - body.size())
			var chunk := file.get_buffer(amount)
			if chunk.size() != amount or file.get_error() != OK:
				result.error = "日志分块读取失败"
				result.error_index = index
				return result
			body.append_array(chunk)
			context.update(chunk)
			if maintenance.is_valid() and maintenance.call() == false:
				result.error = "维护回调取消日志校验"
				return result
		if context.finish() != digest:
			result.error = "记录校验失败"
			result.error_index = index
			return result
		var frame = bytes_to_var(body)
		if not frame is Dictionary or not frame.get("version", 1) is int or frame.get("version", 1) not in [1, FRAME_VERSION] or not frame.get("sequence") is int or frame.get("sequence") != index or not frame.get("record") is Dictionary or not _plain(frame):
			result.error = "记录序号或内容无效"
			result.error_index = index
			return result
		if index == 0 and frame.record.get("kind") == "transaction_audit":
			if file.get_length() > AUDIT_MAX_TOTAL_BYTES:
				result.error = "事务审计总字节超限"
				return result
			read_max_records = AUDIT_MAX_RECORDS + 1
		result.records.append(frame.record)
		previous = digest
	result.chain_head = previous
	result.ok = not result.records.is_empty()
	if not result.ok:
		result.error = "存档缺少完整文件头"
	return result

static func _digest(bytes: PackedByteArray) -> PackedByteArray:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish()

static func _plain(value, depth: int = 0) -> bool:
	if depth > 128:
		return false
	if value is Array:
		for item in value:
			if not _plain(item, depth + 1):
				return false
		return true
	if value is Dictionary:
		for key in value:
			if not _plain(key, depth + 1) or not _plain(value[key], depth + 1):
				return false
		return true
	return typeof(value) in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_PACKED_BYTE_ARRAY]
