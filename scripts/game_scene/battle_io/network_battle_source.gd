class_name NetworkBattleSource
extends RefCounted

## 不拥有会话，不轮询、不关闭 transport，也不推测连接可用性。
## session 断网后的数据与隐私行为完全由真实 session 的读取接口决定。
signal changed

var _session_ref: WeakRef
var _group_selection: RefCounted
var _notifying := false

func _init(session: RefCounted) -> void:
	set_session(session)

## 显式解绑旧会话；调用方在移交或销毁宿主前调用 close 即可。
func set_session(session: RefCounted) -> void:
	var previous = _session()
	if previous == session:
		return
	# 选择器属于原会话；替换会话必须显式重新注入，不能复用碰巧同序号的快照。
	bind_group_selection(null)
	if previous != null and previous.changed.is_connected(_on_session_changed):
		previous.changed.disconnect(_on_session_changed)
	_session_ref = weakref(session) if session != null else null
	if session != null:
		session.changed.connect(_on_session_changed)
	_on_session_changed()

func close() -> void:
	bind_group_selection(null)
	set_session(null)

## 注入已有选择器，不复制其请求/拒绝/过期回执状态机。
func bind_group_selection(selection: RefCounted) -> void:
	_group_selection = selection

func read_group_preview(_cards: Array, _hidden: Array) -> Dictionary:
	var session = _session()
	if session == null or _group_selection == null:
		return {}
	var snapshot: Dictionary = _group_selection.snapshot()
	var preview: Dictionary = snapshot.get("preview", {})
	# 不能把旧视图的可提交结果当作当前组合；缺失序号也不可补猜。
	if int(preview.get("view_seq", -1)) != int(session.read_match().get("seq", 0)):
		snapshot.preview = {}
	return snapshot

func read_view() -> Dictionary:
	var session = _session()
	return session.read_match() if session != null else {}

func read_actions() -> Dictionary:
	var session = _session()
	return session.read_actions() if session != null else {}

func read_pending() -> Dictionary:
	var session = _session()
	return session.read_pending() if session != null else {}

func _session():
	return _session_ref.get_ref() if _session_ref != null else null

func _on_session_changed() -> void:
	if _notifying:
		return
	_notifying = true
	changed.emit()
	_notifying = false
