extends Control

const Session = preload("res://scripts/net/lobby_session.gd")
var session = Session.new()
var cache = session.blobs.cache
var _data_sync = preload("res://scripts/net/room_data_sync.gd").new()
var _sync_revision: int = 0
var _synced_revision: int = 0
var room_data_directory: String = ""
var _local_data_root: String = ""
var modes: Array = []
var _ready_state := false
var _owner := false
var _selected_member: int = 0
var _entering_match: bool = false
var _session_transferred: bool = false
var _p2p = preload("res://scripts/net/p2p_invite.gd").new()
var _signal = preload("res://scripts/net/p2p_signal_client.gd").new()
var _invite_target: int = 0
var _shown_guard_config: Dictionary = {}
@onready var content: VBoxContainer = $Margin/Content
@onready var status: Label = $Margin/Content/Status
@onready var mode: OptionButton = $Margin/Content/Settings/Mode
@onready var ai: SpinBox = $Margin/Content/Settings/AI

func _ready() -> void:
	_signal.room_created.connect(_on_signal_created)
	_signal.rejected.connect(_on_rejected)
	session.changed.connect(_refresh)
	session.rejected.connect(_on_rejected)
	$Margin/Content/Connection/Host.pressed.connect(_host)
	$Margin/Content/Connection/Join.pressed.connect(_join)
	$Margin/Content/Actions/Ready.pressed.connect(_ready_clicked)
	$Margin/Content/Actions/Leave.pressed.connect(_leave)
	$Margin/Content/Actions/ClearCache.pressed.connect(_clear_cache)
	$Margin/Content/Actions/Sync.pressed.connect(_sync_data)
	$Margin/Content/Actions/Data.pressed.connect(_show_room_data)
	$RoomDataPanel.applied.connect(func(directory):
		room_data_directory = directory
		_refresh()
	)
	$Margin/Content/Actions/Start.pressed.connect(func(): session.request("start", {}))
	$Margin/Content/Actions/BeginMatch.pressed.connect(func(): session.request("begin_match", {}))
	$Margin/Content/Selection/Choose.pressed.connect(_choose_master)
	$Margin/Content/Members.item_selected.connect(_select_member)
	$Margin/Content/Actions/Transfer.pressed.connect(func(): session.request("transfer", {"target": _selected_member}))
	$Margin/Content/Actions/Kick.pressed.connect(func(): session.request("kick", {"target": _selected_member}))
	mode.item_selected.connect(_mode_changed)
	ai.value_changed.connect(_ai_changed)
	$Margin/Content/Guard/Fields/Apply.pressed.connect(_apply_guard_config)
	$Margin/Content/Protocol/NetworkMode.item_selected.connect(_network_mode_changed)
	$Margin/Content/P2P/Buttons/Invite.pressed.connect(_new_invite)
	$Margin/Content/P2P/Buttons/Apply.pressed.connect(_apply_answer)
	$Margin/Content/P2P/Buttons/Copy.pressed.connect(func():
		if not $Margin/Content/P2P/Output.text.is_empty():
			DisplayServer.clipboard_set($Margin/Content/P2P/Output.text)
	)
	var file := FileAccess.open(LoadHelper.get_data_dir().path_join("selection_modes.json"), FileAccess.READ)
	if file == null:
		status.text = "无法读取选人模式"
		return
	var declared = JSON.parse_string(file.get_as_text())
	if not declared is Dictionary or not declared.get("modes") is Array:
		status.text = "选人模式数据无效"
		return
	modes = declared.modes
	for item in modes:
		mode.add_item(str(item.get("name", "")))
	_mode_changed(0)
	_network_mode_changed(0)
	if not session.view.is_empty():
		_refresh()

func _process(delta: float) -> void:
	session.poll(delta)
	if session.connection_driver != _p2p:
		_p2p.poll()
	if _invite_target != 0 and $Margin/Content/P2P/Output.text.is_empty():
		var code: String = _p2p.export_code(_invite_target)
		if not code.is_empty():
			$Margin/Content/P2P/Output.text = code
		elif not _p2p.error.is_empty():
			status.text = _p2p.error
	if _data_sync.running:
		_data_sync.poll()
		status.text = "正在同步房间数据：%d / %d" % [_data_sync.completed_files, session.room_files.size()]
		if not _data_sync.running:
			if _data_sync.complete and _sync_revision == session.data_revision and session.install_room_assets(room_data_directory):
				_synced_revision = _sync_revision
				session.request("data_ack", {"revision": _sync_revision})
				status.text = "房间数据同步完成"
			else:
				status.text = _data_sync.error
			_refresh()

func _sync_data() -> void:
	if session._host or session.data_revision <= 0 or _data_sync.running:
		return
	_sync_revision = session.data_revision
	room_data_directory = "user://rooms/%s/data" % str(Time.get_ticks_usec())
	if not _data_sync.begin(session, session.room_files, room_data_directory):
		status.text = _data_sync.error
	_refresh()

func _capacity() -> int:
	if mode.selected < 0 or mode.selected >= modes.size():
		return 0
	var declared: Dictionary = modes[mode.selected]
	var rules = load(str(declared.script)).new()
	return rules.capacity(GameStart.get_masters_can_use(), GameStart.get_servants_can_use(), declared)

func _network_mode_changed(index: int) -> void:
	var server := index == 1
	var p2p := index in [2, 3]
	var signaling := index == 3
	$Margin/Content/Protocol/RoomName.visible = server
	$Margin/Content/Protocol/RoomID.visible = server
	$Margin/Content/Settings/BindLabel.visible = not server and not p2p
	$Margin/Content/Settings/BindAddress.visible = not server and not p2p
	$Margin/Content/Connection/Address.visible = not p2p
	$Margin/Content/Connection/Port.visible = not p2p
	$Margin/Content/P2P.visible = p2p
	$Margin/Content/P2P/Signaling.visible = signaling
	$Margin/Content/P2P/Output.visible = not signaling
	$Margin/Content/P2P/Input.visible = not signaling
	$Margin/Content/P2P/Buttons.visible = not signaling
	$Margin/Content/P2P/Help.text = "服务只交换握手信令，对局始终直连。房主将房间码发送给客机，无法直连时明确失败。" if signaling else "房主发送邀请码，客机回传应答码。每位客机使用独立邀请码，对局流量只走直连。"
	$Margin/Content/Connection/Host.text = "创建 P2P 房间" if p2p else ("在服务端创建房间" if server else "创建局域网房间")

func _on_rejected(reason: String) -> void:
	status.text = reason

func _on_signal_created(code: String) -> void:
	$Margin/Content/P2P/Signaling/Room.text = code
	status.text = "信令房间已创建，请复制房间码给客机"

func _ice_configuration() -> Dictionary:
	var servers: Array = []
	for value in $Margin/Content/P2P/STUN.text.split(",", false):
		var address: String = value.strip_edges()
		if not address.is_empty():
			servers.append({"urls": address})
	return {"iceServers": servers}

func _new_invite() -> void:
	if not session._host or session.connection_driver != _p2p:
		return
	_invite_target = _p2p.offer()
	$Margin/Content/P2P/Output.text = ""
	status.text = "正在收集直连地址" if _invite_target > 1 else "无法创建邀请码"

func _apply_answer() -> void:
	if not session._host or session.connection_driver != _p2p:
		return
	status.text = "正在建立 P2P 直连" if _p2p.accept_answer($Margin/Content/P2P/Input.text.strip_edges()) else "应答码无效、已使用或不属于此房间"

func _initialize_local_owner() -> void:
	_local_data_root = LoadHelper.get_data_dir()
	session.require_room_data = true
	session.configure_selection(modes[mode.selected], GameStart.get_masters_can_use(), GameStart.get_servants_can_use())
	session._publish()

func _mode_changed(_index: int) -> void:
	ai.max_value = maxi(0, _capacity() - 1)

func _read_guard_config() -> Dictionary:
	var step_text:String = $Margin/Content/Guard/Fields/Steps.text.strip_edges()
	if not step_text.is_valid_int():
		return {"ok":false, "error":"步骤预算必须是整数"}
	var normalized := step_text.trim_prefix("+").trim_prefix("-").lstrip("0")
	if normalized.is_empty():
		normalized = "0"
	if step_text.begins_with("-") and normalized != "0":
		return {"ok":false, "error":"步骤预算不能为负数"}
	# 先检查十进制边界，不能先转换再让整数溢出被截断。
	if normalized.length() > 19 or (normalized.length() == 19 and normalized > "9223372036854775807"):
		return {"ok":false, "error":"步骤预算超出整数范围"}
	var seconds_text:String = $Margin/Content/Guard/Fields/Seconds.text.strip_edges()
	if not seconds_text.is_valid_float():
		return {"ok":false, "error":"时间预算必须是有限非负数"}
	var config := {"enabled":$Margin/Content/Guard/Fields/Enabled.button_pressed,
		"steps":normalized.to_int(), "seconds":seconds_text.to_float()}
	if not preload("res://scripts/match/rule_budget.gd").new().configure(config):
		return {"ok":false, "error":"时间预算必须是有限非负数"}
	return {"ok":true, "config":config}

func _apply_guard_config() -> void:
	var result := _read_guard_config()
	if not result.ok:
		status.text = result.error
		return
	session.request("settings", {"changes":{"runtime_guard":result.config}})

func _refresh_guard_config(view:Dictionary) -> void:
	var fields := $Margin/Content/Guard/Fields
	var editable:bool = view.is_empty() or (_owner and view.get("phase") == "lobby")
	fields.get_node("Enabled").disabled = not editable
	fields.get_node("Steps").editable = editable
	fields.get_node("Seconds").editable = editable
	fields.get_node("Apply").disabled = view.is_empty() or not editable
	if view.is_empty():
		_shown_guard_config.clear()
		return
	var config:Dictionary = view.get("settings", {}).get("runtime_guard", {"enabled":false, "steps":0, "seconds":0.0})
	# 成员准备等无关更新不能覆盖尚未应用的输入。
	if config == _shown_guard_config:
		return
	_shown_guard_config = config.duplicate(true)
	fields.get_node("Enabled").set_pressed_no_signal(config.enabled)
	fields.get_node("Steps").text = str(config.steps)
	fields.get_node("Seconds").text = BaseNumber.display_text(config.seconds)

func _host() -> void:
	var budget := _read_guard_config()
	if not budget.ok:
		status.text = budget.error
		return
	_reset_data_sync()
	var capacity := _capacity()
	if capacity <= 0:
		status.text = "当前数据无法创建房间"
		return
	var settings := {"capacity": capacity, "minimum": 1, "selection_mode": str(modes[mode.selected].id), "ai_count": int(ai.value), "spectator_limit": capacity}
	settings["runtime_guard"] = budget.config
	if $Margin/Content/Protocol/NetworkMode.selected == 3:
		var result: Error = _signal.host($Margin/Content/P2P/Signaling/Server.text.strip_edges(), session, $Margin/Content/Connection/Name.text, settings, _ice_configuration())
		if result == OK:
			_initialize_local_owner()
			status.text = "正在连接信令服务"
			_refresh()
		else:
			status.text = "信令创建失败：" + error_string(result)
		return
	if $Margin/Content/Protocol/NetworkMode.selected == 2:
		session.close()
		_p2p.close()
		var p2p_result: Error = _p2p.link.open(1, _ice_configuration())
		if p2p_result == OK:
			p2p_result = session.host_peer(_p2p.link.peer, $Margin/Content/Connection/Name.text, settings)
		if p2p_result != OK:
			status.text = "P2P 创建失败：" + error_string(p2p_result)
			return
		session.connection_driver = _p2p
		_initialize_local_owner()
		_new_invite()
		_refresh()
		return
	if $Margin/Content/Protocol/NetworkMode.selected == 1:
		var server_result: Error = session.join_server($Margin/Content/Connection/Address.text, int($Margin/Content/Connection/Port.value), $Margin/Content/Connection/Name.text, "", $Margin/Content/Protocol/RoomName.text, settings)
		status.text = "正在服务端创建房间" if server_result == OK else "服务端连接失败：" + error_string(server_result)
		return
	var result: Error = session.host(int($Margin/Content/Connection/Port.value), $Margin/Content/Connection/Name.text, settings, $Margin/Content/Settings/BindAddress.text)
	_owner = result == OK
	if _owner:
		_initialize_local_owner()
	status.text = "房间已创建" if result == OK else "无法监听端口：" + error_string(result)
	_refresh()

func _show_room_data() -> void:
	if session.view.get("phase") != "lobby" or (session._host and not _owner):
		return
	if not $RoomDataPanel._preparing and not $RoomDataPanel._validation.running:
		$RoomDataPanel.configure(session, _local_data_root if session._host else LoadHelper.get_data_dir(), modes[mode.selected])
	$RoomDataPanel.popup_centered()

func _join() -> void:
	_reset_data_sync()
	_owner = false
	if $Margin/Content/Protocol/NetworkMode.selected == 3:
		var result: Error = _signal.join($Margin/Content/P2P/Signaling/Server.text.strip_edges(), $Margin/Content/P2P/Signaling/Room.text.strip_edges(), session, $Margin/Content/Connection/Name.text, $Margin/Content/Connection/Spectator.button_pressed, _ice_configuration())
		status.text = "正在自动建立 P2P 直连" if result == OK else "信令加入失败：" + error_string(result)
		return
	if $Margin/Content/Protocol/NetworkMode.selected == 2:
		session.close()
		_p2p.close()
		if not _p2p.accept_offer($Margin/Content/P2P/Input.text.strip_edges(), _ice_configuration()):
			status.text = "邀请码或 STUN 配置无效"
			return
		var p2p_result: Error = session.join_peer(_p2p.link.peer, $Margin/Content/Connection/Name.text, $Margin/Content/Connection/Spectator.button_pressed)
		if p2p_result != OK:
			status.text = "P2P 加入失败：" + error_string(p2p_result)
			return
		session.connection_driver = _p2p
		_invite_target = 1
		$Margin/Content/P2P/Output.text = ""
		status.text = "正在生成应答码，生成后请发回房主"
		return
	var result: Error
	if $Margin/Content/Protocol/NetworkMode.selected == 1:
		var id: String = $Margin/Content/Protocol/RoomID.text
		if id.is_empty():
			status.text = "请填入服务端房间 ID"
			return
		result = session.join_server($Margin/Content/Connection/Address.text, int($Margin/Content/Connection/Port.value), $Margin/Content/Connection/Name.text, id, "", {}, $Margin/Content/Connection/Spectator.button_pressed)
	else:
		result = session.join($Margin/Content/Connection/Address.text, int($Margin/Content/Connection/Port.value), $Margin/Content/Connection/Name.text, $Margin/Content/Connection/Spectator.button_pressed)
	status.text = "正在连接" if result == OK else "连接失败：" + error_string(result)

func _ready_clicked() -> void:
	_ready_state = not _ready_state
	session.request("ready", {"ready": _ready_state})

func _ai_changed(value: float) -> void:
	if _owner:
		session.request("settings", {"changes": {"ai_count": int(value)}})

func _refresh() -> void:
	var p2p_host: bool = session._host and session.connection_driver == _p2p
	$Margin/Content/P2P/Buttons/Invite.disabled = not p2p_host
	$Margin/Content/P2P/Buttons/Apply.disabled = not p2p_host
	if _data_sync.running and _sync_revision != session.data_revision:
		_data_sync.cancel()
	$Margin/Content/Actions/Sync.disabled = session.view.is_empty() or session._host or session.data_revision <= 0 or _data_sync.running or _synced_revision == session.data_revision
	var members: ItemList = $Margin/Content/Members
	members.clear()
	var view: Dictionary = session.view
	_owner = not view.is_empty() and view.get("owner") == session.peer_id()
	if not session.server_room_id.is_empty():
		$Margin/Content/Protocol/RoomID.text = session.server_room_id
	$Margin/Content/Actions/Data.disabled = view.get("phase") != "lobby" or (session._host and not _owner)
	$Margin/Content/Actions/Data.text = "房间数据" if session._host else "共享条目"
	var local_can_ready := false
	for member in view.get("members", []):
		var state := "已准备" if member.ready else "未准备"
		if not member.connected:
			state = "已掉线"
		var role: String = "观战" if member.spectator else "玩家"
		if member.id == view.owner:
			role = "房主"
		members.add_item("%s  %s  %s" % [member.name, role, state])
		members.set_item_metadata(members.item_count - 1, member.id)
		if member.id == _selected_member:
			members.select(members.item_count - 1)
		if member.id == session.peer_id():
			_ready_state = member.ready
			local_can_ready = member.connected and not member.spectator
	var count: int = int(view.get("settings", {}).get("ai_count", 0))
	for i in range(count):
		members.add_item("AI %d" % (i + 1))
		members.set_item_metadata(members.item_count - 1, 0)
	$Margin/Content/Actions/Ready.disabled = not local_can_ready or view.get("phase") != "lobby"
	$Margin/Content/Actions/Ready.text = "取消准备" if _ready_state else "准备"
	mode.disabled = not view.is_empty()
	ai.editable = view.is_empty() or (_owner and view.get("phase") == "lobby")
	if not view.is_empty():
		ai.set_value_no_signal(count)
	_refresh_guard_config(view)
	$Margin/Content/Actions/Start.disabled = not _owner or not view.get("can_start", false)
	if view.get("phase") == "lobby":
		status.text = "已连接房间 · 你拥有房间管理权" if _owner else "已连接房间 · 等待房主开始选人"
		if session._host and session.require_room_data and session._rules_revision != session.data_revision:
			status.text = "请打开房间数据，选择条目并校验应用"
		elif session._host and session.require_room_data and session.data_revision == 0:
			status.text = "请打开房间数据，选择条目并校验应用"
	_update_management()
	var selection: Dictionary = session.selection_view
	$Margin/Content/Selection.visible = not selection.is_empty()
	var picker: OptionButton = $Margin/Content/Selection/Master
	picker.clear()
	for item in selection.get("choices", []):
		picker.add_item(item.label)
		picker.set_item_metadata(picker.item_count - 1, item)
	$Margin/Content/Selection/Choose.disabled = picker.item_count == 0
	if selection.get("complete", false):
		status.text = "御主选择完成，从者已抽取。抽取结果不公示。"
	if _data_sync.running:
		status.text = "正在同步房间数据：%d / %d" % [_data_sync.completed_files, session.room_files.size()]
	elif session.data_revision > 0 and not session._host:
		status.text = "房间数据同步完成" if _synced_revision == session.data_revision else "房间数据已更新，请同步后继续"
	$Margin/Content/Actions/BeginMatch.disabled = not _owner or not selection.get("complete", false) or view.get("phase") != "selecting" or not view.get("data_ready", true)
	if not _entering_match and not session.read_match().is_empty():
		_entering_match = true
		call_deferred("_enter_match")

func _enter_match() -> void:
	if not is_inside_tree() or session.read_match().is_empty():
		_entering_match = false
		return
	var scene := load("res://assets/scenes/game_scene/battle_board_v2.tscn") as PackedScene
	if scene == null:
		_entering_match = false
		status.text = "无法加载对局场景"
		return
	var board = scene.instantiate()
	board.network_session = session
	_session_transferred = true
	set_process(false)
	session.changed.disconnect(_refresh)
	get_tree().root.add_child(board)
	get_tree().current_scene = board
	queue_free()

func _choose_master() -> void:
	var picker: OptionButton = $Margin/Content/Selection/Master
	if picker.selected < 0:
		return
	var choice: Dictionary = picker.get_item_metadata(picker.selected)
	session.request("choose_master", {"seat": choice.seat, "name": choice.name})

func _select_member(index: int) -> void:
	_selected_member = int($Margin/Content/Members.get_item_metadata(index))
	_update_management()

func _update_management() -> void:
	var target: Dictionary = {}
	for member in session.view.get("members", []):
		if member.id == _selected_member:
			target = member
	var allowed: bool = _owner and not target.is_empty() and _selected_member != session.view.get("owner", 0)
	$Margin/Content/Actions/Kick.disabled = not allowed
	$Margin/Content/Actions/Transfer.disabled = not allowed or not target.get("connected", false) or target.get("spectator", true)

func _leave() -> void:
	_reset_data_sync()
	session.close()
	_signal.close()
	_p2p.close()
	_invite_target = 0
	$Margin/Content/P2P/Output.text = ""
	_owner = false
	_ready_state = false
	status.text = "已离开房间"
	_refresh()

func _reset_data_sync() -> void:
	$RoomDataPanel.reset_selection()
	$RoomDataPanel.hide()
	_data_sync.cancel()
	_sync_revision = 0
	_synced_revision = 0
	room_data_directory = ""

func _exit_tree() -> void:
	_data_sync.cancel()
	if _signal.room_created.is_connected(_on_signal_created):
		_signal.room_created.disconnect(_on_signal_created)
	if _signal.rejected.is_connected(_on_rejected):
		_signal.rejected.disconnect(_on_rejected)
	if session.rejected.is_connected(_on_rejected):
		session.rejected.disconnect(_on_rejected)
	if not _session_transferred:
		session.close()
		_signal.close()
		_p2p.close()

func _clear_cache() -> void:
	var removed: int = cache.clear_unused()
	var usage: Dictionary = cache.usage()
	status.text = "已清理缓存 %d，保留使用中 %d" % [removed, usage.pinned]
