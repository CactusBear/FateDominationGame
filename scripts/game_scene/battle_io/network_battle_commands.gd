class_name NetworkBattleCommands
extends RefCounted

## 只转接正式权威回执；发送 OK 或新视图都不是执行成功。
## request_rejected 兼容旧拒绝通知，与 request_completed 共用一次性结算。
signal result(request_id: int, ok: bool, reason: String)
var _session: WeakRef
var _read_view_sequence: Callable
var _request_id: int = 0
var _pending: Dictionary = {}
var _closed: bool = false

func _init(session, read_view_sequence: Callable) -> void:
	_session = weakref(session)
	_read_view_sequence = read_view_sequence
	session.request_completed.connect(_on_request_completed)
	session.request_rejected.connect(_on_request_rejected)
	session.request_associations_invalidated.connect(_on_request_associations_invalidated)

func submit(kind: String, args: Dictionary) -> int:
	_request_id += 1
	var request_id: int = _request_id
	var session = _session.get_ref()
	if _closed or session == null:
		result.emit(request_id, false, "命令适配器已关闭或会话已释放，未发送")
		return request_id
	var sequence = _read_view_sequence.call()
	if _closed:
		result.emit(request_id, false, "命令适配器已关闭，未发送")
		return request_id
	if not sequence is int:
		result.emit(request_id, false, "视图序号无效，未发送")
		return request_id
	var state: Dictionary = {"request_id": request_id, "settled": false, "sequence": null}
	var sent: Error = session.request("match_command", {
		"view_seq": sequence, "command": kind, "params": args.duplicate(true)
	}, _register_request.bind(state))
	if sent != OK and not state.settled:
		state.settled = true
		if state.sequence != null:
			_pending.erase(state.sequence)
		result.emit(request_id, false, "请求发送失败：%s；未确认执行" % error_string(sent))
	return request_id

func _register_request(sequence: int, state: Dictionary) -> void:
	if _closed or state.settled: return
	state.sequence = sequence
	_pending[sequence] = state

func _on_request_rejected(sequence: int, reason: String) -> void:
	_on_request_completed(sequence, false, reason)

func _on_request_completed(sequence: int, ok: bool, reason: String) -> void:
	if not _pending.has(sequence):
		return
	var state: Dictionary = _pending[sequence]
	_pending.erase(sequence)
	state.settled = true
	result.emit(state.request_id, ok, reason)

func pending_request_ids() -> Array:
	var ids: Array = []
	for state in _pending.values():
		ids.append(state.request_id)
	ids.sort()
	return ids

## 生命周期中止不是权威拒绝，更不是执行失败证明；reason 保留未知状态。
func _on_request_associations_invalidated(_generation: int, _reason: String) -> void:
	close()

func close() -> void:
	if _closed:
		return
	_closed = true
	var session = _session.get_ref()
	if session != null and session.request_associations_invalidated.is_connected(_on_request_associations_invalidated):
		session.request_associations_invalidated.disconnect(_on_request_associations_invalidated)
	if session != null and session.request_completed.is_connected(_on_request_completed):
		session.request_completed.disconnect(_on_request_completed)
	if session != null and session.request_rejected.is_connected(_on_request_rejected):
		session.request_rejected.disconnect(_on_request_rejected)
	var pending: Array = _pending.values()
	_pending.clear()
	_read_view_sequence = Callable()
	for state in pending:
		state.settled = true
		result.emit(state.request_id, false, "命令适配器已关闭，执行结果未知")
