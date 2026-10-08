class_name NetworkMatchAuthority
extends RefCounted

var driver = preload("res://scripts/match/match_driver.gd").new()
var builder = preload("res://scripts/match/view_builder.gd").new()
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
var recorder
var _archive_pulse_running:bool = false
var _archive_changed:bool = false
var _archive_serial:int = 0
static var _start_busy:bool = false

## 权威提交闸：审计故障不可转换为动作/管理成功，也不可退回无录制推进。
func confirm_audit() -> bool:
	if preload("res://scripts/match/match_journal.gd").flush_audit(): return true
	EffectManager._guard_audit_failed(EffectManager.runtime_guard_effect())
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
	if not confirm_audit():
		return _reject("事务审计写入失败，启动未确认")
	_configure_controllers(selection.controllers)
	started = true
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
	driver.seats.default_kind = driver.seats.VACANT
	for seat in controllers:
		driver.seats.set_kind(seat, driver.seats.AI if controllers[seat] == 0 else driver.seats.REMOTE)

func view_for(peer: int) -> Dictionary:
	if not started:
		return {}
	var view: Dictionary = builder.build(observer_for(peer))
	_issued[peer] = {"seq": view.seq, "revision": _revision}
	return view

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
	var seat := observer_for(peer)
	if not started or seat < 0 or not _issued.has(peer):
		return _reject("连接没有可操作座位")
	if sequence != _issued[peer].seq or _issued[peer].revision != _revision:
		return _reject("视图已过期")
	if _archive_pulse_running:
		return _reject("正在结算回合，请等待最新视图")
	if EffectManager.runtime_guard_status().paused:
		return _reject("规则执行已暂停，等待房主处理")
	if kind == "cancel_choice":
		if args.size() != 1 or not args.get("effect") is int:
			return _reject("取消参数无效")
		var effect = builder.ids.object_for(args.effect)
		if not effect is BaseEffect or effect._trigger_player_id != seat:
			return _reject("不能取消其他玩家的选择")
		if not _run_command("cancel_pending_choice", [effect]):
			return _reject("该选择当前不允许取消")
		_revision += 1
		return true
	if kind == "location_choice":
		if args.size() != 2 or not args.get("effect") is int or not args.get("area") is int:
			return _reject("位置选择格式无效")
		var pending: Dictionary = EffectManager.get_pending_location_selection()
		var effect = builder.ids.object_for(args.effect)
		if not effect is BaseEffect or pending.get("effect") != effect or effect._trigger_player_id != seat:
			return _reject("当前位置选择不属于该座位")
		var locations: Dictionary = _location_candidates(pending)
		if not locations.has(args.area):
			return _reject("目标战区不满足位置选择规则")
		var accepted: bool = bool(_run_command("submit_location_selection", [effect, locations[args.area]]))
		_revision += 1
		return accepted
	if kind == "activate":
		if args.size() != 1 or not args.get("effect") is int:
			return _reject("发动参数无效")
		var effect = builder.ids.object_for(args.effect)
		if not effect is BaseEffect or not EffectManager.can_manual_activate(effect, seat):
			return _reject("该能力当前不可发动")
		var accepted: bool = bool(_run_command("request_manual_activation", [effect, seat]))
		_revision += 1
		return accepted
	if kind == "player_choice":
		if args.size() != 2 or not args.get("effect") is int or not args.get("players") is Array:
			return _reject("目标选择格式无效")
		var pending: Dictionary = EffectManager.get_pending_player_selection()
		var effect = builder.ids.object_for(args.effect)
		if not effect is BaseEffect or pending.get("effect") != effect or effect._trigger_player_id != seat:
			return _reject("当前目标选择不属于该座位")
		var low: int = int(pending.spec.get("min", 1))
		var high: int = int(pending.spec.get("max", low))
		if args.players.size() < low or (high != -1 and args.players.size() > high):
			return _reject("目标数量不符合声明")
		var picked: Array = []
		for id in args.players:
			if not id is int or not pending.candidates.has(id) or picked.has(id):
				return _reject("目标不在候选集或重复")
			picked.append(id)
		var accepted: bool = bool(_run_command("submit_player_selection", [effect, picked]))
		_revision += 1
		return accepted
	if kind == "card_choice":
		if args.size() != 2 or not args.get("effect") is int or not args.get("cards") is Array:
			return _reject("选牌答复格式无效")
		var pending: Dictionary = EffectManager.get_pending_card_selection()
		var effect = builder.ids.object_for(args.effect)
		if not effect is BaseEffect or pending.get("effect") != effect or effect._trigger_player_id != seat:
			return _reject("当前选牌不属于该座位")
		var cards: Array = []
		for id in args.cards:
			if not id is int:
				return _reject("候选 ID 类型无效")
			var card = builder.ids.object_for(id)
			if not card is BaseCard:
				return _reject("候选卡牌不存在")
			cards.append(card)
		if not EffectManager._is_card_selection_valid(pending, pending.cards, cards, pending.required_cards):
			return _reject("选牌不满足当前候选或数量要求")
		var accepted: bool = bool(_run_command("submit_card_selection", [effect, cards]))
		_revision += 1
		return accepted
	if kind == "option_choice":
		if args.size() != 2 or not args.get("effect") is int or not args.get("choices") is Array:
			return _reject("选项答复格式无效")
		var effect = builder.ids.object_for(args.effect)
		if not effect is BaseEffect or effect != EffectManager.get_pending_active_effect() or effect._trigger_player_id != seat:
			return _reject("当前效果不等待该座位答复")
		var selection: Dictionary = {}
		var quantities: Dictionary = {}
		for choice in args.choices:
			if not choice is Dictionary or not choice.get("index") is int or not choice.get("count") is int:
				return _reject("选项次数格式无效")
			var index: int = choice.index
			if index < 0 or index >= effect._options.size() or selection.has(index) or choice.count <= 0:
				return _reject("选项下标或次数无效")
			var option: Dictionary = effect._options[index]
			if option.has("quantity_range"):
				var bounds = option.quantity_range
				if not bounds is Array or bounds.size() != 2 or not choice.get("quantity") is int:
					return _reject("缺少声明要求的数量")
				if choice.quantity < bounds[0] or choice.quantity > bounds[1]:
					return _reject("数量超出声明范围")
				quantities[index] = choice.quantity
			elif choice.has("quantity"):
				return _reject("选项未声明数量")
			selection[index] = choice.count
		if selection.is_empty():
			return _reject("取消应通过放弃入口提交")
		if not EffectManager.validate_selection(effect, selection):
			return _reject("选项次数不满足现有规则")
		var accepted: bool = bool(_run_command("submit_option_choice", [effect, selection, quantities]))
		_revision += 1
		return accepted
	if kind == "active_choice":
		if args.size() != 2 or not args.get("effect") is int or not args.get("activate") is bool:
			return _reject("效果答复格式无效")
		var effect = builder.ids.object_for(args.effect)
		if not effect is BaseEffect or effect != EffectManager.get_pending_active_effect() or effect._trigger_player_id != seat:
			return _reject("当前效果不等待该座位答复")
		# 选项类发动必须另走明确的选项提交，不用布尔确认绕过选项。
		if args.activate and effect.has_options():
			return _reject("必须提交具体选项")
		var accepted: bool = bool(_run_command("submit_active_choice", [effect, args.activate]))
		_revision += 1
		return accepted
	if kind == "set_concealed":
		if args.size() != 2 or not args.get("card") is int or not args.get("concealed") is bool:
			return _reject("翻面参数无效")
		var card = builder.ids.object_for(args.card)
		if not _flip_modes(seat, card).has(args.concealed):
			return _reject("该牌当前不允许翻面")
		_run_command("set_card_concealed", [card, args.concealed, seat])
		_revision += 1
		return true
	if GameProgress.current_player_id != seat:
		return _reject("尚未轮到该座位")
	match kind:
		"move":
			if args.size() != 1 or not args.get("area") is int or EffectManager.is_waiting_for_choice() or not GameProgress.is_phase_for(seat, "action"):
				return _reject("当前不能常规移动")
			var target = builder.ids.object_for(args.area)
			if not target is BaseMapArea or not MapData.areas.has(target):
				return _reject("移动目标不存在")
			var target_index: int = MapData.areas.find(target)
			var reason: String = driver.LocationQuery.area_action_block_reason_for(seat, target_index)
			if not reason.is_empty():
				return _reject(reason)
			var data: Dictionary = GameDataManager.get_player_data(seat)
			var origin: BaseLocation = data.get("location")
			var steps: int = target_index - MapData.areas.find(origin.get_from())
			_run_command("move", [steps, seat])
			_revision += 1
			return data.get("location") != origin
		"play_group":
			if args.size() != 2 or not args.get("cards") is Array or not args.get("hidden") is Array or EffectManager.is_waiting_for_choice():
				return _reject("出牌参数无效或正在等待效果")
			if args.cards.is_empty() or args.cards.size() != args.hidden.size():
				return _reject("牌组与明暗数量不匹配")
			var cards: Array = []
			for index in range(args.cards.size()):
				if not args.cards[index] is int or not args.hidden[index] is bool:
					return _reject("牌组字段类型无效")
				var card = builder.ids.object_for(args.cards[index])
				if not card is BaseHandCard or cards.has(card):
					return _reject("牌对象无效或重复")
				cards.append(card)
			if not _run_command("submit_group", [seat, cards, args.hidden]):
				return _reject("牌组不满足现有出牌规则")
		"end_action":
			if not args.is_empty() or not _run_command("end_current_player_action", []):
				return _reject("当前不能结束行动")
		"deploy":
			if args.size() != 1 or not args.get("area") is int or EffectManager.is_waiting_for_choice():
				return _reject("部署参数无效或正在等待效果")
			if not GameProgress.is_phase_for(seat, "outpost") or GameDataManager.get_player_data(seat).get("location") != null:
				return _reject("当前不能部署")
			var area = builder.ids.object_for(args.area)
			if not area is BaseMapArea or not DeployRules.deployable_areas().has(area):
				return _reject("目标战区不可部署")
			if not _run_command("deploy_to_area", [area, seat]):
				return _reject("部署失败")
		_:
			return _reject("不支持该对局指令")
	_revision += 1
	return true

## 房间管理权由会话按真实连接校验，此处只校验对局与续行版本。
func guard_diagnostic() -> Dictionary:
	var effect = EffectManager.runtime_guard_effect()
	if effect == null:
		return {}
	var source = GetEffSourceCard.new().exec(effect)
	var origin = EffectManager.runtime_guard_root_effect()
	if source == null and origin != null and origin != effect:
		source = GetEffSourceCard.new().exec(origin)
	var pid:int = EffectManager._effect_fact_actor_id(effect)
	var data:Dictionary = GameData.player_data_library.get(pid, {})
	var source_name:String = source.get_shown_name() if source != null else EffectManager._effect_source_name(effect)
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
	_issued.clear()
	started = false
	# 结束会话会重载模板；只使用重载后的对象，不复用旧局引用。
	var assignments:Dictionary = _resolve_restart_assignments()
	if assignments.is_empty():
		return false
	preload("res://scripts/match/rule_random.gd").start_seed(_restart_seed)
	if not GameStart.game_start(_restart_selection.player_ids, assignments, _restart_selection.order, _restart_guard):
		return _reject("引擎拒绝重开对局")
	if not confirm_audit():
		return _reject("事务审计写入失败，重开未确认")
	_configure_controllers(_restart_selection.controllers)
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

func _run_command(kind:String, args:Array):
	var audit = preload("res://scripts/match/match_journal.gd")
	if not confirm_audit(): return _reject("事务审计不可用，操作未确认")
	var result
	if recorder == null or not recorder._recording:
		result = commands.callv(kind, args)
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
	var previous_root:String = LoadHelper.session_data_dir
	var previous_cache:String = LoadGame.stored_jsons_path
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
		LoadHelper.session_data_dir = previous_root
		LoadGame.stored_jsons_path = previous_cache
		GameStart.end_session()
		journal_script.reset_audit_memory()
		return _reject(reason)
	recorder = candidate
	driver = recorder.driver
	builder = preload("res://scripts/match/view_builder.gd").new()
	_configure_controllers(bindings)
	_issued.clear()
	_restart_selection = {"player_ids":header.players.duplicate(), "assignments":header.assignments.duplicate(true), "order":header.order.duplicate(), "controllers":bindings.duplicate()}
	_restart_guard = header.get("runtime_guard", {}).duplicate(true)
	_restart_seed = header.seed
	started = true
	_revision += 1
	return true

func _restore_stage(stage:String) -> void:
	if OS.get_environment("FD_RESTORE_STAGE_TIMING") != "1": return
	print("RESTORE_SEGMENT pid=", OS.get_process_id(), " ticks_usec=", Time.get_ticks_usec(), " stage=", stage)

func pending_for(peer: int) -> Dictionary:
	var seat := observer_for(peer)
	var location_pending: Dictionary = EffectManager.get_pending_location_selection()
	if started and seat >= 0 and not location_pending.is_empty() and location_pending.effect._trigger_player_id == seat:
		return {"kind": "location_choice", "effect": builder.ids.id_for(location_pending.effect), "label": location_pending.effect.get_shown_name(), "areas": _location_candidates(location_pending).keys(), "allow_cancel": location_pending.allow_cancel}
	var player_pending: Dictionary = EffectManager.get_pending_player_selection()
	if started and seat >= 0 and not player_pending.is_empty() and player_pending.effect._trigger_player_id == seat:
		var low: int = int(player_pending.spec.get("min", 1))
		return {"kind": "player_choice", "effect": builder.ids.id_for(player_pending.effect), "label": player_pending.effect.get_shown_name(), "players": player_pending.candidates.duplicate(), "min": low, "max": int(player_pending.spec.get("max", low)), "allow_cancel": player_pending.allow_cancel}
	var card_pending: Dictionary = EffectManager.get_pending_card_selection()
	if started and seat >= 0 and not card_pending.is_empty() and card_pending.effect._trigger_player_id == seat:
		var cards: Array = []
		var required: Array = []
		for card in card_pending.cards:
			cards.append(builder.ids.id_for(card))
		for card in card_pending.required_cards:
			required.append(builder.ids.id_for(card))
		return {"kind": "card_choice", "effect": builder.ids.id_for(card_pending.effect), "label": str(card_pending.shown_name), "cards": cards, "required": required, "min": card_pending.min, "max": card_pending.max, "allow_cancel": card_pending.allow_cancel}
	var effect: BaseEffect = EffectManager.get_pending_active_effect()
	if not started or seat < 0 or effect == null or effect._trigger_player_id != seat:
		return {}
	var options: Array = []
	for index in range(effect._options.size()):
		var option: Dictionary = effect._options[index]
		var item := {"index": index, "label": str(option.get("shown_option_name", "")), "available": EffectManager.is_option_available(effect, index)}
		if option.has("quantity_range"):
			item.quantity_range = option.quantity_range.duplicate()
		options.append(item)
	return {"kind": "active_choice", "effect": builder.ids.id_for(effect), "label": effect.get_shown_name(), "allow_cancel": EffectManager.choice_allows_cancel(effect), "options": options}

## 提示仅用于呈现；所有提交仍执行当前时刻的规则校验。
func preview_group(peer: int, sequence: int, card_ids: Array, hidden: Array) -> Dictionary:
	var seat := observer_for(peer)
	if not started or seat < 0 or not _issued.has(peer):
		return {"ok": false}
	if sequence != _issued[peer].seq or _issued[peer].revision != _revision or GameProgress.current_player_id != seat:
		return {"ok": false}
	if EffectManager.is_waiting_for_choice() or not GameProgress.is_phase_for(seat, "action") or card_ids.size() != hidden.size():
		return {"ok": false}
	var available: Array = RegularPlay.candidates(seat)
	var cards: Array = []
	var flags: Array = []
	for index in range(card_ids.size()):
		if not card_ids[index] is int or not hidden[index] is bool:
			return {"ok": false}
		var card = builder.ids.object_for(card_ids[index])
		if not available.has(card) or cards.has(card):
			return {"ok": false}
		cards.append(card)
		flags.append(hidden[index])
	var candidates: Array = []
	for card in available:
		if cards.has(card):
			continue
		var modes: Array = RegularPlay.pending_modes(seat, cards, flags, card)
		if not modes.is_empty():
			candidates.append({"id": builder.ids.id_for(card), "modes": modes})
	return {"ok": true, "view_seq": sequence, "candidates": candidates, "can_submit": RegularPlay.can_submit_group(seat, cards, flags)}

func actions_for(peer: int) -> Dictionary:
	var seat := observer_for(peer)
	if not started or seat < 0 or GameProgress.is_game_over:
		return {}
	var result := {"deploy_areas": [], "move_areas": [], "move_costs": {}, "cards": [], "effects": [], "flip_cards": [], "can_end": false}
	if EffectManager.is_waiting_for_choice():
		return result
	for effect in EffectManager.manual_activations(seat):
		result.effects.append({"id": builder.ids.id_for(effect), "label": effect.get_shown_name()})
	for card in RegularPlay.candidates(seat):
		var flip_modes: Array = _flip_modes(seat, card)
		if not flip_modes.is_empty():
			result.flip_cards.append({"id": builder.ids.id_for(card), "modes": flip_modes})
	if GameProgress.current_player_id != seat:
		return result
	result.can_end = GameProgress.can_end_current_player_action()
	var data: Dictionary = GameDataManager.get_player_data(seat)
	if GameProgress.is_phase_for(seat, "outpost") and data.get("location") == null:
		for area in DeployRules.deployable_areas():
			result.deploy_areas.append(builder.ids.id_for(area))
	if GameProgress.is_phase_for(seat, "action"):
		for area in MapData.areas:
			if driver.LocationQuery.area_action_block_reason_for(seat, MapData.areas.find(area)).is_empty():
				result.move_areas.append(builder.ids.id_for(area))
				var origin: BaseLocation = data.get("location")
				var steps: int = MapData.areas.find(area) - MapData.areas.find(origin.get_from())
				result.move_costs[str(builder.ids.id_for(area))] = driver.LocationQuery._estimate_move_cost(data, steps)
		for card in RegularPlay.candidates(seat):
			var modes: Array = RegularPlay.modes(seat, card)
			if not modes.is_empty():
				result.cards.append({"id": builder.ids.id_for(card), "modes": modes})
	return result

func _reject(reason: String) -> bool:
	error = reason
	return false

func _flip_modes(seat: int, card) -> Array:
	if GameProgress.is_game_over or EffectManager.is_waiting_for_choice() or not RegularPlay.candidates(seat).has(card):
		return []
	if card is BaseAttack and RegularPlay.in_play_zone(GameDataManager.get_player_data(seat), card):
		return [false, true]
	if card is BaseSkill and card._is_concealed and card._is_awakened:
		return [false]
	return []

func _location_candidates(pending: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	if not EffectManager._location_option_origin_allowed(pending.effect, pending.spec):
		return result
	var forbidden: Array = pending.spec.get("forbidden_target_areas", [])
	for area in MapData.areas:
		if forbidden.has(str(area._area_name)):
			continue
		var location = driver.LocationQuery._first_effect_location_target(area, pending.spec)
		if location != null:
			result[builder.ids.id_for(area)] = location
	return result
