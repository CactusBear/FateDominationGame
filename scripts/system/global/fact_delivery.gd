extends RefCounted

# 只负责展示事实投递资格，不保存规则历史，也不参加规则检查点回滚。
# recorded 仍由 EventJournal 同步发出；只有展示消费者经过本原语。
var _session_generation:int = 0
var _next_generation:int = 0
var _next_subscription:int = 0
var _listeners:Dictionary = {}
var _transactions:Dictionary = {}
var _pending:Array = []
var _scheduled:bool = false

func observe(listener:Callable) -> void:
	if not _listeners.has(listener):
		_next_subscription += 1
		_listeners[listener] = _next_subscription

func unobserve(listener:Callable) -> void:
	_listeners.erase(listener)

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

func reset() -> void:
	_session_generation += 1
	_transactions.clear()
	_pending.clear()
	_scheduled = false

func enqueue(entry:Dictionary) -> void:
	if _listeners.is_empty():
		return
	# 只复制事实和订阅，依赖 token 保留引用：commit/abort 改变原票据资格。
	_pending.append({"entry":entry.duplicate(true), "listeners":_listeners.duplicate(),
		"dependencies":_transactions.values(), "session":_session_generation})
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
