class_name NetworkMatchAuthority
extends RefCounted

var driver = preload("res://scripts/match/match_driver.gd").new()
var builder = preload("res://scripts/match/view_builder.gd").new()
var seat_query = preload("res://scripts/match/match_seat_query.gd").new(builder)
var commands = preload("res://scripts/match/match_commands.gd").new()
var controllers: Dictionary = {}
var error: String = ""
var started: bool = false
var restore_failed_closed:bool = false
var _issued: Dictionary = {}
var _revision: int = 0
var _restart_selection:Dictionary = {}
var _restart_guard:Dictionary = {}
var _restart_seed = null
var _context: SessionContext = null
var recorder
var _archive_pulse_running:bool = false
var _archive_changed:bool = false
var _archive_serial:int = 0
static var _start_busy:bool = false
var _notification_instance: String = MatchViewBuilder.new_notification_epoch()
var _notification_generation: int = 0
var _notification_boundaries: Dictionary = {}
var _broadcast_confirmation: bool = false
var _broadcast_batch: int = 0
var _broadcast_ai_elapsed: float = 0.0
var _management_folder: String = ""
var _management_journal
const BROADCAST_AI_CONFIRM_STEP: float = 0.28

## 只读权威修订水位；中止对局不归零，不签发视图或推进规则。
func current_revision() -> int:
	return _revision

## 调用方在 start 前声明消费/确认能力；不以 AI/headless 或有连接推测。
## session/worker 共享文件由其所有者显式调用，未调用保持非阻塞默认。
func declare_broadcast_confirmation(enabled: bool) -> bool:
	if started: return false
	_broadcast_confirmation = enabled
	return true

## 仅由认证绑定/恢复提交调用；不是首 view，也不是普通 changed。
## 不回滚的分配器水位涵盖已经移出队列的旧记录。
func bind_notification_boundary(peer: int) -> void:
	var cutoff: int = EffectManager.latest_allocated_message_serial()
	_notification_boundaries[peer] = {"generation": _notification_generation,
		"observer": observer_for(peer), "serial": cutoff}
	_issued.erase(peer)

## 只在成功接纳新的规则生命周期后推进；不使用规则协程号或 view.seq。
func _begin_notification_lifecycle() -> void:
	_notification_boundaries.clear()
	_notification_generation += 1
	builder.set_notification_epoch("%s-%d" % [_notification_instance, _notification_generation])

## 权威提交闸：审计故障不可转换为动作/管理成功，也不可退回无录制推进。
func confirm_audit() -> bool:
	if preload("res://scripts/match/match_journal.gd").flush_audit(): return true
	EffectManager.mark_guard_audit_failed(EffectManager.runtime_guard_effect())
	_issued.clear()
	return _reject("事务审计不可用，操作未确认")

func start(selection, runtime_guard:Dictionary = {}, archive_folder:String = "", maintenance:Callable = Callable()) -> bool:
	if _start_busy or preload("res://scripts/match/match_replay.gd")._maintenance_busy: return false # 不覆盖正在启动实例的 error。
	_start_busy = true
	var accepted:bool = _start(selection, runtime_guard, archive_folder, maintenance)
	_start_busy = false
	return accepted

func _start(selection, runtime_guard:Dictionary, archive_folder:String, maintenance:Callable) -> bool:
	if not confirm_audit(): return false
	if restore_failed_closed or started or selection.rules == null or not selection.rules.is_complete():
		return _reject("选人未完成或对局已启动")
	if not runtime_guard.is_empty() and not preload("res://scripts/match/rule_budget.gd").new().configure(runtime_guard):
		return _reject("规则执行保护配置无效")
	var random_stream = preload("res://scripts/match/rule_random.gd")
	var previous_random:Dictionary = random_stream.snapshot()
	if _restart_seed == null:
		if previous_random.get("known", false):
			_restart_seed = previous_random.seed.to_int()
		else:
			var generator := RandomNumberGenerator.new()
			generator.randomize()
			_restart_seed = generator.seed
	random_stream.start_seed(_restart_seed)
	var names:Dictionary = {}
	var selected:Dictionary = selection.rules.get_assignments()
	for pid in selected:
		var assignment:Dictionary = selected[pid]
		names[pid] = {"master":assignment.master._name, "servant":assignment.servant._name}
	if archive_folder.is_empty():
		if not GameStart.game_start(selection.rules.player_ids, selected, selection.rules.get_initial_order(), runtime_guard):
			if previous_random.get("known", false): random_stream.restore(previous_random)
			else: random_stream.stop_tracking()
			return _reject("引擎拒绝启动对局")
		_context = MatchDriver.capture_runtime_context()
		if not SessionGeneration.validate_context(_context).get("ok", false):
			GameStart.end_session()
			return _reject("开局未建立可验证的规则来源")
		driver = MatchDriver.new(null, _context)
	else:
		var candidate = preload("res://scripts/match/match_replay.gd").new()
		var kinds:Dictionary = {}
		for pid in selection.controllers: kinds[pid] = driver.seats.AI if selection.controllers[pid] == 0 else driver.seats.REMOTE
		if not candidate.begin(archive_folder, selection.rules.player_ids, _restart_seed, names, selection.rules.get_initial_order(), runtime_guard, kinds, maintenance):
			if previous_random.get("known", false): random_stream.restore(previous_random)
			else: random_stream.stop_tracking()
			return _reject(candidate.error)
		recorder = candidate
		driver = recorder.driver
		_context = driver.source_context
		if not SessionGeneration.validate_context(_context).get("ok", false):
			recorder.close()
			return _reject("录制开局未建立可验证的规则来源")
	if not confirm_audit():
		return _reject("事务审计写入失败，启动未确认")
	_configure_controllers(selection.controllers)
	if not _apply_broadcast_declaration(): return false
	_begin_notification_lifecycle()
	started = true
	_management_folder = archive_folder
	_restart_selection = {"player_ids":selection.rules.player_ids.duplicate(), "assignments":names,
		"order":selection.rules.get_initial_order().duplicate(), "controllers":controllers.duplicate()}
	_restart_guard = runtime_guard.duplicate(true)
	_revision += 1
	return true

func observer_for(peer: int) -> int:
	if peer <= 0:
		return -1
	for seat in controllers:
		if controllers[seat] == peer:
			return seat
	return -1

func _configure_controllers(seats:Dictionary) -> void:
	controllers = seats.duplicate()
	_broadcast_batch = 0
	_broadcast_ai_elapsed = 0.0
	# 报价在构造时按来源捕获；每次开局/重开/恢复后用本局来源重建，旧局或建权威时的空报价不得沿用。
	seat_query = preload("res://scripts/match/match_seat_query.gd").new(builder, _context)
	driver.seats.default_kind = driver.seats.VACANT
	for seat in controllers:
		driver.seats.set_kind(seat, driver.seats.AI if controllers[seat] == 0 else driver.seats.REMOTE)

## 声明变化是规则写入；录制与审计失败不得冒充启动成功。
func _apply_broadcast_declaration() -> bool:
	if recorder != null and recorder._recording:
		_run_recorded_driver("set_broadcast_enabled", [_broadcast_confirmation])
		if not recorder.error.is_empty(): return false
	else:
		GameProgress.battle_broadcast_requires_confirm = _broadcast_confirmation
	return confirm_audit()

func view_for(peer: int) -> Dictionary:
	if not started or not SessionGeneration.validate_context(_context).get("ok", false):
		return {}
	var boundary: Dictionary = _notification_boundaries.get(peer, {})
	var cutoff: int = -1
	if not boundary.is_empty() and boundary.generation == _notification_generation:
		if boundary.observer != observer_for(peer):
			_reject("通知观察席位已变更，须重新绑定")
			return {}
		cutoff = boundary.serial
	var view: Dictionary = builder.build(observer_for(peer), cutoff)
	if view.is_empty():
		_reject(builder.notification_error)
		return {}
	_issued[peer] = {"seq": view.seq, "revision": _revision, "observer": observer_for(peer), "context": _context}
	return view

## 仅收尾已自然终局的规则运行态；房主/在线/房间阶段授权由 session 先行校验。
## peer 是已认证稳定成员 ID，sequence 是该成员最近签发视图的 seq，不是请求序号。
func finish_match_to_lobby(peer: int, sequence: int) -> Dictionary:
	error = ""
	if not started:
		return _finish_rejected("not_started", "当前没有已启动对局")
	if not GameProgress.is_game_over:
		return _finish_rejected("not_game_over", "对局尚未结束")
	if not _issued.has(peer):
		return _finish_rejected("missing_view", "连接没有当前对局视图")
	var issued:Dictionary = _issued[peer]
	if sequence != issued.seq or issued.revision != _revision:
		return _finish_rejected("stale_view", "视图已过期")
	if issued.get("observer", -2) != observer_for(peer):
		return _finish_rejected("observer_changed", "视图观察席位已变更")
	if _archive_pulse_running:
		return _finish_rejected("archive_busy", "正在结算回合，请等待最新视图")
	# 档案提交失败不得释放规则对象，也不得向 session 声称可发布大厅。
	if not close_archive():
		var reason:String = error
		if reason.is_empty() and recorder != null: reason = recorder.error
		return _finish_rejected("archive_error", reason if not reason.is_empty() else "终局档案关闭失败")
	GameStart.end_session()
	driver = preload("res://scripts/match/match_driver.gd").new()
	_context = null
	started = false
	controllers.clear()
	_issued.clear()
	_restart_selection.clear()
	_restart_guard.clear()
	_restart_seed = null
	recorder = null
	_revision += 1
	return {"ok": true, "code": "finished", "reason": ""}

func _finish_rejected(code:String, reason:String) -> Dictionary:
	_reject(reason)
	return {"ok": false, "code": code, "reason": reason}

## 仅 Session 管理授权使用；不得由本人 dispatcher 或客户端参数直接调用。
## seats 已由 Session 证明离线，权威仍整批复核规则资格，再同步执行。
## 纯查询：仅提供当前批次中仍需要确认的真人控制席；不授予管理权限，也不替代最终整批复验。
func absent_broadcast_candidates(batch_id: int) -> Array:
	var candidates: Array = []
	if not started or not _broadcast_confirmation or not GameProgress.is_battle_broadcast_pending() or batch_id != GameProgress.battle_broadcast_batch_id():
		return candidates
	for seat in controllers:
		var controller = controllers[seat]
		if seat is int and controller is int and controller > 0 and GameProgress.can_confirm_battle_broadcast(seat, batch_id):
			candidates.append(seat)
	candidates.sort()
	return candidates

func confirm_absent_broadcast(member: int, sequence: int, batch_id: int, seats: Array) -> Dictionary:
	error = ""
	var actor: int = observer_for(member)
	if not started or not _broadcast_confirmation or not _issued.has(member):
		return _finish_rejected("not_started", "当前没有可确认的对局视图")
	var issued: Dictionary = _issued[member]
	if sequence != issued.seq or issued.revision != _revision:
		return _finish_rejected("stale_view", "视图已过期")
	if issued.observer != actor:
		return _finish_rejected("observer_changed", "视图观察席位已变更")
	if _archive_pulse_running or EffectManager.runtime_guard_status().paused:
		return _finish_rejected("paused", "规则正在结算或已暂停")
	if recorder != null and (not recorder._recording or not recorder.error.is_empty()):
		return _finish_rejected("archive_error", "存档录制不可用，管理操作未确认")
	if seats.is_empty() or not GameProgress.is_battle_broadcast_pending() or batch_id != GameProgress.battle_broadcast_batch_id():
		return _finish_rejected("stale_batch", "确认批次无效或已过期")
	var seen: Dictionary = {}
	for seat in seats:
		if not seat is int or seen.has(seat) or not controllers.get(seat) is int or controllers.get(seat, 0) <= 0 or not GameProgress.can_confirm_battle_broadcast(seat, batch_id):
			return _finish_rejected("invalid_seats", "整批席位必须为未确认的离线真人")
		seen[seat] = true
	if not confirm_audit(): return _finish_rejected("audit_error", error)
	var fact: Dictionary = {"action":"broadcast_confirm_absent", "actor":actor,
		"member":member, "seats":seats.duplicate(), "batch_id":batch_id, "view_seq":sequence}
	# 独立 sidecar 不混入 replay 命令序列/规则哈希；意图先持久化，成功再留完成事实。
	if not _record_broadcast_management(fact, "intent"):
		return _finish_rejected("audit_error", error)
	for seat in seats:
		_run_command("confirm_battle_broadcast", [seat])
		if not error.is_empty():
			_revision += 1
			return _finish_rejected("audit_error", error)
		var seat_fact: Dictionary = fact.duplicate(true)
		seat_fact["seat"] = seat
		if not _record_broadcast_management(seat_fact, "seat_confirmed"):
			_revision += 1
			_issued.clear()
			return _finish_rejected("audit_error", error)
		if recorder == null:
			GameLog.record("room_management_seat", actor, seat, "", null, ["broadcast_confirm_absent"], seat_fact)
	_revision += 1
	# GameLog 在 RuleState 哈希内；录制局只写 sidecar，不能注入无法 replay 的规则事实。
	if recorder == null:
		GameLog.record("room_management", actor, -1, "", null, ["broadcast_confirm_absent"], fact)
	if not _record_broadcast_management(fact, "completed") or not confirm_audit():
		_issued.clear()
		return _finish_rejected("audit_error", error)
	return {"ok":true, "code":"confirmed", "reason":""}

func _record_broadcast_management(fact: Dictionary, stage: String) -> bool:
	if _management_folder.is_empty(): return confirm_audit()
	if _management_journal == null:
		_management_journal = preload("res://scripts/match/match_journal.gd").new()
		if not _management_journal.create(_management_folder.path_join("broadcast_management.log"), {"kind":"broadcast_management", "format":1}):
			return _reject("管理审计创建失败：" + _management_journal.error)
	var record: Dictionary = fact.duplicate(true)
	record["stage"] = stage
	if not _management_journal.append(record) or not _management_journal.flush():
		return _reject("管理审计写入失败：" + _management_journal.error)
	return true

func submit(peer: int, sequence: int, kind: String, args: Dictionary) -> bool:
	error = ""
	var audit = preload("res://scripts/match/match_journal.gd")
	if not confirm_audit(): return _reject("事务审计不可用，操作未确认")
	var accepted:bool = _submit(peer, sequence, kind, args)
	if not confirm_audit():
		# 规则可能已变更，拒绝成功回执同时使旧视图失效，不重做动作。
		_revision += 1
		return _reject("事务审计写入失败，操作未确认")
	return accepted and error.is_empty()

func _submit(peer: int, sequence: int, kind: String, args: Dictionary) -> bool:
	error = ""
	if not SessionGeneration.validate_context(_context).get("ok", false):
		return _reject("对局来源已失效")
	var seat := observer_for(peer)
	if not started or seat < 0 or not _issued.has(peer):
		return _reject("连接没有可操作座位")
	if sequence != _issued[peer].seq or _issued[peer].revision != _revision:
		return _reject("视图已过期")
	if not is_same(_issued[peer].get("context"), _context):
		return _reject("请求来源已变更")
	if _issued[peer].get("observer", -2) != seat:
		return _reject("视图观察席位已变更")
	if _archive_pulse_running:
		return _reject("正在结算回合，请等待最新视图")
	if EffectManager.runtime_guard_status().paused:
		return _reject("规则执行已暂停，等待房主处理")
	# 连接与版本闸属于权威端；业务校验与执行仅分派一次。
	var dispatcher = preload("res://scripts/match/match_command_dispatcher.gd").new(
		EffectManager.is_card_selection_valid, EffectManager.location_option_origin_allowed)
	var result: Dictionary = dispatcher.dispatch(seat, kind, args, builder.ids, _run_command, _context)
	_revision += int(result.revision_delta)
	# 执行路径的审计/录制错误优先，不以业务拒绝覆盖故障原因。
	if error.is_empty():
		error = str(result.reason)
	return bool(result.ok)

## 房间管理权由会话按真实连接校验，此处只校验对局与续行版本。
func guard_diagnostic() -> Dictionary:
	var effect = EffectManager.runtime_guard_effect()
	if effect == null:
		return {}
	var source = GetEffSourceCard.new().exec(effect)
	var origin = EffectManager.runtime_guard_root_effect()
	if source == null and origin != null and origin != effect:
		source = GetEffSourceCard.new().exec(origin)
	var pid:int = EffectManager.effect_fact_actor_id(effect)
	var data:Dictionary = GameData.player_data_library.get(pid, {})
	var source_name:String = source.get_shown_name() if source != null else EffectManager.effect_source_name(effect)
	return {"player":pid, "player_name":str(data.get("player_name", "未归属玩家")),
		"card":source_name if not source_name.is_empty() else "无来源卡牌",
		"effect":effect.get_shown_name(), "can_restart":not _restart_selection.is_empty(),
		"can_skip":EffectManager.can_rollback_runtime_guard()}

func restart_guarded_match() -> bool:
	error = ""
	if not confirm_audit(): return false
	if not started or _restart_selection.is_empty() or not EffectManager.runtime_guard_status().paused:
		return false
	# 先验证现有批准模板，已知无法恢复时保留旧局及暂停检查点。
	if _resolve_restart_assignments().is_empty():
		return false
	GameStart.end_session()
	driver = preload("res://scripts/match/match_driver.gd").new()
	_context = null
	_issued.clear()
	started = false
	# 结束会话会重载模板；只使用重载后的对象，不复用旧局引用。
	var assignments:Dictionary = _resolve_restart_assignments()
	if assignments.is_empty():
		return false
	preload("res://scripts/match/rule_random.gd").start_seed(_restart_seed)
	if not GameStart.game_start(_restart_selection.player_ids, assignments, _restart_selection.order, _restart_guard):
		return _reject("引擎拒绝重开对局")
	_context = MatchDriver.capture_runtime_context()
	if not SessionGeneration.validate_context(_context).get("ok", false):
		GameStart.end_session()
		return _reject("重开未建立可验证的规则来源")
	driver = MatchDriver.new(null, _context)
	if not confirm_audit():
		return _reject("事务审计写入失败，重开未确认")
	_configure_controllers(_restart_selection.controllers)
	if not _apply_broadcast_declaration(): return false
	_begin_notification_lifecycle()
	started = true
	_revision += 1
	return true

func _resolve_restart_assignments() -> Dictionary:
	var masters:Dictionary = {}
	var servants:Dictionary = {}
	for master in GameStart.get_masters_can_use(): masters[master._name] = master
	for servant in GameStart.get_servants_can_use(): servants[servant._name] = servant
	var assignments:Dictionary = {}
	for pid in _restart_selection.assignments:
		var names:Dictionary = _restart_selection.assignments[pid]
		if not masters.has(names.master) or not servants.has(names.servant):
			_reject("批准数据无法恢复原阵容")
			return {}
		assignments[pid] = {"master":masters[names.master], "servant":servants[names.servant]}
	return assignments

func continue_runtime_guard(peer: int, sequence: int, action:String = "guard_continue") -> bool:
	error = ""
	if not started or not _issued.has(peer):
		return _reject("连接没有当前对局视图")
	if sequence != _issued[peer].seq or _issued[peer].revision != _revision:
		return _reject("视图已过期")
	var before:Dictionary = EffectManager.runtime_guard_status()
	if not before.paused:
		return _reject("当前没有暂停的规则执行")
	# 审计故障是可消费的拒绝，不允许真实管理入口伪报成功。
	var audit = preload("res://scripts/match/match_journal.gd")
	if not confirm_audit(): return _reject("事务审计不可用，管理操作未确认")
	var actor:int = observer_for(peer)
	var accepted:bool = false
	if action == "guard_continue":
		accepted = EffectManager.resume_runtime_guard()
	elif action == "guard_skip":
		if not EffectManager.skip_runtime_guard():
			# 恢复后提交审计失败时仍废弃旧视图，不将失败误报为无状态变化。
			if not audit.audit_error.is_empty(): _revision += 1
			return _reject("事务审计写入失败，回滚未确认" if not audit.audit_error.is_empty() else "缺少完整回滚检查点，不能跳过效果")
		accepted = true
	elif action == "guard_restart":
		accepted = restart_guarded_match()
	elif action == "guard_lobby":
		GameStart.end_session()
		driver = preload("res://scripts/match/match_driver.gd").new()
		_context = null
		started = false
		controllers.clear()
		_issued.clear()
		_restart_selection.clear()
		_restart_guard.clear()
		_restart_seed = null
		preload("res://scripts/match/rule_random.gd").stop_tracking()
		accepted = true
	if not accepted:
		if not audit.audit_error.is_empty():
			_revision += 1
			return _reject("事务审计写入失败，管理操作未确认")
		return _reject(error if not error.is_empty() else "当前没有可继续的规则执行")
	if not confirm_audit():
		_revision += 1
		return _reject("事务审计写入失败，管理操作未确认")
	GameLog.record("room_management", actor, -1, "", null, [action],
		{"action": action, "peer": peer, "view_seq": sequence,
		"paused_before": before.paused, "paused_after": EffectManager.runtime_guard_status().paused})
	_revision += 1
	return true

func step(delta: float) -> bool:
	if not confirm_audit(): return false
	var changed:bool = _step(delta)
	if not confirm_audit():
		_revision += 1
		return false
	return changed

func _step(delta: float) -> bool:
	if _archive_pulse_running:
		return false
	if _archive_changed:
		_archive_changed = false
		return true
	if not started or EffectManager.runtime_guard_status().paused:
		return false
	if GameProgress.is_battle_broadcast_pending():
		return _step_broadcast_confirmation(delta)
	var changed:bool = false
	if recorder == null or not recorder._recording:
		changed = driver.answer_pending_for_bots()
		changed = driver.step(delta) or changed
	else:
		# 每个答复重新读取下一份等待，不把跨答复失效的对象带入日志。
		var effect = EffectManager.get_pending_active_effect()
		if effect != null and driver.seats.is_ai(effect._trigger_player_id):
			changed = bool(_run_recorded_driver("answer_effect")) or changed
		for kind in ["card", "player", "location"]:
			if _archive_pulse_running: break
			var pending:Dictionary = EffectManager.call("get_pending_" + kind + "_selection")
			if driver._bot_owns_request(pending):
				changed = bool(_run_recorded_driver("answer_" + kind)) or changed
		if not _archive_pulse_running:
			var action:String = driver.prepare_step(delta)
			if action == "end_current_player_action":
				changed = bool(_run_command(action, [])) or changed
			elif action == "ai_turn":
				_run_recorded_driver(action, [GameProgress.current_player_id])
				changed = true
	if changed:
		_revision += 1
	return changed

## 屏障期间只处理显式 AI 控制席；真人、断线真人、未知控制声明均不托管。
func _step_broadcast_confirmation(delta: float) -> bool:
	if not _broadcast_confirmation: return false
	var batch: int = GameProgress.battle_broadcast_batch_id()
	if batch != _broadcast_batch:
		_broadcast_batch = batch
		_broadcast_ai_elapsed = 0.0
	_broadcast_ai_elapsed += maxf(0.0, delta)
	if _broadcast_ai_elapsed < BROADCAST_AI_CONFIRM_STEP: return false
	for seat in GameProgress.battle_broadcast_confirmers():
		if not controllers.has(seat) or not controllers[seat] is int or controllers[seat] != 0: continue
		if not GameProgress.can_confirm_battle_broadcast(seat, batch): continue
		_broadcast_ai_elapsed = 0.0
		_run_command("confirm_battle_broadcast", [seat])
		_revision += 1
		return true
	return false

func _run_command(kind:String, args:Array, requested_context:Variant = null):
	var audit = preload("res://scripts/match/match_journal.gd")
	var source: SessionContext = requested_context as SessionContext if requested_context != null else _context
	if not SessionGeneration.validate_context(source).get("ok", false):
		return _reject("对局来源已失效")
	if not confirm_audit(): return _reject("事务审计不可用，操作未确认")
	var result
	if recorder == null or not recorder._recording:
		if kind == "end_current_player_action":
			result = GameProgress.end_current_player_action(source)
		else:
			var forwarded: Array = args.duplicate()
			if kind in ["submit_group", "request_manual_activation", "set_card_concealed", "deploy", "move", "deploy_to_area", "submit_option_choice", "submit_active_choice", "cancel_pending_choice", "submit_card_selection", "submit_player_selection", "submit_location_selection"]:
				forwarded.append(source)
			result = commands.callv(kind, forwarded)
	else:
		result = _run_recorded_driver(kind, args)
	if not confirm_audit():
		_revision += 1
		return _reject("事务审计写入失败，操作未确认")
	return result

func _run_recorded_driver(kind:String, args:Array = []):
	if not confirm_audit():
		return _reject("事务审计不可用，录制动作未确认")
	var result = recorder.perform(kind, args)
	if not recorder.error.is_empty():
		# 保留最后可信日志，不重做可能已经生效的动作；停止录制后仍使用原引擎。
		error = "存档录制已停止：" + recorder.error
		recorder.close()
		_revision += 1
		return false
	if not confirm_audit():
		_revision += 1
		return _reject("事务审计写入失败，录制动作未确认")
	if GameProgress.current_player_id < 0 and not GameProgress.is_game_over:
		_advance_archive_frames()
	return result

func _advance_archive_frames() -> void:
	var serial:int = _archive_serial
	_archive_pulse_running = true
	await recorder.pulse()
	if serial != _archive_serial: return
	_archive_pulse_running = false
	if not recorder.error.is_empty(): recorder.close()
	if not confirm_audit():
		_revision += 1
		return
	_revision += 1
	_archive_changed = true

func close_archive() -> bool:
	var confirmed:bool = confirm_audit()
	if _management_journal != null:
		if not _management_journal.flush(): confirmed = false
		_management_journal.close()
		_management_journal = null
	_archive_serial += 1
	if recorder != null and not recorder.close(): confirmed = false
	_archive_pulse_running = false
	_archive_changed = false
	return confirmed

## 只接受调用方显式绑定；存档是本机来源，原档只读，新目录独立续写。
func restore_archive(source:String, bindings:Dictionary, target:String, maintenance:Callable = Callable()) -> bool:
	error = ""
	if not confirm_audit(): return false
	if restore_failed_closed or started or _archive_pulse_running or target.is_empty() or DirAccess.dir_exists_absolute(target) or FileAccess.file_exists(target):
		return _reject("当前不能恢复，或续写目录已存在")
	var parsed:Dictionary = preload("res://scripts/match/match_journal.gd").new().read_all(source.path_join("match.log"), maintenance)
	if not parsed.ok or parsed.records.is_empty():
		return _reject(str(parsed.error) if not parsed.ok else "恢复存档没有初始记录")
	var header:Dictionary = parsed.records[0]
	var validation:Dictionary = preload("res://scripts/net/session/recovery_seat_bindings.gd").validate(header, bindings)
	if not validation.ok:
		return _reject(validation.error)
	var journal_script = preload("res://scripts/match/match_journal.gd")
	if GameStart._started or journal_script.audit_writer != null or journal_script.audit_replaying:
		return _reject("全局规则或录制器仍活跃，拒绝覆盖原局")
	var previous_environment:Dictionary = ContentEnvironment.install(LoadHelper.session_data_dir, LoadGame.stored_jsons_path)
	var candidate = preload("res://scripts/match/match_replay.gd").new()
	_restore_stage("replay_begin")
	var accepted:bool = await candidate.restore(source, maintenance)
	_restore_stage("replay_end")
	if accepted:
		_restore_stage("save_restored_begin")
		accepted = candidate.save_restored_as(target, maintenance)
		_restore_stage("save_restored_end")
	if accepted:
		_restore_stage("resume_recording_begin")
		accepted = candidate.resume_recording(maintenance)
		_restore_stage("resume_recording_end")
	if not accepted or not confirm_audit():
		var reason:String = candidate.error
		if reason.is_empty(): reason = "事务审计写入失败，恢复未确认"
		candidate.close()
		restore_failed_closed = true
		ContentEnvironment.restore(previous_environment)
		GameStart.end_session()
		journal_script.reset_audit_memory()
		return _reject(reason)
	recorder = candidate
	driver = recorder.driver
	_context = driver.source_context
	if not SessionGeneration.validate_context(_context).get("ok", false):
		candidate.close()
		restore_failed_closed = true
		ContentEnvironment.restore(previous_environment)
		GameStart.end_session()
		journal_script.reset_audit_memory()
		return _reject("恢复未建立可验证的规则来源")
	builder = preload("res://scripts/match/view_builder.gd").new()
	seat_query = preload("res://scripts/match/match_seat_query.gd").new(builder)
	_configure_controllers(bindings)
	_management_folder = target
	if not _apply_broadcast_declaration():
		candidate.close()
		restore_failed_closed = true
		ContentEnvironment.restore(previous_environment)
		GameStart.end_session()
		journal_script.reset_audit_memory()
		return _reject("播报能力声明审计失败，恢复未确认")
	_issued.clear()
	_restart_selection = {"player_ids":header.players.duplicate(), "assignments":header.assignments.duplicate(true), "order":header.order.duplicate(), "controllers":bindings.duplicate()}
	_restart_guard = header.get("runtime_guard", {}).duplicate(true)
	_restart_seed = header.seed
	_begin_notification_lifecycle()
	started = true
	_revision += 1
	return true

func _restore_stage(stage:String) -> void:
	if OS.get_environment("FD_RESTORE_STAGE_TIMING") != "1": return
	print("RESTORE_SEGMENT pid=", OS.get_process_id(), " ticks_usec=", Time.get_ticks_usec(), " stage=", stage)

func pending_for(peer: int) -> Dictionary:
	var seat := observer_for(peer)
	if not started or seat < 0:
		return {}
	return seat_query.pending(seat)

## 提示仅用于呈现；所有提交仍执行当前时刻的规则校验。
func preview_group(peer: int, sequence: int, card_ids: Array, hidden: Array) -> Dictionary:
	var seat := observer_for(peer)
	if not started or seat < 0 or not _issued.has(peer):
		return {"ok": false}
	if sequence != _issued[peer].seq or _issued[peer].revision != _revision:
		return {"ok": false}
	if card_ids.size() != hidden.size():
		return {"ok": false}
	var cards: Array = []
	var flags: Array = []
	for index in range(card_ids.size()):
		if not card_ids[index] is int or not hidden[index] is bool:
			return {"ok": false}
		var card = builder.ids.object_for(card_ids[index])
		cards.append(card)
		flags.append(hidden[index])
	var result:Dictionary = seat_query.preview(seat, cards, flags)
	if result.get("ok", false): result.view_seq = sequence
	return result

func actions_for(peer: int) -> Dictionary:
	var seat := observer_for(peer)
	if not started or seat < 0:
		return {}
	return seat_query.actions(seat)

func _reject(reason: String) -> bool:
	error = reason
	return false
