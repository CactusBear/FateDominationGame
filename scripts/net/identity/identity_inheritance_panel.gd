extends Window

## 只展示权威公开标签；恢复凭据和认证信息由会话私有处理。
const InputModel = preload("res://scripts/net/identity/identity_inheritance_input.gd")
var _input = InputModel.new()
var _session = null
var _target_member:int = 0
var _revision:int = -1
var _query_pending:bool = false
var _submit_pending:bool = false
@onready var candidates:ItemList = $Content/Candidates
@onready var feedback:Label = $Content/Feedback

func _ready() -> void:
	close_requested.connect(close_panel)
	$Content/Buttons/Close.pressed.connect(close_panel)
	$Content/Buttons/Refresh.pressed.connect(_query_candidates)
	$Content/Buttons/Confirm.pressed.connect(_submit)
	candidates.item_selected.connect(_select_candidate)

static func can_manage(active_session, target_member:int) -> bool:
	if active_session == null or not active_session.identity_authenticated or not active_session.transport.is_connected_to_host():
		return false
	var view:Dictionary = active_session.view
	if view.get("dedicated") != true or view.get("owner") != active_session.peer_id():
		return false
	var owner_connected:bool = false
	var target_disconnected:bool = false
	for member in view.get("members", []):
		if member.id == view.owner:
			owner_connected = member.get("connected") == true and member.get("spectator") == false
		if member.id == target_member and member.id != view.owner:
			target_disconnected = member.get("connected") == false and member.get("spectator") == false
	return owner_connected and target_disconnected

func open_for(active_session, target_member:int, target_label:String) -> void:
	close_panel()
	if not can_manage(active_session, target_member):
		return
	_session = active_session
	_target_member = target_member
	_revision = int(_session.view.get("revision", -1))
	$Content/Target.text = "原身份：" + target_label
	_session.inheritance_candidates_received.connect(_accept_candidates)
	popup_centered()
	_query_candidates()

func _clear_candidates() -> void:
	_input.clear()
	candidates.clear()
	_query_pending = false
	_submit_pending = false
	$Content/Buttons/Confirm.disabled = true

func close_panel() -> void:
	if _session != null and _session.inheritance_candidates_received.is_connected(_accept_candidates):
		_session.inheritance_candidates_received.disconnect(_accept_candidates)
	_session = null
	_target_member = 0
	_revision = -1
	if is_node_ready():
		_clear_candidates()
		$Content/Target.text = ""
		feedback.text = ""
	hide()

## 由大厅每帧调用，传输断线不依赖房间 changed 信号。
func refresh_context() -> void:
	if not visible or _session == null:
		return
	if not can_manage(_session, _target_member):
		close_panel()
		return
	var revision:int = int(_session.view.get("revision", -1))
	if revision != _revision:
		_revision = revision
		_clear_candidates()
		$Content/Buttons/Refresh.disabled = false
		feedback.text = "房间状态已更新，请刷新候选并重新选择"

func request_failed() -> void:
	if not visible:
		return
	_clear_candidates()
	$Content/Buttons/Refresh.disabled = false
	feedback.text = "身份继承请求未完成，请刷新候选后重试"

func _query_candidates() -> void:
	refresh_context()
	if _session == null or not visible:
		return
	_clear_candidates()
	_query_pending = true
	$Content/Buttons/Refresh.disabled = true
	feedback.text = "正在查询可继承身份的新用户"
	if _session.request("identity_candidates", {}) != OK:
		request_failed()

func _accept_candidates(model:Dictionary) -> void:
	refresh_context()
	if not visible or _session == null or not _query_pending:
		return
	if model.get("revision") != _revision or not _input.accept(model):
		request_failed()
		return
	_query_pending = false
	$Content/Buttons/Refresh.disabled = false
	for row in _input.candidates:
		candidates.add_item(row.label)
		candidates.set_item_metadata(candidates.item_count - 1, row.member_id)
	candidates.deselect_all()
	feedback.text = "请选择继承者后确认" if candidates.item_count > 0 else "暂无候选，请让新用户以观战身份加入后刷新"

func _select_candidate(index:int) -> void:
	refresh_context()
	if _session == null or _query_pending or _submit_pending or index < 0 or index >= candidates.item_count:
		return
	var member_id:int = int(candidates.get_item_metadata(index))
	$Content/Buttons/Confirm.disabled = not _input.select_member(member_id) or _input.request_args(_target_member).is_empty()

func _submit() -> void:
	refresh_context()
	if _session == null or _query_pending or _submit_pending:
		return
	var selected:PackedInt32Array = candidates.get_selected_items()
	if selected.size() != 1 or not _input.select_member(int(candidates.get_item_metadata(selected[0]))):
		return
	var args:Dictionary = _input.request_args(_target_member)
	if args.is_empty():
		return
	_clear_candidates()
	_submit_pending = true
	$Content/Buttons/Refresh.disabled = true
	feedback.text = "已提交指定继承请求，等待房间更新；继承者仍须重新连接"
	if _session.request("identity_inherit", args) != OK:
		request_failed()

func _exit_tree() -> void:
	if _session != null and _session.inheritance_candidates_received.is_connected(_accept_candidates):
		_session.inheritance_candidates_received.disconnect(_accept_candidates)
