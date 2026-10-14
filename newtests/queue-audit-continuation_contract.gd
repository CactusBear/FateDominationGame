extends Node
# 真实根事务、真实 writer 容量拒绝；不改审计私字段或伪造规则回调。
var checks:int = 0
var failures:Array = []
var context:SessionContext
var writer
var serial:int = 0
var retained:Array = []
var delivered:Array = []
var delivered_returns:Array = []
var observed_parent:BaseEffect

func on_fact(entry:Dictionary) -> void:
	if entry.get("type") == "effect":
		delivered.append(entry.get("object"))
		delivered_returns.append(observed_parent != null and observed_parent._self_vars.size() == 2 and observed_parent._self_vars[0] is Array and observed_parent._self_vars[1] == "tail")

func check(ok:bool, label:String) -> bool:
	checks += 1
	print("CHECK ", label, " ", ok)
	if not ok: failures.append(label)
	return ok

func setup(cap:int = 3, players:Array = [0,1,2]) -> BaseEffect:
	GameLog.unobserve_facts(on_fact)
	delivered.clear()
	delivered_returns.clear()
	if writer != null: MatchJournal.end_audit(writer)
	writer = null
	GameStart.end_session()
	var reset:Dictionary = GameData.reset_game_session([])
	if not check(reset.ok, "原生命周期创建"): return null
	context = reset.context
	for id in range(3):
		var data:Dictionary = GameData.new_player_data()
		data.order.number = id
		GameData.player_data_library[id] = data
	serial += 1
	writer = MatchJournal.begin_audit(OS.get_user_data_dir().path_join("queue-audit-%d-%d.log" % [OS.get_process_id(), serial]))
	if not check(writer != null, "真实审计writer"): return null
	var declarations:Array = LoadHelper.load_effects([{"effect_name":"queue_audit_root", "time_points":[], "priority":0,
		"is_pure_passive":true, "is_residue":false, "need_activate":false, "effect_numbers":[], "funcs":[]}], null, context)
	if not check(declarations.size() == 1, "可信原根工厂"): return null
	var parent:BaseEffect = declarations[0]
	retained.append(parent)
	if not check(EffectManager.register_effect(parent, 0), "原根登记"): return null
	if players.has(9): GameData.player_data_library[9] = {}
	parent._funcs = LoadHelper.load_funcs([
		{"func_name":"queue_optional_effect_for_players", "parameters":[players, [{"func_name":"store_value", "parameters":["answer"], "var_index":0}], "shown", "queue_audit_child", []], "var_index":0},
		{"func_name":"store_value", "parameters":["tail"], "var_index":1}], parent, context)
	if not check(parent._funcs.size() == 2, "原函数帧工厂"): return null
	# 文件header + start + 第1名child成功，真实第2名child append被容量门拒绝。
	writer.max_records = cap
	observed_parent = parent
	GameLog.observe_facts(on_fact)
	EffectManager.activate_effect(parent)
	return parent

func children() -> Array:
	var result:Array = []
	for effect in GameData.effects:
		if effect is BaseEffect and effect._name == "queue_audit_child": result.append(effect)
	return result

func repair() -> void:
	# 仅撤除公开容量测试故障；不改游标、审计链、receipt、事务或规则状态。
	writer.max_records = MatchJournal.AUDIT_MAX_RECORDS
	writer.error = ""
	MatchJournal.audit_error = ""

func recover() -> void:
	var parent:BaseEffect = setup()
	if parent == null: return
	var initial:Array = children()
	check(EffectManager.runtime_guard_status().paused and MatchJournal.audit_error == "事务审计容量已满，拒绝追加", "第N玩家真实登记审计失败暂停")
	check(initial.size() == 2 and EffectManager.decision_queue.size() == 1, "只创建前缀与第N待续对象")
	check(parent._self_vars.is_empty(), "暂停不发布父部分返回或后续步骤")
	if initial.size() != 2: return
	var prefix:BaseEffect = initial[0]
	var pending:BaseEffect = initial[1]
	check(EffectManager.effect_pool.has(prefix) and not EffectManager.effect_pool.has(pending) and not EffectManager.decision_queue.has(pending), "未登记对象绝不发布")
	check(EffectManager.runtime_guard_root_effect() == parent and EffectManager.runtime_guard_effect() == parent, "守卫保原根不冒充child")
	var transaction = EffectManager.capture_transaction_state().transaction_bindings.get(parent)
	check(transaction != null and transaction.root == parent and not transaction.settled, "真实原根事务持有")
	var before_audit:Array = MatchJournal.audit_records.duplicate(true)
	check(before_audit.size() == 2 and before_audit[0].event == "start" and before_audit[1].event == "child", "第N失败未产生成功child审计")
	await get_tree().process_frame
	check(delivered.is_empty() and GameLog.query({"type":"effect"},null,-1).is_empty(), "故障期间不发成功事实通知")
	repair()
	var accepted:bool = EffectManager.resume_runtime_guard()
	check(accepted and not EffectManager.runtime_guard_status().paused, "公开恢复完成原生尾部")
	var final_children:Array = children()
	check(final_children.size() == 3 and final_children[0] == prefix and final_children[1] == pending, "已排队前缀与待续choice保identity不重建")
	check(parent._self_vars.size() == 2 and parent._self_vars[0] == final_children and parent._self_vars[1] == "tail", "父完整Array及后续步骤准确")
	var counts:Array = []
	for child in final_children:
		counts.append(child_audits(transaction,child))
	check(counts == [1,1,1], "成功前缀与每玩家登记审计恰一次")
	check(not EffectManager.resume_runtime_guard(), "重复公开resume拒绝")
	check(children() == final_children, "重复resume无第二次创建")
	await answer_all(parent,final_children)
	print("AUDIT_RECOVER ",JSON.stringify(MatchJournal.audit_records))

func child_audits(transaction, effect:BaseEffect) -> int:
	var count:int = 0
	for record in MatchJournal.audit_records:
		if record.event == "child" and record.root_id == transaction.transaction_id and record.effect_id == transaction.member_id(effect): count += 1
	return count

func answer_all(parent:BaseEffect, expected:Array) -> void:
	for child in expected:
		check(EffectManager.get_pending_active_effect() == child, "按原玩家顺序只选择一次")
		if EffectManager.get_pending_active_effect() != child: return
		check(EffectManager.submit_active_choice(child,true), "真实公开选择受理")
	check(not EffectManager.is_waiting_for_choice(), "所有玩家选择恰好结束")
	for child in expected:
		check(child._self_vars == ["answer"] and GameLog.query({"type":"effect","object":child},null,-1).size() == 1, "每玩家动作与事实恰一次")
		check(not EffectManager.submit_active_choice(child,true), "重复答复拒绝")
	check(GameLog.query({"type":"effect","object":parent},null,-1).size() == 1, "原父完成事实恰一次")
	await get_tree().process_frame
	await get_tree().process_frame
	check(delivered == [parent] + expected, "失败后通知顺序为完整父结果再逐玩家")
	check(delivered_returns == [true,true,true,true], "每次成功通知均可见完整父Array")
	var parsed:Dictionary = MatchJournal.new().read_all(OS.get_user_data_dir().path_join("queue-audit-%d-%d.log" % [OS.get_process_id(),serial]))
	check(parsed.ok and not parsed.truncated and MatchJournal.audit_chain(parsed.records).ok, "真实落盘审计链读回完整")
	var tickets:Dictionary = {}
	for record in MatchJournal.audit_records:
		if record.event == "tail_registered":
			check(not tickets.has(record.ticket_id), "每张尾票只登记一次")
			tickets[record.ticket_id] = false
		elif record.event == "tail_consumed":
			check(tickets.has(record.ticket_id) and not tickets.get(record.ticket_id,true), "每张尾票先登记再单次消费")
			tickets[record.ticket_id] = true
	check(not tickets.is_empty() and not tickets.values().has(false), "尾票登记消费一一对应")

func repeated_pause() -> void:
	var parent:BaseEffect = setup()
	if parent == null: return
	var initial:Array = children()
	if not check(initial.size() == 2,"再次暂停前真实第N失败"): return
	var snapshot:Dictionary = EffectManager.execution_runtime_snapshot()
	if not check(snapshot.suspended_functions.size() == 1,"保存真实父函数帧"): return
	var frame:Dictionary = snapshot.suspended_functions[0]
	var first_identity:RefCounted = frame.control.continuation
	var first_ticket = frame.native_tail
	var transaction = EffectManager.capture_transaction_state().transaction_bindings.get(parent)
	check(frame.stage == "native_pending" and is_same(frame.control.original_context,parent.runtime_context()) and first_identity != null, "PENDING控制与原context独立于业务返回")
	repair()
	# resume/tail_registered/tail_consumed/第2名child成功，第3名child再次真实失败。
	writer.max_records = 7
	check(not EffectManager.resume_runtime_guard() and EffectManager.runtime_guard_status().paused, "公开恢复遇下一玩家再次暂停")
	check(children().size() == 3 and parent._self_vars.is_empty(), "第二次暂停仍不发布父结果")
	check(EffectManager.effect_pool.has(initial[0]) and EffectManager.effect_pool.has(initial[1]) and not EffectManager.effect_pool.has(children()[2]), "第二次暂停成功前缀保原identity")
	if not check(frame.control.continuation != null and frame.control.continuation != first_identity and frame.has("native_tail") and frame.native_tail != first_ticket, "再次暂停换新控制身份和审计尾票"): return
	var second_ticket = frame.native_tail
	check(not MatchJournal.consume_tail(first_ticket.ticket_id,transaction.transaction_id), "首票已消费不得重放")
	check(not EffectManager.resume_runtime_guard(), "故障未修重复恢复拒绝不二次消费")
	var before:Array = children()
	var revision:int = MatchJournal.audit_revision
	check(not EffectManager.resume_runtime_guard() and children() == before and MatchJournal.audit_revision == revision, "失败重复恢复保持对象和审计次数")
	repair()
	check(EffectManager.resume_runtime_guard() and not EffectManager.runtime_guard_status().paused, "第二票公开恢复完成")
	check(children() == before and parent._self_vars.size() == 2 and parent._self_vars[0] == before, "多次恢复完整结果保持每个identity")
	check(not MatchJournal.consume_tail(second_ticket.ticket_id,transaction.transaction_id) and not EffectManager.resume_runtime_guard(), "第二票及最终resume均不可重放")
	var counts:Array = []
	for child in before: counts.append(child_audits(transaction,child))
	check(counts == [1,1,1], "再次暂停不重登记任何成功玩家")
	await answer_all(parent,before)
	print("AUDIT_REPEATED ",JSON.stringify(MatchJournal.audit_records))

func snapshot_rules() -> Array:
	return [GameData.objects.duplicate(),GameData.effects.duplicate(),EffectManager.effect_pool.duplicate(),EffectManager.decision_queue.duplicate(),GameLog.query({},null,-1),EffectManager.get_pending_active_effect()]

func replaced_member() -> void:
	var parent:BaseEffect = setup()
	if parent == null: return
	var original:Dictionary = GameData.player_data_library[1]
	GameData.player_data_library[1] = GameData.new_player_data()
	repair()
	var before:Array = snapshot_rules()
	var boundary:Dictionary = MatchJournal.audit_boundary()
	check(not EffectManager.resume_runtime_guard(), "等ID成员被替换拒绝原续行")
	check(snapshot_rules() == before and MatchJournal.audit_boundary() == boundary and parent._self_vars.is_empty(), "成员拒绝不写新owner不消费审计票")
	check(GameData.player_data_library[1].self_effects.is_empty(), "待续choice不迁移替换成员")
	GameData.player_data_library[1] = original

func detached_transaction() -> void:
	var parent:BaseEffect = setup()
	if parent == null: return
	var saved:Dictionary = EffectManager.capture_transaction_state(parent.runtime_context())
	var detached:Dictionary = saved.duplicate()
	detached.transaction_bindings = saved.transaction_bindings.duplicate()
	detached.transaction_bindings.erase(parent)
	# 只用既有公开恢复投影撤掉父绑定；不造checkpoint/receipt或改EM私字段。
	check(EffectManager.restore_transaction_state(detached,parent.runtime_context()), "公开事务投影产生父归属缺失负例")
	repair()
	var suspended:Array = EffectManager.execution_runtime_snapshot().suspended_functions
	if not check(suspended.size() == 1, "事务负例具有真实父帧"): return
	var frame:Dictionary = suspended[0]
	var identity:RefCounted = frame.control.continuation
	var before:Array = snapshot_rules()
	var boundary:Dictionary = MatchJournal.audit_boundary()
	check(not EffectManager.resume_runtime_guard(), "父实际事务绑定缺失拒绝恢复")
	check(frame.control.continuation == identity and frame.control.status == "PENDING", "事务拒绝发生在控制身份消费前")
	check(snapshot_rules() == before and MatchJournal.audit_boundary() == boundary and parent._self_vars.is_empty(), "事务归属拒绝不消费票不发布")
	check(EffectManager.restore_transaction_state(saved,parent.runtime_context()), "仅恢复本夹具公开原事务投影")

func stale_generation() -> void:
	var parent:BaseEffect = setup()
	if parent == null: return
	var old_context:SessionContext = parent.runtime_context()
	repair()
	SessionGeneration.invalidate_generation(&"queue_audit_test")
	var before:Array = snapshot_rules()
	var boundary:Dictionary = MatchJournal.audit_boundary()
	check(not EffectManager.resume_runtime_guard(), "原来源换代拒绝保留的真实帧")
	check(snapshot_rules() == before and MatchJournal.audit_boundary() == boundary, "失效帧不消费票或写规则")
	MatchJournal.end_audit(writer)
	writer = null
	GameStart.end_session()
	var reset:Dictionary = GameData.reset_game_session([])
	check(reset.ok and not SessionGeneration.validate_context(old_context).ok, "新局不复活原来源")
	for id in range(3): GameData.player_data_library[id] = GameData.new_player_data()
	before = snapshot_rules()
	check(not EffectManager.resume_runtime_guard() and snapshot_rules() == before, "旧恢复不会迁移到新局")

func ordinary_refusal() -> void:
	var parent:BaseEffect = setup(100,[])
	if parent == null: return
	GameData.player_data_library[9] = {}
	EffectManager.activating_eff = parent
	var outcome:Array = EffectManager.run_func_descriptor({"func_name":"queue_optional_effect_for_players", "parameters":[[9,0,1],[],"shown","queue_audit_child",[]]},parent,parent.runtime_context())
	EffectManager.activating_eff = null
	check(bool(outcome[0]) and not EffectManager.runtime_guard_status().paused and children().size() == 2, "普通登记拒绝仍跳过后续合法玩家")
	check(outcome[1] == children(), "普通拒绝保持原业务Array")
	check(GameData.player_data_library[9].is_empty(), "普通拒绝不修补成员")
	GameData.player_data_library.erase(9)

func unknown_native_parent() -> void:
	var parent:BaseEffect = setup(100,[])
	if parent == null: return
	var card = LoadAttack.resolve("strength:2",context)
	if not check(card != null,"未知native审计负例可信卡工厂"): return
	GameData.player_data_library[0].played_cards.append(card)
	card.set_concealed(true)
	var listeners:Array = LoadHelper.load_effects([{"effect_name":"unknown_parent_queue_listener", "time_points":[TimePoints.SELF_CARD_REVEALED], "priority":0,
		"is_pure_passive":true,"is_residue":false,"need_activate":false,"effect_numbers":[],
		"funcs":[{"func_name":"queue_optional_effect_for_players","parameters":[[0,1],[],"shown","queue_audit_child",[]]}]}],card,context)
	if not check(listeners.size() == 1 and EffectManager.register_effect(listeners[0],0),"未知native真实亮出监听登记"): return
	parent._funcs = LoadHelper.load_funcs([{"func_name":"set_card_concealed","parameters":[card,false,0,context]}],parent,context)
	writer.max_records = MatchJournal.audit_revision + 3
	EffectManager.activate_effect(parent)
	check(EffectManager.runtime_guard_status().paused and not MatchJournal.audit_error.is_empty(),"未知native内部真实child审计拒绝")
	var armed:bool = false
	for frame in EffectManager.execution_runtime_snapshot().suspended_functions:
		if frame.has("queue_origin"): armed = true
	check(not armed and EffectManager.execution_runtime_snapshot().guard_continuations.is_empty(),"未知native祖先不得借Queue获得尾部续行许可")
	check(children().size() == 1 and not EffectManager.effect_pool.has(children()[0]),"未知native审计拒绝仍保留未发布choice")

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	print("USER_PATH ", OS.get_user_data_dir())
	await recover()
	await repeated_pause()
	replaced_member()
	detached_transaction()
	stale_generation()
	ordinary_refusal()
	unknown_native_parent()
	GameLog.unobserve_facts(on_fact)
	if writer != null: MatchJournal.end_audit(writer)
	writer = null
	GameStart.end_session()
	print("RESULT ", JSON.stringify({"suite":"queue_audit_continuation", "checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
