extends PopupPanel

signal applied(directory: String)
signal check_finished
var session
var source_root: String = ""
var config: Dictionary = {}
var _entries: Array = []
var _items: Array = []
var _plan: Dictionary = {}
var _preparation = preload("res://scripts/net/validation/room_data_preparation.gd").new()
var _preparing:bool:
	get: return _preparation.preparing
var files_per_frame: int = 2
var _validation = _preparation.validation
var _server_selecting:bool = false
var _server_pending:bool = false
var _awaiting_risk_confirmation:bool = false
var _server_catalog_revision:int = 0
var _server_previous_request:int = 0
var _server_current_request:int = 0
var _server_confirmed_request:int = 0
const LABELS := {"masters": "御主", "servants": "从者", "attacks": "攻击牌", "events": "事件牌", "situations": "局势牌"}
@onready var tree: Tree = $Margin/Content/Entries
@onready var status: RichTextLabel = $Margin/Content/Status

func _ready() -> void:
	$Margin/Content/Actions/Apply.pressed.connect(_apply)
	$Margin/Content/Actions/Close.pressed.connect(hide)
	$Margin/Content/Actions/CancelCheck.pressed.connect(cancel)
	$Margin/Content/Filter/All.pressed.connect(func(): _select_visible(true))
	$Margin/Content/Filter/None.pressed.connect(func(): _select_visible(false))
	$Margin/Content/Filter/Search.text_changed.connect(_filter)
	$RiskConfirmation.confirmed.connect(_apply_validated)
	$RiskConfirmation.canceled.connect(cancel)
	$RiskConfirmation.add_button("查看详细报告", false, "risk_details")
	$RiskConfirmation.custom_action.connect(_risk_details_action)

	$Margin/Content/Actions/ServerSources.pressed.connect(func(): configure(session, source_root, config, not _server_selecting))

func configure(active_session, directory:String, mode_config:Dictionary, prefer_server:bool = true) -> void:
	var chosen: Dictionary = {}
	for index in range(_items.size()):
		chosen[_entries[index].provider + ":" + _entries[index].key] = _items[index].is_checked(0)
	cancel()
	if session != null and session.rejected.is_connected(_server_rejected): session.rejected.disconnect(_server_rejected)
	session = active_session
	config = mode_config.duplicate(true)
	session.rejected.connect(_server_rejected)
	source_root = directory
	_server_selecting = prefer_server and _server_owner()
	_server_catalog_revision = 0
	$Margin/Content/Actions/ServerSources.visible = _server_owner()
	$Margin/Content/Actions/ServerSources.text = "切换到本机共享" if _server_selecting else "切换到服务端批准"
	if _server_selecting:
		$Margin/Content/Title.text = "房间数据 · 服务端批准条目"
		$Margin/Content/Actions/Apply.text = "服务端校验并应用"
		$Margin/Content/Budget.hide()
		_entries = []
		_render({})
		$Margin/Content/Actions/Apply.disabled = true
		_load_server_catalog(chosen)
		session.request("server_data_catalog", {})
		if _server_catalog_revision <= 0: status.text = "正在读取服务端已登记的提供者与条目"
		return
	var catalog = preload("res://scripts/net/content/data_catalog.gd").new()
	_entries = catalog.scan(source_root, "host").filter(func(entry): return entry.category != "command_spells")
	if session._host:
		for id in session.catalogs:
			if id != 1 and session.room.members.has(id) and session.room.members[id].connected:
				_entries.append_array(session.catalogs[id])
	$Margin/Content/Title.text = "房间数据 · 选择玩家与条目" if session._host else "共享本机条目"
	$Margin/Content/Actions/Apply.text = "校验并应用" if session._host else "共享所选条目"
	$Margin/Content/Budget.visible = session._host
	_render(chosen)
	status.text = ("按玩家选择条目。同名内容冲突时仅保留所需来源。" if session._host else "只共享勾选条目。共享不代表房主已批准使用。") if catalog.errors.is_empty() else "\n".join(catalog.errors)

func _render(chosen:Dictionary) -> void:
	tree.clear()
	_items.clear()
	var root := tree.create_item()
	var groups: Dictionary = {}
	for entry in _entries:
		var group_key: String = entry.provider + ":" + entry.category
		if not groups.has(group_key):
			groups[group_key] = tree.create_item(root)
			var provider_name:String = _provider_name(entry.provider)
			groups[group_key].set_text(0, provider_name + " · " + LABELS.get(entry.category, entry.category))
		var item := tree.create_item(groups[group_key])
		item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		item.set_editable(0, true)
		item.set_checked(0, chosen.get(entry.provider + ":" + entry.key, entry.provider == "host"))
		item.set_text(0, str(entry.get("label", entry.name)))
		item.set_metadata(0, _items.size())
		_items.append(item)

func _provider_name(provider:String) -> String:
	if provider == "host": return "本机"
	if provider == "server": return "服务端"
	for member in session.view.get("members", []):
		if str(member.id) == provider: return str(member.name)
	return provider

func _server_owner() -> bool:
	return session != null and session.view.get("dedicated") == true and session.view.get("owner") == session.peer_id() and session.view.get("phase") == "lobby"

func _load_server_catalog(chosen:Dictionary) -> void:
	if not session.server_data.get("catalog_revision") is int: return
	if chosen.is_empty():
		for index in range(_items.size()): chosen[_entries[index].provider + ":" + _entries[index].key] = _items[index].is_checked(0)
	_entries = session.server_data.get("entries", []).duplicate(true)
	chosen = default_server_selection(_entries, session.server_data.get("selected", []), chosen)
	_server_catalog_revision = session.server_data.catalog_revision
	_render(chosen)
	$Margin/Content/Actions/Apply.disabled = false
	status.text = "选择服务端或玩家的条目，由服务端校验实际文件后采用。"
	var state:Dictionary = session.server_data.get("status", {})
	if _server_current_request > 0 and state.get("request_id") == _server_current_request and state.get("stage") in ["applied", "error", "cancelled"]: status.text = state.text

static func default_server_selection(entries:Array, approved:Array, previous:Dictionary) -> Dictionary:
	var result:Dictionary = previous.duplicate(true)
	var approved_ids:Dictionary = {}
	for reference in approved:
		approved_ids[reference.provider + ":" + reference.key] = true
	var first_use:bool = previous.is_empty() and approved_ids.is_empty()
	for entry in entries:
		var identity:String = entry.provider + ":" + entry.key
		if not result.has(identity):
			result[identity] = entry.provider == "server" if first_use else approved_ids.has(identity)
	return result

func _select_visible(value: bool) -> void:
	if _preparing or _validation.running or _server_pending:
		return
	for item in _items:
		if item.visible:
			item.set_checked(0, value)

func _filter(text: String) -> void:
	for index in range(_items.size()):
		var entry: Dictionary = _entries[index]
		_items[index].visible = text.is_empty() or text.to_lower() in str(entry.get("label", entry.name)).to_lower() or text.to_lower() in entry.name.to_lower()

func _apply() -> void:
	if session == null or session.view.get("phase") != "lobby" or _preparing or _validation.running or _server_pending:
		return
	var selected: Array = []
	for index in range(_items.size()):
		if _items[index].is_checked(0):
			selected.append(_entries[index])
	if _server_selecting:
		if not _server_owner() or _server_catalog_revision <= 0: return
		_server_previous_request = int(session.server_data.get("status", {}).get("request_id", 0))
		_server_current_request = 0
		_server_confirmed_request = 0
		_server_pending = true
		session.error = ""
		_set_busy(true)
		var references:Array = selected.map(func(entry): return {"provider":entry.provider, "key":entry.key})
		if session.request("server_data_prepare", {"catalog_revision":_server_catalog_revision, "selected":references}) != OK: _server_rejected("无法发送服务端数据准备请求")
		return
	if not session._host:
		status.text = "所选条目已共享，等待房主选择。" if session.share_catalog(source_root, selected) else session.error
		return
	var catalog = preload("res://scripts/net/content/data_catalog.gd").new()
	var base: Array = []
	for relative in catalog._files(source_root, "card_backs") + catalog._files(source_root, "command_spells") + ["selection_modes.json"]:
		if relative.get_extension().to_lower() not in catalog.EXTENSIONS:
			continue
		var handle := FileAccess.open(source_root.path_join(relative), FileAccess.READ)
		if handle == null:
			status.text = "基础集合文件不可读：" + relative
			return
		base.append({"provider": "host", "path": relative, "hash": FileAccess.get_sha256(source_root.path_join(relative)), "size": handle.get_length()})
	if $Margin/Content/Budget/Seconds.value <= 0:
		status.text = "数据校验时间预算必须大于零"
		return
	_preparation.cancel()
	_preparation = session.create_data_preparation()
	_validation = _preparation.validation
	_preparation.source_root = source_root
	_preparation.source_provider = "host"
	_preparation.files_per_poll = files_per_frame
	if not _preparation.start(selected, base, $Margin/Content/Budget/Seconds.value):
		status.text = _preparation.error
		return
	_plan = _preparation.plan
	_set_busy(true)

func _process(_delta: float) -> void:
	if _server_selecting:
		_poll_server()
		return
	if not _preparing and not _validation.running and not _awaiting_risk_confirmation:
		return
	if session == null or not session._host or session.room.phase != "lobby":
		cancel()
		return
	if _awaiting_risk_confirmation:
		if visible and not $RiskConfirmation.visible: $RiskConfirmation.popup_centered()
		return
	_preparation.poll()
	status.text = _preparation.status
	if not _preparation.error.is_empty():
		_fail(_preparation.error)
		return
	if not _preparing and not _validation.running:
		_show_validation_result()

func _show_validation_result() -> void:
	if not _validation.complete:
		_fail(_validation.error)
		return
	var report: Dictionary = _validation.report.get("loop_analysis", {})
	if _needs_risk_confirmation(report):
		_awaiting_risk_confirmation = true
		$RiskConfirmation/Report.text = _risk_text(report)
		if visible: $RiskConfirmation.popup_centered()
		status.text = "内容有效性检查已通过，运行检查有提示，等待房主确认。"
	else:
		_apply_validated()

func _risk_details_action(action:StringName) -> void:
	if action != &"risk_details": return
	var report:Dictionary = session.server_data.get("status", {}).get("report", {}) if _server_selecting else _validation.report.get("loop_analysis", {})
	$RiskConfirmation/Report.text = _risk_text(report, true)

func _risk_text(report: Dictionary, detailed:bool = false) -> String:
	var summary:Array[String] = ["内容有效性检查已通过。以下是运行检查提示，不是数据文件损坏报告。"]
	var cycles:Array = report.get("cycles", [])
	if not cycles.is_empty():
		summary.append("\n疑似循环链：" + str(cycles.size()) + "。不等于已确认死循环，请查看详细报告。")
	for item in report.get("warnings", []):
		if item.get("kind") == "random_simulation":
			summary.append("\n试运行结果：" + str(item.message) + "。不代表数据格式错误，也不代表已排除运行风险。")
		else:
			summary.append("\n存在循环步骤提示，请查看详细报告。")
	var unknowns:Array = report.get("unknowns", [])
	if not unknowns.is_empty():
		summary.append("\n静态分析未覆盖：" + str(unknowns.size()) + "。动态创建或延迟执行等效果无法仅靠静态图确认，不表示这些效果已经出错。")
	if not detailed:
		summary.append("\n可确认使用所选数据，或返回调整选择与试运行设置。")
		return "\n".join(summary)
	var origins: Dictionary = {}
	if _server_selecting:
		for path in session.server_data.get("status", {}).get("origins", {}):
			var source:Dictionary = session.server_data.status.origins[path]
			origins[path] = _provider_name(source.provider) + " · " + source.path
	else:
		for index in range(_plan.files.size()):
			var source:Dictionary = _plan.sources[index]
			origins[_plan.files[index].path] = _provider_name(source.provider) + " · " + source.path
	var lines: Array[String] = []
	lines.assign(summary)
	lines.append("\n详细报告：未完成模拟也不等于已排除风险。")
	for group in report.get("cycles", []):
		lines.append("\n高风险环" if group.risk == "high" else "\n有限制的风险环")
		for id in group.nodes:
			var node: Dictionary = report.nodes[id]
			lines.append(node.name + " · " + origins.get(node.path, "来源未声明 · " + node.path) + "\n" + node.pointer)
	for item in report.get("warnings", []):
		if item.get("kind") == "random_simulation":
			lines.append("\n" + item.message)
			continue
		var node: Dictionary = report.nodes[item.node]
		lines.append("\n循环步骤风险 · " + node.name + " · " + origins.get(node.path, node.path))
	for item in report.get("unknowns", []):
		lines.append("\n无法静态确认 · " + item.reason + " · " + origins.get(item.path, item.path) + "\n" + item.pointer)
	return "\n".join(lines)

func _apply_validated() -> void:
	_awaiting_risk_confirmation = false
	if _server_selecting:
		if _server_owner() and _server_pending and _server_current_request > 0 and _server_confirmed_request != _server_current_request:
			_server_confirmed_request = _server_current_request
			session.request("server_data_commit", {"request_id":_server_current_request})
		return
	if session == null or not session._host or session.room.phase != "lobby" or not _validation.complete:
		_fail("当前房间无法应用这次校验结果")
		return
	if not _preparation.simulation_is_current():
		_fail("预检策略已变化，请重新校验")
		return
	if not session.apply_room_data(_validation, config):
		_fail(session.error)
		return
	status.text = "房间数据已应用。等待成员同步。"
	_set_busy(false)
	applied.emit(_validation.directory.path_join("validation-data"))

func _set_busy(value: bool) -> void:
	$Margin/Content/Actions/CancelCheck.disabled = not value
	$Margin/Content/Actions/Apply.disabled = value
	$Margin/Content/Actions/ServerSources.disabled = value
	$Margin/Content/Filter/All.disabled = value
	$Margin/Content/Filter/None.disabled = value
	$Margin/Content/Budget/Seconds.editable = not value
	for item in _items:
		item.set_editable(0, not value)

func _fail(reason: String) -> void:
	cancel()
	status.text = reason

func cancel() -> void:
	var had_work:bool = _server_pending or _preparing or _validation.running or _awaiting_risk_confirmation
	_awaiting_risk_confirmation = false
	if _server_pending and _server_owner() and _server_current_request > 0:
		session.request("server_data_cancel", {"request_id":_server_current_request})
	_server_pending = false
	_preparation.cancel()
	_preparation = preload("res://scripts/net/validation/room_data_preparation.gd").new()
	_validation = _preparation.validation
	if is_node_ready():
		$RiskConfirmation.hide()
		_set_busy(false)
		if had_work: status.text = "已请求取消校验，等待服务端回执" if _server_selecting else "本次数据校验已取消"

func _exit_tree() -> void:
	cancel()
	if session != null and session.rejected.is_connected(_server_rejected): session.rejected.disconnect(_server_rejected)
	session = null

func _needs_risk_confirmation(report:Dictionary) -> bool:
	return report.get("cycles", []).any(func(group): return group.risk == "high") or not report.get("warnings", []).is_empty()

func _server_rejected(reason:String) -> void:
	if not _server_selecting or not visible: return
	_server_pending = false
	_set_busy(false)
	status.text = reason

func _poll_server() -> void:
	if not visible and not _server_pending: return
	if not _server_owner():
		cancel()
		$Margin/Content/Actions/Apply.disabled = true
		$Margin/Content/Actions/ServerSources.hide()
		return
	if not _server_pending:
		if int(session.server_data.get("catalog_revision", 0)) != _server_catalog_revision: _load_server_catalog({})
		var terminal:Dictionary = session.server_data.get("status", {})
		if _server_current_request > 0 and terminal.get("request_id") == _server_current_request and terminal.get("stage") in ["applied", "error", "cancelled"]:
			status.text = terminal.text
		return
	var state:Dictionary = session.server_data.get("status", {})
	if int(state.get("request_id", 0)) <= _server_previous_request: return
	_server_current_request = state.request_id
	status.text = state.text
	if state.stage in ["applied", "error", "cancelled"]:
		_awaiting_risk_confirmation = false
		_server_pending = false
		$RiskConfirmation.hide()
		_set_busy(false)
		check_finished.emit()
	elif state.stage == "ready" and _server_confirmed_request == 0 and not $RiskConfirmation.visible:
		if _needs_risk_confirmation(state.report):
			_awaiting_risk_confirmation = true
			$RiskConfirmation/Report.text = _risk_text(state.report)
			status.text = "校验完成，等待房主确认；请查看运行风险报告。"
			if visible: $RiskConfirmation.popup_centered(Vector2i(800, 440))
			else: status.text = "校验完成，等待确认，请打开本局内容查看运行风险报告。"
		else: _apply_validated()

func background_status() -> String:
	if _awaiting_risk_confirmation: return "后台校验完成，等待确认，请打开本局内容"
	if _server_pending:
		var state:Dictionary = session.server_data.get("status", {}) if session != null else {}
		if state.get("request_id") == _server_current_request and state.get("stage") == "ready":
			return "校验完成，正在请求应用所选数据" if _server_confirmed_request == _server_current_request else "后台校验完成，等待确认，请打开本局内容"
	if _server_pending or _preparing or _validation.running: return "本局内容正在后台检查：" + status.text
	return ""

func reset_selection() -> void:
	cancel()
	_entries.clear()
	_items.clear()
	if is_node_ready():
		tree.clear()
