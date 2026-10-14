extends RefCounted

# 只负责展示事实投递资格，不保存规则历史，也不参加规则检查点回滚。
# recorded 仍由 EventJournal 同步发出；只有展示消费者经过本原语。
enum TransactionStatus { NOT_PENDING, PENDING }

var _session_generation:int = 0
var _next_generation:int = 0
var _next_subscription:int = 0
var _listeners:Dictionary = {}
var _transactions:Dictionary = {}
# 不透明句柄只属于此投递器；终态从活动表移除，票据仍持有内部 token 引用。
var _owned:Dictionary = {}
var _pending:Array = []
var _scheduled:bool = false

# A4 完整发布后的只读终态通道；旧 observe/enqueue 不自动获得只读能力。
# 注册入口仅供受信 owner；声明不是任意 GDScript callback 的沙箱。
var _committed_listeners:Dictionary = {}
var _batch_snapshots:Dictionary = {}
var _committed_receipts:Dictionary = {}
const AtomicPlan = preload("res://scripts/system/atomic_action_plan.gd")
const AtomicDomain = preload("res://scripts/system/atomic_execution_domain.gd")

func observe_committed(listener:Callable) -> bool:
	if not listener.is_valid() or AtomicDomain.publication_is_open(): return false
	if not _committed_listeners.has(listener):
		_next_subscription += 1
		_committed_listeners[listener] = _next_subscription
	return true

func unobserve_committed(listener:Callable) -> void:
	_committed_listeners.erase(listener)

func prepare_committed_batch() -> Dictionary:
	if not _transactions.is_empty() or not _owned.is_empty() or not _listeners.is_empty():
		return {"status":"UNSUPPORTED", "reason":"legacy_delivery_not_proven_readonly_or_idle"}
	var handle:RefCounted = RefCounted.new()
	_batch_snapshots[handle] = {"session":_session_generation, "listeners":_committed_listeners.duplicate(false)}
	return {"status":"COMPLETED", "reason":"", "snapshot_handle":handle}

func committed_batch_matches(snapshot:Dictionary) -> bool:
	var handle = snapshot.get("snapshot_handle")
	if not (handle is RefCounted) or not _batch_snapshots.has(handle): return false
	var saved:Dictionary = _batch_snapshots[handle]
	return saved.session == _session_generation and saved.listeners == _committed_listeners and _transactions.is_empty() and _owned.is_empty() and _listeners.is_empty()

func seal_committed_batch(snapshot:Dictionary, plan_identity:RefCounted) -> Dictionary:
	if not committed_batch_matches(snapshot) or AtomicPlan.inspect(plan_identity).get("state") != "PREPARED":
		return {"status":"UNSUPPORTED", "reason":"delivery_batch_not_prevalidated"}
	var batch:Dictionary = _batch_snapshots[snapshot.snapshot_handle]
	if batch.has("plan"):
		return {"status":"UNSUPPORTED", "reason":"delivery_batch_already_sealed"}
	batch["plan"] = plan_identity
	return {"status":"COMPLETED", "reason":""}

# 无规则数据/trace；仅保存的真 receipt 放行。会话/订阅资格漂移只丢输出，不 undo。
func activate_committed_batch(snapshot:Dictionary, receipt:Variant, terminal:Dictionary) -> Dictionary:
	if AtomicDomain.publication_is_open() or AtomicDomain.current_frame().status == "COMPLETED" or not (receipt is Dictionary):
		return {"status":"UNSUPPORTED", "reason":"invalid_committed_delivery_boundary"}
	var saved:Dictionary = AtomicPlan.inspect(receipt.get("plan_identity"))
	if saved.get("state") != "COMMITTED" or not is_same(saved.receipt, receipt):
		return {"status":"UNSUPPORTED", "reason":"delivery_receipt_not_saved_committed"}
	if _committed_receipts.has(receipt.plan_identity):
		return {"status":"COMPLETED", "reason":"already_activated"}
	# 终态载体严格白名单，不能由通知方把规则对象或追踪夹带进来。
	if terminal.keys().size() != 3 or terminal.get("state") != "COMMITTED" or terminal.get("notification_boundary") != "after_complete_install" or not (terminal.get("retained_facts") is int):
		return {"status":"UNSUPPORTED", "reason":"unsupported_terminal_payload"}
	var handle = snapshot.get("snapshot_handle")
	if not (handle is RefCounted) or not _batch_snapshots.has(handle):
		return {"status":"UNSUPPORTED", "reason":"unknown_delivery_batch"}
	var batch:Dictionary = _batch_snapshots[handle]
	if not is_same(batch.get("plan"), receipt.plan_identity):
		return {"status":"UNSUPPORTED", "reason":"delivery_batch_plan_identity_mismatch"}
	_committed_receipts[receipt.plan_identity] = receipt
	var payload:Dictionary = terminal.duplicate(false)
	payload.make_read_only()
	for listener in batch.listeners:
		if batch.session != _session_generation: break
		if listener.is_valid() and _committed_listeners.get(listener) == batch.listeners[listener]:
			listener.call(payload)
	return {"status":"COMPLETED", "reason":""}


func observe(listener:Callable) -> void:
	if not _listeners.has(listener):
		_next_subscription += 1
		_listeners[listener] = _next_subscription

func unobserve(listener:Callable) -> void:
	_listeners.erase(listener)

# 只读隔离投影：PENDING 保留原 generation/state；NOT_PENDING 不含这些字段。
# NOT_PENDING 不能区分提交、中止、未开始；不保留终态，不调度或消费投递。
func transaction_status(transaction_id:int) -> Dictionary:
	var token = _transactions.get(transaction_id)
	if token == null:
		return {"status":TransactionStatus.NOT_PENDING}
	return {"status":TransactionStatus.PENDING, "generation":token.generation, "state":token.state}

func begin(transaction_id:int) -> void:
	if _transactions.has(transaction_id):
		return
	_next_generation += 1
	_transactions[transaction_id] = {"generation":_next_generation, "state":"pending"}

func commit(transaction_id:int) -> void:
	var token = _transactions.get(transaction_id)
	if token == null:
		return
	token.state = "committed"
	_transactions.erase(transaction_id)
	_schedule()

func abort(transaction_id:int) -> void:
	var token = _transactions.get(transaction_id)
	if token == null:
		return
	token.state = "aborted"
	_transactions.erase(transaction_id)
	_schedule()

# 显式父链捕获创建时的根依赖；不是规则检查点或审计身份。
# 失效父句柄不能降级成新根，调用方重试必须另建 scope。
func begin_owned(parent:RefCounted = null) -> RefCounted:
	var dependencies:Array = _transactions.values()
	if parent != null:
		var parent_token = _pending_owned(parent)
		if parent_token == null:
			return null
		dependencies = parent_token.dependencies.duplicate()
		dependencies.append(parent_token)
	_next_generation += 1
	var owner := RefCounted.new()
	_owned[owner] = {"generation":_next_generation, "state":"pending", "dependencies":dependencies}
	return owner

# 只返回资格投影，不暴露可改写的内部 token 或依赖集合。
func owned_status(owner:RefCounted) -> Dictionary:
	var token = _pending_owned(owner)
	if token == null:
		return {"status":TransactionStatus.NOT_PENDING}
	return {"status":TransactionStatus.PENDING, "generation":token.generation, "state":token.state}

func enqueue_owned(entry:Dictionary, owner:RefCounted) -> bool:
	var token = _pending_owned(owner)
	if token == null:
		return false
	var dependencies:Array = token.dependencies.duplicate()
	dependencies.append(token)
	_enqueue(entry, dependencies)
	return true

# 成功只释放自己；父 owned/root 仍由其调用方决定终态。
func release_owned(owner:RefCounted) -> bool:
	var token = _pending_owned(owner)
	if token == null:
		return false
	token.state = "committed"
	_owned.erase(owner)
	_schedule()
	return true

# 永久中止本票据，并按引用身份失效活动后代；绝不撤父/兄弟。
func abort_owned(owner:RefCounted) -> bool:
	var token = _owned.get(owner)
	if token == null:
		return false
	token.state = "aborted"
	_owned.erase(owner)
	for descendant_owner in _owned.keys():
		var descendant:Dictionary = _owned[descendant_owner]
		if descendant.dependencies.any(func(dependency): return is_same(dependency, token)):
			descendant.state = "aborted"
			_owned.erase(descendant_owner)
	_schedule()
	return true

func _pending_owned(owner:RefCounted):
	var token = _owned.get(owner)
	if token == null:
		return null
	for dependency in token.dependencies:
		if dependency.state == "aborted":
			return null
	return token

func reset() -> void:
	_session_generation += 1
	_transactions.clear()
	for token in _owned.values():
		token.state = "aborted"
	_owned.clear()
	_pending.clear()
	_scheduled = false

func enqueue(entry:Dictionary) -> void:
	_enqueue(entry, _transactions.values())

func _enqueue(entry:Dictionary, dependencies:Array) -> void:
	if _listeners.is_empty():
		return
	# 只复制事实和订阅，依赖 token 保留引用：commit/abort 改变原票据资格。
	_pending.append({"entry":entry.duplicate(true), "listeners":_listeners.duplicate(),
		"dependencies":dependencies, "session":_session_generation})
	_schedule()

func _schedule() -> void:
	if _scheduled or _pending.is_empty():
		return
	_scheduled = true
	_drain.call_deferred(_session_generation)

func _drain(session:int) -> void:
	# 旧回调不得清除新会话的 scheduled 标志，也不得取走新会话的票据。
	if session != _session_generation:
		return
	_scheduled = false
	while not _pending.is_empty():
		if session != _session_generation:
			return
		var ticket:Dictionary = _pending[0]
		var blocked:bool = false
		var aborted:bool = false
		for dependency in ticket.dependencies:
			blocked = blocked or dependency.state == "pending"
			aborted = aborted or dependency.state == "aborted"
		if blocked and not aborted:
			# commit/abort 再次唤醒；不逐帧自旋，不让后续事实越过待提交事实。
			return
		_pending.pop_front()
		if aborted or ticket.session != _session_generation:
			continue
		for listener in ticket.listeners:
			if session != _session_generation:
				return
			if listener.is_valid() and _listeners.get(listener) == ticket.listeners[listener]:
				listener.call(ticket.entry.duplicate(true))
