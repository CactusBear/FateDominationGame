extends RefCounted

## 宿主只拥有会话生命周期，不拥有规则、展示器或卡牌。
## 协议、参数/完成态查询与场景由组合根显式注入。
signal changed
signal notice(reason: String)
signal transferring

var _host: WeakRef
var _session: WeakRef
var _lobby_scene: PackedScene
var _request_kind: String
var _read_request: Callable
var _read_lobby: Callable
var _attempt: Dictionary = {}
var _requires_acceptance := false
var _generation := 0
var _retired := false
var _closed := false
var _unknown := false
var _queued := false
var _transferred := false

func _init(host: Node, session, lobby_scene: PackedScene, request_kind: String,
		read_request: Callable, read_lobby: Callable) -> void:
	_host = weakref(host)
	_session = weakref(session)
	_lobby_scene = lobby_scene
	_request_kind = request_kind
	_read_request = read_request
	_read_lobby = read_lobby
	session.request_completed.connect(_on_completed)
	session.request_rejected.connect(_on_rejected)
	session.request_associations_invalidated.connect(_on_invalidated)

func transferred() -> bool:
	return _transferred

func outcome_unknown() -> bool:
	return _unknown

func pending() -> bool:
	return not _attempt.is_empty()

## 对自身发出的请求，权威成功回执和真实完成态缺一不可。
## 未发请求的其它成员仍可观察真实大厅移交，不伪造请求成功。
func lobby_available() -> bool:
	if _closed or _retired or _unknown or _transferred or not _read_lobby.is_valid():
		return false
	if _requires_acceptance and (_attempt.is_empty() or not _attempt.accepted):
		return false
	return _completion_ready()

func _completion_ready() -> bool:
	if not _read_lobby.is_valid():
		return false
	var ready = _read_lobby.call()
	return ready is bool and ready and not _closed and not _retired

func request_lobby() -> void:
	if lobby_available():
		_schedule_transfer()
		return
	if _closed or _retired or _unknown or _queued or _transferred or pending():
		return
	var args = _read_request.call() if _read_request.is_valid() else null
	var session = _session.get_ref()
	if _closed or _retired or session == null or not args is Dictionary or args.is_empty() or _request_kind.is_empty():
		return
	var state := {"sequence":0, "settled":false, "accepted":false, "generation":_generation}
	_attempt = state
	_requires_acceptance = true
	changed.emit() # 在途门先于可能同步完成的 request。
	if not _is_current(state):
		return
	var sent: Error = session.request(_request_kind, args.duplicate(true), _register.bind(state))
	if _is_current(state) and not state.settled and sent != OK:
		state.settled = true
		_attempt = {}
		notice.emit("返回大厅请求未发送：" + error_string(sent))
		changed.emit()
	_schedule_transfer()

func _is_current(state: Dictionary) -> bool:
	return not _closed and not _retired and not _attempt.is_empty() and is_same(_attempt, state) and state.generation == _generation

func _register(sequence: int, state: Dictionary) -> void:
	if _is_current(state) and not state.settled:
		state.sequence = sequence

func _on_rejected(sequence: int, reason: String) -> void:
	_on_completed(sequence, false, reason)

func _on_completed(sequence: int, ok: bool, reason: String) -> void:
	if _closed or _retired or _attempt.is_empty() or _attempt.settled or sequence <= 0 or sequence != _attempt.sequence:
		return
	_attempt.settled = true # 发任何信号之前防止重复/重入结算。
	_attempt.accepted = ok
	if not ok:
		_attempt = {}
		notice.emit(reason)
	changed.emit()
	_schedule_transfer()

func _on_invalidated(_session_generation: int, _reason: String) -> void:
	if _closed or _retired or _transferred:
		return
	_retired = true # 先永久失效，再断信号/通知；不得同号复用。
	_generation += 1
	_unknown = pending()
	_attempt = {}
	_queued = false
	_detach()
	_clear_queries()
	if _unknown:
		notice.emit("返回大厅执行结果未知；请先确认权威状态，不自动重发")
	changed.emit()

## 返回 false 表示旧宿主不再刷新/推进；等待回执仍继续 poll。
## 已失效或大厅先于回执到达时保留终局展示，不能由空视图清掉。
func poll(delta: float) -> bool:
	if _closed or _transferred or _queued:
		return false
	if _retired:
		return false
	var session = _session.get_ref()
	if session == null:
		_on_invalidated(_generation + 1, "released")
		return false
	session.poll(delta)
	_schedule_transfer()
	if _requires_acceptance and _completion_ready():
		return false
	return not _closed and not _transferred and not _queued

func _schedule_transfer() -> void:
	if not _queued and lobby_available():
		_queued = true
		call_deferred("_transfer", _generation)

func _transfer(generation: int) -> void:
	if generation != _generation or _closed or _retired or _transferred:
		return
	_queued = false
	if not lobby_available():
		return
	var host = _host.get_ref()
	var session = _session.get_ref()
	if host == null or not host.is_inside_tree() or session == null or _lobby_scene == null:
		return
	var lobby = _lobby_scene.instantiate()
	lobby.set("session", session)
	_transferred = true # add_child/退出回调可重入 close，必须先移交所有权。
	_attempt = {}
	_detach()
	_clear_queries()
	transferring.emit()
	host.set_process(false)
	var tree: SceneTree = host.get_tree()
	tree.root.add_child(lobby)
	tree.current_scene = lobby
	host.queue_free()
	changed.emit()

func _detach() -> void:
	var session = _session.get_ref()
	if session == null:
		return
	if session.request_completed.is_connected(_on_completed):
		session.request_completed.disconnect(_on_completed)
	if session.request_rejected.is_connected(_on_rejected):
		session.request_rejected.disconnect(_on_rejected)
	if session.request_associations_invalidated.is_connected(_on_invalidated):
		session.request_associations_invalidated.disconnect(_on_invalidated)

func _clear_queries() -> void:
	_read_request = Callable()
	_read_lobby = Callable()
	_lobby_scene = null

func close() -> void:
	if _closed:
		return
	_closed = true
	_generation += 1
	_queued = false
	_unknown = _unknown or pending()
	_attempt = {}
	_detach()
	_clear_queries()
	var session = _session.get_ref()
	if not _transferred and session != null:
		session.close()