class_name MatchReplay
extends RefCounted

## 显式录制会话。恢复重跑原引擎，不反序列化 Object/Callable，不接收远端存档。
const Journal = preload("res://scripts/match/match_journal.gd")
const Ids = preload("res://scripts/match/net_ids.gd")
const Driver = preload("res://scripts/match/match_driver.gd")
const Commands = preload("res://scripts/match/match_commands.gd")
const RuleRandom = preload("res://scripts/match/rule_random.gd")
const RuleState = preload("res://scripts/match/rule_state.gd")
const COMMANDS: Array = ["submit_group", "request_manual_activation", "set_card_concealed", "deploy", "deploy_to_area", "move", "submit_option_choice", "submit_active_choice", "cancel_pending_choice", "submit_card_selection", "submit_player_selection", "submit_location_selection", "confirm_battle_broadcast", "end_current_player_action"]
var error: String = ""
var error_index: int = -1
var truncated: bool = false
var driver = Driver.new()
var commands = Commands.new()
var ids = Ids.new()
var journal = Journal.new()
var _entropy := RandomNumberGenerator.new()
var _last_hash: String = ""
var _recording: bool = false
var _source_data: String = ""
var _restored_folder: String = ""
var _restored_log_hash: String = ""
var initial:Dictionary = {}
var _recording_serial:int = 0
var _audit_journal = null
var _restored_audit_hash:String = ""
var _restored_audit_revision:int = 0
# 主线程协作维护，不启动线程、不增加规则等待点。跨实例锁覆盖原有 frames await。
static var _maintenance_busy:bool = false
const MAINTENANCE_CHUNK_BYTES:int = 256 * 1024

func _confirm_audit() -> bool:
	if Journal.flush_audit(): return true
	if error.is_empty(): error = Journal.audit_error
	EffectManager._guard_audit_failed(EffectManager.runtime_guard_effect())
	return false

func _checkpoint(maintenance:Callable) -> bool:
	if not Journal.audit_error.is_empty(): return _confirm_audit()
	if not error.is_empty(): return false
	if not maintenance.is_valid(): return true
	var random_entry:Dictionary = RuleRandom.snapshot()
	var entropy_seed:int = _entropy.seed
	var entropy_state:int = _entropy.state
	var replaying:bool = Journal.audit_replaying
	var revision:int = Journal.audit_revision
	var count:int = Journal.audit_records.size()
	var audit_error:String = Journal.audit_error
	var audit_writer = Journal.audit_writer
	var audit_namespace:String = Journal._audit_namespace
	var audit_identity:int = Journal._audit_identity
	# 回调必须同步，仅做网络/看门狗维护，不得执行规则、重置审计或 await。
	var accepted = maintenance.call()
	_entropy.seed = entropy_seed
	_entropy.state = entropy_state
	if random_entry.get("known") == true:
		RuleRandom.restore(random_entry)
	else:
		RuleRandom.stop_tracking()
	var audit_changed:bool = Journal.audit_replaying != replaying or Journal.audit_revision != revision or Journal.audit_records.size() != count or Journal.audit_error != audit_error
	audit_changed = audit_changed or Journal.audit_writer != audit_writer or Journal._audit_namespace != audit_namespace or Journal._audit_identity != audit_identity
	Journal.audit_replaying = replaying
	if audit_changed:
		error = "维护回调修改了事务审计，拒绝继续恢复"
	elif accepted is bool and not accepted:
		error = "维护回调取消了存档操作"
	return error.is_empty()

func _maintenance_callback(maintenance:Callable) -> Callable:
	return _checkpoint.bind(maintenance) if maintenance.is_valid() else Callable()

func begin(folder: String, players: Array, match_seed: int, assignments: Dictionary = {}, order: Array = [], runtime_guard:Dictionary = {}, seat_kinds:Dictionary = {}, maintenance:Callable = Callable()) -> bool:
	if _maintenance_busy or not _confirm_audit(): return false
	_maintenance_busy = true
	var serial:int = _recording_serial
	_begin_stage("begin_enter")
	var accepted:bool = _begin(folder, players, match_seed, assignments, order, runtime_guard, seat_kinds, _maintenance_callback(maintenance))
	if not _confirm_audit(): accepted = false
	if not accepted and _recording_serial != serial: _close_unchecked()
	_begin_stage("begin_ok" if accepted else "begin_failed")
	_maintenance_busy = false
	return accepted

# 与 restore 共用跨实例锁、随机流/审计检查；维护回调不得 await 或运行规则。
func _begin(folder: String, players: Array, match_seed: int, assignments: Dictionary, order: Array, runtime_guard:Dictionary, seat_kinds:Dictionary, maintenance:Callable) -> bool:
	error = ""
	if not runtime_guard.is_empty() and not preload("res://scripts/match/rule_budget.gd").new().configure(runtime_guard):
		error = "存档保护配置无效"
		return false
	if FileAccess.file_exists(folder.path_join("match.log")):
		error = "存档已存在，不覆盖"
		return false
	if not _close_confirmed(): return false
	_restored_folder = ""
	_restored_log_hash = ""
	_source_data = LoadHelper.get_data_dir()
	var archive := folder.path_join("data")
	_begin_stage("copy_enter")
	if not _copy_data(_source_data, archive, maintenance): return false
	_begin_stage("copy_exit")
	_begin_stage("engine_hash_enter")
	var engine:String = _engine_hash(maintenance)
	if not error.is_empty() or engine.is_empty():
		if error.is_empty(): error = "规则指纹为空，拒绝录制"
		return false
	_begin_stage("engine_hash_exit")
	_begin_stage("manifest_enter")
	var data:Dictionary = _manifest(archive, maintenance)
	if not _tick(maintenance): return false
	_begin_stage("manifest_exit")
	var header := {"format": 1, "engine": engine, "data": data, "players": players, "assignments": assignments, "order": order, "seed": match_seed, "local_id": GameData.player_id, "default_master": GameData.default_master, "default_servant": GameData.default_servant}
	if not error.is_empty() or str(header.engine).is_empty():
		if error.is_empty(): error = "规则指纹为空，拒绝录制"
		return false
	header["runtime_guard"] = runtime_guard.duplicate(true)
	if not seat_kinds.is_empty(): header["seat_kinds"] = seat_kinds.duplicate(true)
	_begin_stage("audit_enter")
	_audit_journal = Journal.begin_audit(folder.path_join("transactions.log"))
	if _audit_journal == null:
		error = Journal.audit_error if not Journal.audit_error.is_empty() else "另一录制器持有审计文件"
		return false
	_begin_stage("audit_exit")
	if not _tick(maintenance): return false
	_begin_stage("rules_enter")
	if not _start(header, archive):
		_close_unchecked()
		return false
	_begin_stage("rules_exit")
	if not _tick(maintenance): return false
	_begin_stage("state_hash_enter")
	header["initial_hash"] = state_hash()
	_begin_stage("state_hash_exit")
	if not error.is_empty():
		_close_unchecked()
		return false
	if not _tick(maintenance): return false
	_begin_stage("journal_enter")
	if not journal.create(folder.path_join("match.log"), header):
		error = journal.error
		_close_unchecked()
		return false
	_begin_stage("journal_exit")
	_last_hash = header.initial_hash
	_recording = true
	initial = header.duplicate(true)
	return true

func _start(header: Dictionary, archive: String) -> bool:
	LoadHelper.session_data_dir = archive
	GameStart.end_session()
	GameData.player_id = int(header.local_id)
	GameData.default_master = str(header.default_master)
	GameData.default_servant = str(header.default_servant)
	DummyBot._phase_attempt_scope = ""
	DummyBot._phase_attempted_effect_ids.clear()
	driver = Driver.new()
	if header.has("seat_kinds"):
		driver.seats.default_kind = driver.seats.VACANT
		for pid in header.seat_kinds: driver.seats.set_kind(pid, header.seat_kinds[pid])
	ids = Ids.new()
	ids.data_root = archive
	var assignments: Dictionary = {}
	for id in header.assignments:
		var declared: Dictionary = header.assignments[id]
		var master = _template(GameData.loaded_masters, str(declared.get("master", "")))
		var servant = _template(GameData.loaded_servants, str(declared.get("servant", "")))
		if master == null or servant == null:
			error = "存档阵容模板不存在"
			return false
		assignments[id] = {"master": master, "servant": servant}
	_entropy.seed = int(header.seed)
	RuleRandom.start_seed(int(header.seed))
	if not GameStart.game_start(header.players, assignments, header.order, header.get("runtime_guard", {})):
		error = "存档开局参数无效"
		return false
	return true

func perform(kind: String, args: Array = []):
	if _maintenance_busy or not _confirm_audit(): return null
	if not _recording or not error.is_empty():
		return null
	if not _allowed(kind):
		error = "未知存档操作: " + kind
		return null
	var before := state_hash()
	if before != _last_hash:
		error = "存在未记录的规则修改，请勿继续写入此存档"
		return null
	var packed = ids.encode(args)
	if not ids.error.is_empty():
		error = ids.error
		return null
	# 每次外部动作独立保存随机入口，避免界面或其他会话消耗全局 RNG 后改变恢复。
	var action_seed: int = _entropy.randi()
	var guard_management:bool = kind in ["guard_skip", "guard_continue"]
	var random_entry:Dictionary = RuleRandom.snapshot()
	# 管理续行不是新规则取样入口，不得改变暂停前随机流。
	if not guard_management: RuleRandom.start_seed(action_seed)
	var result = _execute(kind, args)
	var after := state_hash()
	var record := {"kind": kind, "args": packed, "seed": action_seed, "before": before, "after": after}
	if guard_management: record["random_entry"] = random_entry
	if not _confirm_audit(): return null
	if error.is_empty() and journal.append(record):
		_last_hash = after
	else:
		if error.is_empty():
			error = journal.error
		return null
	return result

## 回合末的 await 由真实 SceneTree 续行。把等待帧显式记录，不能用墙钟重放。
func pulse() -> void:
	if _maintenance_busy or not _confirm_audit(): return
	if not _recording or not error.is_empty():
		return
	var serial:int = _recording_serial
	var before := state_hash()
	if before != _last_hash:
		error = "等待前存在未记录的规则修改"
		return
	var action_seed: int = _entropy.randi()
	RuleRandom.start_seed(action_seed)
	await GameProgress.get_tree().process_frame
	await GameProgress.get_tree().process_frame
	if serial != _recording_serial or not _recording:
		return
	if not _confirm_audit(): return
	var after := state_hash()
	if error.is_empty() and journal.append({"kind": "frames", "args": [], "seed": action_seed, "before": before, "after": after}):
		_last_hash = after
	else:
		if error.is_empty():
			error = journal.error

func restore(folder: String, maintenance:Callable = Callable()) -> bool:
	# 必须在 _restore 的清理/reset 之前拒绝已锁存的审计故障。
	if _maintenance_busy or not _confirm_audit(): return false
	_maintenance_busy = true
	var previous_replaying:bool = Journal.audit_replaying
	Journal.audit_replaying = true
	var restored:bool = await _restore(folder, _maintenance_callback(maintenance))
	if not _confirm_audit(): restored = false
	Journal.audit_replaying = previous_replaying
	_maintenance_busy = false
	return restored

func _restore(folder: String, maintenance:Callable = Callable()) -> bool:
	_close_unchecked()
	error = ""
	error_index = -1
	_restored_folder = ""
	_restored_log_hash = ""
	var original_digest := _file_hash(folder.path_join("match.log"), maintenance)
	var original_audit_digest:String = _file_hash(folder.path_join("transactions.log"), maintenance) if FileAccess.file_exists(folder.path_join("transactions.log")) else ""
	if not error.is_empty(): return false
	var parsed: Dictionary = journal.read_all(folder.path_join("match.log"), maintenance)
	if not parsed.ok:
		error = str(parsed.error)
		error_index = int(parsed.error_index)
		return false
	var audit_prefix:Dictionary = {}
	if not original_audit_digest.is_empty():
		audit_prefix = journal.read_all(folder.path_join("transactions.log"), maintenance)
		if not audit_prefix.ok or audit_prefix.truncated or not Journal.audit_chain(audit_prefix.records, maintenance).ok:
			error = "事务审计链损坏"
			return false
	truncated = bool(parsed.truncated)
	var records: Array = parsed.records
	var header: Dictionary = records[0]
	var archive := folder.path_join("data")
	if not _valid_header(header):
		error = "存档文件头字段无效"
		return false
	var current_engine:String = _engine_hash(maintenance)
	if not error.is_empty() or current_engine.is_empty():
		if error.is_empty(): error = "规则指纹为空，拒绝恢复"
		return false
	if header.get("format") != 1 or header.get("engine") != current_engine:
		error = "存档引擎版本不一致"
		return false
	if not Journal.reset_audit_memory():
		error = "另一录制器持有事务审计文件"
		return false
	if header.get("data") != _manifest(archive, maintenance):
		error = "存档数据缺失或被修改"
		return false
	if not _tick(maintenance): return false
	if not _start(header, archive):
		return false
	if not _tick(maintenance): return false
	if state_hash() != header.get("initial_hash"):
		error = "开局状态校验失败"
		error_index = 0
		return false
	for i in range(1, records.size()):
		error_index = i
		var record: Dictionary = records[i]
		if not record.get("seed") is int or not record.get("args") is Array or not record.get("before") is String or not record.get("after") is String:
			error = "存档操作字段无效"
			return false
		if not _allowed(str(record.get("kind"))) and record.get("kind") != "frames":
			error = "存档含未知操作"
			return false
		if state_hash() != record.get("before"):
			error = "操作前状态校验失败"
			return false
		if _entropy.randi() != int(record.seed):
			error = "随机入口序列校验失败"
			return false
		if record.kind in ["guard_skip", "guard_continue"]:
			if record.get("random_entry") != RuleRandom.snapshot():
				error = "管理续行随机入口不一致"
				return false
		else:
			RuleRandom.start_seed(int(record.seed))
		if record.kind == "frames":
			await GameProgress.get_tree().process_frame
			await GameProgress.get_tree().process_frame
		else:
			var args = ids.decode(record.args)
			if not ids.error.is_empty() or not args is Array:
				error = ids.error
				return false
			_execute(record.kind, args)
		if state_hash() != record.get("after"):
			error = "操作后状态校验失败"
			return false
		if not error.is_empty():
			return false
		if not _tick(maintenance): return false
	error_index = -1
	_last_hash = state_hash()
	if _file_hash(folder.path_join("match.log"), maintenance) != original_digest:
		error = "恢复期间存档文件被修改"
		return false
	if not original_audit_digest.is_empty() and _file_hash(folder.path_join("transactions.log"), maintenance) != original_audit_digest:
		error = "恢复期间事务审计文件被修改"
		return false
	if not audit_prefix.is_empty() and audit_prefix.records.size() < Journal.audit_revision + 1:
		error = "事务审计缺少已恢复规则边界"
		return false
	if not _tick(maintenance): return false
	if state_hash() != _last_hash:
		error = "维护期间规则状态被修改"
		return false
	_restored_audit_hash = original_audit_digest
	_restored_audit_revision = Journal.audit_revision
	_restored_folder = folder
	_restored_log_hash = original_digest
	initial = header.duplicate(true)
	return true

## 已验证的恢复前缀另存为独立存档，不修补或覆盖原始文件。
func save_restored_as(folder: String, maintenance:Callable = Callable()) -> bool:
	if _maintenance_busy or not _confirm_audit(): return false
	_maintenance_busy = true
	var saved:bool = _save_restored_as(folder, _maintenance_callback(maintenance))
	if not _confirm_audit(): saved = false
	_maintenance_busy = false
	return saved

func _save_restored_as(folder:String, maintenance:Callable) -> bool:
	if not _restored_source_is_current(maintenance):
		return false
	if DirAccess.dir_exists_absolute(folder) or FileAccess.file_exists(folder):
		error = "另存目录已存在，不覆盖"
		return false
	var source_log := _restored_folder.path_join("match.log")
	var parsed:Dictionary = journal.read_all(source_log, maintenance)
	if not parsed.ok:
		error = str(parsed.error)
		return false
	var archive := _restored_folder.path_join("data")
	if _manifest(archive, maintenance) != parsed.records[0].data:
		error = "原存档数据已修改，不能另存"
		return false
	var target_archive := folder.path_join("data")
	if not _copy_data(archive, target_archive, maintenance):
		return false
	if _manifest(target_archive, maintenance) != parsed.records[0].data:
		error = "另存数据校验失败"
		return false
	var copy = Journal.new()
	if not copy.create(folder.path_join("match.log"), parsed.records[0]):
		error = copy.error
		copy.close()
		return false
	for index in range(1, parsed.records.size()):
		if not _tick(maintenance):
			copy.close()
			return false
		if not copy.append(parsed.records[index]):
			error = copy.error
			copy.close()
			return false
	copy.close()
	var verified:Dictionary = copy.read_all(folder.path_join("match.log"), maintenance)
	if not verified.ok or verified.truncated or verified.records != parsed.records:
		error = "另存日志校验失败"
		return false
	if not _copy_restored_audit(folder, maintenance): return false
	# 复制期间再次验证源文件及规则状态；失败不提交另存身份。
	if not _restored_source_is_current(maintenance): return false
	var saved_log_hash:String = _file_hash(folder.path_join("match.log"), maintenance)
	var saved_audit_hash:String = _file_hash(folder.path_join("transactions.log"), maintenance)
	if not error.is_empty(): return false
	if state_hash() != _last_hash:
		error = "维护期间规则状态被修改"
		return false
	_restored_folder = folder
	_restored_log_hash = saved_log_hash
	_restored_audit_hash = saved_audit_hash
	truncated = false
	return true

## 恢复只读；确认后才允许在同一日志末尾继续追加。
func resume_recording(maintenance:Callable = Callable()) -> bool:
	if _maintenance_busy or not _confirm_audit(): return false
	_maintenance_busy = true
	var accepted:bool = _resume_recording(_maintenance_callback(maintenance))
	if not _confirm_audit(): accepted = false
	_maintenance_busy = false
	return accepted

func _resume_recording(maintenance:Callable) -> bool:
	if not _tick(maintenance): return false
	if truncated or not _restored_source_is_current(maintenance):
		return false
	if not journal.resume(_restored_folder.path_join("match.log"), false, maintenance):
		error = journal.error
		return false
	_audit_journal = Journal.resume_audit(_restored_folder.path_join("transactions.log"), _restored_audit_revision, maintenance)
	if _audit_journal == null:
		error = Journal.audit_error
		journal.close()
		return false
	if not _confirm_audit():
		_close_unchecked()
		return false
	if not _tick(maintenance):
		_close_unchecked()
		return false
	_recording = true
	return true

func _copy_restored_audit(folder:String, maintenance:Callable = Callable()) -> bool:
	var source:String = _restored_folder.path_join("transactions.log")
	if not FileAccess.file_exists(source):
		error = "旧存档缺少事务审计，不能声明完整另存"
		return false
	var parsed:Dictionary = journal.read_all(source, maintenance)
	if not parsed.ok or parsed.truncated or not Journal.audit_chain(parsed.records, maintenance).ok or parsed.records.size() < _restored_audit_revision + 1:
		error = "事务审计缺少完整恢复边界"
		return false
	var copy = Journal.new()
	if not copy.create(folder.path_join("transactions.log"), parsed.records[0]):
		error = copy.error
		return false
	# 独立审计不可回滚；另存复制全部历史，而不是裁剪到规则前缀。
	for index in range(1, parsed.records.size()):
		if not _tick(maintenance):
			copy.close()
			return false
		if not copy.append(parsed.records[index]):
			error = copy.error
			copy.close()
			return false
	copy.close()
	var verified:Dictionary = copy.read_all(folder.path_join("transactions.log"), maintenance)
	if not verified.ok or verified.truncated or verified.records != parsed.records:
		error = "另存事务审计校验失败"
		return false
	return true

func _restored_source_is_current(maintenance:Callable = Callable()) -> bool:
	if _recording or not error.is_empty() or _restored_folder.is_empty():
		return false
	if state_hash() != _last_hash:
		error = "恢复后存在未记录的规则修改，请重新验证恢复"
		return false
	var path := _restored_folder.path_join("match.log")
	var audit_path:String = _restored_folder.path_join("transactions.log")
	if not _restored_audit_hash.is_empty() and _file_hash(audit_path, maintenance) != _restored_audit_hash:
		error = "原事务审计文件已修改，请重新验证恢复"
		return false
	if _file_hash(path, maintenance) != _restored_log_hash:
		error = "原存档已修改，请重新验证恢复"
		return false
	var parsed:Dictionary = journal.read_all(path, maintenance)
	if not parsed.ok or _manifest(_restored_folder.path_join("data"), maintenance) != parsed.records[0].data:
		error = "原存档数据或日志已修改，请重新验证恢复"
		return false
	return true

func close() -> bool:
	if _maintenance_busy: return false
	return _close_confirmed()

func _close_confirmed() -> bool:
	# 故障仍释放句柄/租约，但绝不将清理完成作为提交成功。
	var confirmed:bool = _confirm_audit()
	if _recording and not journal.flush():
		if error.is_empty(): error = journal.error
		confirmed = false
	_close_unchecked()
	return confirmed and error.is_empty()

func _close_unchecked() -> void:
	_recording_serial += 1
	journal.close()
	Journal.end_audit(_audit_journal)
	_audit_journal = null
	_recording = false

func release() -> void:
	if _maintenance_busy: return
	close()
	_restored_folder = ""
	_restored_log_hash = ""
	initial.clear()
	LoadHelper.session_data_dir = ""
	GameStart.end_session()

func _allowed(kind: String) -> bool:
	return kind in COMMANDS or kind in ["guard_skip", "guard_continue", "ai_turn", "answer_effect", "answer_card", "answer_player", "answer_location", "set_broadcast_enabled"]

func _execute(kind: String, args: Array):
	if not _valid_args(kind, args):
		error = "存档操作参数无效: " + kind
		return null
	if kind in COMMANDS:
		return commands.callv(kind, args)
	if kind in ["guard_skip", "guard_continue"]:
		var before:Dictionary = EffectManager.runtime_guard_status()
		var accepted:bool = EffectManager.skip_runtime_guard() if kind == "guard_skip" else EffectManager.resume_runtime_guard()
		if accepted and args.size() == 3:
			GameLog.record("room_management", args[0], -1, "", null, [kind],
				{"action":kind, "peer":args[1], "view_seq":args[2],
				"paused_before":before.paused, "paused_after":EffectManager.runtime_guard_status().paused})
		return accepted
	match kind:
		"set_broadcast_enabled":
			if args[0]:
				GameProgress.register_battle_broadcast_consumer(self)
			else:
				GameProgress.unregister_battle_broadcast_consumer(self)
		"ai_turn":
			driver.run_bot_turn(int(args[0]))
		"answer_effect":
			return driver.answer_effect(EffectManager.get_pending_active_effect())
		"answer_card":
			return driver.answer_card(EffectManager.get_pending_card_selection())
		"answer_player":
			return driver.answer_player(EffectManager.get_pending_player_selection())
		"answer_location":
			return driver.answer_location(EffectManager.get_pending_location_selection())
	return null

func _valid_args(kind: String, args: Array) -> bool:
	if kind in ["guard_skip", "guard_continue"]:
		return args.is_empty() or (args.size() == 3 and args[0] is int and args[0] >= -1 and args[1] is int and args[1] > 0 and args[2] is int and args[2] >= 0)
	if kind == "ai_turn":
		return args.size() == 1 and args[0] is int and GameData.player_data_library.has(args[0])
	if kind == "set_broadcast_enabled":
		return args.size() == 1 and args[0] is bool
	if kind.begins_with("answer_"):
		return args.is_empty()
	for method in commands.get_method_list():
		if str(method.name) != kind:
			continue
		var declared: Array = method.args
		if args.size() > declared.size() or args.size() < declared.size() - method.default_args.size():
			return false
		for i in range(args.size()):
			var type: int = declared[i].type
			if type == TYPE_NIL:
				continue
			if type == TYPE_OBJECT:
				if args[i] == null:
					continue
				var classes := {"BaseCard": BaseCard, "BaseEffect": BaseEffect, "BaseLocation": BaseLocation, "BaseMapArea":BaseMapArea}
				if not classes.has(str(declared[i].class_name)) or not is_instance_of(args[i], classes[str(declared[i].class_name)]):
					return false
			elif typeof(args[i]) != type:
				return false
		return true
	return false

func state_hash() -> String:
	var snapshot: Dictionary = RuleState.capture(ids)
	if not ids.error.is_empty():
		error = ids.error
	return Journal._digest(var_to_bytes(snapshot)).hex_encode()

func _valid_header(header: Dictionary) -> bool:
	if header.has("seat_kinds"):
		if not header.seat_kinds is Dictionary or header.seat_kinds.size() != header.get("players", []).size(): return false
		for pid in header.seat_kinds:
			if not pid is int or not header.get("players", []).has(pid) or header.seat_kinds[pid] not in [driver.seats.AI, driver.seats.REMOTE]: return false
	var guard = header.get("runtime_guard", {})
	if not guard is Dictionary or (not guard.is_empty() and not preload("res://scripts/match/rule_budget.gd").new().configure(guard)):
		return false
	for key in ["players", "order"]:
		if not header.get(key) is Array:
			return false
		for id in header[key]:
			if not id is int:
				return false
	for key in ["seed", "local_id"]:
		if not header.get(key) is int:
			return false
	for key in ["engine", "initial_hash", "default_master", "default_servant"]:
		if not header.get(key) is String:
			return false
	if not header.get("assignments") is Dictionary or not header.get("data") is Dictionary:
		return false
	for id in header.assignments:
		var declared = header.assignments[id]
		if not id is int or not declared is Dictionary or not declared.get("master") is String or not declared.get("servant") is String:
			return false
	return true

func _template(pool: Array, name: String):
	for object in pool:
		if object._name == name:
			return object
	return null

# 所有维护点都是同步 call；false 传播取消，不把协作预算冒充硬时限。
func _tick(maintenance:Callable) -> bool:
	if not Journal.audit_error.is_empty(): return _confirm_audit()
	if not error.is_empty(): return false
	if maintenance.is_valid() and maintenance.call() == false:
		if error.is_empty(): error = "维护回调取消了存档操作"
		return false
	return error.is_empty()

func _copy_data(source: String, target: String, maintenance:Callable = Callable()) -> bool:
	for relative in _files(source, "", maintenance):
		if not _tick(maintenance): return false
		var destination := target.path_join(relative)
		if DirAccess.make_dir_recursive_absolute(destination.get_base_dir()) != OK:
			error = "无法创建存档数据目录"
			return false
		var input := FileAccess.open(source.path_join(relative), FileAccess.READ)
		if input == null:
			error = "无法读取存档数据"
			return false
		var file := FileAccess.open(destination, FileAccess.WRITE)
		if file == null:
			input.close()
			error = "无法写入存档数据"
			return false
		var length:int = input.get_length()
		while input.get_position() < length:
			var amount:int = mini(MAINTENANCE_CHUNK_BYTES, length - input.get_position())
			var bytes := input.get_buffer(amount)
			if bytes.size() != amount or input.get_error() != OK:
				error = "读取存档数据失败"
				break
			file.store_buffer(bytes)
			if file.get_error() != OK:
				error = "写入存档数据失败"
				break
			if not _tick(maintenance): break
		input.close()
		file.flush()
		var write_error := file.get_error()
		file.close()
		if write_error != OK and error.is_empty(): error = "写入存档数据失败"
		if not error.is_empty(): return false
	return error.is_empty()

func _file_hash(path:String, maintenance:Callable = Callable()) -> String:
	if not _tick(maintenance): return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		error = "无法校验存档文件: " + path
		return ""
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	var length:int = file.get_length()
	while file.get_position() < length:
		var amount:int = mini(MAINTENANCE_CHUNK_BYTES, length - file.get_position())
		var bytes := file.get_buffer(amount)
		if bytes.size() != amount or file.get_error() != OK:
			error = "校验读取失败: " + path
			break
		context.update(bytes)
		if not _tick(maintenance): break
	file.close()
	return context.finish().hex_encode() if error.is_empty() else ""

func _manifest(root: String, maintenance:Callable = Callable()) -> Dictionary:
	var manifest: Dictionary = {}
	for relative in _files(root, "", maintenance):
		manifest[relative] = _file_hash(root.path_join(relative), maintenance)
		if not error.is_empty(): return {}
	return manifest

func _files(root: String, relative: String = "", maintenance:Callable = Callable()) -> Array:
	var result: Array = []
	if not _tick(maintenance): return result
	var dir := DirAccess.open(root.path_join(relative))
	if dir == null: return result
	for folder in dir.get_directories():
		if not _tick(maintenance): return []
		if not folder.begins_with("."):
			result.append_array(_files(root, relative.path_join(folder), maintenance))
	for file in dir.get_files():
		if not _tick(maintenance): return []
		if not file.begins_with(".") and not file.ends_with(".import") and file != "tag_list.json":
			result.append(relative.path_join(file))
	result.sort()
	return result

# 仅规则指纹使用 ResourceLoader 的逻辑目录；数据目录仍走原 _files/_manifest。
func _engine_script_files(root:String, maintenance:Callable = Callable()) -> Array:
	if not _tick(maintenance): return []
	var dir := DirAccess.open(root)
	if dir == null or dir.list_dir_begin() != OK:
		error = "无法枚举规则目录: " + root
		return []
	dir.list_dir_end()
	var result:Array = []
	for entry in ResourceLoader.list_directory(root):
		if not _tick(maintenance): return []
		if entry.begins_with("."): continue
		var path:String = root.path_join(entry.trim_suffix("/"))
		if entry.ends_with("/"):
			result.append_array(_engine_script_files(path, maintenance))
			if not error.is_empty(): return []
		elif entry.ends_with(".gd"):
			result.append(path)
	result.sort()
	return result

# 发行 .gd.remap 优先于残留源码，与 ResourceLoader 的加载选择一致。
# 不通过 load()/get_source_code() 取指纹，不执行规则，也不依赖发行包保留源码。
func _engine_script_payload(path:String, maintenance:Callable = Callable()) -> Dictionary:
	if not _tick(maintenance): return {}
	var actual:String = path
	var remap:String = path + ".remap"
	if FileAccess.file_exists(remap):
		var config := ConfigFile.new()
		if config.load(remap) != OK:
			error = "规则脚本映射无效: " + path
			return {}
		if not config.has_section_key("remap", "path"):
			error = "规则脚本映射目标缺失: " + path
			return {}
		var target = config.get_value("remap", "path")
		if not target is String or not target.begins_with("res://") or target != target.simplify_path() or not target.get_extension() in ["gd", "gdc"]:
			error = "规则脚本映射目标无效: " + path
			return {}
		actual = target
	var digest:String = _file_hash(actual, maintenance)
	if not error.is_empty() or digest.is_empty(): return {}
	return {"path": actual, "sha256": digest}

func _engine_hash(maintenance:Callable = Callable()) -> String:
	var paths:Array = _engine_script_files("res://scripts", maintenance)
	if not error.is_empty(): return ""
	# 必需规则范围不得退化成空清单；其他所有 scripts 下的脚本也一并覆盖。
	for root in ["res://scripts/system/", "res://scripts/match/"]:
		var found:bool = false
		for path in paths:
			if path.begins_with(root):
				found = true
				break
		if not found:
			error = "规则指纹缺少必要目录: " + root
			return ""
	if not paths.has("res://scripts/main_menu/game_start.gd"):
		error = "规则指纹缺少开局脚本"
		return ""
	var manifest:Dictionary = {"godot": Engine.get_version_info(), "script_payloads": {}}
	for path in paths:
		var payload:Dictionary = _engine_script_payload(path, maintenance)
		if not error.is_empty() or payload.is_empty(): return ""
		manifest.script_payloads[path] = payload
	return Journal._digest(var_to_bytes(manifest)).hex_encode()

# 默认关闭；不输出路径、玩家、房间、密钥或数据内容，不改变规则指纹算法。
func _begin_stage(stage:String) -> void:
	if OS.get_environment("FD_RECOVERY_DIAGNOSTICS") == "1":
		print("RECORDING_BEGIN_STAGE ", stage, " ", Time.get_ticks_msec())
