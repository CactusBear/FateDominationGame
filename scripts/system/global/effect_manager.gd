extends Node


#效果系统的唯一入口：效果池登记、时点检查、询问顺序、优先级结算、时点关闭打断。
#注册为autoload"EffectManager"，所以不能再带class_name(两者会重名冲突)。
#GameProgress只负责游戏回合进程，不再持有任何效果处理逻辑。


#全局效果池。池中效果的_trigger_player_id即其归属玩家，-1表示还没进入游戏
var effect_pool:Array#[BaseEffect]
#选项级 select_cards 的 owner 取值：声明成它表示"挑先由 select_players 选定的那名玩家的牌"。
#不声明时挑的是触发者自己的牌，既有卡不受影响
const CARD_SELECTION_OWNER_TARGET := "target_player"
#当前正在结算的效果，供各effect脚本取上下文
var activating_eff:BaseEffect

#本时点的待决定队列。被动直接入池，主动逐个询问，两者按顺位交错排在同一条队列里
var decision_queue:Array#[BaseEffect]
#本时点确定要发动的效果，全部决定完后按优先级结算
var activation_pool:Array#[BaseEffect]
#正在等待其归属玩家答复的效果，非null时整条流程暂停
var waiting_effect:BaseEffect
#正在等待玩家挑具体牌张的效果（被选中的选项声明了 select_cards）。
#与 waiting_effect 并列的第二种等待：前者等"发动/放弃"，这里等"挑哪几张牌"；
#两者不会同时非null——选项提交先过 waiting_effect，再进选牌等待
var waiting_selection:BaseEffect = null
#正在等待选牌的那个选项下标（声明挂在选项字典里，所以要知道是第几项）
var _waiting_selection_option:int = -1
# {BaseEffect : Dictionary}，等选牌期间暂扣的选项提交，挑完牌再一起记用量/扣资源
var _pending_selection_choice:Dictionary = {}
#正在等待选择位置的效果。位置不是卡牌，独立于 select_cards，但同样在支付前等待。
var waiting_location:BaseEffect = null
var _pending_location_choice:Dictionary = {}
#正在等待选择玩家目标的效果（选项级 select_players）。与选牌/选位置并列的第三种玩家输入，
#同样在支付前等待：玩家取消或提交不在候选集里的目标时，效果等于没发动
var waiting_players:BaseEffect = null
var _pending_player_choice:Dictionary = {}
var matched_time_points:Dictionary
#{BaseEffect : int}，本时点已结算过的效果，避免同一时点内重复触发
var resolved_effects:Dictionary
#{player_id : Array[String]}，本时点被关闭的时点
var closed_time_points:Dictionary
#{BaseEffect : Array[BaseFunc]}，被反制的func，结算时跳过
var countered_funcs:Dictionary
#时点批次编号，每进入一个新时点递增
var time_point_id:int = 0
#结算中标记。结算过程里派发的新时点只追加效果，不另起批次
var is_running:bool = false
#待展示的提示消息队列：[{"text":String, "player_id":int}]，player_id=-1表示全员可见。
#operation只负责产生消息，界面取走并展示(取走即移除)，显示形态由界面决定
var messages:Array = []
# 两个展示 lane 共用身份水位，不属于规则状态；-1 表示 int64 已耗尽。
# reset 和事务回滚均不能复用已经发出的号。
class MessageRecordStream extends RefCounted:
	var _next_serial:int
	func _init(first_serial:int = 0) -> void:
		_next_serial = first_serial
	## 最新已分配身份；未分配为 -1，耗尽后保持 int64 最大值。
	func latest_allocated_serial() -> int:
		return 9223372036854775807 if _next_serial < 0 else _next_serial - 1
	func publish(text:String, player_id:int = -1) -> Dictionary:
		if text.is_empty(): return {}
		if _next_serial < 0:
			push_error("EffectManager message serial exhausted (int64); notification rejected")
			return {}
		var record:Dictionary = {"text":text, "player_id":player_id, "serial":_next_serial}
		# 最大值本身仍可分配，不执行会回绕的 +1。
		_next_serial = -1 if _next_serial == 9223372036854775807 else _next_serial + 1
		return record

var _message_serial:MessageRecordStream = MessageRecordStream.new()
## 只读共享消息水位；与队列是否已取走、reset 或规则回滚无关。
func latest_allocated_message_serial() -> int:
	return _message_serial.latest_allocated_serial()

#玩家资源字段的显示名。发动结果要写清"谁受到什么影响"，这些名字是玩家能核对的口径
const PLAYER_NUMERIC_FIELDS:Dictionary = {
	"magic": "魔力", "score": "战果", "command_spell_count": "令咒",
	"power": "合计威力", "total_power_bonus": "合计威力加成",
}
#对象上可被效果改动的数值字段的显示名（卡牌数值、状态层数、席位地利）
const OBJECT_NUMERIC_FIELDS:Dictionary = {
	"_power": "威力", "_cost": "魔力消耗", "_buff_level": "层数", "_benefit": "地利",
}
#牌区归属在规则状态快照里的字段名。它不是"对象的数值"，而是"这张牌此刻在谁手上、落在哪个区"，
#由 capture_rule_state 单独记一份，diff_rule_state 把它的前后差聚合成"手牌 → 弃牌堆 ×3"这类明细。
#没这一维时，弃牌/抽牌这类只改归属、不改数值的效果全都会显示"未产生即时变化"
const ZONE_FIELD:String = "zone"
#牌区路径各段的显示名：明细要写"手牌 → 弃牌堆"而不是内部键名 hand_cards/discard。
#路径由容器键拼成（side/skills 这类嵌套也表达得出来），这里只负责显示，不参与任何规则判定；
#没有登记中文名的段按原键名显示，不猜含义
const ZONE_SEGMENT_SHOWN:Dictionary = {
	"hand_cards": "手牌", "discard": "弃牌堆", "deck": "牌库", "played_cards": "打出区",
	"servant_skills": "从者技能区", "master_skills": "御主技能区", "command_spell": "令咒",
	"buffs": "状态", "out_of_game": "游戏外", "others": "附带物",
	"attacks": "攻击牌", "skills": "技能牌",
}
#手动发动成功后的独立结果队列。它与普通规则提示分开，界面用专门的“发动结果”弹窗展示，
#避免结果提示复用战术确认框并与下一条能力询问重叠。
var effect_results:Array = []

#本时点内累积的效果提示，按可见范围分桶 {player_id: [文案]}。
#战斗结算这类时点会连续触发一批效果，逐条推会把提示刷成一长串、还互相覆盖，
#所以先攒起来，等本时点整条管线跑完再合并成一条推送
var _pending_announcements:Dictionary = {}

# 返回待播报队列的只读值快照；不 flush、不消费，也不改变队列或其他运行时副作用。
func pending_announcements_snapshot() -> Dictionary:
	return _pending_announcements.duplicate(true)

# 玩家选择尚未完成时到达的后续时点批次；保存各玩家时点快照，答复后按顺序恢复处理。
var _queued_time_point_batches:Array = []
#执行中的一步提出、还没交给玩家的选择效果（request_choice 写入，那一步做完后取走）
var _pending_choices:Array = []
#{选择效果: {run: 暂停的那次执行, queue: 同一步里还没问的选择}}。选择结束后按它接着做
var _paused_runs:Dictionary = {}
# 等待资格是捕获记录，不由 getter 或提交现场补票。
var _waiting_origins:Dictionary = {}
var _function_frames:Array = []
var _active_runs:Array = []
var _runtime_guard = preload("res://scripts/match/rule_budget.gd").new()
var _guard_run:Dictionary = {}
var _guard_frames:Array = []
var _resume_frames:Array = []
# 每次登记拥有独立身份；相等 Callable 也不能共享事务归属。
class GuardContinuation extends RefCounted:
	var continuation:Callable
	var origin:Dictionary
	var ticket_id:int = MatchJournal.next_audit_identity()
	func _init(callback:Callable, captured:Dictionary) -> void:
		continuation = callback
		origin = captured

var _guard_continuations:Array = []
var _draining_guard_continuations:bool = false
var _guard_transactions:Dictionary = {}
var _transaction_scope = null
# 支付/同步回调的会话资格只由共享服务签发；主体 identity/事务身份仍各自独立。
const PAYMENT_BINDINGS_META:StringName = &"effect_payment_bindings"
const PAYMENT_SUBJECT_META:StringName = &"effect_payment_subject"
func _payment_session_token() -> SessionToken:
	# 兼容既有捕获点的纯查询，不在 metadata 中惰性创建第二套会话票。
	return preload("res://scripts/system/session_generation.gd").current_token().token

func _payment_subject_bindings() -> Array:
	if not has_meta(PAYMENT_BINDINGS_META): set_meta(PAYMENT_BINDINGS_META, [])
	return get_meta(PAYMENT_BINDINGS_META)
class PaymentSubject extends RefCounted:
	var data:Dictionary
	func _init(subject:Dictionary) -> void:
		data = subject
# 效果只弱持载体，避免 self_effects → effect → 玩家字典的引用环。
# 身份载体放 metadata，不进入可回滚规则字段。
var _continuation_transactions:Dictionary = {}
var _batch_transactions:Array = []

## 当前执行作用域的根效果身份；不暴露事务检查点或允许改变归属。
## 未处于事务回调时为 null，与暂停中的根效果查询语义不同。
func active_transaction_root() -> BaseEffect:
	return _transaction_scope.root if _transaction_scope != null else null

## 进程内事务归属令牌，不是持久化快照或完整规则检查点。
## 只隔离外层容器；检查点、批次、票据和 Callable 保持原引用身份。
func capture_transaction_state(context:SessionContext = null) -> Dictionary:
	context = _captured_function_context(context)
	return {"context":context,
		"transaction_bindings":_guard_transactions.duplicate(),
		"batch_transactions":_batch_transactions.duplicate(),
		"continuation_queue":_guard_continuations.duplicate(),
		"continuation_transactions":_continuation_transactions.duplicate()}

## 调用方须先完成规则对象图恢复；此处不回滚 guard、调用栈或审计身份计数。
## 先校验全部容器，错误令牌不得造成部分写入。
func restore_transaction_state(state:Dictionary, context:SessionContext = null) -> bool:
	var captured = context if context != null else state.get("context")
	if not state.get("transaction_bindings") is Dictionary or not state.get("batch_transactions") is Array or not state.get("continuation_queue") is Array or not state.get("continuation_transactions") is Dictionary:
		return false
	# A1-12 的无来源空投影没有可恢复执行资格：仅兼容成功 no-op，绝不清掉新图。
	if captured == null and state.transaction_bindings.is_empty() and state.batch_transactions.is_empty() and state.continuation_queue.is_empty() and state.continuation_transactions.is_empty(): return true
	if not SessionGeneration.validate_context(captured).ok: return false
	context = captured
	for effect in state.transaction_bindings:
		if not _effect_execution_status(effect, context).ok: return false
		var owner = state.transaction_bindings[effect]
		if owner == null or not _effect_execution_status(owner.root, context).ok: return false
	for registration in state.continuation_queue:
		if not registration is GuardContinuation or not _wait_origin_is_current(registration.origin): return false
	for registration in state.continuation_transactions:
		if not registration is GuardContinuation or not _wait_origin_is_current(registration.origin): return false
		var owner = state.continuation_transactions[registration]
		if owner == null or not _effect_execution_status(owner.root, context).ok: return false
	for record in state.batch_transactions:
		if not record is Dictionary or not SessionGeneration.validate_context(record.get("batch", {}).get("context")).ok: return false
		if not _wait_origin_is_current(record.batch.get("origin", {})): return false
		if record.get("transaction") == null or not _effect_execution_status(record.transaction.root, context).ok: return false
	_guard_continuations = state.continuation_queue.duplicate()
	_guard_transactions = state.transaction_bindings.duplicate()
	_batch_transactions = state.batch_transactions.duplicate()
	_continuation_transactions = state.continuation_transactions.duplicate()
	return true

## 隔离暂停记录外层，允许消费者替换 run 投影；嵌套执行状态仍保留引用。
func paused_runs_snapshot() -> Dictionary:
	var paused:Dictionary = {}
	for choice in _paused_runs:
		paused[choice] = _paused_runs[choice].duplicate()
	return paused

func _settle_idle_guard_transactions() -> void:
	var busy:Array = []
	var candidates:Array = decision_queue + activation_pool + _pending_choices + _paused_runs.keys()
	candidates.append_array([waiting_effect, waiting_selection, waiting_location, waiting_players])
	for active in _active_runs: candidates.append(active.run.effect)
	for effect in candidates:
		var owner = _guard_transactions.get(effect)
		if owner != null and not busy.has(owner): busy.append(owner)
	for owner in _continuation_transactions.values():
		if not busy.has(owner): busy.append(owner)
	for batch in _batch_transactions:
		if not busy.has(batch.transaction): busy.append(batch.transaction)
	if _transaction_scope != null and not busy.has(_transaction_scope): busy.append(_transaction_scope)
	var idle:Array = []
	for owner in _guard_transactions.values():
		if not busy.has(owner) and not idle.has(owner): idle.append(owner)
	for owner in idle:
		if not owner.settled and not owner.audit("commit"):
			_runtime_guard.paused = true
			_runtime_guard.reason = "audit_write_failed"
			_guard_run = {"effect":owner.root}
			return
		owner.settled = true
		GameLog.commit_fact_transaction(owner.transaction_id)
		for effect in _guard_transactions.keys():
			if _guard_transactions[effect] == owner: _guard_transactions.erase(effect)

## 公开审计失败入口：仅标记 guard 故障，不恢复规则或提交事务。
func mark_guard_audit_failed(effect:BaseEffect) -> bool:
	return _guard_audit_failed(effect)


# 只处理审计故障，不执行规则恢复，也不提交或重新激活展示事实。
func _guard_audit_failed(effect:BaseEffect) -> bool:
	_runtime_guard.paused = true
	_runtime_guard.reason = "audit_write_failed"
	if _guard_run.is_empty(): _guard_run = {"effect":effect}
	return false

func _guard_audit_confirmed(effect:BaseEffect) -> bool:
	if not MatchJournal.flush_audit(): return _guard_audit_failed(effect)
	return true

func _begin_guard_transaction(effect:BaseEffect) -> bool:
	_remember_payment_subject(effect)
	if not MatchJournal.audit_error.is_empty(): return _guard_audit_failed(effect)
	if (not _runtime_guard.enabled and MatchJournal.audit_writer == null and not MatchJournal.audit_replaying) or effect == null or _guard_transactions.has(effect):
		return true
	if _transaction_scope != null:
		return _inherit_guard_transaction(effect)
	_settle_idle_guard_transactions()
	if not MatchJournal.audit_error.is_empty(): return _guard_audit_failed(effect)
	var checkpoint = preload("res://scripts/match/effect_checkpoint.gd").new(effect, _runtime_guard.enabled, effect.runtime_context())
	# 捕获失败不登记事务、不开始游戏事实；这里不创建执行帧或等待上下文。
	if checkpoint.transaction_id == 0: return false
	# 独立根交错支付/待答没有可原子分离的对象图前态，必须失败关闭。
	for owner in _guard_transactions.values():
		owner.ready = false
		owner.error = "独立根事务交错，不能证明完整独立回滚"
		checkpoint.ready = false
		checkpoint.error = owner.error
	_guard_transactions[effect] = checkpoint
	GameLog.begin_fact_transaction(checkpoint.transaction_id)
	if not checkpoint.audit("start", effect, checkpoint.error): return _guard_audit_failed(effect)
	return true

func _inherit_guard_transaction(effect:BaseEffect) -> bool:
	if not MatchJournal.audit_error.is_empty(): return _guard_audit_failed(effect)
	if _transaction_scope != null and not _guard_transactions.has(effect):
		_guard_transactions[effect] = _transaction_scope
		var parent:BaseEffect = _active_runs.back().run.effect if not _active_runs.is_empty() else activating_eff
		if not _transaction_scope.audit("child", effect, "", parent): return _guard_audit_failed(effect)
	return true

func _release_guard_transactions() -> void:
	if _transaction_scope == null and not _draining_guard_continuations and not is_waiting_for_choice() and _active_runs.is_empty() and activation_pool.is_empty() and decision_queue.is_empty() and _queued_time_point_batches.is_empty() and _guard_continuations.is_empty():
		var roots:Array = []
		for checkpoint in _guard_transactions.values():
			if not roots.has(checkpoint): roots.append(checkpoint)
		for checkpoint in roots:
			if not checkpoint.settled:
				if not checkpoint.audit("commit"):
					_runtime_guard.paused = true
					_runtime_guard.reason = "audit_write_failed"
					_guard_run = {"effect":checkpoint.root}
					return
				checkpoint.settled = true
			GameLog.commit_fact_transaction(checkpoint.transaction_id)
		_guard_transactions.clear()
		_continuation_transactions.clear()
		_batch_transactions.clear()

func can_rollback_runtime_guard() -> bool:
	if not _effect_execution_status(_guard_run.get("effect"), _guard_run.get("context")).ok: return false
	var checkpoint = _guard_transactions.get(runtime_guard_effect())
	return checkpoint != null and checkpoint.ready and MatchJournal.audit_error.is_empty()


func runtime_guard_effect():
	return _guard_run.get("effect") if _runtime_guard.paused else null

func runtime_guard_root_effect():
	var effect = runtime_guard_effect()
	var checkpoint = _guard_transactions.get(effect)
	return checkpoint.root if checkpoint != null else effect

func skip_runtime_guard() -> bool:
	if not can_rollback_runtime_guard() or not _active_runs.is_empty():
		return false
	var checkpoint = _guard_transactions[runtime_guard_effect()]
	var external:Array = []
	var external_owners:Dictionary = {}
	for registration in _guard_continuations:
		var owner = _continuation_transactions.get(registration)
		if owner != checkpoint:
			external.append(registration)
			if owner != null: external_owners[registration] = owner
	if not checkpoint.audit("rollback_intent", null, "host_skip") or not checkpoint.restore():
		return false
	# 恢复已撤销规则事实，即使完成回执写盘失败，也不能再广播旧事实。
	GameLog.abort_fact_transaction(checkpoint.transaction_id)
	if not checkpoint.audit("rollback", null, "host_skip"):
		return false
	checkpoint.settled = true
	var root:BaseEffect = checkpoint.root
	# 恢复等待与队列后，只移除事务根效果，不派发成功完成时点。
	decision_queue.erase(root)
	activation_pool.erase(root)
	if waiting_effect == root: waiting_effect = null
	if waiting_selection == root: waiting_selection = null
	if waiting_location == root: waiting_location = null
	if waiting_players == root: waiting_players = null
	_pending_selection_choice.erase(root)
	_pending_location_choice.erase(root)
	_pending_player_choice.erase(root)
	resolved_effects[root] = "skipped"
	_guard_run = {}
	_guard_frames.clear()
	_resume_frames.clear()
	# 其他根事务和批次归属已由检查点恢复，不能整表清空。
	_transaction_scope = null
	# 检查点恢复的同一票据不能重播；相等 Callable 的新票据必须保留。
	for registration in external:
		if not _guard_continuations.has(registration): _guard_continuations.append(registration)
		if external_owners.has(registration): _continuation_transactions[registration] = external_owners[registration]
	is_running = false
	_runtime_guard.begin_slice()
	run_pipeline(true)
	if not MatchJournal.flush_audit(): return _guard_audit_failed(root)
	return true

func configure_runtime_guard(config:Dictionary) -> bool:
	if _runtime_guard.paused or not _active_runs.is_empty():
		return false
	return _runtime_guard.configure(config)

func runtime_guard_status() -> Dictionary:
	var status:Dictionary = _runtime_guard.status()
	# 旧循环用 paused 作为立即退栈信号；不把来源拒绝写入可恢复预算状态。
	# A1-17 可消费 source_rejected，不能把它送到 resume 当一次合法暂停。
	if not _function_frames.is_empty():
		var frame:Dictionary = _function_frames.back()
		var source:Dictionary = _function_origin_status(frame.get("function"), frame.get("effect"), frame.get("context"))
		if frame.get("source_rejected", false) or not source.ok:
			status["paused"] = true
			status["source_rejected"] = true
			status["reason"] = frame.get("source_reason", source.reason)
	return status

## 只登记调用方已显式保存的尾部；未暂停时仍由调用方同步执行。
func defer_until_runtime_guard_complete(continuation:Callable, context:SessionContext = null) -> bool:
	context = _captured_function_context(context)
	if not SessionGeneration.validate_context(context).ok: return false
	var root:BaseEffect = _guard_run.get("effect")
	var origin:Dictionary = _guard_run.get("wait_origin", {})
	if not _effect_execution_status(root, context).ok or not _wait_origin_is_current(origin): return false
	if not _runtime_guard.paused or not continuation.is_valid():
		return false
	# Refill 的旧主体/牌区尾部必须在票据和审计登记之前拒绝。
	if continuation.get_object() == preload("res://scripts/system/operations/RefillHand.gd") and continuation.get_method() == &"_resume_refill":
		if continuation.get_bound_arguments_count() != 1 or continuation.get_unbound_arguments_count() != 0:
			return false
		var arguments:Array = continuation.get_bound_arguments()
		if not arguments[0] is Dictionary: return false
		var state:Dictionary = arguments[0]
		if not state.get("player") is int or not state.get("data") is Dictionary: return false
		if not state.get("hand") is Array or not state.get("deck") is Array or not state.get("discard") is Array: return false
		if not state.get("completed") is bool: return false
		if not RefillHand.continuation_is_current(state): return false
	var native_frame:Dictionary = {}
	if not _function_frames.is_empty():
		var frame:Dictionary = _function_frames.back()
		if _native_guard_adapter(frame) == &"event_entered" and continuation.get_object() == preload("res://scripts/system/operations/AddEventFromDeck.gd") and continuation.get_method() == &"_resume_add":
			var args:Array = continuation.get_bound_arguments()
			if args.size() == 1 and is_same(args[0], frame.get("loop")):
				native_frame = frame
				# 尾部属于原生父，不属于可在结算后注销的当前子监听。
				origin = _capture_wait_origin(frame.effect, frame.context)
				if origin.is_empty(): return false
	var registration := GuardContinuation.new(continuation, origin)
	if not MatchJournal.audit_event("tail_registered", {"ticket_id":registration.ticket_id, "root_id":_transaction_scope.transaction_id if _transaction_scope != null else 0}):
		# true 只表示调用方不能同步执行尾部，不是审计成功回执。
		# 保留尾部并失败关闭；consume_tail 会拒绝审计故障下的执行。
		_guard_audit_failed(runtime_guard_effect())
	_guard_continuations.append(registration)
	if not native_frame.is_empty(): native_frame["native_tail"] = registration
	if _transaction_scope != null:
		_continuation_transactions[registration] = _transaction_scope
	return true

func _drain_guard_continuations() -> void:
	if _draining_guard_continuations or is_running or not _active_runs.is_empty():
		return
	_draining_guard_continuations = true
	while not _guard_continuations.is_empty() and not is_waiting_for_choice():
		var pending:Array = _guard_continuations
		_guard_continuations = []
		var registration:GuardContinuation = pending.pop_front()
		if not _wait_origin_is_current(registration.origin):
			_continuation_transactions.erase(registration)
			_guard_continuations.append_array(pending)
			continue
		var continuation:Callable = registration.continuation
		if not continuation.is_valid():
			_guard_continuations.append(registration)
			_guard_continuations.append_array(pending)
			push_error("规则外层续行目标已失效")
			break
		var previous_scope = _transaction_scope
		_transaction_scope = _continuation_transactions.get(registration)
		if not MatchJournal.consume_tail(registration.ticket_id, _transaction_scope.transaction_id if _transaction_scope != null else 0):
			_transaction_scope = previous_scope
			_guard_continuations.append(registration)
			_guard_continuations.append_array(pending)
			_guard_audit_failed(runtime_guard_effect())
			break
		_continuation_transactions.erase(registration)
		var executing_scope = _transaction_scope
		continuation.call()
		if not _wait_origin_is_current(registration.origin):
			if _transaction_scope == executing_scope: _transaction_scope = null
			_draining_guard_continuations = false
			return
		if not _draining_guard_continuations:
			# 回调已重置会话，旧执行片的其余尾部不可写回新会话。
			break
		_transaction_scope = previous_scope
		# 新登记的内层尾部先完成，才轮到原队列的剩余外层动作。
		_guard_continuations.append_array(pending)
	_draining_guard_continuations = false

func resume_runtime_guard() -> bool:
	if not _wait_origin_is_current(_guard_run.get("wait_origin", {})): return false
	if _guard_run.get("source_rejected", false) or not _effect_execution_status(_guard_run.get("effect"), _guard_run.get("context")).ok: return false
	if not _saved_frames_are_current(_guard_frames) or not _saved_frames_are_current(_resume_frames): return false
	if not _runtime_guard.paused or _guard_run.is_empty():
		return false
	var checkpoint = _guard_transactions.get(runtime_guard_effect())
	if not MatchJournal.audit_error.is_empty() or (checkpoint != null and not checkpoint.audit("resume")):
		return false
	var run:Dictionary = _guard_run
	_resume_frames = _guard_frames
	_guard_frames = []
	_guard_run = {}
	_runtime_guard.begin_slice()
	#恢复仍属于原结算批次；结束时点不能清空本次新排入的真人待答。
	var was_running:bool = is_running
	is_running = true
	_continue_run(run)
	is_running = was_running
	if not _effect_execution_status(run.get("effect"), run.get("context")).ok: return false
	_resume_frames.clear()
	if not _runtime_guard.paused and not is_running:
		run_pipeline(true)
	if not _effect_execution_status(run.get("effect"), run.get("context")).ok: return false
	if not MatchJournal.flush_audit(): return _guard_audit_failed(run.effect)
	return _effect_execution_status(run.get("effect"), run.get("context")).ok

# 两条已有支持合同的原生恢复适配；不是未知 native/callback 的准入表。
# 仍先走 BaseFunc 的原来源/能力门；精确 Script 身份，不按函数名字猜权限。
func _native_guard_adapter(frame:Dictionary) -> StringName:
	var f:BaseFunc = frame.get("function")
	if f == null or f._instance == null or frame.get("stage") not in ["call", "native_pending"]: return &""
	var captured = frame.get("callable", Callable()).get_object()
	if not captured is BaseFunc.RuntimeCallable: return &""
	if captured.callback.get_object() != f._instance or LoadHelper.registered_callable_script(captured.callback) != f._instance.get_script(): return &""
	if f._instance.get_script() == preload("res://scripts/system/operations/EditMagic.gd"):
		return &"magic_after"
	if f._instance.get_script() == preload("res://scripts/system/operations/AddEventFromDeck.gd"):
		if frame.has("loop") and frame.get("loop_owner") == _loop_frame_owner(frame): return &"event_entered"
	if f._instance.get_script() == preload("res://scripts/system/operations/QueueOptionalEffectForPlayers.gd"):
		if frame.has("queue_origin") and frame.has("loop") and frame.get("loop_owner") == _loop_frame_owner(frame): return &"queue_registration"
	return &""

func _native_guard_stack_is_resumable() -> bool:
	if _active_runs.size() < 2: return false
	# 每个父 run 必须有自己的真实原生函数帧；不能拿一个父游标替所有祖先背书。
	for index in range(_active_runs.size() - 1):
		var represented:bool = false
		for frame in _function_frames:
			if is_same(frame.get("effect"), _active_runs[index].run.effect) and _native_guard_adapter(frame) != &"":
				represented = true
				break
		if not represented: return false
	return true

# P1-E 可直接将本 scope 的 PENDING/单次 continuation 接入 P 的控制信封。
# 这里不创建计划、不单独 commit 子工作，也不把 live 票冒充 D 的发布回执。
func _set_native_guard_outcome(frame:Dictionary, status:String, reason:String = "") -> void:
	var identity:RefCounted = null
	if status == "PENDING":
		var previous:Dictionary = frame.get("control", {})
		if previous.get("status") == "PENDING": identity = previous.get("continuation")
		if identity == null: identity = RefCounted.new()
	frame["control"] = {"status":status, "original_context":frame.context, "reason":reason,
		"continuation":identity}

func _retain_native_guard_tail(frame:Dictionary, scope) -> void:
	var adapter:StringName = _native_guard_adapter(frame)
	if adapter not in [&"event_entered", &"queue_registration"] or frame.has("native_tail"): return
	# 原事件循环自己的检查点可能直接退栈，尚未走到 operation 的 defer。
	# 每次重挂都生成独立票据，不复用已经消费的票。
	var origin:Dictionary = frame.queue_origin if adapter == &"queue_registration" else _capture_wait_origin(frame.effect, frame.context)
	if origin.is_empty():
		_set_native_guard_outcome(frame, "REJECTED", "stale_tail_source")
		return
	var callback:Callable = Callable(frame.function._instance, "_resume_queue") if adapter == &"queue_registration" else Callable(AddEventFromDeck, "_resume_add")
	var registration := GuardContinuation.new(callback.bind(frame.loop), origin)
	if not MatchJournal.audit_event("tail_registered", {"ticket_id":registration.ticket_id,"root_id":scope.transaction_id if scope != null else 0}):
		_guard_audit_failed(frame.effect)
	_guard_continuations.append(registration)
	if scope != null: _continuation_transactions[registration] = scope
	frame["native_tail"] = registration

func _resume_native_guard_frame(frame:Dictionary) -> Variant:
	var control:Dictionary = frame.get("control", {})
	if control.get("status") != "PENDING" or control.get("continuation") == null:
		_set_native_guard_outcome(frame, "REJECTED", "consumed_continuation")
		return null
	# 先消费当前 identity；状态仍待续，实际子工作与尾部完成后才标 COMPLETED。
	control["continuation"] = null
	var child:Dictionary = frame.get("child_run", {})
	if not child.is_empty():
		_continue_run(child)
		if not _accept_run_source(child):
			_set_native_guard_outcome(frame, "REJECTED", "stale_child_source")
			return null
		if _runtime_guard.paused:
			_set_native_guard_outcome(frame, "PENDING", _runtime_guard.reason)
			return null
		frame.erase("child_run")
		# 原同步派发未 drain 的同批监听必须先完成，不能让原生尾部抢先。
		var was_running:bool = is_running
		run_pipeline(true)
		is_running = was_running
		if _runtime_guard.paused:
			_set_native_guard_outcome(frame, "PENDING", _runtime_guard.reason)
			return null
	var registration:GuardContinuation = frame.get("native_tail")
	if registration != null:
		if not _wait_origin_is_current(registration.origin):
			_set_native_guard_outcome(frame, "REJECTED", "stale_tail_source")
			return null
		var scope = _continuation_transactions.get(registration)
		# 初次审计故障可能同时挡住 tail_registered；重试同票幂等审计，不能跳过登记。
		if _native_guard_adapter(frame) == &"queue_registration":
			if not _queue_registration_is_current(frame) or not is_same(scope, frame.queue_scope):
				_set_native_guard_outcome(frame, "REJECTED", "stale_queue_owner")
				return null
			if not MatchJournal.audit_event("tail_registered", {"ticket_id":registration.ticket_id,"root_id":scope.transaction_id}):
				_guard_audit_failed(runtime_guard_effect())
				_set_native_guard_outcome(frame, "PENDING", "audit_write_failed")
				return null
		if not MatchJournal.consume_tail(registration.ticket_id, scope.transaction_id if scope != null else 0):
			_guard_audit_failed(runtime_guard_effect())
			_set_native_guard_outcome(frame, "PENDING", "audit_write_failed")
			return null
		_guard_continuations.erase(registration)
		_continuation_transactions.erase(registration)
		frame.erase("native_tail")
		var previous_scope = _transaction_scope
		var was_running:bool = is_running
		_transaction_scope = scope
		# 重建原派发阶段；恢复器的 running=true 不能把同步子监听悄悄改成延后队列。
		is_running = frame.get("native_running", false)
		var tail_result = registration.continuation.call()
		if _native_guard_adapter(frame) == &"queue_registration": frame["result"] = tail_result
		if not _accept_function_source(frame.function, frame.effect, frame.context):
			_set_native_guard_outcome(frame, "REJECTED", "stale_tail_source")
			return null
		is_running = was_running
		_transaction_scope = previous_scope
		if _runtime_guard.paused:
			_set_native_guard_outcome(frame, "PENDING", _runtime_guard.reason)
			_retain_native_guard_tail(frame, scope)
			return null
	if _native_guard_adapter(frame) in [&"event_entered", &"queue_registration"]:
		if not frame.loop.get("completed", false):
			_set_native_guard_outcome(frame, "REJECTED", "incomplete_native_tail")
			return null
		return frame.loop.placed if _native_guard_adapter(frame) == &"event_entered" else frame.loop.queued
	# EditMagic 已从 AFTER 派发返回，原业务 null/false 保留，绝不再 set/扣款/记事实。
	return frame.get("result")

func runtime_guard_checkpoint(loop_state:Dictionary = {}) -> bool:
	if not _function_frames.is_empty():
		var frame:Dictionary = _function_frames.back()
		if not _accept_function_source(frame.get("function"), frame.get("effect"), frame.get("context")): return false
	if not loop_state.is_empty():
		var valid:Dictionary = SessionGeneration.validate_context(loop_state.get("context"))
		if not valid.ok:
			_reject_execution_source(loop_state.get("context"), valid.reason)
			return false
	if not _runtime_guard.enabled:
		return true
	if _active_runs.size() != 1 and not _native_guard_stack_is_resumable():
		return true
	if not loop_state.is_empty() and (_function_frames.is_empty() or not is_same(_function_frames.back().get("loop"), loop_state)):
		# 未拥有独立续行帧的辅助循环只能同步完成，不能借外层游标暂停。
		return true
	#before_* 的取消与改写必须同步返回，动作栈没有可恢复调用边界。
	#遵循原生区间策略：不在其中中断，在外侧可恢复边界检查预算。
	if not pending_actions.is_empty():
		return true
	# 保存的子调用已经跨过本层入口；重建它不是新的规则步骤。
	var depth := _function_frames.size()
	if depth < _resume_frames.size() and _resume_frames[depth] != null:
		return true
	# 不在未显式记录续行状态的原生方法内部暂停。
	for frame in _function_frames:
		if not frame.has("loop") or frame.get("loop_owner") != _loop_frame_owner(frame):
			if _native_guard_adapter(frame) != &"magic_after":
				return true
	if not MatchJournal.audit_error.is_empty():
		_runtime_guard.paused = true
		_runtime_guard.reason = "audit_write_failed"
	elif _runtime_guard.checkpoint():
		return true
	_guard_frames = _function_frames.duplicate()
	for index in range(_guard_frames.size(), _resume_frames.size()):
		if _resume_frames[index] != null:
			_guard_frames.append(_resume_frames[index])
	return false

# 只读资格查询，不把可赋值的 activating_eff 或当前域当执行来源。
func execution_context() -> Dictionary:
	if _function_frames.is_empty():
		return {"ok":false, "context":null, "reason":&"unbound_origin"}
	var frame:Dictionary = _function_frames.back()
	var status:Dictionary = _function_origin_status(frame.get("function"), frame.get("effect"), frame.get("context"))
	if not status.ok: return {"ok":false, "context":null, "reason":status.reason}
	if frame.get("source_rejected", false):
		return {"ok":false, "context":null, "reason":frame.get("source_reason", &"unbound_origin")}
	return {"ok":true, "context":frame.context, "reason":&"current"}

# 调度图与来源资格分开；规则快照消费者须迁移到此入口，不从图推断资格。
func execution_runtime_snapshot() -> Dictionary:
	return {"functions": _function_frames, "runs": _active_runs, "suspended_functions": _guard_frames, "suspended_run": _guard_run, "guard_continuations": _guard_continuations}

# 保存真实来源与对象身份；只读 find，不绑定、不取 current、不查询位置资格。
func _capture_wait_origin(effect:BaseEffect, context:SessionContext, root:BaseEffect = null) -> Dictionary:
	if not _effect_execution_status(effect, context).ok or not _effect_entry_is_current(effect): return {}
	if effect._trigger_player_id == -1: return {}
	var owner:Dictionary = GameDataManager.find_player_data(effect._trigger_player_id)
	if owner.is_empty(): return {}
	if root == null: root = effect
	if not _effect_execution_status(root, context).ok or not _effect_entry_is_current(root): return {}
	if root._trigger_player_id == -1: return {}
	var root_owner:Dictionary = GameDataManager.find_player_data(root._trigger_player_id)
	if root_owner.is_empty(): return {}
	var topology:Array = []
	for area in MapData.areas:
		var seats:Array = []
		for location in area._locations:
			seats.append({"location":location, "players":location._players})
		topology.append({"area":area, "locations":area._locations.duplicate(), "container":area._locations, "seats":seats})
	return {"context":context, "root":root, "effect":effect, "root_trigger":root._trigger_player_id, "root_owner":root_owner,
		"owner":owner, "trigger":effect._trigger_player_id, "owner_location":owner.get("location"),
		"members":GameData.player_data_library.duplicate(), "member_container":GameData.player_data_library, "map":topology, "map_container":MapData.areas,
		"targets":effect._selected_players.duplicate(), "target":effect._selected_player,
		"location":effect._selected_location, "cards":effect._selected_cards.duplicate()}

func _wait_origin_is_current(origin:Dictionary) -> bool:
	var context:SessionContext = origin.get("context")
	if not SessionGeneration.validate_context(context).ok: return false
	var effect:BaseEffect = origin.get("effect")
	if not _effect_execution_status(effect, context).ok or not _effect_entry_is_current(effect): return false
	var root:BaseEffect = origin.get("root")
	if not _effect_execution_status(root, context).ok or not _effect_entry_is_current(root): return false
	if root._trigger_player_id != origin.get("root_trigger") or not is_same(origin.get("root_owner"), GameDataManager.find_player_data(root._trigger_player_id)): return false
	if not is_same(origin.get("member_container"), GameData.player_data_library): return false
	if effect._trigger_player_id == -1 or effect._trigger_player_id != origin.get("trigger"): return false
	if not is_same(origin.get("owner"), GameDataManager.find_player_data(effect._trigger_player_id)): return false
	var members:Dictionary = origin.get("members", {})
	if members.size() != GameData.player_data_library.size(): return false
	for id in members:
		if not is_same(members[id], GameDataManager.find_player_data(id)): return false
	var topology:Array = origin.get("map", [])
	if not is_same(origin.get("map_container"), MapData.areas) or topology.size() != MapData.areas.size(): return false
	for index in range(topology.size()):
		var saved:Dictionary = topology[index]
		if not is_same(saved.area, MapData.areas[index]) or not is_same(saved.container, saved.area._locations) or saved.locations != saved.area._locations: return false
		for seat in saved.seats:
			if not is_same(seat.players, seat.location._players): return false
	return true

func _waiting_source_is_current(effect:BaseEffect) -> bool:
	if effect == null or not _waiting_origins.has(effect): return false
	var origin:Dictionary = _waiting_origins[effect]
	if not _wait_origin_is_current(origin): return false
	if not is_same(origin.owner_location, origin.owner.get("location")): return false
	return effect._selected_player == origin.target and effect._selected_players == origin.targets and effect._selected_cards == origin.cards and is_same(effect._selected_location, origin.location)

# 来源失效时仅删除精确旧对象的等待；不发布拒绝事实、不扣费、不推进新局。
func _discard_exact_wait(effect:BaseEffect) -> bool:
	if effect == null: return false
	var found:bool = waiting_effect == effect or waiting_selection == effect or waiting_players == effect or waiting_location == effect or _paused_runs.has(effect)
	if waiting_effect == effect: waiting_effect = null
	if waiting_selection == effect:
		waiting_selection = null
		_waiting_selection_option = -1
	if waiting_players == effect: waiting_players = null
	if waiting_location == effect: waiting_location = null
	_pending_selection_choice.erase(effect)
	_pending_player_choice.erase(effect)
	_pending_location_choice.erase(effect)
	_pending_choices.erase(effect)
	_paused_runs.erase(effect)
	decision_queue.erase(effect)
	activation_pool.erase(effect)
	_waiting_origins.erase(effect)
	return found

func _saved_frames_are_current(frames:Array) -> bool:
	for frame in frames:
		if frame == null: continue
		if not frame is Dictionary: return false
		if not _function_origin_status(frame.get("function"), frame.get("effect"), frame.get("context")).ok: return false
		if frame.get("source_rejected", false): return false
		if frame.has("queue_origin") and not _queue_registration_is_current(frame): return false
		if frame.has("loop") and not SessionGeneration.validate_context(frame.loop.get("context")).ok: return false
	return true

func _paused_source_is_current(paused:Dictionary) -> bool:
	var run:Dictionary = paused.get("run", {})
	if run.get("source_rejected", false) or not _effect_execution_status(run.get("effect"), run.get("context")).ok: return false
	if not _wait_origin_is_current(paused.get("origin", {})): return false
	for choice in paused.get("queue", []):
		if not _waiting_source_is_current(choice): return false
	return true

const EXECUTION_SOURCE_RESULT_META:StringName = &"effect_execution_source_result"
# 诊断不是游戏事实或可回滚规则字段；不登记、不续行，也不刷新 context。
func execution_source_status() -> Dictionary:
	return get_meta(EXECUTION_SOURCE_RESULT_META, {"ok":false, "context":null, "reason":&"unbound_origin"}).duplicate()

func _effect_execution_status(effect:BaseEffect, context:SessionContext) -> Dictionary:
	var status:Dictionary = SessionGeneration.validate_context(context)
	if not status.ok: return status
	if effect == null: return {"ok":false, "reason":&"unbound_origin"}
	status = effect.runtime_source_status()
	if not status.ok: return status
	if not is_same(effect.runtime_context().token(), context.token()):
		return {"ok":false, "reason":&"stale_session"}
	return {"ok":true, "reason":&"current"}

func _function_origin_status(f:BaseFunc, effect:BaseEffect, context:SessionContext) -> Dictionary:
	var status:Dictionary = _effect_execution_status(effect, context)
	if not status.ok: return status
	if f == null: return {"ok":false, "reason":&"unbound_origin"}
	return f.runtime_source_status(effect, context)

func _reject_execution_source(context:SessionContext, reason:StringName) -> void:
	set_meta(EXECUTION_SOURCE_RESULT_META, {"ok":false, "context":context, "reason":reason})
	# 仅污染同一来源根，不误杀同步重入中独立创建的新局根。
	for frame in _function_frames:
		var original:SessionContext = frame.get("context")
		if original != null and context != null and is_same(original.token(), context.token()):
			frame["source_rejected"] = true
			frame["source_reason"] = reason
	for active in _active_runs:
		var original:SessionContext = active.run.get("context")
		if original != null and context != null and is_same(original.token(), context.token()):
			active.run["source_rejected"] = true
			active.run["source_reason"] = reason

func _accept_function_source(f:BaseFunc, effect:BaseEffect, context:SessionContext) -> bool:
	var status:Dictionary = _function_origin_status(f, effect, context)
	# 来源先验；能力门复用 BaseFunc，不另造动态方法许可或白名单。
	if status.ok: status = f.execution_capability_status()
	if not status.ok:
		_reject_execution_source(context, status.reason)
		return false
	for frame in _function_frames:
		if frame.get("source_rejected", false) and frame.get("context") != null and is_same(frame.context.token(), context.token()): return false
	return true

func _accept_run_source(run:Dictionary) -> bool:
	var context:SessionContext = run.get("context")
	var status:Dictionary = _effect_execution_status(run.get("effect"), context)
	if run.get("source_rejected", false) or not status.ok:
		var reason:StringName = run.get("source_reason", status.reason)
		run["source_rejected"] = true
		run["source_reason"] = reason
		_reject_execution_source(context, reason)
		return false
	return true

# 旧循环适配器仅可继承已经验证的栈帧，绝不从 current/effect 补票。
func _captured_function_context(context:SessionContext) -> SessionContext:
	if context != null: return context
	return _function_frames.back().get("context") if not _function_frames.is_empty() else null

# 来源包装 Callable 的接收者是包装器，续行游标仍属于原注册 operation 实例。
func _loop_frame_owner(frame:Dictionary) -> Object:
	var f:BaseFunc = frame.get("function")
	return f._instance if f != null and f._instance != null else frame.get("callable", Callable()).get_object()

func record_loop_state(state:Dictionary, owner:Object) -> Dictionary:
	var captured:Dictionary = execution_context()
	if not captured.ok: return {}
	state["context"] = captured.context
	if not _function_frames.is_empty():
		var frame:Dictionary = _function_frames.back()
		# 辅助对象没有独立调用帧，不能覆盖或领取原生调用者的续行游标。
		if _loop_frame_owner(frame) != owner:
			return state
		if frame.get("resuming", false) and frame.has("loop"):
			var valid:Dictionary = SessionGeneration.validate_context(frame.loop.get("context"))
			if not valid.ok:
				_reject_execution_source(frame.loop.get("context"), valid.reason)
				return {}
			return frame.loop
		frame["loop_owner"] = owner
		frame["loop"] = state
	return state


#产生一条提示消息。消息先入队，由界面在刷新时取走展示——
#效果结算过程中不应直接操作界面节点，否则界面没加载时效果会崩
func push_message(text:String, player_id:int = -1):
	if text == "":
		return
	var record:Dictionary = _new_message_record(text, player_id)
	if not record.is_empty():
		messages.append(record)


func _new_message_record(text:String, player_id:int) -> Dictionary:
	return _message_serial.publish(text, player_id)


#取走该玩家的全部消息(取走即移除)。界面每次刷新时调用。
#不属于该玩家的消息留在队列里，等对应玩家来取，不会串看别人的提示
func pop_messages(player_id:int) -> Array:
	var taken:Array = []
	var left:Array = []
	for msg in messages:
		var pid:int = int(msg.get("player_id", -1))
		if pid == -1 or pid == player_id:
			taken.append(str(msg.get("text", "")))
		else:
			left.append(msg)
	messages = left
	return taken


#把已经取走的消息再塞回队列。界面把一批消息切 toast 显示时，把剩下的归还。
#别让任何一条消息在被 _show_tactical_confirm / _say 看到之前丢失
func return_messages(player_id:int, texts:Array) -> void:
	if texts.is_empty():
		return
	var rebuilt:Array = []
	# 文本接口无法恢复旧身份：归还视作重新发布，仍使用指定收件人。
	for t in texts:
		var text:String = str(t)
		if text == "":
			continue
		var record:Dictionary = _new_message_record(text, player_id)
		if not record.is_empty():
			rebuilt.append(record)
	# 插到队首，按原有顺序继续显示
	for i in range(rebuilt.size() - 1, -1, -1):
		messages.insert(0, rebuilt[i])


func push_effect_result(text:String, player_id:int = -1) -> void:
	if text == "":
		return
	var record:Dictionary = _new_message_record(text, player_id)
	if not record.is_empty():
		effect_results.append(record)


func pop_effect_results(player_id:int) -> Array:
	var taken:Array = []
	var left:Array = []
	for result in effect_results:
		var pid:int = int(result.get("player_id", -1))
		if pid == -1 or pid == player_id:
			taken.append(str(result.get("text", "")))
		else:
			left.append(result)
	effect_results = left
	return taken


#发动结果的依据：结算前后各取一次"规则状态"快照，用差值说明谁/哪个对象被改了什么。
#快照只覆盖规则上会被效果改动的数值（玩家资源、卡牌数值、状态层数、席位地利），
#键里带对象实例编号，因此同名多张牌也能各自对应；存的是当时的数值，之后对象再变不影响。
func capture_rule_state() -> Dictionary:
	var snapshot:Dictionary = {}
	var indexes:Array = _card_zone_indexes()
	var owners:Dictionary = indexes[0] as Dictionary
	for id in GameData.player_data_library.keys():
		var data:Dictionary = GameData.player_data_library[id] as Dictionary
		for field in PLAYER_NUMERIC_FIELDS.keys():
			var value = data.get(field)
			if value is BaseNumber:
				snapshot["p%d|%s" % [int(id), field]] = {
					"player_id": int(id), "object_name": "", "field": field, "value": value.number}
	for obj in GameData.objects:
		if obj == null:
			continue
		var object_name:String = str(obj.get_shown_name()) if obj is BaseObject else ""
		var owner_id:int = int(owners.get(obj.get_instance_id(), -1))
		for field in OBJECT_NUMERIC_FIELDS.keys():
			var value = obj.get(field)
			if value is BaseNumber:
				snapshot["o%d|%s" % [obj.get_instance_id(), field]] = {
					"player_id": owner_id, "object_name": object_name, "field": field, "value": value.number}
	#牌区归属：同一张牌在这两次快照里"属于谁、落在哪个区"。只在前后都存在的同一张牌上比较
	#（与数值字段同一口径），所以结算中新建的克隆牌不会冒充一次搬运
	var zones:Dictionary = indexes[1] as Dictionary
	for instance_id in zones.keys():
		var info:Dictionary = zones[instance_id] as Dictionary
		snapshot["z%d" % int(instance_id)] = {
			"player_id": int(info["player_id"]), "object_name": "", "field": ZONE_FIELD,
			"zone_path": str(info["zone"]),
			"value": "%d|%s" % [int(info["player_id"]), str(info["zone"])]}
	return snapshot


#玩家的牌区遍历：一次遍历同时产出两份索引——
#① 对象实例 → 所属玩家（给数值快照标注"这张牌/这个状态是谁的"）；
#② 卡牌实例 → {所属玩家, 所在牌区路径}（给牌区归属快照用）。
#递归遍历每个玩家的所有容器（含 side/out_of_game 这类嵌套），区路径由容器键拼成，
#不写死任何区名；状态/御主/从者这类不是卡的对象只进第 ① 份索引
func _card_zone_indexes() -> Array:
	var owners:Dictionary = {}
	var zones:Dictionary = {}
	for id in GameData.player_data_library.keys():
		var data:Dictionary = GameData.player_data_library[id] as Dictionary
		for key in data.keys():
			if GameDataManager.is_shared_with_controller(int(id), key):
				continue
			_collect_zone_cards(data[key], owners, int(id), zones, str(key))
	return [owners, zones]


func _collect_zone_cards(value, owners:Dictionary, player_id:int, zones:Dictionary, zone_path:String) -> void:
	if value is Array:
		for item in value:
			if item is BaseObject:
				owners[item.get_instance_id()] = player_id
				if item is BaseCard:
					zones[item.get_instance_id()] = {"player_id": player_id, "zone": zone_path}
			elif item is Array or item is Dictionary:
				_collect_zone_cards(item, owners, player_id, zones, zone_path)
	elif value is Dictionary:
		for key in value.keys():
			_collect_zone_cards(value[key], owners, player_id, zones, "%s/%s" % [zone_path, str(key)])


#两次快照的差值。只在同一把键前后都存在时比较（结算中新建/销毁的对象不参与），
#返回按"玩家 → 对象 → 字段"排序的明细，供结果弹窗逐条展示。
#牌区归属的变化单独聚合成"手牌 → 弃牌堆 ×3"这类搬运明细，排在数值变化之前——
#玩家先要知道"这次发动的牌去了哪"，再看数值被改了多少
func diff_rule_state(before:Dictionary, after:Dictionary) -> Array:
	var changes:Array = []
	var transfers:Dictionary = {}
	for key in before.keys():
		if !after.has(key):
			continue
		var old:Dictionary = before[key]
		var now:Dictionary = after[key]
		if str(now.get("field", "")) == ZONE_FIELD:
			#同一张牌换了牌区：按 (来源|去向) 聚合成一条，不逐张刷屏。
			#分组键只是两张快照里的归属描述；跨玩家的搬运照样表达得出来（目标玩家写进明细）
			if str(old.get("value")) == str(now.get("value")):
				continue
			var group_key:String = "%s>%s" % [str(old.get("value")), str(now.get("value"))]
			if !transfers.has(group_key):
				transfers[group_key] = {
					"player_id": int(old.get("player_id", -1)), "from_zone": str(old.get("zone_path", "")),
					"to_player": int(now.get("player_id", -1)), "to_zone": str(now.get("zone_path", "")),
					"count": 0}
			transfers[group_key]["count"] = int(transfers[group_key]["count"]) + 1
			continue
		if old.get("value") == now.get("value"):
			continue
		changes.append({
			"player_id": int(now.get("player_id", -1)),
			"object_name": str(now.get("object_name", "")),
			"field": str(now.get("field", "")),
			"before": old.get("value"),
			"after": now.get("value"),
		})
	changes.sort_custom(func(a, b):
		if int(a["player_id"]) != int(b["player_id"]):
			return int(a["player_id"]) < int(b["player_id"])
		if str(a["object_name"]) != str(b["object_name"]):
			return str(a["object_name"]) < str(b["object_name"])
		return str(a["field"]) < str(b["field"]))
	var lines:Array = []
	for group_key in transfers.keys():
		var transfer:Dictionary = transfers[group_key]
		lines.append({
			"kind": "zone_move", "player_id": int(transfer["player_id"]), "object_name": "",
			"field": ZONE_FIELD, "from_zone": str(transfer["from_zone"]),
			"to_player": int(transfer["to_player"]), "to_zone": str(transfer["to_zone"]),
			"count": int(transfer["count"])})
	lines.sort_custom(func(a, b):
		if str(a["from_zone"]) != str(b["from_zone"]):
			return str(a["from_zone"]) < str(b["from_zone"])
		return str(a["to_zone"]) < str(b["to_zone"]))
	lines.append_array(changes)
	return lines


#一条变化的中文行：谁／哪个对象／哪个字段／前值 → 后值。字段名取显式声明，不猜
func format_rule_change(change:Dictionary) -> String:
	if str(change.get("kind", "")) == "zone_move":
		return _format_zone_move(change)
	var field:String = str(change.get("field", ""))
	var shown_field:String = str(OBJECT_NUMERIC_FIELDS.get(field, PLAYER_NUMERIC_FIELDS.get(field, field)))
	var owner:String = ""
	var id:int = int(change.get("player_id", -1))
	if id >= 0:
		owner = player_shown_name(id)
	var object_name:String = str(change.get("object_name", ""))
	if object_name != "":
		owner += "【%s】" % object_name
	var prefix:String = (owner + " ") if owner != "" else ""
	return "%s%s %s → %s" % [prefix, shown_field, change.get("before"), change.get("after")]


#一条牌区搬运的中文行：谁手上的哪个区 → 谁手上的哪个区 ×张数。
#目标玩家与来源玩家相同时不重复写名字（"远坂凛 手牌 → 弃牌堆 ×3"），
#与数值明细"玩家 字段 前 → 后"同一写法：名字和它描述的东西之间留一个空格
func _format_zone_move(change:Dictionary) -> String:
	var from_player:int = int(change.get("player_id", -1))
	var to_player:int = int(change.get("to_player", -1))
	var from_zone:String = _zone_shown_name(str(change.get("from_zone", "")))
	var to_zone:String = _zone_shown_name(str(change.get("to_zone", "")))
	var from_part:String = from_zone
	if from_player >= 0:
		from_part = "%s %s" % [player_shown_name(from_player), from_zone]
	var to_part:String = to_zone
	if to_player >= 0 and to_player != from_player:
		to_part = "%s %s" % [player_shown_name(to_player), to_zone]
	return "%s → %s ×%d" % [from_part, to_part, int(change.get("count", 0))]


#牌区路径 → 显示名：按"段"登记（side/skills 这类嵌套每段各自翻译），
#没有登记中文名的段按原键名显示——不猜含义，缺登记只是显示得不好看，不会显示错
func _zone_shown_name(zone_path:String) -> String:
	if zone_path == "":
		return ""
	var shown:Array = []
	for part in zone_path.split("/"):
		shown.append(str(ZONE_SEGMENT_SHOWN.get(str(part), str(part))))
	return "".join(shown)


## 纯展示查询：未知玩家不创建数据；显示名 → 内部名 → 带空格的玩家编号。
func player_shown_name(player_id:int) -> String:
	if !GameData.player_data_library.has(player_id):
		return "玩家 %d" % player_id
	var master = GameDataManager.find_player_data(player_id).get("master")
	if master != null:
		var shown:String = str(master.get_shown_name())
		if shown != "":
			return shown
		var internal_name:String = str(master.get("_name"))
		if internal_name != "":
			return internal_name
	return "玩家 %d" % player_id


#公共独立重置：必须先撤旧签新，再触碰任何运行值/清理回调。
func reset_runtime() -> Dictionary:
	var generation:Dictionary = preload("res://scripts/system/session_generation.gd").begin_generation(&"EffectManager.reset_runtime")
	if not generation.ok:
		return {"ok":false, "context":null, "reason":generation.reason}
	var derived:Dictionary = preload("res://scripts/system/session_generation.gd").derive_context(generation.token, &"EffectManager.reset_runtime")
	if not derived.ok: return derived
	# 旧域已撤销才释放主体载体；同域清理不能释放仍合法的 identity。
	if has_meta(PAYMENT_BINDINGS_META): remove_meta(PAYMENT_BINDINGS_META)
	return clear_runtime_in_context(derived.context)


#仅供生命周期所有者显式同域编排；拒绝在首写前发生，不从 current 补 context。
func clear_runtime_in_context(context:Variant) -> Dictionary:
	if not context is SessionContext:
		return {"ok":false, "context":null, "reason":&"unbound_origin"}
	var valid:Dictionary = preload("res://scripts/system/session_generation.gd").validate_context(context)
	if not valid.ok: return {"ok":false, "context":null, "reason":valid.reason}
	if not _clear_runtime_values(context, false):
		valid = preload("res://scripts/system/session_generation.gd").validate_context(context)
		return {"ok":false, "context":null, "reason":valid.reason}
	return {"ok":true, "context":context, "reason":&"current"}


#release/end 已关闭资格后的专用清理；绝不重新开启可执行域。
func clear_runtime_after_invalidation() -> Dictionary:
	if preload("res://scripts/system/session_generation.gd").current_token().ok:
		return {"ok":false, "context":null, "reason":&"session_not_closed"}
	if has_meta(PAYMENT_BINDINGS_META): remove_meta(PAYMENT_BINDINGS_META)
	if not _clear_runtime_values(null, true):
		return {"ok":false, "context":null, "reason":&"session_changed"}
	return {"ok":true, "context":null, "reason":&"invalidated"}


func _runtime_cleanup_is_current(context:Variant, closed:bool) -> bool:
	if closed: return not preload("res://scripts/system/session_generation.gd").current_token().ok
	return preload("res://scripts/system/session_generation.gd").validate_context(context).ok


#不签票、不判断费用/成员规则。每个清理/断引用都可析构重入，返回后复验原域。
func _clear_runtime_values(context:Variant, closed:bool) -> bool:
	if not _runtime_cleanup_is_current(context, closed): return false
	GameLog.reset_fact_delivery()
	if not _runtime_cleanup_is_current(context, closed): return false
	_guard_transactions.clear()
	if not _runtime_cleanup_is_current(context, closed): return false
	_transaction_scope = null
	if not _runtime_cleanup_is_current(context, closed): return false
	_continuation_transactions.clear()
	if not _runtime_cleanup_is_current(context, closed): return false
	_batch_transactions.clear()
	if not _runtime_cleanup_is_current(context, closed): return false
	_runtime_guard.configure({"enabled": false, "steps": 0, "seconds": 0.0})
	if not _runtime_cleanup_is_current(context, closed): return false
	_guard_run.clear()
	if not _runtime_cleanup_is_current(context, closed): return false
	_guard_frames.clear()
	if not _runtime_cleanup_is_current(context, closed): return false
	_resume_frames.clear()
	if not _runtime_cleanup_is_current(context, closed): return false
	AbilityRestrictions.entries.clear()
	if not _runtime_cleanup_is_current(context, closed): return false
	_guard_continuations.clear()
	if not _runtime_cleanup_is_current(context, closed): return false
	_draining_guard_continuations = false
	if not _runtime_cleanup_is_current(context, closed): return false
	effect_pool.clear()
	if not _runtime_cleanup_is_current(context, closed): return false
	activating_eff = null
	if not _runtime_cleanup_is_current(context, closed): return false
	decision_queue.clear()
	if not _runtime_cleanup_is_current(context, closed): return false
	activation_pool.clear()
	if not _runtime_cleanup_is_current(context, closed): return false
	waiting_effect = null
	if not _runtime_cleanup_is_current(context, closed): return false
	waiting_selection = null
	if not _runtime_cleanup_is_current(context, closed): return false
	waiting_location = null
	if not _runtime_cleanup_is_current(context, closed): return false
	waiting_players = null
	if not _runtime_cleanup_is_current(context, closed): return false
	_waiting_selection_option = -1
	if not _runtime_cleanup_is_current(context, closed): return false
	_pending_selection_choice.clear()
	if not _runtime_cleanup_is_current(context, closed): return false
	_pending_location_choice.clear()
	if not _runtime_cleanup_is_current(context, closed): return false
	_pending_player_choice.clear()
	if not _runtime_cleanup_is_current(context, closed): return false
	_pending_choices.clear()
	if not _runtime_cleanup_is_current(context, closed): return false
	_paused_runs.clear()
	if not _runtime_cleanup_is_current(context, closed): return false
	_waiting_origins.clear()
	if not _runtime_cleanup_is_current(context, closed): return false
	pending_actions.clear()
	if not _runtime_cleanup_is_current(context, closed): return false
	messages.clear()
	if not _runtime_cleanup_is_current(context, closed): return false
	effect_results.clear()
	if not _runtime_cleanup_is_current(context, closed): return false
	_pending_announcements.clear()
	if not _runtime_cleanup_is_current(context, closed): return false
	_queued_time_point_batches.clear()
	if not _runtime_cleanup_is_current(context, closed): return false
	matched_time_points.clear()
	if not _runtime_cleanup_is_current(context, closed): return false
	resolved_effects.clear()
	if not _runtime_cleanup_is_current(context, closed): return false
	closed_time_points.clear()
	if not _runtime_cleanup_is_current(context, closed): return false
	countered_funcs.clear()
	if not _runtime_cleanup_is_current(context, closed): return false
	settled_phase_windows.clear()
	if not _runtime_cleanup_is_current(context, closed): return false
	time_point_id = 0
	if not _runtime_cleanup_is_current(context, closed): return false
	is_running = false
	if not _runtime_cleanup_is_current(context, closed): return false
	# 原库已被替换时也只清捕获的精确旧 owner，不让保活载体经 self_effects 反持旧 effect。
	for entry in _registration_owners.duplicate():
		var registered = entry.effect.get_ref()
		if registered == null:
			_registration_owners.erase(entry)
		else:
			(entry.subject.data["self_effects"] as Array).erase(registered)
		if not _runtime_cleanup_is_current(context, closed): return false
	for id in GameData.player_data_library.keys():
		var player_data = GameData.player_data_library[id] as Dictionary
		(player_data["self_effects"] as Array).clear()
		if not _runtime_cleanup_is_current(context, closed): return false
	ActivateEffect.clear_registration_attempts()
	if not _runtime_cleanup_is_current(context, closed): return false
	return true


#每回合开始时调用：清空所有声明了"每回合重置"的选项类效果的用量计数，
#让"本回合选过的选项"这类限制在新回合重新可选
func reset_round_option_counts():
	for effect:BaseEffect in effect_pool:
		if effect.has_options():
			reset_effect_option_counts(effect)


#单个效果的计数重置：若声明了_reset_counts_each_round才清空，不声明的效果维持全局永久计数不变
func reset_effect_option_counts(effect:BaseEffect):
	if effect._reset_counts_each_round:
		effect._option_use_counts.clear()
		effect._option_quantities.clear()


#某个选项在当前重置周期内已用了几次
func get_option_use_count(effect:BaseEffect, option_index:int) -> int:
	return effect._option_use_counts.get(option_index, 0) as int


#当前重置周期内该效果所有选项累计用了几次
func get_total_use_count(effect:BaseEffect) -> int:
	var total := 0
	for v in effect._option_use_counts.values():
		total += v as int
	return total


#来源对象(effect.from)的剩余资源层数；没有声明消耗或来源没有_buff_level时返回-1(不限)
func get_source_resource_level(effect:BaseEffect) -> int:
	if !effect._consumes_source_resource or effect.from == null:
		return -1
	if !("_buff_level" in effect.from):
		return -1
	var lvl = effect.from._buff_level
	return (lvl.number as int) if lvl is BaseNumber else -1


#某个选项还能不能再选extra_count次：没超过该选项自身的max_uses(累计)、没超过效果整体的max_total_uses(累计)、
#没超过这一次提交的max_choices限额、来源资源层数够扣。extra_count默认1，供UI/AI判断"至少还能选一次"用
func is_option_available(effect:BaseEffect, option_index:int, extra_count:int = 1) -> bool:
	if option_index < 0 or option_index >= effect._options.size():
		return false
	var opt_max:int = effect._options[option_index].get("max_uses", -1) as int
	if opt_max != -1 and get_option_use_count(effect, option_index) + extra_count > opt_max:
		return false
	if effect._max_total_uses != -1 and get_total_use_count(effect) + extra_count > effect._max_total_uses:
		return false
	if effect._max_choices != -1 and extra_count > effect._max_choices:
		return false
	if effect._options[option_index].get("select_location", null) is Dictionary and !_location_option_origin_allowed(effect, effect._options[option_index].get("select_location", {})):
		return false
	#声明了玩家目标但候选集为空（如所在战场没有别的玩家）时该选项不可选：
	#与"起点不在声明战区"同一条口径，避免玩家点下去才发现没有可点的目标
	if effect._options[option_index].get("select_players", null) is Dictionary:
		var pl_spec:Dictionary = effect._options[option_index].get("select_players", {})
		if int(pl_spec.get("min", 1)) > 0 and get_player_selection_candidates(pl_spec, effect).is_empty():
			return false
	var res_level := get_source_resource_level(effect)
	if res_level != -1 and extra_count > res_level:
		return false
	# 选项可声明发动前置查询（如「本回合必须打出了某种牌」）。这里必须在"能不能选"这一层预判，
	# 否则玩家会看到一条点下去才被拒的选项；预判阶段不推消息，避免每帧刷提示
	if !_option_activation_requirements_met(effect, {option_index: extra_count}, true):
		return false
	return true


## 公开起点查询：沿用战区锁与声明限制，不执行移动或选择提交。
func location_option_origin_allowed(effect:BaseEffect, spec:Dictionary) -> bool:
	return _location_option_origin_allowed(effect, spec)


func _location_option_origin_allowed(effect:BaseEffect, spec:Dictionary) -> bool:
	if not _effect_entry_is_current(effect) or effect._trigger_player_id == -1:
		return false
	var player_data:Dictionary = GameDataManager.find_player_data(effect._trigger_player_id)
	if player_data.is_empty(): return false
	var origin:BaseLocation = player_data.get("location") as BaseLocation
	var area:BaseMapArea = origin.get_from() as BaseMapArea if origin != null else null
	if area == null:
		return false
	#未声明起点限制时不限制：卡面「移动至任意地点」这类没有起点条件，
	#与"未声明 owner 就挑自己的牌"同一口径（缺声明=不限，而不是恒假）
	#位置选择是一次移动：身处被锁战区（固有结界等）时不能离开，选项整体不可用。
	#与落位 SetLocation 共用同一份战区锁查询，界面与 AI 因此不会再弹出这个选项
	if SetLocation.area_locked(area):
		return false
	var allowed:Array = spec.get("allowed_origin_areas", []) as Array
	return allowed.is_empty() or allowed.has(str(area._area_name))


#是否还有任何一个选项可选；全部耗尽(次数上限用完或来源资源为0)时UI/AI都不应再弹出这个效果
func has_available_options(effect:BaseEffect) -> bool:
	if effect._consumes_source_resource and get_source_resource_level(effect) == 0:
		return false
	for i in range(effect._options.size()):
		if is_option_available(effect, i, 1):
			return true
	return false


#校验一份完整的选择提交是否合法：每项次数、这一次提交的总次数、累计总次数、来源资源都要够，
#任一超限则整体不合法。selection为{选项下标:本次要用几次}
func validate_selection(effect:BaseEffect, selection:Dictionary) -> bool:
	if selection.is_empty():
		return false
	var total := 0
	for idx in selection.keys():
		var count:int = selection[idx] as int
		if !(idx is int) or count <= 0:
			return false
		if idx < 0 or idx >= effect._options.size():
			return false
		var opt_max:int = effect._options[idx].get("max_uses", -1) as int
		if opt_max != -1 and get_option_use_count(effect, idx) + count > opt_max:
			return false
		total += count
	if effect._max_choices != -1 and total > effect._max_choices:
		return false
	if effect._max_total_uses != -1 and get_total_use_count(effect) + total > effect._max_total_uses:
		return false
	var res_level := get_source_resource_level(effect)
	if res_level != -1 and total > res_level:
		return false
	return true


#选项可声明发动前置查询；查询在记用量/扣来源资源之前执行。
#每项 requirement 的 funcs 共用一张临时变量表，最后一个返回值为真才通过；
#失败消息完全由数据声明，引擎不认识具体卡名或资源名。
func _option_activation_requirements_met(effect:BaseEffect, selection:Dictionary, silent:bool = false) -> bool:
	var previous_effect = activating_eff
	var previous_vars:Array = effect._self_vars.duplicate()
	activating_eff = effect
	for idx in selection.keys():
		if !(idx is int) or idx < 0 or idx >= effect._options.size():
			continue
		var requirements = effect._options[idx].get("activation_requirements", [])
		if !(requirements is Array):
			continue
		for requirement in requirements:
			if !(requirement is Dictionary):
				continue
			effect._self_vars = []
			var final_result = null
			var called:bool = false
			for desc in (requirement.get("funcs", []) as Array):
				var outcome:Array = run_func_descriptor(desc, effect, effect.runtime_context())
				if bool(outcome[0]):
					called = true
					final_result = outcome[1]
			var passed:bool = called
			if final_result is BaseNumber:
				passed = passed and final_result.number != 0
			elif final_result == null:
				passed = false
			else:
				passed = passed and bool(final_result)
			if !passed:
				var message:String = str(requirement.get("message", "无法发动该选项"))
				if !silent:
					push_message(message, effect._trigger_player_id)
				effect._self_vars = previous_vars
				activating_eff = previous_effect
				return false
	effect._self_vars = previous_vars
	activating_eff = previous_effect
	return true


#把一份已校验通过的选择计入用量，并按声明消耗来源资源层数。
#在validate_selection通过、确定要发动之后调用一次
func record_selection_usage(effect:BaseEffect, selection:Dictionary):
	var total := 0
	for idx in selection.keys():
		var count:int = selection[idx] as int
		effect._option_use_counts[idx] = get_option_use_count(effect, idx) + count
		total += count
	if effect._consumes_source_resource and effect.from != null and ("_buff_level" in effect.from):
		var lvl = effect.from._buff_level
		if lvl is BaseNumber:
			lvl.minus(BaseNumber.new(total))
	effect._chosen_selection = selection.duplicate()
	#选项使用事实：记下"谁用了哪个效果的哪一项"，供后续规则查询（如"本回合是否以令咒获得过魔力"）。
	#带选项标签，让查询按语义匹配而不是按下标——选项顺序或文案变化不会让规则静默失效
	for idx in selection.keys():
		if !(idx is int) or idx < 0 or idx >= effect._options.size():
			continue
		var opt:Dictionary = effect._options[idx]
		var tags:Array = (opt.get("tags", []) as Array).duplicate()
		tags.append("option_used")
		GameLog.record("option_used", effect._trigger_player_id, -1, "", effect, tags,
			{"effect_name": effect._name, "option_index": int(idx),
				"option_name": str(opt.get("shown_option_name", ""))})


#按选中的选择字典取要结算的funcs：次数>1的选项，其funcs重复追加相应次数
func get_chosen_funcs(effect:BaseEffect) -> Array:
	var result:Array = []
	for idx in effect._chosen_selection.keys():
		if !(idx is int) or idx < 0 or idx >= effect._options.size():
			continue
		var count:int = effect._chosen_selection[idx] as int
		var opt_funcs:Array = effect._options[idx].get("funcs", [])
		for i in range(count):
			result.append_array(opt_funcs)
	return result


func get_all_players_id():
	return GameData.player_data_library.keys()


#把-1解析成"当前效果的触发者"，供各effect的player_id参数使用，避免默认成本地玩家
func resolve_player_id(player_id:int) -> int:
	if player_id != -1:
		return player_id
	if activating_eff != null and activating_eff._trigger_player_id != -1:
		return activating_eff._trigger_player_id
	return GameData.player_id


#顺位
#按玩家数据里的order排序。order可被ChangePlOrder改动，所以顺位不等于玩家id
#唯一实现在数据层 GameDataManager，这里保留公开入口供现有调用方使用
func get_player_order_ids() -> Array:
	return GameDataManager.get_domain_ordered_player_ids()


func get_player_order_index(player_id:int) -> int:
	var i = get_player_order_ids().find(player_id)
	if i == -1:
		return GameData.player_max + 1
	return i


#效果池登记
#player_id不为-1时同时把效果登记为该玩家所有，并写入其self_effects供反查
# 登记身份属于运行期元数据；普通重登/注销不能擦掉旧主体授权。
const REGISTRATION_SUBJECT_META:StringName = &"effect_registration_subject"
# 弱持效果、保活精确 owner；生命周期清池不删除仍由外部持有的旧登记身份。
# 不让 effect -> 玩家字典形成 self_effects 引用环，也不以数值实例 ID 授权。
var _registration_owners:Array = []

func _effect_origin_is_current(effect:BaseEffect) -> bool:
	return effect != null and effect.runtime_source_status().ok

func _effect_entry_is_current(effect:BaseEffect) -> bool:
	if not _effect_origin_is_current(effect): return false
	if effect.has_meta(REGISTRATION_SUBJECT_META) and effect.get_meta(REGISTRATION_SUBJECT_META).id != effect._trigger_player_id: return false
	return can_register_effect(effect, effect._trigger_player_id)

func _retain_registration_owner(effect:BaseEffect, subject:PaymentSubject) -> void:
	for entry in _registration_owners.duplicate():
		if entry.effect.get_ref() == null: _registration_owners.erase(entry)
	_registration_owners.append({"effect":weakref(effect), "subject":subject})

func _registration_subject_is_current(effect:BaseEffect, player_id:int, data:Dictionary) -> bool:
	if _payment_session_token() == null: return false
	if not effect.has_meta(REGISTRATION_SUBJECT_META): return true
	var binding:Dictionary = effect.get_meta(REGISTRATION_SUBJECT_META)
	var subject = binding.subject.get_ref()
	return preload("res://scripts/system/session_generation.gd").validate_token(binding.session).ok and binding.id == player_id and subject != null and is_same(subject.data, data)

#只读登记资格查询：不建库、不登记；true 不替代 register_effect 的审计门。
func can_register_effect(effect:BaseEffect, player_id:int) -> bool:
	if not _effect_origin_is_current(effect): return false
	var id:int = player_id
	if id == -1:
		id = int(effect.get_meta(REGISTRATION_SUBJECT_META).id) if effect.has_meta(REGISTRATION_SUBJECT_META) else effect._trigger_player_id
	var data:Dictionary = GameDataManager.find_player_data(id) if id != -1 else {}
	if id != -1 and data.is_empty(): return false
	return _registration_subject_is_current(effect, id, data)

func register_effect(effect:BaseEffect, player_id:int = -1) -> bool:
	if not can_register_effect(effect, player_id): return false
	if not _inherit_guard_transaction(effect): return false
	# 审计/同步回调返回后复验原来源，不用 current 刷新。
	if not can_register_effect(effect, player_id): return false
	var id:int = player_id if player_id != -1 else (int(effect.get_meta(REGISTRATION_SUBJECT_META).id) if effect.has_meta(REGISTRATION_SUBJECT_META) else effect._trigger_player_id)
	if id != -1 and not effect.has_meta(REGISTRATION_SUBJECT_META):
		var data:Dictionary = GameDataManager.find_player_data(id)
		var subject := PaymentSubject.new(data)
		_payment_subject_bindings().append(subject)
		_retain_registration_owner(effect, subject)
		if not can_register_effect(effect, player_id): return false
		effect.set_meta(REGISTRATION_SUBJECT_META, {"session":effect.runtime_context().token(), "id":id, "subject":weakref(subject)})
	if player_id != -1:
		effect._trigger_player_id = player_id
	if !effect_pool.has(effect):
		effect_pool.append(effect)
	if player_id != -1:
		var pl_data:Dictionary = GameDataManager.find_player_data(player_id)
		var self_effects = pl_data["self_effects"] as Array
		if !self_effects.has(effect):
			self_effects.append(effect)
	return true


## 单步登记控制回执；业务 Array/null/false 仍由 operation/原函数帧保存。
## 只为已声明 Queue 的真实根事务帧保存 audit child 重试，不赋予其它 native 续行能力。
func register_native_effect_result(effect:BaseEffect, player_id:int) -> Dictionary:
	var execution:Dictionary = execution_context()
	var context:SessionContext = execution.get("context")
	var frame:Dictionary = _function_frames.back() if execution.ok else {}
	var f:BaseFunc = frame.get("function")
	var supported:bool = f != null and f._instance != null and f._instance.get_script() == preload("res://scripts/system/operations/QueueOptionalEffectForPlayers.gd") and frame.has("loop") and frame.get("loop_owner") == f._instance and not _active_runs.is_empty() and _transaction_scope != null and pending_actions.is_empty()
	# 不能用 Queue 的一张票给未知原生祖先或没有独立游标的 helper 背书。
	for ancestor in _function_frames:
		if is_same(ancestor, frame): break
		if _native_guard_adapter(ancestor) == &"" and (not ancestor.has("loop") or ancestor.get("loop_owner") != _loop_frame_owner(ancestor)):
			supported = false
	if not supported:
		var accepted:bool = register_effect(effect, player_id)
		return {"status":"COMPLETED" if accepted else "REJECTED", "original_context":context, "reason":"" if accepted else "registration_refused", "continuation":null}
	if not frame.has("queue_origin"):
		frame["queue_origin"] = _capture_wait_origin(frame.effect, context, _transaction_scope.root)
		frame["queue_scope"] = _transaction_scope
	if not _queue_registration_is_current(frame):
		_set_native_guard_outcome(frame, "REJECTED", "stale_queue_owner")
		_reject_execution_source(context, &"stale_queue_owner")
		return frame.control
	var pending:Dictionary = frame.get("native_registration", {})
	if pending.is_empty():
		pending = {"effect":effect, "player_id":player_id, "retry_child":false,
			"parent":_active_runs.back().run.effect}
		frame["native_registration"] = pending
	if not is_same(pending.effect, effect) or pending.player_id != player_id or not can_register_effect(effect, player_id):
		frame.erase("native_registration")
		return {"status":"REJECTED", "original_context":context, "reason":"registration_refused", "continuation":null}
	var accepted:bool = true
	# inherit 已保留原 checkpoint 绑定，但失败的 child 审计必须以同一原 parent 重试。
	if pending.retry_child:
		accepted = _transaction_scope.audit("child", effect, "", pending.parent)
		if not accepted: _guard_audit_failed(effect)
	if accepted:
		pending.retry_child = false
		accepted = register_effect(effect, player_id)
	if accepted:
		if not _queue_registration_is_current(frame):
			_set_native_guard_outcome(frame, "REJECTED", "stale_queue_owner")
			_reject_execution_source(context, &"stale_queue_owner")
			return frame.control
		frame.erase("native_registration")
		return {"status":"COMPLETED", "original_context":context, "reason":"", "continuation":null}
	if _runtime_guard.paused and _runtime_guard.reason == "audit_write_failed":
		pending.retry_child = is_same(_guard_transactions.get(effect), _transaction_scope)
		_set_native_guard_outcome(frame, "PENDING", "audit_write_failed")
		return frame.control
	frame.erase("native_registration")
	return {"status":"REJECTED", "original_context":context, "reason":"registration_refused", "continuation":null}

func _queue_registration_is_current(frame:Dictionary) -> bool:
	if not _wait_origin_is_current(frame.get("queue_origin", {})): return false
	var scope = frame.get("queue_scope")
	if scope == null or scope.settled or not is_same(_guard_transactions.get(frame.effect), scope) or not is_same(scope.root, frame.queue_origin.root): return false
	var pending:Dictionary = frame.get("native_registration", {})
	if not pending.is_empty():
		if not _effect_execution_status(pending.effect, frame.context).ok or not can_register_effect(pending.effect, pending.player_id): return false
		if pending.retry_child and not is_same(_guard_transactions.get(pending.effect), scope): return false
	return true


func register_effects(effects:Array, player_id:int = -1) -> bool:
	# 成员/身份拒绝在任何子项副作用之前发生；审计失败仍由原恢复门负责。
	for effect in effects:
		if effect is BaseEffect and not can_register_effect(effect, player_id): return false
	if player_id != -1 and GameDataManager.find_player_data(player_id).is_empty(): return false
	for effect in effects:
		if effect is BaseEffect and not register_effect(effect, player_id): return false
	return true


#效果离场(卡牌被移除游戏等)时取消登记，之后的时点不再检查它
func unregister_effect(effect:BaseEffect):
	if effect == null:
		return
	effect_pool.erase(effect)
	_waiting_origins.erase(effect)
	decision_queue.erase(effect)
	activation_pool.erase(effect)
	matched_time_points.erase(effect)
	if waiting_effect == effect:
		waiting_effect = null
	if waiting_selection == effect:
		waiting_selection = null
		_waiting_selection_option = -1
		_pending_selection_choice.erase(effect)
	if waiting_location == effect:
		waiting_location = null
		_pending_location_choice.erase(effect)
	if waiting_players == effect:
		waiting_players = null
		_pending_player_choice.erase(effect)
	# 注销是精确对象清理，不要求旧来源有效；不查当前同 ID，也不擦绑定以便重登记洗票。
	if effect.has_meta(REGISTRATION_SUBJECT_META):
		var binding:Dictionary = effect.get_meta(REGISTRATION_SUBJECT_META)
		var subject = binding.subject.get_ref()
		if subject != null:
			(subject.data["self_effects"] as Array).erase(effect)


# 合法归属迁移：本局效果整体改登记给另一名玩家（如“夺取技能”）。
# 注销保留旧绑定是为防跨局洗票；这里只接受本局来源且旧绑定仍属本局的效果，迁移时才擦旧绑定。
func can_transfer_effect(effect:BaseEffect, player_id:int) -> bool:
	if not _effect_origin_is_current(effect) or _payment_session_token() == null: return false
	if GameDataManager.find_player_data(player_id).is_empty(): return false
	if not effect.has_meta(REGISTRATION_SUBJECT_META): return true
	var binding:Dictionary = effect.get_meta(REGISTRATION_SUBJECT_META)
	return preload("res://scripts/system/session_generation.gd").validate_token(binding.session).ok

func transfer_effect(effect:BaseEffect, player_id:int) -> bool:
	if not can_transfer_effect(effect, player_id): return false
	unregister_effect(effect)
	effect.remove_meta(REGISTRATION_SUBJECT_META)
	return register_effect(effect, player_id)


#开局加载完的效果先全部入池，此时还没有归属玩家；
#选完御主/从者后再用register_effects(xx._effects, id)绑定归属
func sync_loaded_effect_pool():
	# 模板池不是资格；批量复用预检，避免混合旧来源时先登记前项。
	register_effects(GameData.effects)


#即将发生的动作（before_* 时点）
#淘汰、败北、关闭、移出游戏、获得战果/魔力这类动作在真正执行前先派发一个 before_* 时点，
#期间结算的效果可以用 cancel_pending_action 取消它、用 edit_pending_action 改写它的数值；
#发起方拿到返回的动作字典后，按 cancelled 与 values 决定怎么执行。
#这类时点必须当场结算完才能知道结果，所以不走排队的时点流程，只同步结算强制效果（is_pure_passive），
#需要玩家抉择的效果无法在这里暂停等待。动作嵌套时按栈处理，改写只作用于最内层那一个
var pending_actions:Array = []


#发起一个即将发生的动作并同步结算监听它的效果。
#player_id 为动作当事人：监听者按自己是不是当事人区分 self_/others_ 前缀；-1 表示不属于任何玩家，只匹配原始时点。
#values 里放可被改写的数值（BaseNumber）或供效果查询的对象，键名由发起方与卡牌数据约定
func begin_pending_action(time_point:String, player_id:int = -1, values:Dictionary = {}, source = null) -> Dictionary:
	var action := {"time_point": time_point, "player_id": player_id, "cancelled": false,
		"values": values, "source": source}
	var session:RefCounted = _payment_session_token()
	var subject:Dictionary = GameDataManager.find_player_data(player_id)
	pending_actions.push_back(action)
	GameLog.record("time_point", player_id, -1, "", source, [time_point], {"time_points": [time_point]})
	var was_running:bool = is_running
	#同步结算期间视作在流程中：效果内部再派发的时点只收集、不重开一批
	is_running = true
	for effect in effect_pool.duplicate():
		if !_listens_pending(effect, time_point, player_id, source):
			continue
		var previous = activating_eff
		activating_eff = effect
		activate_effect(effect)
		# reset 已建立新上下文，旧栈不得恢复旧字段或弹新局动作。
		if session != _payment_session_token():
			action["invalidated"] = true
			return action
		activating_eff = previous
		if not subject.is_empty() and not is_same(subject, GameDataManager.find_player_data(player_id)):
			action["invalidated"] = true
			break
	is_running = was_running
	pending_actions.pop_back()
	#同步结算中收集到的后续效果交给常规流程
	if !action.get("invalidated", false) and !was_running and !decision_queue.is_empty():
		run_pipeline()
	return action


#最内层正在发生的动作；没有时为空字典
func current_pending_action() -> Dictionary:
	return pending_actions.back() if !pending_actions.is_empty() else {}


func _listens_pending(effect:BaseEffect, time_point:String, player_id:int, source) -> bool:
	if not _effect_entry_is_current(effect): return false
	if effect == null or effect._trigger_player_id == -1 or effect._is_manual or !effect._is_pure_passive:
		return false
	if !card_state_allows(effect):
		return false
	var points:Array = [time_point]
	if player_id >= 0:
		points.append((TimePoints.SELF_PREFIX if effect._trigger_player_id == player_id else TimePoints.OTHERS_PREFIX) + time_point)
	var matched:Array = []
	for tp in effect._time_points:
		if points.has(tp):
			matched.append(tp)
	if matched.is_empty():
		return false
	var owner = effect.from.get_ref() if effect.from is WeakRef else effect.from
	if effect._source_bound and owner != source:
		return false
	effect._trigger_time_points = matched
	return true


#当前结算中的效果来自哪里：供数值变化记录"是谁、因为哪类对象"改的。
#source_kind 取来源对象的真实类型（局势/事件/御主/从者/状态/技能/攻击/令咒/其他），by_player 是发动者
#（场上牌借锚点玩家结算时记 -1，与效果公告同一口径）。没有正在结算的效果时 source_kind 为 "rule"
func activating_source_info() -> Dictionary:
	var effect:BaseEffect = activating_eff
	if effect == null:
		return {"source_kind": "rule", "source_name": "", "by_player": -1}
	var owner = effect.from.get_ref() if effect.from is WeakRef else effect.from
	return {"source_kind": object_source_kind(owner), "source_name": _effect_source_name(effect),
		"by_player": _effect_fact_actor_id(effect)}


#对象属于哪一类来源。令咒按是否登记在令咒卡库里判断，不按名字猜
static func object_source_kind(owner) -> String:
	if owner is BaseSituation:
		return "situation"
	if owner is BaseEvent:
		return "event"
	if owner is BaseMaster:
		return "master"
	if owner is BaseServant:
		return "servant"
	if owner is BaseBuff:
		return "buff"
	if owner is BaseSkill:
		return "skill"
	if owner is BaseAttack:
		return "attack"
	if owner is BaseCard and LoadCommandSpell.get_command_spell(owner._name) != null:
		return "command_spell"
	return "other"


#按基础时点查询是否存在玩家级监听。调用方据此决定是否需要派发
#玩家自己的阶段开始/结束；不把卡牌名称或具体时点写死在引擎里。
func has_player_time_point_listener(base_time_point:String) -> bool:
	if base_time_point.is_empty():
		return false
	var self_point:String = TimePoints.SELF_PREFIX + base_time_point
	var others_point:String = TimePoints.OTHERS_PREFIX + base_time_point
	for effect:BaseEffect in effect_pool:
		if effect == null or effect._trigger_player_id == -1:
			continue
		if effect._time_points.has(self_point) or effect._time_points.has(others_point):
			return true
	return false


#时点流程
#进入一个新时点。调用方(TimePointChecker)负责先把各玩家的current_time_points更新好
# 可选尾参保留旧 0/1/2 参 ABI；缺省仅继承真实已验函数帧，不补当前票。
func run_time_point(source = null, event_player_id:int = -1, context:SessionContext = null, root:BaseEffect = null) -> bool:
	context = RegisterObjectEffects.captured_context(context)
	if not RegisterObjectEffects.source_is_current(context, source): return false
	if root != null and (not _effect_execution_status(root, context).ok or not _effect_entry_is_current(root)): return false
	if event_player_id != -1 and GameDataManager.find_player_data(event_player_id).is_empty(): return false
	if is_running:
		#结算过程中派发的时点只追加效果，交由外层流程继续处理
		collect_current_effects(source, event_player_id)
		if not RegisterObjectEffects.source_is_current(context, source): return false
		TimePointChecker.consume_transient_time_points()
		return true
	if is_waiting_for_choice():
		root = _waiting_time_point_root(context, root)
		if root == null: return false
		if not queue_time_point_batch(source, event_player_id, context, root): return false
		TimePointChecker.consume_transient_time_points()
		return true
	time_point_id += 1
	decision_queue.clear()
	activation_pool.clear()
	matched_time_points.clear()
	resolved_effects.clear()
	closed_time_points.clear()
	countered_funcs.clear()
	waiting_effect = null
	collect_current_effects(source, event_player_id)
	if not RegisterObjectEffects.source_is_current(context, source): return false
	# 匹配結果保存于效果快照后才消费瞬态；拒绝不消费等待/控制票。
	TimePointChecker.consume_transient_time_points()
	run_pipeline()
	return RegisterObjectEffects.source_is_current(context, source)

# source 可以是卡或 null；根只能来自仍有效的真实等待记录，不能猜 activating_eff。
# 合法 context 按原 token 验证，保留传入对象，不要求与工厂 context 同 identity。
func _waiting_time_point_root(context:SessionContext, root:BaseEffect) -> BaseEffect:
	var original_root:BaseEffect = null
	for effect:BaseEffect in [waiting_effect, waiting_selection, waiting_players, waiting_location]:
		if effect == null: continue
		if not _waiting_source_is_current(effect): return null
		var origin:Dictionary = _waiting_origins[effect]
		if not is_same(origin.get("effect"), effect): return null
		var saved_root:BaseEffect = origin.get("root")
		if not _effect_execution_status(saved_root, context).ok: return null
		if original_root != null and not is_same(original_root, saved_root): return null
		original_root = saved_root
	if original_root == null or (root != null and not is_same(root, original_root)): return null
	return original_root


## 只捕获各玩家当前/动态时点并排队；不立即执行，也不消费瞬态时点。
## 批次继承当前根事务（若有）；source 保持必传，event_player_id 默认 -1。
func queue_time_point_batch(source, event_player_id:int = -1, context:SessionContext = null, root:BaseEffect = null) -> bool:
	context = RegisterObjectEffects.captured_context(context)
	if not SessionGeneration.validate_context(context).ok: return false
	if root == null and execution_context().ok: root = _function_frames.back().get("effect")
	var origin:Dictionary = _capture_wait_origin(root, context)
	if origin.is_empty(): return false
	var members:Dictionary = GameData.player_data_library.duplicate()
	var players: Dictionary = {}
	for id in get_all_players_id():
		var data: Dictionary = GameDataManager.find_player_data(id)
		players[id] = {
			"current": (data["current_time_points"] as Array).duplicate(),
			"dynamic": (data["dynamic_time_points"] as Array).duplicate()
		}
	_queued_time_point_batches.append({"source": source, "players": players, "event_player_id": event_player_id, "context":context, "members":members, "origin":origin, "root":root})
	# 等待会退掉 scope；按已验原 root 查原归属，不另造根/外部 checkpoint。
	var transaction = _transaction_scope if _transaction_scope != null else _guard_transactions.get(root)
	if transaction != null:
		_batch_transactions.append({"batch":_queued_time_point_batches.back(), "transaction":transaction})
	return true


func _run_next_queued_time_point() -> bool:
	if is_waiting_for_choice() or _queued_time_point_batches.is_empty(): return false
	var batch:Dictionary = _queued_time_point_batches.front()
	if not _wait_origin_is_current(batch.get("origin", {})): return false
	if not RegisterObjectEffects.source_is_current(batch.get("context"), batch.get("source")): return false
	var members:Dictionary = batch.get("members", {})
	if members.size() != GameData.player_data_library.size(): return false
	for id in members:
		if not is_same(members[id], GameDataManager.find_player_data(id)): return false
	_queued_time_point_batches.pop_front()
	var previous_scope = _transaction_scope
	for record in _batch_transactions.duplicate():
		if is_same(record.batch, batch):
			_transaction_scope = record.transaction
			_batch_transactions.erase(record)
			break
	# 新批次会清时点池；暂存原待结算成员，避免其中产生新选择时丢掉已接受分支。
	var previous_decisions:Array = decision_queue.duplicate()
	var previous_activations:Array = activation_pool.duplicate()
	var was_running:bool = is_running
	var players:Dictionary = batch.get("players", {})
	for id in players:
		var data:Dictionary = GameDataManager.find_player_data(id)
		var snapshot:Dictionary = players[id]
		data["current_time_points"] = (snapshot.get("current", []) as Array).duplicate()
		data["dynamic_time_points"] = (snapshot.get("dynamic", []) as Array).duplicate()
	is_running = false
	var accepted:bool = run_time_point(batch.get("source"), int(batch.get("event_player_id", -1)), batch.get("context"), batch.get("root"))
	# 换局/成员变化后不恢复旧 scope/running/队列，更不能接到新局。
	if not _wait_origin_is_current(batch.get("origin", {})): return false
	for effect in previous_decisions:
		if not _effect_entry_is_current(effect): return false
	for effect in previous_activations:
		if not _effect_entry_is_current(effect): return false
	for effect in previous_decisions:
		if not decision_queue.has(effect): decision_queue.append(effect)
	for effect in previous_activations:
		if not activation_pool.has(effect): activation_pool.append(effect)
	sort_by_turn_order(decision_queue)
	sort_by_priority(activation_pool)
	is_running = was_running
	_transaction_scope = previous_scope
	return accepted


#检查全局效果池，把本时点命中的效果按顺位排进待决定队列
func collect_current_effects(source = null, event_player_id:int = -1):
	var newly_matched:Array = []
	# 到期注销会修改效果池，遍历快照避免跳过相邻效果。
	for effect:BaseEffect in effect_pool.duplicate():
		if not _effect_entry_is_current(effect): continue
		if effect._trigger_player_id == -1:
			continue
		#手动发动类效果(如令咒)不进自动询问队列：它只在玩家主动点击发动时才被询问，
		#否则会在每个命中时点自动弹窗问玩家用不用
		if effect._is_manual:
			continue
		if resolved_effects.has(effect):
			continue
		if decision_queue.has(effect) or activation_pool.has(effect):
			continue
		var matched = get_matched_time_points(effect)
		var expired: bool = false
		if not effect._expire_time_points.is_empty():
			var current_points = (GameDataManager.find_player_data(effect._trigger_player_id) as Dictionary)["current_time_points"] as Array
			for expire_point in effect._expire_time_points:
				if current_points.has(expire_point):
					expired = true
					break
		# 目标与到期同帧时目标优先；只有目标未命中才注销。
		if matched.is_empty() and expired:
			unregister_effect(effect)
			continue
		if !card_state_allows(effect):
			continue
		if source != null:
			var owner = effect.from.get_ref() if effect.from is WeakRef else effect.from
			#卡牌亮出时的三个来源语义：任意不筛选，自身只保留同一张卡，
			#其他只保留不同卡。非卡牌来源的效果仍可使用任意时点监听。
			if owner == source:
				matched.erase(TimePoints.OTHERS_CARD_REVEALED)
			else:
				matched.erase(TimePoints.SELF_CARD_REVEALED)
			if effect._source_bound and owner != source:
				continue
		if matched.is_empty():
			continue
		#持续阶段窗口（self_action_phase / self_battle_phase / self_climax …）派发后会一直留在
		#玩家的时点表里，直到阶段轮转才被 clear_player_scope_time_points 清掉。同一阶段内
		#后续每个批次（战力结算、事件进场、战后选择…）都会再命中它，纯被动效果因此被反复执行
		#——实测言峰"战斗阶段：总威力+2"在同一个战斗阶段里叠到 8 点。这里按"窗口内只结算一次"过滤，
		#瞬时时点（PLAYED_CARD、MAGIC_ADD…）不受影响，仍然每次命中都算
		matched = _first_settlement_of_phase_windows(effect, matched)
		if matched.is_empty():
			continue
		matched_time_points[effect] = matched
		#快照触发上下文。start_effect会清空动态时点，所以要在结算前记下来，供When判断分支
		effect._trigger_time_points = matched.duplicate()
		effect._event_player_id = event_player_id
		newly_matched.append(effect)
		if not _inherit_guard_transaction(effect): return
	decision_queue.append_array(newly_matched)
	sort_by_turn_order(decision_queue)


#持续阶段窗口的结算记录：效果 → 本窗口内已结算过的窗口时点。
#窗口靠换行动者/换阶段轮转（由 TimePointChecker 调 reset_phase_window_settlements 清空），
#不随每个时点批次清，否则等于没去重
var settled_phase_windows:Dictionary = {}


## 只保留本窗口内"还没结算过"的持续窗口时点，瞬时时点原样通过。
## 缺了这一步，持续窗口会被同一阶段内的每个后续批次重复结算（威力类效果表现为暴涨）
func _first_settlement_of_phase_windows(effect:BaseEffect, matched:Array) -> Array:
	var result:Array = []
	var settled:Array = settled_phase_windows.get(effect, [])
	for tp in matched:
		var point := str(tp)
		if !TimePointChecker.is_persistent_player_window(point):
			result.append(tp)
			continue
		if settled.has(point):
			continue
		settled.append(point)
		result.append(tp)
	if !settled.is_empty():
		settled_phase_windows[effect] = settled
	return result


## 阶段窗口整体轮转（换行动者、换阶段、重开一局）时清空
func reset_phase_window_settlements() -> void:
	settled_phase_windows.clear()


#统一的能力禁用入口：自动询问、手动请求与直接 ActivateEffect 都经 card_state_allows。
#阶段能力按显式 time_points 的阶段 mid 声明识别；不猜 shown 文案，
#不把纯被动事件、打出时或残留结算误当成使用卡牌。
func ability_is_disabled(effect:BaseEffect) -> bool:
	if AbilityRestrictions.is_disabled(effect):
		return true
	if effect == null:
		return true
	var owner = effect.from.get_ref() if effect.from is WeakRef else effect.from
	if not (owner is BaseHandCard):
		return false
	if not owner._attributes.has(Attributes.NOBLE_PHANTASM):
		return false
	var has_phase_window:bool = false
	for phase in GameProgress.phases:
		for prefix in [TimePoints.SELF_PREFIX, TimePoints.OTHERS_PREFIX, ""]:
			if effect._time_points.has(prefix + str(phase["mid"])):
				has_phase_window = true
	if not has_phase_window:
		return false
	return BoardHasEffect.new().exec(ForbidNoblePhantasmEffect.EFFECT_NAME)


#_need_activate表示"这个效果需不需要卡牌处于激活状态"。
#是否强制结算由_is_pure_passive控制，不绕过数据声明的激活要求。
func card_state_allows(effect:BaseEffect) -> bool:
	if ability_is_disabled(effect):
		return false
	#声明了每局限一次的效果，本局已经触发过就不再进决断队列
	if effect._once_per_game and is_effect_used_once(effect):
		return false
	#被禁用的效果、以及所属卡牌已失去文字时，效果不结算（效果本身保留，恢复后照常生效）
	if effect._disabled:
		return false
	var owner = effect.from.get_ref() if effect.from is WeakRef else effect.from
	if owner is BaseCard and (owner as BaseCard)._text_disabled:
		return false
	#buff 的激活状态是它自身声明的（is_active:false 表示"条件满足才点亮"），
	#未激活时它身上的效果不结算。口径与 PlayerBuffsHaveEffect / BoardHasEffect /
	#MapAreaHasEffect 这几个查询入口一致：效果仍留在池里，点亮后照常参与结算。
	#缺这一条时"执行者""天之衣""黑泥""被污染的圣杯"在未激活状态下就已经生效
	if owner is BaseSkill and not owner._is_awakened:
		return false
	if owner is BaseBuff and !(owner as BaseBuff)._is_active:
		return false
	if owner is BaseBuff and owner._values.has("bound_upgrade_skill"):
		var master = GameDataManager.get_player_data(effect._trigger_player_id).get("master")
		var unlocked:bool = false
		if master is BaseMaster:
			for skill in master._upgrade_skill:
				if skill._name == str(owner._values.bound_upgrade_skill) and skill._is_awakened:
					unlocked = true
		if not unlocked:
			return false
	# 事件没有激活概念：正面允许，暗置须由效果显式声明；前述门仍优先。
	if owner is BaseEvent:
		return not owner._is_concealed or effect._allow_while_concealed
	if !effect._need_activate:
		return true
	if owner is BaseHandCard:
		return (owner as BaseHandCard)._is_activating
	return true


#返回效果在其归属玩家的当前时点表里命中的所有时点。
#命中多个时，关掉其中一个不会让效果整体失效。
#AND模式(_time_points_require_all)下要求全部时点同时命中，任一未命中就返回空数组
#——用于"高潮回合且正处于自己行动阶段"这类需要两个时点同时成立的规则。
func get_matched_time_points(effect:BaseEffect) -> Array:
	if not _effect_entry_is_current(effect): return []
	var pl_data:Dictionary = GameDataManager.find_player_data(effect._trigger_player_id)
	if pl_data.is_empty(): return []
	var current_tps = pl_data["current_time_points"] as Array
	if effect._is_manual:
		#事件时点会被 start_effect 消耗；持续窗口按当前阶段/行动者重建，
		#只用于手动查询，不重派自动效果，也不恢复已消耗的事件时点。
		current_tps = current_tps.duplicate()
		var phase = GameProgress.get_current_phase()
		for phase_data in GameProgress.phases:
			for prefix in [TimePoints.SELF_PREFIX, TimePoints.OTHERS_PREFIX]:
				erase_all(current_tps, prefix + str(phase_data["mid"]))
		for tp in [TimePoints.CLIMAX, TimePoints.NON_CLIMAX]:
			for prefix in [TimePoints.SELF_PREFIX, TimePoints.OTHERS_PREFIX]:
				erase_all(current_tps, prefix + str(tp))
		if not phase.is_empty() and GameProgress.current_player_id >= 0:
			var is_self:bool = effect._trigger_player_id == GameProgress.current_player_id
			var prefix = TimePoints.SELF_PREFIX if is_self else TimePoints.OTHERS_PREFIX
			#行动者视为处于的阶段（phase_as）决定窗口：与 next_player_in_phase 派发的窗口同一口径。
			#全局阶段时点表只含实际阶段，所以被映射出来的阶段不再要求在 phase_time_points 里
			var mids:Array = GameProgress.effective_phase_mids(GameProgress.current_player_id)
			for tp in mids:
				current_tps.append(prefix + str(tp))
			var round_tp = TimePoints.CLIMAX if GameProgress.is_climax_round() else TimePoints.NON_CLIMAX
			if TimePointChecker.phase_time_points.has(round_tp):
				current_tps.append(prefix + str(round_tp))
	var closed = closed_time_points.get(effect._trigger_player_id, []) as Array
	var matched:Array = []
	for tp in effect._time_points:
		if closed.has(tp):
			if effect._time_points_require_all:
				return []
			continue
		if current_tps.has(tp):
			if !matched.has(tp):
				matched.append(tp)
		elif effect._time_points_require_all:
			return []
	return matched


#询问顺序：按顺位，同一玩家内按优先级
func sort_by_turn_order(effects:Array):
	var order = get_player_order_ids()
	effects.sort_custom(func(a:BaseEffect, b:BaseEffect):
		var a_index = order.find(a._trigger_player_id)
		var b_index = order.find(b._trigger_player_id)
		if a_index != b_index:
			return a_index < b_index
		if a._priority != b._priority:
			return a._priority < b._priority
		return effect_pool.find(a) < effect_pool.find(b)
	)


#结算顺序：按优先级，同一优先级按顺位
func sort_by_priority(effects:Array):
	var order = get_player_order_ids()
	effects.sort_custom(func(a:BaseEffect, b:BaseEffect):
		if a._priority != b._priority:
			return a._priority < b._priority
		var a_index = order.find(a._trigger_player_id)
		var b_index = order.find(b._trigger_player_id)
		if a_index != b_index:
			return a_index < b_index
		return effect_pool.find(a) < effect_pool.find(b)
	)


#主流程：先决定(交错)，再按优先级结算。结算中产生的新效果同样先决定再结算
func run_pipeline(preserve_budget:bool = false):
	var pipeline_context:SessionContext = null
	var sources:Array = decision_queue + activation_pool
	if not sources.is_empty() and sources[0] is BaseEffect: pipeline_context = sources[0].runtime_context()
	elif not _active_runs.is_empty(): pipeline_context = _active_runs.back().run.get("context")
	elif not _guard_continuations.is_empty(): pipeline_context = _guard_continuations.front().origin.get("context")
	# 外部可直接填公开队列；先预检，不能先清预算/改 running 再把拒绝当没命中。
	for effect in decision_queue + activation_pool:
		if not effect is BaseEffect or not _effect_entry_is_current(effect): return
	if not preserve_budget and not is_running and _active_runs.is_empty() and not _runtime_guard.paused:
		_runtime_guard.begin_slice()
	is_running = true
	while true:
		if pipeline_context != null and not SessionGeneration.validate_context(pipeline_context).ok: return
		# 回调换局后不消费旧队列，也不执行公告/续行尾部；等待来源归 A1-15。
		for effect in decision_queue + activation_pool:
			if not effect is BaseEffect or not _effect_entry_is_current(effect):
				is_running = false
				return
		#等玩家答复或被要求挑牌，由 submit_active_choice / submit_card_selection 继续跑
		if _runtime_guard.paused or waiting_effect != null or waiting_selection != null or waiting_location != null or waiting_players != null:
			break
		if !decision_queue.is_empty():
			var head = decision_queue[0]
			var queued:int = decision_queue.size()
			drain_decision_queue()
			# 被拒入口既没出队也没开始等待：再转一圈结果相同，停下而不是空转卡死整个进程。
			if not is_waiting_for_choice() and decision_queue.size() == queued and not decision_queue.is_empty() and is_same(decision_queue[0], head):
				break
			continue
		if !activation_pool.is_empty():
			# 已接受的原等待根先释放其旧 FIFO；批次内新选择须先完成自身分支。
			if not _queued_time_point_batches.is_empty() and is_same(_queued_time_point_batches.front().get("root"), activation_pool.front()):
				if not _run_next_queued_time_point():
					if pipeline_context != null and not SessionGeneration.validate_context(pipeline_context).ok: return
					is_running = false
					return
				continue
			resolve_one()
			continue
		#执行到一半提出的选择被放弃、取消或付不起时不会再结算，
		#它挂着的那条效果要从下一步接着做，而不是停在半路
		if _resume_abandoned_choice():
			continue
		break
	is_running = false
	#本时点的效果都结算完了：把攒下的效果提示合并成一条推给玩家。
	#放在这里而不是每个效果各推一条——同一时点连续触发的一批效果只弹一次
	_flush_announcements()
	if not is_waiting_for_choice():
		_run_next_queued_time_point()
		_drain_guard_continuations()
	_release_guard_transactions()


#被放弃的选择：不在等待、不在队列、也不在结算池里。找到一个就让它挂着的效果继续，返回是否继续了
func _resume_abandoned_choice() -> bool:
	for choice in _paused_runs.keys():
		if decision_queue.has(choice) or activation_pool.has(choice):
			continue
		if choice == waiting_effect or choice == waiting_selection or choice == waiting_location or choice == waiting_players:
			continue
		_resume_after_choice(choice)
		return true
	return false


#被动直接按顺位加入效果池，不询问；遇到需要玩家决定的效果就停下等答复
func drain_decision_queue():
	while !decision_queue.is_empty():
		var effect = decision_queue[0] as BaseEffect
		if not _effect_entry_is_current(effect): return
		if not effect._is_pure_passive and not _begin_guard_transaction(effect): return
		if is_pruned(effect):
			decision_queue.pop_front()
			continue
		if effect._is_pure_passive:
			decision_queue.pop_front()
			add_to_activation_pool(effect)
			continue
		#选项类效果所有选项都已耗尽用量：没有可选的分支，直接视为放弃，不打扰玩家
		if effect.has_options() and !has_available_options(effect):
			decision_queue.pop_front()
			continue
		# 上一次等待（如已取消的手动请求）留下的旧前态不代表这次新入队；过期就按此刻重新捕获，
		# 否则下方来源校验永远不过，本函数原地返回，run_pipeline 会无限重入。
		if not _waiting_origins.has(effect) or not _waiting_source_is_current(effect):
			var origin:Dictionary = _capture_wait_origin(effect, effect.runtime_context())
			if origin.is_empty(): return
			_waiting_origins[effect] = origin
		if not _waiting_source_is_current(effect): return
		waiting_effect = effect
		var checkpoint = _guard_transactions.get(effect)
		if checkpoint != null and not checkpoint.audit("pause", effect, "player_choice"):
			_guard_audit_failed(effect)
		return


#当前正在等待答复的效果，null表示没有待决定的效果
func get_pending_active_effect() -> BaseEffect:
	return waiting_effect if _waiting_source_is_current(waiting_effect) else null


#本局是否已经触发过这个效果。直接查效果日志，不再另存一份 used_once_effects——
#日志本来就是"发生过什么"的唯一出处
func is_effect_used_once(effect:BaseEffect) -> bool:
	if effect == null:
		return false
	# 负触发 id 的原查询边界不变；合法玩家锚点并不等于场上牌的事实归属。
	if effect._trigger_player_id < 0:
		return false
	# 与记录 effect 事实共用 actor：事件/局势为 -1，玩家效果仍按原玩家查询。
	var id:int = _effect_fact_actor_id(effect)
	return !GameLog.query({"type": "effect", "actor": id, "data": {"effect_name": effect._name}}, null).is_empty()


#效果自己的消耗(effect._cost)付不付得起——纯查询，不改任何状态。
#与 pay_effect_cost 共用同一份判断：界面按它决定"能不能发动"，结算按它决定扣不扣，
#两边不会出现"提示能发动、真发动时却付不起"的分裂。
#消耗形状由数据声明：{"number":N}是魔力数字消耗；{"type":"command_spell","amount":N}是令咒消耗；
#未识别的 type 一律放行——缺声明不给行为，避免新资源形状悄悄拦住老效果
func can_pay_effect_cost(effect:BaseEffect) -> bool:
	# 报价先验原来源；免费/免疫不是旧来源或未知主体的授权。
	if not _effect_entry_is_current(effect): return false
	var id:int = effect._trigger_player_id
	if id == -1: id = GameData.player_id
	if GameDataManager.find_player_data(id).is_empty(): return false
	var cost = effect._cost
	if cost == null:
		return true
	#数字形状：与卡牌费用同构的魔力消耗。无限魔力(is_magic_immune)视为付得起
	if cost is BaseNumber:
		if cost.number <= 0:
			return true
		var player_data:Dictionary = GameDataManager.find_player_data(id)
		if player_data == null or player_data.is_empty():
			return false
		if player_data.get("is_magic_immune", false):
			return true
		var magic = player_data["magic"] as BaseNumber
		return magic != null and magic.number >= cost.number
	#其他资源形状：type 声明消耗哪种资源，amount 声明数量
	if cost is Dictionary and cost.has("type"):
		#令咒不是魔力，is_magic_immune 是"魔力免疫"，不豁免令咒消耗
		if str(cost["type"]) != "command_spell":
			return true
		var count:int = int(cost.get("amount", 0))
		if count <= 0:
			return true
		var pl_data:Dictionary = GameDataManager.find_player_data(id)
		if pl_data == null or pl_data.is_empty():
			return false
		var spells = pl_data["command_spell_count"] as BaseNumber
		return spells != null and spells.number >= count
	return true


# 仅正的已识别费用需要主体授权；报价不建立绑定。
func _has_positive_effect_cost(effect:BaseEffect) -> bool:
	if effect == null: return false
	var cost = effect._cost
	if cost is BaseNumber: return cost.number > 0
	return cost is Dictionary and str(cost.get("type", "")) == "command_spell" and int(cost.get("amount", 0)) > 0

func _remember_payment_subject(effect:BaseEffect) -> void:
	if not _has_positive_effect_cost(effect) or effect.has_meta(PAYMENT_SUBJECT_META): return
	var id:int = effect._trigger_player_id if effect._trigger_player_id >= 0 else GameData.player_id
	var data:Dictionary = GameDataManager.find_player_data(id)
	if not data.is_empty():
		var subject := PaymentSubject.new(data)
		_payment_subject_bindings().append(subject)
		effect.set_meta(PAYMENT_SUBJECT_META, {"session":_payment_session_token(), "id":id, "subject":weakref(subject)})

func _payment_subject_is_current(effect:BaseEffect, id:int, data:Dictionary) -> bool:
	if data.is_empty() or _payment_session_token() == null: return false
	if effect == null or not effect.has_meta(PAYMENT_SUBJECT_META): return true
	var binding:Dictionary = effect.get_meta(PAYMENT_SUBJECT_META)
	var subject = binding.subject.get_ref()
	return preload("res://scripts/system/session_generation.gd").validate_token(binding.session).ok and binding.id == id and subject != null and is_same(subject.data, data)

#效果自己的消耗(effect._cost)：明确支付成功/合法豁免返回true，拒付返回false。
#报价不是余额锁；付款必须复核主体并消费底层明确的 bool。
#魔力消耗与卡牌出牌同一套规则：无限魔力(is_magic_immune)状态下不检查也不扣；
#扣费复用EditMagic，让魔力变化照常派发MAGIC_DECREASE时点。
#令咒消耗扣command_spell_count并派发COMMAND_SPELL_USED时点
const PAYMENT_COMPLETED:String = "completed"
const PAYMENT_PENDING:String = "pending"
const PAYMENT_REJECTED:String = "rejected"
const PAYMENT_RECEIPT_META:StringName = &"effect_payment_receipt"

# 旧外部调用的过渡入口；新调用须消费 pay_effect_cost_result 的三态。
func pay_effect_cost(effect:BaseEffect) -> bool:
	return pay_effect_cost_result(effect).status == PAYMENT_COMPLETED

func _payment_result(status:String, reason:String = "") -> Dictionary:
	return {"status":status, "reason":reason}

func _reject_payment_result(effect:BaseEffect, reason:String) -> Dictionary:
	# 失效/未知请求没有本局获准主体；不把旧局提示投到同 ID 的新玩家。
	if _has_positive_effect_cost(effect):
		var id:int = effect._trigger_player_id if effect._trigger_player_id >= 0 else GameData.player_id
		if _payment_subject_is_current(effect, id, GameDataManager.find_player_data(id)):
			push_message("代价无法支付，已取消发动。", id)
	return _payment_result(PAYMENT_REJECTED, reason)

# completed 才能发动；pending 必须等待恢复，rejected 提示并取消。
# 审计暂停不是拒付；若实际支付已完成，保留回执避免恢复时重复扣费。
func pay_effect_cost_result(effect:BaseEffect) -> Dictionary:
	# 付款入口同样先验原登记/来源；不能让 null、旧对象或免费形状绕过授权。
	if not _effect_entry_is_current(effect):
		return _payment_result(PAYMENT_REJECTED, "invalid_source")
	if _has_positive_effect_cost(effect):
		var id:int = effect._trigger_player_id if effect._trigger_player_id >= 0 else GameData.player_id
		if not _payment_subject_is_current(effect, id, GameDataManager.find_player_data(id)):
			return _payment_result(PAYMENT_REJECTED, "invalid_subject")
	if _runtime_guard.paused or not MatchJournal.audit_error.is_empty():
		return _payment_result(PAYMENT_PENDING, "runtime_guard")
	if effect != null and effect.has_meta(PAYMENT_RECEIPT_META):
		var receipt:Dictionary = effect.get_meta(PAYMENT_RECEIPT_META)
		if receipt.session == _payment_session_token() and receipt.completed:
			if not _guard_audit_confirmed(effect): return _payment_result(PAYMENT_PENDING, "audit")
			effect.remove_meta(PAYMENT_RECEIPT_META)
			return _payment_result(PAYMENT_COMPLETED)
	if not _begin_guard_transaction(effect):
		return _payment_result(PAYMENT_PENDING, "audit")
	var session:RefCounted = _payment_session_token()
	var previous_scope = _transaction_scope
	_transaction_scope = _guard_transactions.get(effect)
	var accepted:bool = _pay_effect_cost(effect)
	if session != _payment_session_token(): return _payment_result(PAYMENT_REJECTED, "session_changed")
	_transaction_scope = previous_scope
	if _runtime_guard.paused or not MatchJournal.audit_error.is_empty() or (accepted and not _guard_audit_confirmed(effect)):
		if accepted and effect != null:
			effect.set_meta(PAYMENT_RECEIPT_META, {"session":session, "completed":true})
		return _payment_result(PAYMENT_PENDING, "runtime_guard")
	if not accepted: return _reject_payment_result(effect, "cannot_pay")
	return _payment_result(PAYMENT_COMPLETED)

func _pay_effect_cost(effect:BaseEffect) -> bool:
	if !can_pay_effect_cost(effect):
		return false
	if effect == null or effect._cost == null:
		return true
	var cost = effect._cost
	var id:int = effect._trigger_player_id
	if id < 0:
		id = GameData.player_id
	if cost is BaseNumber:
		if cost.number <= 0:
			return true
		var player_data:Dictionary = GameDataManager.find_player_data(id)
		if not _payment_subject_is_current(effect, id, player_data):
			return false
		if player_data.get("is_magic_immune", false):
			return true
		var session:RefCounted = _payment_session_token()
		#手动发动的付款发生在效果执行帧之外；用效果自身已验的本局来源，不借当前帧
		var paid = preload("res://scripts/system/operation_router.gd").exec_registered("edit_magic", [null, BaseNumber.new(0 - cost.number), id, "effect_cost", effect, effect.runtime_context()], effect.runtime_context())
		return paid is bool and paid and session == _payment_session_token() and is_same(player_data, GameDataManager.find_player_data(id))
	if cost is Dictionary and cost.has("type"):
		if str(cost["type"]) != "command_spell":
			return true
		return _pay_command_spell_cost(effect, int(cost.get("amount", 0)))
	return true


#令咒消耗：扣玩家的command_spell_count，记日志并派发COMMAND_SPELL_USED时点。
#数量不足时拒绝且不扣。count为0视为没声明，直接放行
func _pay_command_spell_cost(effect:BaseEffect, count:int) -> bool:
	if count <= 0:
		return true
	var id:int = effect._trigger_player_id
	if id < 0:
		id = GameData.player_id
	var player_data:Dictionary = GameDataManager.find_player_data(id)
	if not _payment_subject_is_current(effect, id, player_data):
		return false
	_remember_payment_subject(effect)
	var session:RefCounted = _payment_session_token()
	var spells = player_data["command_spell_count"] as BaseNumber
	if spells == null or spells.number < count:
		return false
	#即将使用令咒：效果可以让这次不消耗令咒（取消），或改写消耗的数量
	var action:Dictionary = begin_pending_action(TimePoints.BEFORE_COMMAND_SPELL_SPEND, id,
		{"amount": BaseNumber.new(count)}, effect)
	var current_data:Dictionary = GameDataManager.find_player_data(id)
	if session != _payment_session_token() or action.get("invalidated", false) or not is_same(player_data, current_data) or not _payment_subject_is_current(effect, id, current_data):
		return false
	if _runtime_guard.paused or not MatchJournal.audit_error.is_empty(): return false
	if action.get("cancelled", false):
		return true
	count = maxi(0, int((action.values.amount as BaseNumber).number))
	# 同主体可替换资源对象；只对当前对象复核并扣减。
	spells = current_data["command_spell_count"] as BaseNumber
	if spells == null or spells.number < count:
		return false
	var spells_before:int = spells.number
	spells.minus(BaseNumber.new(count))
	EditDataNumber.notify_changed(id, "command_spell_count", spells_before, spells.number, effect.runtime_context())
	GameLog.record("command_spell_used", id, -1, "", effect, ["command_spell_used"],
		{"amount": count})
	TimePointChecker.dynamic_time_point([TimePoints.COMMAND_SPELL_USED], id)
	return session == _payment_session_token() and is_same(current_data, GameDataManager.find_player_data(id))


#正在等待玩家挑牌的效果信息，供界面生成选牌面板；没有等待时返回空字典
func get_pending_card_selection() -> Dictionary:
	if not _waiting_source_is_current(waiting_selection): return {}
	if waiting_selection == null:
		return {}
	var spec := card_selection_spec(waiting_selection)
	return {
		"effect" : waiting_selection,
		"shown_name" : waiting_selection.get_shown_name(),
		"min" : int(spec.get("min", 1)),
		"max" : int(spec.get("max", 1)),
		"cards" : card_selection_source(waiting_selection),
		"required_cards" : card_selection_required(waiting_selection),
		"option_index" : _waiting_selection_option,
		"allow_cancel" : choice_allows_cancel(waiting_selection, _waiting_selection_option),
	}


#当前等待的选牌所在选项的下标。引擎在等待选牌时一直记录，提交后清零。
#给 UI 用：选项 tags（如 secret_choice）的读取需要这个下标
func get_pending_card_selection_option_index() -> int:
	return _waiting_selection_option if _waiting_source_is_current(waiting_selection) else -1


func is_waiting_for_card_selection() -> bool:
	return waiting_selection != null


#当前等待挑牌的这次声明的选牌要求（选项级）。没有等待或该项没声明时返回空字典
func card_selection_spec(effect:BaseEffect) -> Dictionary:
	if effect == null or _waiting_selection_option < 0 or _waiting_selection_option >= effect._options.size():
		return {}
	var spec = effect._options[_waiting_selection_option].get("select_cards", null)
	if !(spec is Dictionary):
		return {}
	return spec


#挑牌的来源数组：按声明的 source（player_data 的键名）取。
#来源由数据声明而不是写死手牌——以后"从弃牌堆挑一张"之类不必改这里
# "挑谁的牌"同样由声明决定：owner 写 target_player 时取先由 select_players 选定的那名玩家；
# 未声明时保持原语义（触发者自己），既有卡不受影响
func card_selection_source(effect:BaseEffect) -> Array:
	if effect == null:
		return []
	var spec := card_selection_spec(effect)
	return _card_selection_cards(effect, spec)


# 必选范围同候选一样由数据来源声明；每次查询读实时牌区，不缓存快照。
func card_selection_required(effect:BaseEffect) -> Array:
	var spec := card_selection_spec(effect)
	if spec.has("mandatory_candidates"):
		return _evaluate_candidate_cards(spec.get("mandatory_candidates"), effect)
	return _card_selection_cards(effect, {"source": spec.get("mandatory_source", []), "owner": spec.get("owner", "")})


func _card_selection_cards(effect:BaseEffect, spec:Dictionary) -> Array:
	if effect == null:
		return []
	#候选牌由数据声明的 operation 串求值（与 select_players.candidates 同一写法、同一求值入口）：
	#每条描述返回一个数组，并集（去重）即候选；引擎不认识任何具体牌区或筛选条件
	if spec.has("candidates"):
		return _evaluate_candidate_cards(spec.get("candidates"), effect)
	var declared = spec.get("source", "")
	var keys:Array = declared if declared is Array else [declared]
	if keys.is_empty():
		return []
	var owner_id:int = effect._trigger_player_id
	if str(spec.get("owner", "")) == CARD_SELECTION_OWNER_TARGET:
		owner_id = effect._selected_player
	elif str(spec.get("owner", "")) == "event_player":
		owner_id = effect._event_player_id
	if owner_id == -1:
		return []
	var pl_data = GameDataManager.find_player_data(owner_id) as Dictionary
	if pl_data == null:
		return []
	# 多来源只合并真实对象引用，不复制卡，也不改动来源数组。
	# 同一对象通过重复来源或跨区引用出现时，只提供一次。
	var arr:Array = []
	for key in keys:
		if !(key is String) or key == "":
			continue
		var zone = pl_data.get(key, null)
		if zone == null:
			zone = pl_data
			for part in str(key).split("."):
				zone = zone.get(part) if zone is Dictionary or zone is Object else null
		_append_selection_cards(zone, arr)
	if str(spec.get("card_type", "")) == "hand_card":
		arr = arr.filter(func(card): return card is BaseHandCard)
	if bool(spec.get("exclude_source_card", false)):
		arr.erase(GetEffSourceCard.new().exec(effect))
	if spec.has("excluded_source"):
		var excluded := _card_selection_cards(effect, {"source": spec.excluded_source, "owner": spec.get("owner", "")})
		arr = arr.filter(func(card): return not excluded.has(card))
	if str(spec.get("card_type", "")) == "servant_skill":
		arr = arr.filter(func(card): return card is BaseSkill and card.get_from() is BaseServant)
	#可选的属性筛选：卡面「从手牌打出一张力量基础攻击」这类限定由数据声明，
	#候选里就不会出现选不了的目标（与 select_players 的候选集同一口径：
	#范围由数据算，引擎不认识任何具体牌型）
	var wanted = spec.get("attributes", null)
	if wanted is Array and !wanted.is_empty():
		arr = GetCardsByAttributesFrArr.new().exec(wanted, arr)
	#可选的属性等值筛选：卡面「基础攻击」这类限定由数据声明 {属性名: 值}，
	#逐项交给通用 FilterByProperty，引擎不认识具体字段或牌型
	var property_filters = spec.get("property_filters", null)
	if property_filters is Dictionary:
		var filter := FilterByProperty.new()
		for property in property_filters:
			arr = filter.exec(arr, str(property), property_filters[property])
	#可选的印刷威力上限：卡面「打出至多3张基本威力为3或更低的手牌」这类限定，
	#与 attributes 同属"候选范围由数据算"（引擎不认识具体牌型，也不写死数字）
	var max_power = spec.get("max_power", null)
	if max_power != null:
		var kept:Array = []
		for card in arr:
			if card is BaseAttack and (card._power as BaseNumber).number <= int(max_power):
				kept.append(card)
		arr = kept
	return arr


# 候选牌求值：与 get_player_selection_candidates 同口径（临时置当前效果，-1 即效果触发者）
func _evaluate_candidate_cards(descs, effect:BaseEffect) -> Array:
	var cards:Array = []
	if descs is Dictionary:
		descs = [descs]
	if !(descs is Array):
		return cards
	var prev_eff = activating_eff
	var prev_vars:Array = effect._self_vars.duplicate()
	activating_eff = effect
	effect._self_vars = []
	var last = null
	for desc in descs:
		if !(desc is Dictionary) and !(desc is BaseFunc):
			continue
		var res:Array = run_func_descriptor(desc, effect, effect.runtime_context())
		if res[0]:
			last = res[1]
	#一串描述按效果链规则执行（可用 self_var 串联），最后一步的返回数组即候选
	if last is Array:
		for card in last:
			if card != null and not cards.has(card):
				cards.append(card)
	effect._self_vars = prev_vars
	activating_eff = prev_eff
	return cards


# 只递归数据声明的区域字典，不遍历卡牌或角色对象，避免把模板当实际持有牌。
func _append_selection_cards(zone, cards:Array) -> void:
	if zone is Array:
		for card in zone:
			if card != null and not cards.has(card):
				cards.append(card)
	elif zone is Dictionary:
		for value in zone.values():
			_append_selection_cards(value, cards)


#本次提交里第一个"还要求玩家挑牌"的选项下标（没有则 -1）。
#一次提交只处理一个：当前规则一次只选一项，多选场景下"挑完一个再问下一个"不属于本函数职责
func _option_requiring_card_selection(effect:BaseEffect, selection:Dictionary) -> int:
	for idx in selection.keys():
		if !(idx is int) or idx < 0 or idx >= effect._options.size():
			continue
		var spec = effect._options[idx].get("select_cards", null)
		if spec is Dictionary and int(spec.get("max", 1)) != 0:
			return idx
	return -1


# 位置选择与 select_cards 同为选项级的延迟输入；只有选项显式声明才会等待。
func _option_requiring_location_selection(effect:BaseEffect, selection:Dictionary) -> int:
	for idx in selection.keys():
		if !(idx is int) or idx < 0 or idx >= effect._options.size():
			continue
		if effect._options[idx].get("select_location", null) is Dictionary:
			return idx
	return -1


#玩家目标选择同样是选项级延迟输入：只有选项声明了 select_players 才会等待
func _option_requiring_player_selection(effect:BaseEffect, selection:Dictionary) -> int:
	for idx in selection.keys():
		if !(idx is int) or idx < 0 or idx >= effect._options.size():
			continue
		if effect._options[idx].get("select_players", null) is Dictionary:
			return idx
	return -1


#候选玩家集由选项声明的 candidates 求值得到：那段声明是普通 func 描述（可写多条），
#用与效果链完全相同的求值入口跑，把每条返回的数组并起来即候选id。
#候选范围（同战区、在场、某职阶拥有者…）全部由数据决定，引擎不认识任何具体范围
func get_player_selection_candidates(spec:Dictionary, effect:BaseEffect) -> Array:
	var ids:Array = []
	var descs = spec.get("candidates", [])
	if descs is Dictionary or descs is String:
		descs = [descs]
	if !(descs is Array):
		return ids
	#求值要在"本效果为当前效果"的上下文里进行：候选声明里的 -1 表示"效果的触发者"，
	#而查询可能发生在还没激活时（如选项可选性判断）。临时置上下文并在结束后还原，
	#这样候选声明与效果链用同一套 player_id 约定，数据不必为"查询时点"换写法
	var prev_eff = activating_eff
	activating_eff = effect
	for desc in descs:
		if !(desc is Dictionary) and !(desc is BaseFunc):
			continue
		var res:Array = run_func_descriptor(desc, effect, effect.runtime_context())
		if !res[0] or !(res[1] is Array):
			continue
		for raw_id in res[1]:
			var id:int = int(raw_id)
			if GameData.player_data_library.has(id) and !ids.has(id):
				ids.append(id)
	activating_eff = prev_eff
	return ids


func get_pending_player_selection() -> Dictionary:
	if not _waiting_source_is_current(waiting_players): return {}
	if waiting_players == null:
		return {}
	var pending:Dictionary = _pending_player_choice.get(waiting_players, {})
	var option_index:int = int(pending.get("option", -1))
	if option_index < 0 or option_index >= waiting_players._options.size():
		return {}
	var spec:Dictionary = waiting_players._options[option_index].get("select_players", {})
	return {"effect": waiting_players, "spec": spec,
		"candidates": (pending.get("candidates", []) as Array).duplicate(),
		"allow_cancel": choice_allows_cancel(waiting_players, option_index)}


#提交玩家目标选择，仍在支付前。校验两条：人数落在声明范围内、每个目标都在候选集里。
#不合法时整体按"放弃"处理（与选牌一致），避免 UI 传坏数据时结算到不该结算的目标
func submit_player_selection(effect:BaseEffect, players:Array) -> bool:
	if not _waiting_source_is_current(effect):
		_discard_exact_wait(effect)
		return false
	var origin:Dictionary = _waiting_origins[effect]
	var session:RefCounted = _payment_session_token()
	if effect == null or waiting_players != effect:
		return false
	var pending:Dictionary = _pending_player_choice.get(effect, {})
	var option_index:int = int(pending.get("option", -1))
	var selection:Dictionary = pending.get("selection", {})
	waiting_players = null
	_pending_player_choice.erase(effect)
	if option_index < 0 or option_index >= effect._options.size() or selection.is_empty():
		if !is_running: run_pipeline()
		return false
	var spec:Dictionary = effect._options[option_index].get("select_players", {})
	var candidates:Array = pending.get("candidates", [])
	var min_count:int = int(spec.get("min", 1))
	var max_count:int = int(spec.get("max", min_count))
	var picked:Array = []
	for raw_id in players:
		var id:int = int(raw_id)
		if !candidates.has(id) or picked.has(id):
			if !is_running: run_pipeline()
			return false
		picked.append(id)
	if picked.size() < min_count or (max_count != -1 and picked.size() > max_count):
		if !is_running: run_pipeline()
		return false
	if not _wait_origin_is_current(origin): return false
	origin["targets"] = picked.duplicate()
	origin["target"] = int(picked[0]) if picked.size() == 1 else -1
	effect._selected_players = picked
	effect._selected_player = int(picked[0]) if picked.size() == 1 else -1
	#同一个选项可以同时要求"选玩家"和"选这名玩家的牌"（如"关闭一名交战玩家至多一张基础攻击"）：
	#先记下目标，再转成等待选牌；支付与用量留到挑完牌，语义与只声明 select_cards 时一致
	#（挑完才扣资源、取消或提交不合法等于这个效果没发动）
	if effect._options[option_index].get("select_cards", null) is Dictionary:
		waiting_selection = effect
		_waiting_selection_option = option_index
		_pending_selection_choice[effect] = selection
		return true
	var payment:Dictionary = pay_effect_cost_result(effect)
	if not _wait_origin_is_current(origin): return false
	if payment.status != PAYMENT_COMPLETED:
		if payment.status == PAYMENT_PENDING: return false
		if session != _payment_session_token(): return false
		effect._selected_players = []
		effect._selected_player = -1
		if !is_running: run_pipeline()
		return false
	record_selection_usage(effect, selection)
	add_to_activation_pool(effect)
	if !is_running: run_pipeline()
	return _wait_origin_is_current(origin) and _guard_audit_confirmed(effect) and _wait_origin_is_current(origin)


func get_pending_location_selection() -> Dictionary:
	if not _waiting_source_is_current(waiting_location): return {}
	if waiting_location == null:
		return {}
	var pending:Dictionary = _pending_location_choice.get(waiting_location, {})
	var option_index:int = int(pending.get("option", -1))
	if option_index < 0 or option_index >= waiting_location._options.size():
		return {}
	return {"effect": waiting_location, "spec": waiting_location._options[option_index].get("select_location", {}), "allow_cancel": choice_allows_cancel(waiting_location, option_index)}


func _location_selection_is_eligible(effect:BaseEffect, spec:Dictionary, location:BaseLocation) -> bool:
	if not _effect_entry_is_current(effect) or effect._trigger_player_id == -1 or location == null:
		return false
	var player_data:Dictionary = GameDataManager.find_player_data(effect._trigger_player_id)
	if player_data.is_empty(): return false
	var origin:BaseLocation = player_data.get("location") as BaseLocation
	var origin_area:BaseMapArea = origin.get_from() as BaseMapArea if origin != null else null
	var target_area:BaseMapArea = location.get_from() as BaseMapArea
	if origin_area == null or target_area == null or not SetLocation.current_map_location(location): return false
	var allowed:Array = spec.get("allowed_origin_areas", []) as Array
	if not allowed.is_empty() and not allowed.has(str(origin_area._area_name)): return false
	var forbidden:Array = spec.get("forbidden_target_areas", []) as Array
	if forbidden.has(str(target_area._area_name)): return false
	if SetLocation.locked_area_for_move(effect._trigger_player_id, target_area) != null: return false
	# 席位口径与候选同源，避免“能点到却提交被拒”。
	return AreaActionRules.effect_slot_accepts(location, spec)


func submit_location_selection(effect:BaseEffect, location:BaseLocation) -> bool:
	if not _waiting_source_is_current(effect):
		_discard_exact_wait(effect)
		return false
	var session:RefCounted = _payment_session_token()
	if effect == null or waiting_location != effect:
		return false
	var pending:Dictionary = _pending_location_choice.get(effect, {})
	var option_index:int = int(pending.get("option", -1))
	var selection:Dictionary = pending.get("selection", {})
	if option_index < 0 or option_index >= effect._options.size() or selection.is_empty():
		if !is_running: run_pipeline()
		return false
	var spec:Dictionary = effect._options[option_index].get("select_location", {})
	if not _location_selection_is_eligible(effect, spec, location):
		return false
	var origin:Dictionary = _waiting_origins[effect]
	waiting_location = null
	_pending_location_choice.erase(effect)
	var start_location:BaseLocation = GetLocation.new().exec(effect._trigger_player_id)
	var origin_area:BaseMapArea = start_location.get_from() as BaseMapArea if start_location != null else null
	var allowed:Array = spec.get("allowed_origin_areas", []) as Array
	if origin_area == null or !(location.get_from() is BaseMapArea):
		if !is_running: run_pipeline()
		return false
	if !allowed.is_empty() and !allowed.has(str(origin_area._area_name)):
		if !is_running: run_pipeline()
		return false
	#目标区域的排除同样由数据声明（卡面「移动至除魔术工房外的任意地点」这类限定），
	#与 allowed_origin_areas 对称：范围由数据算，引擎不认识具体区域名
	var target_area:BaseMapArea = location.get_from() as BaseMapArea
	var forbidden:Array = spec.get("forbidden_target_areas", []) as Array
	if target_area != null and forbidden.has(str(target_area._area_name)):
		if !is_running: run_pipeline()
		return false
	#出发地或目标战区被锁：在支付令咒/魔力与记录用量之前拒绝，等同于没发动
	if SetLocation.locked_area_for_move(effect._trigger_player_id, target_area) != null:
		if !is_running: run_pipeline()
		return false
	if not _wait_origin_is_current(origin): return false
	origin["location"] = location
	effect._selected_location = location
	var payment:Dictionary = pay_effect_cost_result(effect)
	if not _wait_origin_is_current(origin): return false
	if payment.status != PAYMENT_COMPLETED:
		if payment.status == PAYMENT_PENDING: return false
		if session != _payment_session_token(): return false
		effect._selected_location = null
		if !is_running: run_pipeline()
		return false
	record_selection_usage(effect, selection)
	add_to_activation_pool(effect)
	if !is_running: run_pipeline()
	return _wait_origin_is_current(origin) and _guard_audit_confirmed(effect) and _wait_origin_is_current(origin)


#玩家为选牌提交了具体牌张。张数或来源不合法时整体视为放弃：
#此刻资源与用量都还没动过，所以放弃等价于"这个效果没发动"，不会白扣宝石层数
func submit_card_selection(effect:BaseEffect, cards:Array) -> bool:
	if not _waiting_source_is_current(effect):
		_discard_exact_wait(effect)
		return false
	var origin:Dictionary = _waiting_origins[effect]
	var session:RefCounted = _payment_session_token()
	if effect == null or waiting_selection != effect:
		return false
	#声明与来源必须在清掉等待状态之前取好：card_selection_spec 依赖 _waiting_selection_option，
	#先清状态再校验会取到空声明、让合法提交也被判非法
	var spec := card_selection_spec(effect)
	var source := card_selection_source(effect)
	var required := card_selection_required(effect)
	var pending:Dictionary = _pending_selection_choice.get(effect, {})
	var selected_players_for_option:bool = _waiting_selection_option >= 0 and _waiting_selection_option < effect._options.size() and effect._options[_waiting_selection_option].get("select_players", null) is Dictionary
	if !_is_card_selection_valid(spec, source, cards, required) and !choice_allows_cancel(effect, _waiting_selection_option):
		return false
	waiting_selection = null
	_waiting_selection_option = -1
	_pending_selection_choice.erase(effect)
	if spec.is_empty() or !_is_card_selection_valid(spec, source, cards, required):
		effect._selected_cards = []
		if selected_players_for_option:
			effect._selected_players = []
			effect._selected_player = -1
		if !is_running:
			run_pipeline()
		return false
	if not _wait_origin_is_current(origin): return false
	origin["cards"] = cards.duplicate()
	effect._selected_cards = cards.duplicate()
	#挑完牌才真正记用量/扣来源资源，然后把效果交给结算
	var payment:Dictionary = pay_effect_cost_result(effect)
	if not _wait_origin_is_current(origin): return false
	if payment.status != PAYMENT_COMPLETED:
		if payment.status == PAYMENT_PENDING: return false
		if session != _payment_session_token(): return false
		effect._selected_cards = []
		if selected_players_for_option:
			effect._selected_players = []
			effect._selected_player = -1
		if !is_running:
			run_pipeline()
		return false
	record_selection_usage(effect, pending)
	decision_queue.erase(effect)
	add_to_activation_pool(effect)
	if !is_running:
		run_pipeline()
	return _wait_origin_is_current(origin) and _guard_audit_confirmed(effect) and _wait_origin_is_current(origin)


## 公开卡牌选择判定：只校验显式参数，不读取或修改等待状态。
func is_card_selection_valid(spec:Dictionary, source:Array, cards:Array, required:Array = []) -> bool:
	return _is_card_selection_valid(spec, source, cards, required)


#spec 与 source 都由调用方先取好再传进来：这个判断本身不读等待状态，
#免得"先清状态后校验"的顺序问题又把合法提交判成非法
func _is_card_selection_valid(spec:Dictionary, source:Array, cards:Array, required:Array = []) -> bool:
	var low:int = int(spec.get("min", 1))
	var high:int = int(spec.get("max", low))
	if cards.size() < low:
		return false
	if high != -1 and cards.size() > high:
		return false
	for card in required:
		if not source.has(card) or not cards.has(card):
			return false
	var picked:Array = []
	for card in cards:
		#必须来自声明的来源区，且同一张牌不能重复提交
		if card == null or !source.has(card) or picked.has(card):
			return false
		picked.append(card)
	return true



## 显式取消与“提交合法空选择”不同；取消不支付、不记选项次数。
func cancel_pending_choice(effect: BaseEffect) -> bool:
	if effect != null and not _waiting_source_is_current(effect): return _discard_exact_wait(effect)
	if effect == null:
		return false
	if waiting_effect == effect:
		return submit_active_choice(effect, false)
	var option_index := -1
	if waiting_selection == effect:
		option_index = _waiting_selection_option
	elif waiting_players == effect:
		option_index = int(_pending_player_choice.get(effect, {}).get("option", -1))
	elif waiting_location == effect:
		option_index = int(_pending_location_choice.get(effect, {}).get("option", -1))
	else:
		return false
	if not choice_allows_cancel(effect, option_index):
		return false
	if waiting_selection == effect:
		waiting_selection = null
		_waiting_selection_option = -1
		_pending_selection_choice.erase(effect)
	if waiting_players == effect:
		waiting_players = null
		_pending_player_choice.erase(effect)
	if waiting_location == effect:
		waiting_location = null
		_pending_location_choice.erase(effect)
	effect._selected_cards = []
	effect._selected_players = []
	effect._selected_player = -1
	effect._selected_location = null
	decision_queue.erase(effect)
	resolved_effects[effect] = "declined"
	if not is_running:
		run_pipeline()
	return _guard_audit_confirmed(effect)

func is_waiting_for_choice() -> bool:
	return _runtime_guard.paused or waiting_effect != null or waiting_selection != null or waiting_location != null or waiting_players != null


#玩家此刻能不能主动发动这个手动效果。判据全部复用既有规则：
#效果自己声明了 is_manual、属于该玩家、没有别的答复/挑牌在等、
#卡状态允许(每局限一次、每回合一次等)、付得起自己的消耗、
#且当前时点命中它自己声明的发动窗口(time_points 在这类效果上是"允许发动的时机窗口")。
#界面提示与点击入口共用这一个判据，避免出现"看起来能发动、点下去没反应"
func can_manual_activate(effect:BaseEffect, player_id:int) -> bool:
	if not _effect_entry_is_current(effect): return false
	if effect == null or !effect._is_manual:
		return false
	if player_id < 0 or effect._trigger_player_id != player_id:
		return false
	if waiting_effect != null or waiting_selection != null or waiting_location != null or waiting_players != null:
		return false
	if !card_state_allows(effect):
		return false
	# 选项全都不可用（前置条件不满足/次数耗尽）时不询问：这条能力此刻没有可做的事，
	# 进入询问只会让玩家点开一个什么都选不了的窗口
	if effect.has_options() and !has_available_options(effect):
		return false
	if !can_pay_effect_cost(effect):
		return false
	return !get_matched_time_points(effect).is_empty()


#这个玩家此刻有没有"能点着发动"的手动效果。
#战斗阶段与准备好阶段没有点击类操作，界面靠它决定"跳过这个玩家"还是"停下来等他点"——
#只看有没有正在等待的答复会漏掉"还没点、但点得动"的情况：宝石这类手动效果
#不会自己进等待队列，必须等玩家点击才产生等待。
#判据与点击入口、金框提示共用 can_manual_activate，不另写一套
func has_manual_activation(player_id:int) -> bool:
	return not manual_activations(player_id).is_empty()


#列出这个玩家此刻能点着发动的所有手动效果。
#AI 决策与界面停驻判断共用它；判据与点击入口完全同源，不另写一套
func manual_activations(player_id:int) -> Array:
	var result:Array = []
	if player_id < 0:
		return result
	for effect in effect_pool:
		if not (effect is BaseEffect) or not effect._is_manual:
			continue
		if can_manual_activate(effect, player_id):
			result.append(effect)
	return result


#玩家主动发动一个手动效果(如令咒)：把它排进待答复队列，之后的询问、选项弹窗、
#费用支付、放弃语义、用量计数全部走与自动触发效果相同的那条链路。
#返回是否真的开始询问
func request_manual_activation(effect:BaseEffect, player_id:int) -> bool:
	var origin:Dictionary = _capture_wait_origin(effect, effect.runtime_context() if effect != null else null)
	if origin.is_empty(): return false
	if !can_manual_activate(effect, player_id):
		return false
	if not _begin_guard_transaction(effect): return false
	if not _wait_origin_is_current(origin): return false
	_waiting_origins[effect] = origin
	matched_time_points[effect] = get_matched_time_points(effect)
	effect._trigger_time_points = matched_time_points[effect].duplicate()
	#新的一次主动请求不是同一批次里的自动重触发。
	resolved_effects.erase(effect)
	if !decision_queue.has(effect):
		decision_queue.append(effect)
		sort_by_turn_order(decision_queue)
	if !is_running:
		run_pipeline()
	return _wait_origin_is_current(origin) and _guard_audit_confirmed(effect) and _wait_origin_is_current(origin)


# 选择取消权限来自选项数据；未声明时保留既有可取消行为。
func choice_allows_cancel(effect:BaseEffect, option_index:int = -1) -> bool:
	if effect == null:
		return true
	if option_index >= 0 and option_index < effect._options.size():
		return bool(effect._options[option_index].get("allow_cancel", true))
	# 任一选项声明必须答复时，不能跳过整个选择；不按效果名称推断。
	for option in effect._options:
		if not bool(option.get("allow_cancel", true)):
			return false
	return true


# 可选效果拒绝也算完成答复；必须答复的效果拒绝时保留等待。
func _pause_choice_restore_conflict(effect:BaseEffect) -> void:
	# 付款监听若重入了别的等待/队列，不能用旧快照覆盖新工作；保持暂停交给真实恢复门。
	_runtime_guard.paused = true
	_runtime_guard.reason = "choice_restore_conflict"
	_guard_run = {"effect":effect}


func _restore_required_choice_wait(effect:BaseEffect, queue_before:Array, queue_index:int) -> bool:
	if not _waiting_source_is_current(effect): return false
	if _runtime_guard.paused or waiting_selection != null or waiting_location != null or waiting_players != null:
		_pause_choice_restore_conflict(effect)
		return false
	var queue_without_effect:Array = queue_before.duplicate()
	queue_without_effect.erase(effect)
	# 只有付款期间没有改动其它队列成员时才恢复；不抹掉监听产生的新队列工作。
	if decision_queue != queue_without_effect:
		_pause_choice_restore_conflict(effect)
		return false
	var restored_index:int = clampi(queue_index, 0, decision_queue.size())
	decision_queue.insert(restored_index, effect)
	waiting_effect = effect
	return true


func submit_active_choice(effect:BaseEffect, should_activate:bool) -> bool:
	if not _waiting_source_is_current(effect):
		_discard_exact_wait(effect)
		return false
	var origin:Dictionary = _waiting_origins[effect]
	if effect == null or waiting_effect != effect:
		return false
	if !should_activate and !choice_allows_cancel(effect):
		return false
	if should_activate and effect.has_options() and !choice_allows_cancel(effect) and effect._chosen_selection.is_empty() and _pending_selection_choice.get(effect, {}).is_empty():
		return false
	var session:RefCounted = _payment_session_token()
	if should_activate:
		if not _begin_guard_transaction(effect): return false
	if not _wait_origin_is_current(origin): return false
	# 支付前必须摘等待；成功路径的队列/等待/支付/入池顺序保持不变。
	decision_queue.erase(effect)
	waiting_effect = null
	if !should_activate:
		if !ActivateEffect.reject_registration(effect):
			_pause_choice_restore_conflict(effect)
			return false
		#拒绝在本窗口内即放弃：这里必须记一笔，否则 run_pipeline 会立刻把同一个自动效果
		#重新收进决策队列，"拒绝→重问"无限循环，整局卡死（实测：一个没有效果体的空壳效果
		#在战斗阶段能把对局永久卡在第2回合）。窗口轮转由 reset_phase_window_settlements 统一清理，
		#与纯被动效果"窗口内只结算一次"同一口径；玩家之后主动请求会 erase 掉这笔记录（见
		#request_manual_activation），所以拒绝不封死再次发动的机会
		resolved_effects[effect] = "declined"
	if should_activate:
		# 只有付款完成才发动；待续不推进，拒绝取消本次（包括必须答复的选择）。
		var payment:Dictionary = pay_effect_cost_result(effect)
		if not _wait_origin_is_current(origin): return false
		if payment.status != PAYMENT_COMPLETED:
			if payment.status == PAYMENT_PENDING: return false
			if session != _payment_session_token(): return false
			if !ActivateEffect.reject_registration(effect):
				_pause_choice_restore_conflict(effect)
				return false
			_pending_selection_choice.erase(effect)
			resolved_effects[effect] = "declined"
			if !is_running: run_pipeline()
			return false
		var paid_selection:Dictionary = _pending_selection_choice.get(effect, {})
		if not paid_selection.is_empty(): record_selection_usage(effect, paid_selection)
		_pending_selection_choice.erase(effect)
		ActivateEffect.accept_registration(effect)
		add_to_activation_pool(effect)
	if !is_running:
		run_pipeline()
	return _wait_origin_is_current(origin) and _guard_audit_confirmed(effect) and _wait_origin_is_current(origin)


#选项类效果的玩家答复。selection可以是：
#  - Array[int]：下标数组，每项默认用1次(简单单选/多选场景，如令咒三选一)
#  - Dictionary{下标:次数}：同一下标可以要求用多次(一次提交里连用同一选项多次)
#校验不通过(超过用量上限/来源资源不够)时整体视为放弃，避免UI传坏数据时结算到不该结算的分支
func submit_option_choice(effect:BaseEffect, selection) -> bool:
	if not _waiting_source_is_current(effect):
		_discard_exact_wait(effect)
		return false
	var origin:Dictionary = _waiting_origins[effect]
	if effect == null or waiting_effect != effect:
		return false
	var selection_dict:Dictionary = {}
	if selection is Array:
		for idx in selection:
			selection_dict[idx] = selection_dict.get(idx, 0) + 1
	elif selection is Dictionary:
		selection_dict = selection
	else:
		return submit_active_choice(effect, false)
	if selection_dict.is_empty() and !choice_allows_cancel(effect):
		return false
	if !validate_selection(effect, selection_dict):
		return submit_active_choice(effect, false)
	#发动条件先于任何延迟选择、用量记录和资源支付；失败按放弃处理，提示由数据声明。
	if !_option_activation_requirements_met(effect, selection_dict):
		return submit_active_choice(effect, false)
	if not _wait_origin_is_current(origin): return false
	if not _begin_guard_transaction(effect): return false
	if not _wait_origin_is_current(origin): return false
	#选玩家必须排在选牌之前：同一个选项可以声明"选玩家 + 选那名玩家的牌"，
	#选牌要拿 _selected_player 去定位来源区，顺序反了会先停下等选牌却没有目标。
	#只声明其中一项时另一项判为 -1，顺序调整对既有卡没有影响
	var player_option := _option_requiring_player_selection(effect, selection_dict)
	if player_option != -1:
		var candidates:Array = get_player_selection_candidates(effect._options[player_option].get("select_players", {}), effect)
		if not _wait_origin_is_current(origin): return false
		decision_queue.erase(effect)
		waiting_effect = null
		waiting_players = effect
		_pending_player_choice[effect] = {"selection": selection_dict.duplicate(), "option": player_option, "candidates":candidates, "origin":origin}
		return true
	#选中的选项还要求玩家挑具体牌张时，先停下等挑牌：
	#此刻刻意不记用量也不扣来源资源，玩家取消挑牌时等于"这个效果没发动"，不会白扣
	var selection_option := _option_requiring_card_selection(effect, selection_dict)
	if selection_option != -1:
		decision_queue.erase(effect)
		waiting_effect = null
		waiting_selection = effect
		_waiting_selection_option = selection_option
		_pending_selection_choice[effect] = selection_dict
		return true
	var location_option := _option_requiring_location_selection(effect, selection_dict)
	if location_option != -1:
		decision_queue.erase(effect)
		waiting_effect = null
		waiting_location = effect
		_pending_location_choice[effect] = {"selection": selection_dict.duplicate(), "option": location_option, "origin":origin}
		return true
	# 选择先暂存；支付完成之前不扣来源层数、不记用量/option_used。
	_pending_selection_choice[effect] = selection_dict.duplicate()
	return submit_active_choice(effect, true)


func add_to_activation_pool(effect:BaseEffect):
	if not _effect_entry_is_current(effect): return
	if effect == null or activation_pool.has(effect):
		return
	if not _inherit_guard_transaction(effect): return
	if not _effect_entry_is_current(effect): return
	activation_pool.append(effect)
	sort_by_priority(activation_pool)


#结算效果池里优先级最高的一个。一次只结算一个，
#这样它关闭时点或反制其他效果的结果能立刻影响后面还没结算的效果
func resolve_one():
	while !activation_pool.is_empty():
		# 必须在 pop/guard/已结算标记之前独立拒绝绕过入池门的旧对象。
		if not _effect_entry_is_current(activation_pool[0] as BaseEffect): return
		if not _begin_guard_transaction(activation_pool[0] as BaseEffect): return
		if not _effect_entry_is_current(activation_pool[0] as BaseEffect): return
		var effect = activation_pool.pop_front() as BaseEffect
		if is_pruned(effect):
			continue
		if resolved_effects.has(effect):
			continue
		#优先级为-1是未填写的占位符，跳过不结算
		if effect._priority < 0:
			continue
		if not _begin_guard_transaction(effect): return
		resolved_effects[effect] = time_point_id
		activating_eff = effect
		activate_effect(effect)
		if not _effect_origin_is_current(effect): return
		activating_eff = null
		return


#时点关闭
#关闭某个时点(如结束其他玩家的回合)。因该时点触发、且没有其他命中时点的效果会被打断。
#已经结算完的效果不回滚——规则里没有回退机制。player_id为-1表示关闭所有玩家的该时点
func close_time_point(time_point:String, player_id:int = -1):
	if activating_eff != null and not _effect_entry_is_current(activating_eff): return
	if player_id != -1 and GameDataManager.find_player_data(player_id).is_empty(): return
	var ids:Array = []
	if player_id != -1:
		ids.append(player_id)
	else:
		ids = get_all_players_id()
	for id in ids:
		var closed = closed_time_points.get(id, []) as Array
		if !closed.has(time_point):
			closed.append(time_point)
		closed_time_points[id] = closed
		var pl_data:Dictionary = GameDataManager.find_player_data(id)
		if pl_data.is_empty(): continue
		erase_all(pl_data["current_time_points"] as Array, time_point)
		erase_all(pl_data["dynamic_time_points"] as Array, time_point)
	prune_closed()


func is_time_point_closed(time_point:String, player_id:int) -> bool:
	var closed = closed_time_points.get(player_id, []) as Array
	return closed.has(time_point)


func erase_all(arr:Array, value):
	var i = arr.find(value)
	while i != -1:
		arr.remove_at(i)
		i = arr.find(value)


#把被关闭的时点从各效果的命中集合里剔除，命中集合空掉的效果就被打断
func prune_closed():
	for effect in matched_time_points.keys():
		var matched = matched_time_points[effect] as Array
		var closed = closed_time_points.get(effect._trigger_player_id, []) as Array
		for tp in closed:
			erase_all(matched, tp)
		if matched.is_empty():
			decision_queue.erase(effect)
			activation_pool.erase(effect)
			#正在等待答复或等待挑牌的效果也一并打断
			if waiting_effect == effect:
				waiting_effect = null
			if waiting_selection == effect:
				waiting_selection = null
				_waiting_selection_option = -1
				_pending_selection_choice.erase(effect)


func is_pruned(effect:BaseEffect) -> bool:
	if !matched_time_points.has(effect):
		return false
	return (matched_time_points[effect] as Array).is_empty()


#反制
#countered_func留空时整个效果不结算；否则只跳过其中一个func，效果里其余func照常
func counter_effect(effect:BaseEffect, countered_func:BaseFunc = null):
	if effect == null:
		return
	if countered_func == null:
		decision_queue.erase(effect)
		activation_pool.erase(effect)
		if waiting_effect == effect:
			waiting_effect = null
		if waiting_selection == effect:
			waiting_selection = null
			_waiting_selection_option = -1
			_pending_selection_choice.erase(effect)
		return
	var funcs = countered_funcs.get(effect, []) as Array
	if !funcs.has(countered_func):
		funcs.append(countered_func)
	countered_funcs[effect] = funcs


func is_func_countered(effect:BaseEffect, _func:BaseFunc) -> bool:
	if !countered_funcs.has(effect):
		return false
	return (countered_funcs[effect] as Array).has(_func)


#效果执行
#只管理时点上下文，不推进回合，也不再维护效果批次索引
func start_effect():
	TimePointChecker.consume_transient_time_points()


func end_effect():
	TimePointChecker.time_point_check()


#把占位符解析成实际值。{"number_index":i}取效果自带的数字，{"self_var":i}取前面func存下的返回值，
#{"option_quantity_index":i}取第 i 个选项本次玩家额外选定的数量(选项声明了quantity_range才有)。
#返回[是否解析成功, 值]，越界或下标为-1、或该项数量没被玩家设定时视为失败
func resolve_placeholder(para, effect:BaseEffect, context:SessionContext = null) -> Array:
	context = _captured_function_context(context)
	var status:Dictionary = _effect_execution_status(effect, context)
	if not status.ok:
		_reject_execution_source(context, status.reason)
		return [false, null]
	if !(para is Dictionary):
		return [true, para]

	if para.has("number_index"):
		var i = para["number_index"] as int
		if i < 0 or i >= effect._using_numbers.size():
			return [false, null]
		return [true, effect._using_numbers[i]]

	if para.has("option_quantity_index"):
		var oi = para["option_quantity_index"] as int
		if oi < 0 or oi >= effect._options.size():
			return [false, null]
		#玩家没为这项设定过数量(0)时视为失败：调用方通常用 for_func 按数量重复，
		#数量为0本就该什么都不做，不必让调用方再写一层条件
		var qty := effect.get_option_quantity(oi)
		if qty <= 0:
			return [false, null]
		return [true, qty]

	if para.has("self_var"):
		var i = para["self_var"] as int
		if i < 0 or i >= effect._self_vars.size():
			return [false, null]
		return [true, effect._self_vars[i]]

	return [true, para]


#判断func的执行条件是否成立
func check_condition(_func:BaseFunc, effect:BaseEffect, context:SessionContext = null) -> bool:
	context = _captured_function_context(context)
	if not _accept_function_source(_func, effect, context): return false
	if _func._condition == null:
		return true
	var resolved = resolve_placeholder(_func._condition, effect, context)
	if !resolved[0]:
		return false
	var value = resolved[1]
	#跳过的生产者可能留下已解析的空槽；它不是无条件声明，也不能传给 bool 构造器。
	if value == null:
		return false
	if value is BaseNumber:
		return value.number != 0
	return bool(value)


#执行单个BaseFunc：反制检查、条件检查、延迟绑定、参数解析、调用、写回var_index。
#抽成公共入口，好让循环类operation(ForFunc/ForeachFunc/WhileFunc)复用同一套规则，
#而不是直接调callable绕开self_var/number_index/condition。
#返回[是否真正调用了callable, 调用结果]；未调用时结果为null
func run_base_func(f:BaseFunc, effect:BaseEffect, context:SessionContext = null) -> Array:
	context = _captured_function_context(context)
	if not _accept_function_source(f, effect, context): return [false, null]
	var frame := {"function": f, "effect": effect, "context":context, "stage": "condition", "parameters": []}
	var depth := _function_frames.size()
	if depth < _resume_frames.size() and _resume_frames[depth] != null:
		var saved:Dictionary = _resume_frames[depth]
		if not _accept_function_source(saved.get("function"), saved.get("effect"), saved.get("context")): return [false, null]
		if not is_same(saved.get("effect"), effect) or not is_same(saved.get("function"), f):
			_reject_execution_source(context, &"stale_session")
			return [false, null]
		frame = saved
		_resume_frames[depth] = null
		frame["resuming"] = true
		f = frame.function
	_function_frames.append(frame)
	var outcome: Array = _run_base_func(f, effect, frame)
	_function_frames.pop_back()
	return outcome

func _run_base_func(f:BaseFunc, effect:BaseEffect, frame:Dictionary) -> Array:
	var context:SessionContext = frame.get("context")
	if not _accept_function_source(f, effect, context): return [false, null]
	if frame.get("resuming", false):
		return _invoke_function_frame(f, effect, frame)
	var raw_params:Array = f._parameters.duplicate()
	#没真正调用的失败也留一条记录，否则分不清"JSON 没执行"与"条件没满足"。
	#先落记录再立刻结束，call_id 才连续、父子关系也不断
	if is_func_countered(effect, f):
		GameLog.end_func_call(GameLog.begin_func_call(effect, f._name, raw_params, []), null, "countered")
		return [false, null]
	if !check_condition(f, effect, context):
		if not _accept_function_source(f, effect, context): return [false, null]
		GameLog.end_func_call(GameLog.begin_func_call(effect, f._name, raw_params, []), null, "condition_false")
		return [false, null]

	if not _accept_function_source(f, effect, context): return [false, null]
	var callable:Callable = f.runtime_callable(effect, context)
	#延迟绑定的方法调用，目标对象此刻才从变量表里取出
	if f._self_var_index != -1:
		if f._self_var_index >= effect._self_vars.size():
			GameLog.end_func_call(GameLog.begin_func_call(effect, f._name, raw_params, []), null, "invalid_target")
			return [false, null]
		var target = effect._self_vars[f._self_var_index]
		if target == null or !target.has_method(f._method_name):
			GameLog.end_func_call(GameLog.begin_func_call(effect, f._name, raw_params, []), null, "invalid_target")
			return [false, null]
		callable = Callable(target, f._method_name)
	if !callable.is_valid():
		GameLog.end_func_call(GameLog.begin_func_call(effect, f._name, raw_params, []), null, "invalid_callable")
		return [false, null]

	var paras = f._parameters.duplicate()
	frame.stage = "parameters"
	var paras_ready:bool = true
	for i in paras.size():
		var resolved = resolve_placeholder(paras[i], effect, context)
		if !resolved[0]:
			paras_ready = false
			break
		paras[i] = resolved[1]
	#参数解析不出来就跳过这个func，但效果里后续的func照常处理
	if !paras_ready:
		if not _accept_function_source(f, effect, context): return [false, null]
		GameLog.end_func_call(GameLog.begin_func_call(effect, f._name, raw_params, []), null, "invalid_parameter")
		return [false, null]

	#先落记录再调用：嵌套进来的 func 才会排在本条之后、parent 指向本条
	if not _accept_function_source(f, effect, context): return [false, null]
	var call_id:int = GameLog.begin_func_call(effect, f._name, raw_params, paras)
	frame.parameters = paras
	frame["callable"] = callable
	frame["call_id"] = call_id
	frame.stage = "call"
	return _invoke_function_frame(f, effect, frame)

func _invoke_function_frame(f:BaseFunc, effect:BaseEffect, frame:Dictionary) -> Array:
	var context:SessionContext = frame.get("context")
	if not _accept_function_source(f, effect, context): return [false, null]
	if frame.get("resuming", false):
		frame.call_id = GameLog.begin_func_call(effect, f._name, f._parameters, frame.parameters)
	var result
	if frame.get("stage") == "native_pending":
		result = _resume_native_guard_frame(frame)
	else:
		if _native_guard_adapter(frame) != &"": frame["native_running"] = is_running
		result = frame.callable.callv(frame.parameters)
		if _runtime_guard.paused and _native_guard_adapter(frame) != &"":
			frame["result"] = result
			frame.stage = "native_pending"
			_set_native_guard_outcome(frame, "PENDING", _runtime_guard.reason)
			_retain_native_guard_tail(frame, _transaction_scope)
	if _runtime_guard.paused and _native_guard_adapter(frame) == &"queue_registration":
		_guard_frames = _function_frames.duplicate()
	# 同步 BEFORE/方法回调返回后，先原源复验，再碰结果、自变量或日志。
	if not _accept_function_source(f, effect, context): return [false, null]
	if frame.get("control", {}).get("status") == "REJECTED":
		_reject_execution_source(context, StringName(frame.control.reason))
		return [false, null]
	if _runtime_guard.paused:
		GameLog.end_func_call(frame.call_id, null, "runtime_paused")
		return [false, null]
	if frame.has("control"): _set_native_guard_outcome(frame, "COMPLETED")
	frame.stage = "result"
	frame["result"] = result
	if f._var_index != -1:
		while effect._self_vars.size() <= f._var_index:
			effect._self_vars.append(null)
		effect._self_vars[f._var_index] = result
	GameLog.end_func_call(frame.call_id, result, "executed")
	return [true, result]


#按JSON可表达的函数描述{"func_name":.., "parameters":[..], "var_index":-1, "condition":null}
#动态加载operation并执行，规则与load_game.gd里加载func_name的方式一致。
#兼容直接传入BaseFunc(内部/旧代码构造的循环体)。
#用于循环体这类"JSON里无法直接构造BaseFunc/Callable"的场合，
#让self_var既能传数组/次数，也能传循环体本身需要的参数。
#返回同run_base_func：[是否真正调用了callable, 调用结果]
func run_func_descriptor(desc, effect:BaseEffect, context:SessionContext = null) -> Array:
	# 二参只供已有循环继承已验帧；无帧直接入口缺 context 必拒绝。
	context = _captured_function_context(context)
	var status:Dictionary = _effect_execution_status(effect, context)
	if not status.ok:
		_reject_execution_source(context, status.reason)
		return [false, null]
	if desc is BaseFunc:
		return run_base_func(desc, effect, context)
	if not desc is Dictionary: return [false, null]
	# 可信工厂独占构造/能力审查/绑定；消费口不 new 无来源函数，不取 current。
	var funcs:Array = LoadHelper.load_funcs([desc], effect, context)
	status = _effect_execution_status(effect, context)
	if not status.ok:
		_reject_execution_source(context, status.reason)
		return [false, null]
	if funcs.size() != 1: return [false, null]
	return run_base_func(funcs[0], effect, context)


#效果执行到一半要玩家做选择：operation 把建好的选择效果交到这里，
#当前这一步做完后整条效果暂停，选完（或放弃）再从下一步接着做。
#同一步里提出多个选择时按提出顺序依次问
func request_choice(choice:BaseEffect, context:SessionContext = null) -> bool:
	context = _captured_function_context(context)
	var root:BaseEffect = _active_runs.back().run.effect if not _active_runs.is_empty() else (_function_frames.back().get("effect") if not _function_frames.is_empty() else choice)
	var origin:Dictionary = _capture_wait_origin(choice, context, root)
	if origin.is_empty(): return false
	if not _inherit_guard_transaction(choice): return false
	if not _wait_origin_is_current(origin): return false
	_waiting_origins[choice] = origin
	_pending_choices.append(choice)
	return true


func activate_effect(effect:BaseEffect):
	if _paused_runs.has(effect) and not _paused_source_is_current(_paused_runs[effect]): return
	if not _effect_entry_is_current(effect): return
	var context:SessionContext = effect.runtime_context()
	var session:RefCounted = _payment_session_token()
	if _runtime_guard.paused:
		return
	if not _begin_guard_transaction(effect): return
	if not _effect_entry_is_current(effect): return
	#选择效果与发起它的那条效果共用一张变量表：选项里的步骤能读前面算出的结果，
	#后面的步骤也能读选项里算出的结果。普通激活都从空白的变量表开始，避免读到上一次激活的残留值
	var paused = _paused_runs.get(effect)
	#效果即将开始结算：作为"即将发生"的动作派发 effect_start，监听者可以 cancel_pending_action 让它不结算
	#（信仰的加护"延后他人能力"这类）。被延后/取消的效果不记为触发过、也不派发 effect_end。
	#选择效果是发起效果的一部分，不单独派发
	if paused == null and _should_announce_effect_start(effect):
		var previous_scope = _transaction_scope
		_transaction_scope = _guard_transactions.get(effect)
		var action:Dictionary = begin_pending_action(TimePoints.EFFECT_START, effect._trigger_player_id, {"effect": effect}, effect)
		var source:Dictionary = _effect_execution_status(effect, context)
		if not source.ok:
			_reject_execution_source(context, source.reason)
			return
		_transaction_scope = previous_scope
		if action.get("invalidated", false): return
		if bool(action.get("cancelled", false)):
			if effect._remove_after_trigger:
				unregister_effect(effect)
			_resume_after_choice(effect)
			return
	effect._self_vars = paused.run.effect._self_vars if paused != null else []
	var run := {
		"effect": effect,
		"context": context,
		"source_rejected": false,
		#多选一效果结算选中分支的funcs，不结算effect自身的_funcs(那里本就是空的)
		"funcs": get_chosen_funcs(effect) if effect.has_options() else effect._funcs,
		"index": 0,
		"applied": false,
		#手动发动的结果要写清"谁/哪个对象被改了什么"：结算前后各取一次规则状态快照，
		#差值就是这次发动的实际影响（与卡面文案无关，条件不满足时差值为空）
		"state_before": capture_rule_state() if effect._is_manual else {},
	}
	_continue_run(run)
	if session != _payment_session_token(): return
	if not is_running:
		_release_guard_transactions()

#从 run.index 那一步往下做；某一步提出了选择就停在这里，等选择结束后由 _resume_after_choice 接着做
func _continue_run(run:Dictionary) -> void:
	if not _accept_run_source(run): return
	var session:RefCounted = _payment_session_token()
	var previous_scope = _transaction_scope
	_transaction_scope = _guard_transactions.get(run.effect)
	if not is_running and _active_runs.is_empty() and _resume_frames.is_empty():
		_runtime_guard.begin_slice()
	var parent_frame:Dictionary = _function_frames.back() if not _function_frames.is_empty() else {}
	_active_runs.append({"run": run, "previous_effect": activating_eff})
	_continue_run_body(run)
	_active_runs.pop_back()
	if _runtime_guard.paused and not parent_frame.is_empty() and _native_guard_adapter(parent_frame) != &"":
		parent_frame["child_run"] = run
	if session != _payment_session_token(): return
	_transaction_scope = previous_scope

func _continue_run_body(run:Dictionary) -> void:
	if not _accept_run_source(run): return
	var context:SessionContext = run.context
	var effect:BaseEffect = run.effect
	#一次结算的执行编号：名下所有 func 日志都带同一个 execution_id。
	#收栈时按编号定位，中途抛错没走到的执行不会留在栈上
	var execution_id:int = GameLog.begin_execution()
	var previous_effect = activating_eff
	activating_eff = effect
	start_effect()
	if not _accept_run_source(run): return
	var funcs:Array = run.funcs
	while int(run.index) < funcs.size():
		if not _accept_run_source(run): return
		if not runtime_guard_checkpoint():
			run["wait_origin"] = _capture_wait_origin(effect, context)
			_guard_run = run
			if _transaction_scope != null and not _transaction_scope.audit("pause", effect, _runtime_guard.reason):
				_guard_audit_failed(effect)
			end_effect()
			if not _accept_run_source(run): return
			GameLog.end_execution(execution_id)
			activating_eff = previous_effect
			return
		var f:BaseFunc = funcs[int(run.index)]
		run.index = int(run.index) + 1
		var outcome: Array = run_base_func(f, effect, context)
		if not _accept_run_source(run): return
		if _runtime_guard.paused:
			run.index = int(run.index) - 1
			run["wait_origin"] = _capture_wait_origin(effect, context)
			_guard_run = run
			if _transaction_scope != null and not _transaction_scope.audit("pause", effect, _runtime_guard.reason):
				_guard_audit_failed(effect)
			end_effect()
			if not _accept_run_source(run): return
			GameLog.end_execution(execution_id)
			activating_eff = previous_effect
			return
		if bool(outcome[0]) and f._var_index == -1 and f._name != "do_nothing":
			run.applied = true
		if !_pending_choices.is_empty():
			var choices:Array = _pending_choices.duplicate()
			_pending_choices.clear()
			end_effect()
			if not _accept_run_source(run): return
			GameLog.end_execution(execution_id)
			activating_eff = previous_effect
			_ask_next_choice({"run": run, "queue": choices, "origin":_capture_wait_origin(effect, context)})
			return
	if not _accept_run_source(run): return
	end_effect()
	if not _accept_run_source(run): return
	GameLog.end_execution(execution_id)
	activating_eff = previous_effect
	_finish_effect(effect, bool(run.applied), run.state_before, run)


#把排队的下一个选择交给玩家；都问完了就让发起的那条效果接着往下做
func _ask_next_choice(paused:Dictionary) -> void:
	if not _paused_source_is_current(paused): return
	var queue:Array = paused.queue
	if queue.is_empty():
		_continue_run(paused.run)
		return
	var choice:BaseEffect = queue.pop_front()
	_paused_runs[choice] = paused
	if not _inherit_guard_transaction(choice): return
	decision_queue.push_front(choice)
	#不在结算流程里（直接调 activate_effect 的入口）时自己推动一次，否则选择没人问
	if !is_running:
		run_pipeline()


#选择效果结算完或被放弃：它挂着的那条效果继续。没有挂着的效果时什么都不做
func _resume_after_choice(choice:BaseEffect) -> void:
	if _paused_runs.has(choice) and not _paused_source_is_current(_paused_runs[choice]):
		_discard_exact_wait(choice)
		return
	if !_paused_runs.has(choice):
		return
	var paused:Dictionary = _paused_runs[choice]
	_paused_runs.erase(choice)
	if choice._remove_after_trigger:
		unregister_effect(choice)
	_ask_next_choice(paused)


#要不要为这条效果派发 effect_start：没有归属玩家的不派发；正在为某个 effect_start 做同步结算时不派发，
#否则两名玩家的"他人效果开始时"监听会互相触发、无限嵌套
func _should_announce_effect_start(effect:BaseEffect) -> bool:
	if effect == null or effect._trigger_player_id < 0:
		return false
	for action in pending_actions:
		if str(action.get("time_point", "")) == TimePoints.EFFECT_START:
			return false
	return true


func _finish_effect(effect:BaseEffect, applied:bool, state_before:Dictionary, run:Dictionary) -> void:
	if not _accept_run_source(run): return
	#日志：这个效果本局触发过了。"每局限一次"的判断也从这里查，
	#不再另外维护一份 used_once_effects
	GameLog.record("effect", _effect_fact_actor_id(effect), -1, "", effect, ["effect"],
		{"effect_name": effect._name, "shown_effect": str(effect._shown_name),
		 "source_name": _effect_source_name(effect), "applied": applied,
		 "trigger_time_points": effect._trigger_time_points.duplicate()})
	if not _accept_run_source(run): return
	# 手动发动即使没有产生即时数值变化，也要给玩家交代结算结果。
	# applied 只表示执行了写入型函数，不表示玩家没有确认发动。
	if applied or effect._is_manual:
		var changes:Array = diff_rule_state(state_before, capture_rule_state()) if effect._is_manual else []
		_announce_effect(effect, changes)
		if not _accept_run_source(run): return
	#效果结算完：派发 effect_end（"受到他人能力影响后"类监听）。来源就是这条效果，
	#监听者用 query_log 查最近一条 time_point 日志的 object 取到它
	#不在流程里时（选择答复后直接续跑的路径）按流程内处理：只收集监听者、不清空当前队列，收集到的再交给常规流程
	if effect._trigger_player_id >= 0 and GameData.player_data_library.has(effect._trigger_player_id):
		var was_running:bool = is_running
		is_running = true
		TimePointChecker.dynamic_time_point([TimePoints.EFFECT_END], effect._trigger_player_id, effect, run.context)
		if not _accept_run_source(run): return
		is_running = was_running
		if !was_running and !is_waiting_for_choice() and (!decision_queue.is_empty() or !activation_pool.is_empty()):
			run_pipeline()
	if effect._remove_after_trigger:
		unregister_effect(effect)
	_resume_after_choice(effect)


#效果结算完后统一告知玩家"谁因为什么受到了什么效果"。
#放在这一处而不是各效果自己推：所有效果（自己的、他人的、事件牌、局势牌、buff）
#都经由 activate_effect 结算，一处接线即全量覆盖。
#只推有卡面文案的效果：没有 shown_name 的是系统内部效果（禁令声明、
#排除胜负判定这类持续型被动），推内部英文名对玩家没有意义。
#来源对象名（哪张牌/哪个状态发动的）从效果的 from 取，取不到就只报效果文案
func _announce_effect(effect:BaseEffect, changes:Array = []) -> void:
	if effect == null:
		return
	var text:String = str(effect.get_shown_name())
	#选项类效果（如令咒的三选一）要报出本次实际选中的选项名：效果级文案只是"令咒"这种统称，
	#不报选项玩家无法核对刚才选的哪一项。选项名由数据声明，不按牌名/角色名分支
	var chosen_lines:Array = []
	for idx in effect._chosen_selection.keys():
		if !(idx is int) or idx < 0 or idx >= effect._options.size():
			continue
		#秘密选择：公告不报选了哪一项，整条公告也不发（选没选、选了什么由发起的效果决定是否公开）
		if (effect._options[idx].get("tags", []) as Array).has("secret_choice"):
			return
		var opt_name:String = str(effect._options[idx].get("shown_option_name", ""))
		if opt_name != "":
			chosen_lines.append(opt_name)
	if !chosen_lines.is_empty():
		text = "\n".join(chosen_lines)
	if text == "":
		return
	var actor:String = _effect_actor_name(effect)
	var source:String = _effect_source_name(effect)
	var parts:Array = []
	if actor != "":
		parts.append(actor)
	#御主自身能力中“触发玩家”和“来源对象”可能是同一个名字；此时只显示一次。
	#来源为卡牌、状态或其他对象时仍保留【来源】，玩家才能知道是哪张牌发动。
	var actor_name:String = actor.trim_suffix("：")
	if source != "" and source != actor_name:
		parts.append("【%s】" % source)
	var line:String = text if parts.is_empty() else ("%s%s" % ["".join(parts), text])
	#玩家主动发动的能力使用独立结果队列：确认完成后由专门的“发动结果”弹窗展示，
	#不与下一条能力询问共用或重叠。自动/被动效果仍按时点折叠成普通公告。
	if effect._is_manual:
		var lines:Array = [line]
		# 明细逐条写明"谁／哪个对象／哪个字段／前值 → 后值"：
		# 玩家要能核对这次发动到底影响了谁，而不是只看到一句卡面文案。
		if changes.is_empty():
			lines.append("未产生即时变化")
		else:
			for change in changes:
				lines.append(format_rule_change(change))
		push_effect_result("\n".join(lines), -1)
		return
	#同一时点内触发的多条效果折叠成一条推送：战斗结算这类时点会连续触发一批效果，
	#逐条推会把提示刷成一长串、还会互相覆盖。按玩家可见范围分桶累积，
	#等本时点整条管线跑完（run_pipeline 收尾）再合并成一条
	var scope:int = effect._trigger_player_id
	var bucket:Array = _pending_announcements.get(scope, [])
	#同一时点里同名效果只报一次（多张同名牌各触发一次时不必重复刷同一行）
	if !bucket.has(line):
		bucket.append(line)
	_pending_announcements[scope] = bucket


#把本时点累积的效果提示合并推送。由 run_pipeline 在整条管线跑完时调用——
#那里才是"这个时点的效果都结算完了"的边界
func _flush_announcements() -> void:
	if _pending_announcements.is_empty():
		return
	var pending:Dictionary = _pending_announcements.duplicate()
	#先清空再推送：push_message 不会再回头触发效果，但清空在前可避免任何重入重复推
	_pending_announcements.clear()
	#效果公布是公开事件：要让人知道"谁因为什么做了什么"，只推给触发者本人等于没公布。
	#同一时点内触发的多条效果合并成一条，避免战斗结算时刷屏
	var all_lines:Array = []
	for scope in pending.keys():
		for line in pending[scope]:
			if not all_lines.has(line):
				all_lines.append(line)
	if not all_lines.is_empty():
		push_message("\n".join(all_lines), -1)


#效果触发者的示人名字（"谁"）。未归属玩家的效果（事件牌/局势牌挂在场上）返回空串
func _effect_actor_name(effect:BaseEffect) -> String:
	var id:int = _effect_fact_actor_id(effect)
	if id < 0 or !GameData.player_data_library.has(id):
		return ""
	var master = GameDataManager.find_player_data(id).get("master")
	if master == null:
		return "玩家 %d：" % id
	var shown:String = str(master.get_shown_name())
	return ("%s：" % shown) if shown != "" else ("玩家 %d：" % id)


## 公开事实行动者查询：场上事件牌、局势牌仍不归属玩家。
func effect_fact_actor_id(effect:BaseEffect) -> int:
	return _effect_fact_actor_id(effect)


func _effect_fact_actor_id(effect:BaseEffect) -> int:
	var owner = effect.from
	if owner is WeakRef:
		owner = owner.get_ref()
	# 场上牌效果借玩家 id 作为结算顺序锚点，该玩家不是发动者；提示只显示真实来源牌。
	if owner is BaseSituation or owner is BaseEvent:
		return -1
	return effect._trigger_player_id


## 公开来源名称查询：复用直接对象与 WeakRef 的既有解析口径。
func effect_source_name(effect:BaseEffect) -> String:
	return _effect_source_name(effect)


#效果来源对象的示人名字（"因为什么"）：哪张牌、哪个状态发动的
func _effect_source_name(effect:BaseEffect) -> String:
	var owner = effect.from
	if owner == null:
		return ""
	#from 有两种形态：WeakRef（打断所有权强引用环用）与直接持有对象本身。
	#两种都要兼容——只按 WeakRef 处理会在直接持有对象时报
	#"Nonexistent function 'get_ref' in base 'RefCounted (BaseMaster)'"
	if owner is WeakRef:
		owner = owner.get_ref()
	if owner == null or !owner.has_method("get_shown_name"):
		return ""
	return str(owner.get_shown_name())
