extends RefCounted

const SharedViewSections = preload("res://scripts/game_scene/battle_io/shared_view_sections.gd")

## 仅消费会话过滤视图；不得查询 GameData、EffectManager 或执行规则。
var board: Control
var session
var _sequence: int = -1
var selection = preload("res://scripts/net/ui/group_selection.gd").new()
var _hand_dirty: bool = true
var _hand_revision: int = 0
var _mine: Dictionary = {}
var _guard_requested_seq: int = -1
var _guard_request_sequence: int = 0
var _inheritance_switch_pending: bool = false
var _browse_observer: int = -2

var _game_over_presented: bool = false
var _area_submitted_seq: int = -1
var _area_request_sequence: int = 0

func _init(target: Control, source) -> void:
	board = target
	session = source
	board.get_node("NetworkChoices/Panel").bind_session(session)
	# 未迁移区域隐藏，避免显示场景内的样例数据。
	for path in ["Main", "Events", "Seats", "Rivals", "Situation", "Piles", "Route", "Board", "Hand", "AreaTitle", "Hint", "Self/Spells", "Self/Me", "Self/CountBadge"]:
		board.get_node(path).hide()
	for path in ["Ops/PlayButton", "Ops/EndButton", "Top/BoardButton", "Top/LogButton"]:
		board.get_node(path).disabled = true
	board.get_node("Self").hide()
	board.get_node("Master").hide()
	board.get_node("Top/Center/Dots").hide()
	board.get_node("Top/Center/NightLabel").text = "等待主机视图"
	board.get_node("Top/Center/RoundLabel").text = ""
	board._clear(board.get_node("Top/Center/Phases"))
	board.get_node("Banner").show()
	board.get_node("Banner/Text").text = "等待主机视图"
	board.get_node("Banner/Avatar").hide()
	board.get_node("Ops/PlayButton").pressed.connect(board._confirm_held_cards)

	board.get_node("NetworkChoices/Guard/Margin/Row/Actions/Skip").pressed.connect(_skip_guard)
	board.get_node("NetworkChoices/Guard/Margin/Row/Actions/Restart").pressed.connect(_show_restart_choices)
	board.get_node("NetworkChoices/Guard/Margin/Row/RestartChoices/Current").pressed.connect(_restart_guard)
	board.get_node("NetworkChoices/Guard/Margin/Row/RestartChoices/Lobby").pressed.connect(_return_guard_lobby)
	board.get_node("NetworkChoices/Guard/Margin/Row/RestartChoices/Cancel").pressed.connect(_cancel_restart_choices)
	board.get_node("NetworkChoices/ConnectionWait/Margin/Row/Reconnect").pressed.connect(_reconnect)
	session.request_rejected.connect(_guard_rejected)
	session.request_rejected.connect(_area_rejected)
	session.rejected.connect(_inheritance_rejected)
	session.inheritance_ticket_received.connect(_inheritance_ticket_received)
	board.get_node("NetworkChoices/ConnectionWait/Margin/Row/InheritIdentity").pressed.connect(_open_identity_inheritance)
	session.server_notice_received.connect(_server_notice)
	selection.bind_session(session)
	selection.changed.connect(_selection_changed)
	board.get_node("Top/LogButton").pressed.connect(open_log)
	board.get_node("Top/BoardButton").pressed.connect(board._toggle_scoreboard)


func open_log() -> void:
	var snapshot: Dictionary = session.read_match()
	var lines: Array = snapshot.get("public_log", []).duplicate()
	lines.reverse()
	var battle_lines := SharedViewSections.public_battle_result_lines(snapshot.get("battle_result", {}), snapshot.get("players", []))
	if not battle_lines.is_empty():
		lines = battle_lines + [""] + lines
	var entries: RichTextLabel = board.get_node("LogBrowser/Panel/Entries")
	entries.bbcode_enabled = false
	entries.text = "══ 公共对局日志 ══\n\n" + "\n\n".join(PackedStringArray(lines))
	entries.scroll_to_line(0)
	board.get_node("LogBrowser").show()
	board._raise_modal(board.get_node("LogBrowser"))

## 联机终局只消费权威快照，保留战果榜供玩家选择去向。
## 战斗摘要由玩家手动打开公共日志查看，不在客户端重新计算胜负。
func show_game_over(_view: Dictionary) -> void:
	# 兼容旧调用名；终局判据与一次性展示只由 board 的过滤数据源决定。
	board._check_game_over()
	_game_over_presented = board._game_over_shown


func browse_input(event: InputEvent) -> bool:
	for overlay in [board._hover_zoom, board._hover_desc]:
		if overlay.visible and event is InputEventMouse and overlay.get_global_rect().has_point(event.position):
			return event is InputEventMouseMotion
	# 浏览器拥有当前输入；防止在上层浏览器内点击误收底层抽屉。
	for path in ["CardBrowser", "LogBrowser"]:
		var reader: Control = board.get_node(path)
		if not reader.visible:
			continue
		if event is InputEventMouseButton and event.pressed:
			var panel: Control = reader.get_node("Panel")
			if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT] and not panel.get_global_rect().has_point(event.position):
				reader.hide()
				board._hide_event_zoom()
				board.get_viewport().set_input_as_handled()
				return true
			var direction: int = board._wheel_direction(event)
			if path == "CardBrowser" and direction != 0:
				var scroll: ScrollContainer = reader.get_node("Panel/CardScroll")
				if scroll.get_global_rect().has_point(event.position):
					board._wheel_scroll(scroll, direction)
					board.get_viewport().set_input_as_handled()
					return true
		# 禁止只读模态期间全局地图悬浮切换。
		return event is InputEventMouseMotion
	if board._is_paused():
		return event is InputEventMouseMotion
	var drawer: Control = board._opponent_drawer
	if event is InputEventMouseButton and event.pressed and drawer.visible:
		var direction: int = board._wheel_direction(event)
		if drawer.get_global_rect().has_point(event.position) and direction != 0:
			for row in board._drawer_rows():
				var sc: ScrollContainer = row.get_node_or_null("Scroll")
				if sc != null and sc.is_visible_in_tree() and sc.get_global_rect().has_point(event.position):
					board._wheel_scroll(sc, direction)
					board.get_viewport().set_input_as_handled()
					return true
		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT] and not drawer.get_global_rect().has_point(event.position):
			var hovered: Control = board.get_viewport().gui_get_hovered_control()
			while hovered != null:
				if hovered.has_meta("turn_order_player_id"):
					return false
				hovered = hovered.get_parent_control()
			board._on_close_opponent_drawer_pressed()
			board.get_viewport().set_input_as_handled()
			return true
	return false


## 数值只来自权威声明的构成；缺字段不从本机规则补齐。
func player_view(pid: int) -> Dictionary:
	for player in session.read_match().get("players", []):
		if player.id == pid:
			return player
	return {}

func power_lines(player: Dictionary) -> Array[String]:
	return SharedViewSections.power_lines(player)

func update_drawer(opponent: Control = null) -> void:
	board._update_drawer_visuals(opponent)

func _refresh_group_reveal() -> void:
	var ready: bool = not board._scroll_is_animating() and board._strip_open(board._strip_by_index(board._main_area_index))
	if not ready:
		return
	for group in board._play_group_nodes():
		if not is_instance_valid(group) or group.has_meta("shown"):
			continue
		group.set_meta("shown", true)
		group.set_meta("shown_at", Time.get_ticks_msec() / 1000.0)
		group.modulate.a = 1.0
		board._play_avatar_entrance(group.get_node("Who/Avatar"), group.get_node("Who/Total"))

func _clear_phase_residue_visuals() -> void:
	# 同序号恢复需要失效传输缓存；视觉生命周期由 board 共享。
	_sequence = -1
	_mine.clear()
	_hand_dirty = true
	board._clear_shared_phase_residue_visuals()

func refresh() -> void:
	_refresh_group_reveal()
	var view: Dictionary = session.read_match()
	var observer: int = int(view.get("observer", -1))
	if observer != _browse_observer:
		_invalidate_area_confirmation(-1)
		_area_submitted_seq = -1
		_area_request_sequence = 0
		_browse_observer = observer
		_game_over_presented = false
		board._game_over_shown = false
		_clear_phase_residue_visuals()
		board._close_card_modification_history()
		board._close_card_browser()
		board.get_node("LogBrowser").hide()
		board._on_close_opponent_drawer_pressed()
		board.get_node("Board").hide()
	_invalidate_area_confirmation(int(view.get("seq", -1)))
	if int(view.get("seq", -1)) != _area_submitted_seq:
		_area_submitted_seq = -1
	_refresh_guard(view.get("seq", -1))
	_refresh_connection_wait()
	board.get_node("IdentityInheritancePanel").refresh_context()
	board.get_node("NetworkChoices/Panel").refresh_submission_availability()
	board._update_end_command_button()
	board.get_node("Top/LogButton").disabled = view.is_empty()
	board.get_node("Top/BoardButton").disabled = view.is_empty()
	board.get_node("Piles").visible = not view.is_empty()

	if view.is_empty():
		_game_over_presented = false
		board._check_game_over()
		_clear_phase_residue_visuals()
		for path in ["Self", "Master", "Hand"]:
			board.get_node(path).hide()
		board._on_close_opponent_drawer_pressed()
		board.get_node("CardBrowser").hide()
		board.get_node("LogBrowser").hide()
		board.get_node("Board").hide()
		_refresh_selection_feedback()
		return
	if view.seq == _sequence:
		if _hand_dirty:
			_bind_hand()
		_refresh_selection_feedback()
		return
	_sequence = view.seq
	board._bind_shared_phase_view(view)
	show_game_over(view)
	var mine: Dictionary = {}
	var actor: Dictionary = {}

	for player in view.players:
		if player.id == view.observer:
			mine = player
		if player.id == view.current_player:
			actor = player
	board.get_node("Banner/Text").text = "对局结束" if view.game_over else ("%s 的行动" % actor.get("master", {}).get("name", actor.get("player_name", "")))
	board.get_node("Banner/Avatar").visible = not actor.is_empty()
	board._bind_avatar(board.get_node("Banner/Avatar"), actor.get("avatar", ""))
	board._bind_rivals()
	board._bind_residue_piles()
	_mine = mine
	var buff_list: Control = board.get_node("Ops/BuffBox/List")
	buff_list.get_node("None").visible = board._fill_buff_rows(buff_list, mine.get("buffs", []), ["None"]) == 0
	if board.get_node("Board").visible:
		board._bind_board()
	if board._opponent_drawer.visible:
		update_drawer()
	board._bind_situation_and_piles()
	board._local_player_id = int(view.observer)
	board._bind_strips()
	board._fly_armed = true
	if mine.is_empty():
		board.get_node("Self").hide()
		board.get_node("Master").hide()
		_bind_hand()
		_refresh_selection_feedback()
		return
	board._bind_self()
	board.get_node("Master").visible = not mine.master.is_empty()
	board._set_img(board.get_node("Master"), "Frame/Img", mine.master.get("image", ""))
	board.bind_zoom_for_card(board.get_node("Master/Frame/Img"), mine.master)
	board._set_text(board.get_node("Master"), "Name", mine.master.get("name", ""))

	_bind_action_hint(view, actor)
	_bind_hand()
	_refresh_selection_feedback()

## 数据来自私有预览回执；无字段时收起浮窗，不用卡面数字补齐。
func _refresh_selection_feedback() -> void:
	var snapshot: Dictionary = selection.snapshot()
	var preview: Dictionary = snapshot.preview
	var valid: bool = not snapshot.cards.is_empty() and not snapshot.waiting and not snapshot.submitted and preview.get("ok", false) and preview.get("view_seq", -1) == _sequence
	board._render_group_cost_preview(board._read_group_preview(), input_available())
	var breakdown: Dictionary = preview.get("power_breakdown", {}) if valid else _mine.get("power_breakdown", {})
	SharedViewSections.render_self_power(board.get_node("Self/Stats"), _mine, breakdown)


func _bind_action_hint(view: Dictionary, actor: Dictionary) -> void:
	var hint: Control = board.get_node("Hint")
	hint.show()
	var area_name: String = ""
	for area in view.get("areas", []):
		for location in area.locations:
			if location.id == actor.get("location", -1):
				area_name = area.name
	var text: String = "对局已结束" if view.game_over else ("轮到你行动" if actor.get("id", -1) == view.observer else actor.get("master", {}).get("name", actor.get("player_name", "")) + " 正在行动")
	if not view.game_over:
		text += " · " + board._phase_cn(view.phase) + "阶段" + (" · " + area_name if not area_name.is_empty() else "")
	board._set_text(hint, "Main", text)
	board._set_text(hint, "Sub", "")
	var pending: Dictionary = session.read_pending()
	if pending.get("kind") == "location_choice":
		preload("res://scripts/game_scene/native_choice_renderer.gd").location(board,pending.label,pending.allow_cancel,board.get_node("NetworkChoices/Panel")._cancel)


func _selection_changed() -> void:
	_hand_dirty = true
	_hand_revision += 1


func _refresh_connection_wait() -> void:
	var waiting:Dictionary = session.read_actions().get("connection_wait", {})
	var panel:Control = board.get_node("NetworkChoices/ConnectionWait")
	var lost:bool = session.has_resume_identity() and not session.transport.is_connected_to_host()
	var management_paused:bool = session.read_actions().get("management_paused",false)
	panel.visible = waiting.get("paused", false) or lost or management_paused
	var message:Label = panel.get_node("Margin/Row/Message")
	message.text = "对局已暂停\n等待重新连接\n" + "、".join(PackedStringArray(waiting.get("names", [])))
	if management_paused:
		message.text = "管理员已暂停对局" + ("\n等待重新连接\n" + "、".join(PackedStringArray(waiting.get("names", []))) if waiting.get("paused",false) else "")
	if lost:
		message.text = "正在重新连接" if session.is_reconnecting() or session.transport.is_connecting() else "与房主连接中断"
		if not session.error.is_empty(): message.text += "\n" + session.error
	var button:Button = panel.get_node("Margin/Row/Reconnect")
	button.visible = lost and session.reconnect_available()
	button.disabled = not session.can_reconnect()
	_refresh_inheritance_targets()

## 原身份与继承者分别选择；这里仅从公开房间视图取原身份标签。
func _refresh_inheritance_targets() -> void:
	var row:Node = board.get_node("NetworkChoices/ConnectionWait/Margin/Row")
	var targets:OptionButton = row.get_node("InheritanceTarget")
	var selected:int = 0
	if targets.selected >= 0:
		selected = int(targets.get_item_metadata(targets.selected))
	targets.clear()
	var panel = board.get_node("IdentityInheritancePanel")
	for member in session.view.get("members", []):
		if panel.can_manage(session, int(member.id)):
			targets.add_item(str(member.name))
			targets.set_item_metadata(targets.item_count - 1, int(member.id))
			if member.id == selected:
				targets.select(targets.item_count - 1)
	targets.visible = targets.item_count > 0
	row.get_node("InheritIdentity").visible = targets.visible
	if targets.visible:
		board.get_node("NetworkChoices/ConnectionWait").show()

func _open_identity_inheritance() -> void:
	var targets:OptionButton = board.get_node("NetworkChoices/ConnectionWait/Margin/Row/InheritanceTarget")
	if targets.selected < 0:
		return
	var target:int = int(targets.get_item_metadata(targets.selected))
	board.get_node("IdentityInheritancePanel").open_for(session, target, targets.get_item_text(targets.selected))

func _inheritance_rejected(_reason:String) -> void:
	board.get_node("IdentityInheritancePanel").request_failed()

## 收包回调只排队，避免在 transport.poll 的遍历内关闭连接。
func _inheritance_ticket_received(_member:int) -> void:
	if _inheritance_switch_pending:
		return
	_inheritance_switch_pending = true
	call_deferred("_disconnect_for_inheritance")

func _disconnect_for_inheritance() -> void:
	if session == null:
		return
	board.get_node("IdentityInheritancePanel").close_panel()
	if session.transport.is_connected_to_host() or session.transport.is_connecting():
		session.transport.close()
	call_deferred("_activate_inheritance_ticket")

func _activate_inheritance_ticket() -> void:
	if session == null:
		return
	_inheritance_switch_pending = false
	if not session.activate_inheritance_ticket():
		session.error = "身份继承凭据尚未可以安全启用"
		_refresh_connection_wait()
		return
	# 同一对局序号可以对应不同 observer 的过滤视图，不能复用观战缓存。
	_sequence = -1
	_mine.clear()
	_hand_dirty = true
	_guard_requested_seq = -1
	_guard_request_sequence = 0
	selection.bind_session(null)
	var result:Error = session.reconnect()
	selection.bind_session(session)
	if result != OK:
		session.error = "身份继承重连失败：" + error_string(result)
	_refresh_connection_wait()

func _reconnect() -> void:
	var result:Error = session.reconnect_after_worker_crash()
	if result != OK: session.error = "无法重新连接：" + error_string(result)
	_refresh_connection_wait()

func _refresh_guard(sequence: int) -> void:
	var guard: Dictionary = session.read_actions().get("guard", {})
	var paused: bool = guard.get("paused", false)
	var allowed: bool = guard.get("can_continue", false)
	var panel: Control = board.get_node("NetworkChoices/Guard")
	panel.visible = paused
	if not paused or not allowed:
		panel.get_node("Margin/Row/RestartChoices").visible = false
	var diagnostic:Dictionary = guard.get("diagnostic", {})
	var message:String = "规则执行已暂停"
	if paused and allowed:
		message = "结算未完成，疑似异常\n玩家：%s\n卡牌：%s\n效果：%s\n跳过会撤销整个效果，重开会重新开始本局。" % [diagnostic.get("player_name", "未归属玩家"), diagnostic.get("card", "无来源卡牌"), diagnostic.get("effect", "未知效果")]
		if not diagnostic.get("can_skip", false):
			message += "\n缺少完整回滚检查点，不能跳过。"
	panel.get_node("Margin/Row/Message").text = message
	panel.get_node("Margin/Row/Waiting").visible = not allowed
	panel.get_node("Margin/Row/Actions").visible = allowed
	panel.get_node("Margin/Row/Actions/Skip").disabled = _guard_requested_seq == sequence or not diagnostic.get("can_skip", false)
	panel.get_node("Margin/Row/Actions/Restart").disabled = _guard_requested_seq == sequence or not diagnostic.get("can_restart", false)
	panel.get_node("Margin/Row/RestartChoices/Current").disabled = _guard_requested_seq == sequence
	panel.get_node("Margin/Row/RestartChoices/Lobby").disabled = _guard_requested_seq == sequence

func _show_restart_choices() -> void:
	board.get_node("NetworkChoices/Guard/Margin/Row/RestartChoices").visible = true

func _cancel_restart_choices() -> void:
	board.get_node("NetworkChoices/Guard/Margin/Row/RestartChoices").visible = false

func _return_guard_lobby() -> void:
	_request_guard_action("guard_lobby")

func _skip_guard() -> void:
	_request_guard_action("guard_skip")

func _restart_guard() -> void:
	_request_guard_action("guard_restart")

func _request_guard_action(action:String) -> void:
	if _guard_requested_seq == _sequence or not session.read_actions().get("guard", {}).get("can_continue", false):
		return
	_guard_request_sequence = 0
	_guard_requested_seq = _sequence
	_refresh_guard(_sequence)
	if session.request(action, {"view_seq": _sequence}, _register_guard_request) != OK:
		_guard_request_sequence = 0
		_guard_requested_seq = -1
		_refresh_guard(_sequence)

func _server_notice(text:String) -> void:
	board._say("服务器通知："+text)

func _register_guard_request(sequence: int) -> void:
	_guard_request_sequence = sequence

func _guard_rejected(sequence: int, _reason: String) -> void:
	if sequence <= 0 or sequence != _guard_request_sequence or _guard_requested_seq != _sequence:
		return
	_guard_request_sequence = 0
	_guard_requested_seq = -1
	_refresh_guard(_sequence)

func release() -> void:
	board.get_node("IdentityInheritancePanel").close_panel()
	if session.rejected.is_connected(_inheritance_rejected):
		session.rejected.disconnect(_inheritance_rejected)
	if session.inheritance_ticket_received.is_connected(_inheritance_ticket_received):
		session.inheritance_ticket_received.disconnect(_inheritance_ticket_received)
	var inherit_button:Button = board.get_node("NetworkChoices/ConnectionWait/Margin/Row/InheritIdentity")
	if inherit_button.pressed.is_connected(_open_identity_inheritance):
		inherit_button.pressed.disconnect(_open_identity_inheritance)

	if session.server_notice_received.is_connected(_server_notice): session.server_notice_received.disconnect(_server_notice)
	var skip:Button = board.get_node("NetworkChoices/Guard/Margin/Row/Actions/Skip")
	var restart:Button = board.get_node("NetworkChoices/Guard/Margin/Row/Actions/Restart")
	if skip.pressed.is_connected(_skip_guard): skip.pressed.disconnect(_skip_guard)
	if restart.pressed.is_connected(_show_restart_choices): restart.pressed.disconnect(_show_restart_choices)
	var choices = board.get_node("NetworkChoices/Guard/Margin/Row/RestartChoices")
	if choices.get_node("Current").pressed.is_connected(_restart_guard): choices.get_node("Current").pressed.disconnect(_restart_guard)
	if choices.get_node("Lobby").pressed.is_connected(_return_guard_lobby): choices.get_node("Lobby").pressed.disconnect(_return_guard_lobby)
	if choices.get_node("Cancel").pressed.is_connected(_cancel_restart_choices): choices.get_node("Cancel").pressed.disconnect(_cancel_restart_choices)
	if session.request_rejected.is_connected(_guard_rejected):
		session.request_rejected.disconnect(_guard_rejected)
	if session.request_rejected.is_connected(_area_rejected):
		session.request_rejected.disconnect(_area_rejected)
	selection.bind_session(null)
	if selection.changed.is_connected(_selection_changed):
		selection.changed.disconnect(_selection_changed)
	board = null
	session = null

func playable_signature() -> String:
	return "%d:%d" % [_sequence, _hand_revision]

func input_available() -> bool:
	var view: Dictionary = session.read_match()
	var browser_open: bool = board.get_node("LogBrowser").visible or board.get_node("CardBrowser").visible or board.get_node("EventDiscardMenu").visible
	return not browser_open and not view.is_empty() and view.observer >= 0 and not view.game_over and session.read_pending().is_empty() and session.match_commands_available() and not board._is_paused()

func is_selected(card: Dictionary) -> bool:
	return selection.snapshot().cards.has(card.id)

func manual_effects_of(card: Dictionary) -> Array:
	var result: Array = []
	for effect in session.read_actions().get("effects", []):
		if card.get("effects", []).has(effect.id):
			result.append(effect)
	return result

func request_effect(effect: Dictionary) -> void:
	board._request_held_effect(effect)

func held_entry(id: int) -> Dictionary:
	for entry in _mine.get("held_cards", []):
		if entry.card.id == id:
			return entry
	return {}

func card_unpublished(card: Dictionary) -> bool:
	return bool(held_entry(card.id).get("unpublished", card.concealed))

func card_input(event: InputEvent, slot: Control, submit_command: Callable = Callable()) -> void:
	if not event is InputEventMouseButton or not event.pressed or not input_available():
		return
	var card: Dictionary = slot.get_meta("card")
	if event.button_index == MOUSE_BUTTON_LEFT:
		if held_entry(card.id).get("played", false):
			board._on_held_effect_pressed(slot)
		elif is_selected(card):
			selection.remove(card.id)
		else:
			selection.add(card.id, card.concealed)
		slot.accept_event()
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		if held_entry(card.id).get("played", false):
			return
		for item in session.read_actions().get("flip_cards", []):
			if item.id == card.id and item.modes.has(not card.concealed):
				if _sequence != int(session.read_match().get("seq", -1)):
					board._say("局面已更新，请重新选择手牌")
					return
				if not submit_command.is_valid():
					board._say("翻面命令能力未绑定，未提交")
					return
				# 调用方显式注入共同入口；锁定、完成回执与代际隔离由该入口持有。
				submit_command.call("set_concealed", {"card": card.id, "concealed": not card.concealed})
				break
		slot.accept_event()

func bind_hand_card(slot: Control, card: Dictionary, unpublished: bool) -> void:
	var frame: Control = slot.get_node("Frame")
	var face: String = card.back_image if card.concealed else card.image
	board._bind_hand_face(frame, face, unpublished)
	var effects := manual_effects_of(card)
	var playable: bool = board._held_card_playable(card)
	board._bind_hand_availability(slot, effects, playable, true, false)
	board.bind_zoom_for_card(slot, card, "", "desc" if held_entry(card.id).get("played", false) else "none")

func _bind_hand() -> void:
	_hand_dirty = false
	var hand: Control = board.get_node("Hand")
	var entries_by_zone: Dictionary = {"hand": [], "master": [], "servant": []}
	var live: Array = []
	var declared: Array = _mine.get("held_cards", [])
	# 仅兼容旧视图夹具；不查本机规则或同名模板补信息。
	if not _mine.has("held_cards"):
		for zone in ["hand_cards", "master_skills", "servant_skills"]:
			for card in _mine.get(zone, []):
				declared.append({"card": card, "group": "hand" if zone == "hand_cards" else ("master" if zone == "master_skills" else "servant"), "label": "手牌" if zone == "hand_cards" else ("御主牌" if zone == "master_skills" else "从者技能")})
	for entry in declared:
		var card: Dictionary = entry.card
		if not card.get("visible", false) or not card.has_all(["kind", "cost", "power", "back_image"]):
			continue
		live.append(card.id)
		entries_by_zone[entry.group].append({"card": card, "kind": entry.label, "count": 1})
	for slot in hand.get_children():
		if not live.has(slot.get_meta("card", {}).get("id")):
			hand.remove_child(slot)
			slot.queue_free()
	hand.visible = not live.is_empty()
	var portrait: Rect2 = board.get_node("Master").get_rect()
	var center: float = portrait.get_center().x
	board._layout_held_group(entries_by_zone.servant, "ZoneCard", board.get_node("Self").get_rect().end.x + board.HELD_GAP, portrait.position.x - board.HELD_GAP, "zone")
	board._layout_held_group(entries_by_zone.master, "ZoneCard", portrait.end.x + board.HELD_GAP, board.get_node("Ops/PlayButton").get_global_rect().position.x - board.HELD_GAP, "zone")
	board._layout_held_group(entries_by_zone.hand, "HandCard", center - portrait.size.x * 0.9, center + portrait.size.x * 0.9, "hand")
	board._update_held_cards(0.0)

func default_area_index() -> int:
	var view: Dictionary = session.read_match()
	for i in view.get("areas", []).size():
		for location in view.areas[i].locations:
			if location.players.has(view.observer):
				return i
	var fallback:int = MapData.areas.find(MapData.magic_workshop)
	return fallback if fallback >= 0 and fallback < view.get("areas", []).size() else -1

func area_input(event: InputEvent, strip: Control) -> void:
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if board._is_progress_blocked(): return
	var area_id: int = strip.get_meta("area_id", 0)
	if board.get_node("NetworkChoices/Panel").choose_area(area_id):
		strip.accept_event()
		return
	if not input_available() or _area_submitted_seq == int(session.read_match().get("seq", -1)): return
	if session.read_actions().get("deploy_areas", []).has(area_id):
		board._pending_tactical_action = {"type": "deploy", "area": area_id, "view_seq": _sequence}
		board._show_tactical_confirm("部署至【%s】" % strip.get_meta("area_name", ""))
		strip.accept_event()
	elif session.read_actions().get("move_areas", []).has(area_id):
		var cost = session.read_actions().get("move_costs", {}).get(str(area_id))
		if cost == null:
			return
		board._pending_tactical_action = {"type": "move", "area": area_id, "view_seq": _sequence}
		board._show_tactical_confirm("移动至【%s】\n魔力消耗 %s" % [strip.get_meta("area_name", ""), cost])
		strip.accept_event()

func confirm_area(action: Dictionary) -> void:
	if action.get("type") not in ["deploy", "move"]:
		return
	var current_seq: int = int(session.read_match().get("seq", -1))
	if current_seq < 0 or action.get("view_seq", -1) != current_seq:
		_invalidate_area_confirmation(current_seq)
		board._say("局面已更新，请重新选择战区并确认")
		return
	if not input_available() or _area_submitted_seq == current_seq:
		return
	var targets: String = "deploy_areas" if action.type == "deploy" else "move_areas"
	if not session.read_actions().get(targets, []).has(action.get("area")):
		return
	_area_submitted_seq = current_seq
	_area_request_sequence = 0
	var result: Error = session.request("match_command", {"view_seq": action.view_seq, "command": action.type, "params": {"area": action.area}}, _register_area_request)
	if result != OK:
		_area_submitted_seq = -1
		_area_request_sequence = 0
		board._say("战区请求未发送：" + error_string(result))
	# OK 仅表示发送；位置、费用与成功展示必须等待权威快照。

func _invalidate_area_confirmation(current_seq: int) -> void:
	var action: Dictionary = board._pending_tactical_action
	if action.get("type") not in ["deploy", "move"] or action.get("view_seq", -1) == current_seq:
		return
	board._pending_tactical_action.clear()
	board._pending_confirm_desc = ""
	board._confirm_alert_mode = false
	board._tactical_confirm.hide()
	board._say("局面已更新，请重新选择战区并确认")

func _register_area_request(sequence: int) -> void:
	_area_request_sequence = sequence

func _area_rejected(sequence: int, reason: String) -> void:
	if sequence <= 0 or sequence != _area_request_sequence:
		return
	_area_request_sequence = 0
	_area_submitted_seq = -1
	board._say("战区请求被拒绝：" + reason)

func played_card_live(slot: Control) -> bool:
	return _mine.get("played_cards", []).any(func(card): return card.id == slot.get_meta("card", {}).get("id"))
