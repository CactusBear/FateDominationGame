extends RefCounted

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
	board.get_node("Ops/EndButton").pressed.connect(_end_action)
	board.get_node("NetworkChoices/Guard/Margin/Row/Actions/Skip").pressed.connect(_skip_guard)
	board.get_node("NetworkChoices/Guard/Margin/Row/Actions/Restart").pressed.connect(_show_restart_choices)
	board.get_node("NetworkChoices/Guard/Margin/Row/RestartChoices/Current").pressed.connect(_restart_guard)
	board.get_node("NetworkChoices/Guard/Margin/Row/RestartChoices/Lobby").pressed.connect(_return_guard_lobby)
	board.get_node("NetworkChoices/Guard/Margin/Row/RestartChoices/Cancel").pressed.connect(_cancel_restart_choices)
	board.get_node("NetworkChoices/ConnectionWait/Margin/Row/Reconnect").pressed.connect(_reconnect)
	session.request_rejected.connect(_guard_rejected)
	session.rejected.connect(_inheritance_rejected)
	session.inheritance_ticket_received.connect(_inheritance_ticket_received)
	board.get_node("NetworkChoices/ConnectionWait/Margin/Row/InheritIdentity").pressed.connect(_open_identity_inheritance)
	session.server_notice_received.connect(_server_notice)
	selection.bind_session(session)
	selection.changed.connect(_selection_changed)
	board.get_node("Top/LogButton").pressed.connect(open_log)
	board.get_node("Top/BoardButton").pressed.connect(toggle_scoreboard)
	var out_button: Button = board._opponent_drawer.get_node("VBox/BtnOutOfGame")
	if out_button.pressed.is_connected(board._on_drawer_out_of_game_pressed):
		out_button.pressed.disconnect(board._on_drawer_out_of_game_pressed)
	out_button.pressed.connect(open_out_of_game)
	board.get_node("Piles/EventPile/Open").pressed.connect(open_event_discard)
	board.get_node("Ops/Discard").gui_input.connect(discard_input)
	for child in board.get_node("Ops/Discard").find_children("*", "Control", true, false):
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE

func open_log() -> void:
	var lines: Array = session.read_match().get("public_log", []).duplicate()
	lines.reverse()
	var entries: RichTextLabel = board.get_node("LogBrowser/Panel/Entries")
	entries.bbcode_enabled = false
	entries.text = "══ 公共对局日志 ══\n\n" + "\n\n".join(PackedStringArray(lines))
	entries.scroll_to_line(0)
	board.get_node("LogBrowser").show()
	board._raise_modal(board.get_node("LogBrowser"))

func open_event_discard() -> void:
	board._show_card_browser("公共事件弃牌", session.read_match().get("event_discard", []))

func discard_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		board._show_card_browser("我方弃牌", _mine.get("discard", []))
		board.get_node("Ops/Discard").accept_event()

func toggle_scoreboard() -> void:
	var panel: Control = board.get_node("Board")
	panel.visible = not panel.visible
	if not panel.visible:
		return
	var players: Array = session.read_match().get("players", []).duplicate()
	players.sort_custom(func(a, b): return a.score > b.score)
	var rows: Control = panel.get_node("Rows")
	board._clear(rows)
	var row_height: float = 0.0
	for i in players.size():
		var player: Dictionary = players[i]
		var row: Control = board._spawn("BoardRow", rows)
		row_height = row.custom_minimum_size.y
		board._set_text(row, "Rank", str(i + 1))
		board._bind_avatar(row.get_node("Avatar"), player.avatar)
		board._set_text(row, "Name", player.master.get("name", player.player_name))
		board._set_text(row, "Class", player.servant_class)
		board._set_text(row, "Score", BaseNumber.display_text(player.score))
	panel.size.y = 52.0 + players.size() * row_height

func browse_input(event: InputEvent) -> bool:
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
		if event.button_index == MOUSE_BUTTON_LEFT and not drawer.get_global_rect().has_point(event.position):
			var hovered: Control = board.get_viewport().gui_get_hovered_control()
			while hovered != null:
				if hovered.has_meta("turn_order_player_id"):
					return false
				hovered = hovered.get_parent_control()
			board._on_close_opponent_drawer_pressed()
			board.get_viewport().set_input_as_handled()
			return true
	return false

func open_out_of_game() -> void:
	for player in session.read_match().get("players", []):
		if player.id == board._selected_opponent_id:
			var button: Button = board._opponent_drawer.get_node("VBox/BtnOutOfGame")
			board._show_card_browser(str(button.get_meta("base_text", button.text)), player.get("out_of_game_cards", []))
			return

## 数值只来自权威声明的构成；缺字段不从本机规则补齐。
func power_lines(player: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var breakdown: Dictionary = player.get("power_breakdown", {})
	for item in [["power", "出牌威力"], ["bonus", "合计威力加成"], ["board", "场上牌加成"], ["location_benefit", "地利"], ["preview", "待确认出牌"], ["total", "合计"]]:
		if not breakdown.has(item[0]):
			continue
		var value = breakdown[item[0]]
		if value == 0 and item[0] not in ["power", "total"]:
			continue
		result.append("%s %s%s" % [item[1], "+" if value > 0 and item[0] not in ["power", "total"] else "", BaseNumber.display_text(value)])
	return result

func _bind_buffs(row: Control, buffs: Array) -> void:
	var list: Control = row.get_node("Scroll/Buffs")
	board._clear(list)
	for buff in buffs:
		var entry: Control = board._spawn("BuffRow", list)
		board._set_variation(entry, "BuffActive" if buff.active else "BuffInactive")
		var avatar: Control = entry.get_node("H/Avatar")
		var image: String = buff.card.get("image", "")
		avatar.visible = not image.is_empty() and LoadHelper.texture_exists(image)
		if avatar.visible:
			board._bind_avatar(avatar, image)
		board.bind_zoom_for_card(entry, buff.card, "", "desc")
		board._set_text(entry, "H/Name", buff.card.get("name", ""))
		entry.get_node("H/Inactive").visible = not buff.active
	row.visible = not buffs.is_empty()
	var title: Control = row.get_node("Title")
	row.get_node("Scroll").custom_minimum_size.y = minf(list.get_combined_minimum_size().y, maxf(0.0, board._drawer_row_share(board._drawer_rows()) - title.get_combined_minimum_size().y - row.get_theme_constant("separation"))) if row.visible else 0.0

func update_drawer(opponent: Control = null) -> void:
	var pid: int = int(opponent.get_meta("turn_order_player_id", -1)) if is_instance_valid(opponent) else board._selected_opponent_id
	var player: Dictionary = {}
	var view: Dictionary = session.read_match()
	for item in view.get("players", []):
		if item.id == pid:
			player = item
	if player.is_empty():
		board._on_close_opponent_drawer_pressed()
		return
	var drawer: Control = board._opponent_drawer
	board._set_img(drawer, "VBox/HeaderBar/SelectedAvatarFrame/Avatar", player.avatar)
	board._set_text(drawer, "VBox/HeaderBar/OrderBadge", "%s · %s\n战果 %s" % [player.master.get("name", player.player_name), player.servant_class, BaseNumber.display_text(player.score)])
	var hint: Label = drawer.get_node("VBox/IdentityHint")
	hint.text = "真名已解放" if player.get("servant_released", false) else "真名未解放"
	hint.theme_type_variation = "Gold2" if player.get("servant_released", false) else "Dim2"
	board._set_text(drawer, "VBox/ResourceVisuals/MagicH/Magic", "魔力 " + BaseNumber.display_text(player.magic))
	board._set_text(drawer, "VBox/ResourceVisuals/CommandSpells", "令咒 ×" + BaseNumber.display_text(player.command_spell_count))
	board._set_text(drawer, "VBox/ResourceVisuals/Power", "合计威力 " + BaseNumber.display_text(player.total_power))
	var area_name: String = "未部署"
	for area in view.get("areas", []):
		for loc in area.locations:
			if loc.id == player.location:
				area_name = area.name
	board._set_text(drawer, "VBox/ResourceVisuals/BattleMarker", area_name + (" · 交战" if player.is_battle else ""))
	var rows: Array = board._drawer_rows()
	var size: Vector2 = board._drawer_card_size(rows[0])
	var identities: Control = rows[0].get_node("Scroll/CardsH")
	for key in ["master", "servant"]:
		var slot: TextureRect = identities.get_node("MasterCard" if key == "master" else "ServantCard")
		slot.custom_minimum_size = size
		slot.visible = not player[key].is_empty()
		if slot.visible:
			slot.texture = LoadHelper.load_texture(player[key].get("image", ""))
			board.bind_zoom_for_card(slot, player[key])
		else:
			slot.texture = null
			board._disable_card_zoom(slot)
	rows[0].visible = identities.get_node("MasterCard").visible or identities.get_node("ServantCard").visible
	var sources: Array = player.get("master_skills", []).duplicate()
	sources.append_array(player.get("servant_skills", []))
	for entry in player.get("held_cards", []):
		if entry.group != "hand" and not entry.played and not sources.any(func(card): return card.get("id") == entry.card.id):
			sources.append(entry.card)
	for i in [1, 2]:
		var cards: Array = player.played_cards if i == 1 else sources
		rows[i].visible = not cards.is_empty()
		board._fill_card_row_from_list(board._drawer_row_cards(rows[i]), cards, false, player.own, false, size)
	board._set_text(rows[1], "Title", "%s 已打出牌 · 威力 %s" % [area_name, BaseNumber.display_text(player.total_power)])
	_bind_buffs(rows[3], player.get("buffs", []))
	drawer.get_node("VBox/Sections/Row_CommandSpells").hide()
	var out_button: Button = drawer.get_node("VBox/BtnOutOfGame")
	if not out_button.has_meta("base_text"):
		out_button.set_meta("base_text", out_button.text)
	var removed: Array = player.get("out_of_game_cards", [])
	out_button.visible = not removed.is_empty()
	out_button.text = "%s ×%d" % [str(out_button.get_meta("base_text")), removed.size()]
	drawer.get_node("VBox/ResourceVisuals/Power").tooltip_text = "\n".join(power_lines(player))
	for row in rows:
		board._bind_drawer_row_remeasure(row)
	board._queue_drawer_remeasure(null)

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

func refresh() -> void:
	_refresh_group_reveal()
	var view: Dictionary = session.read_match()
	_refresh_guard(view.get("seq", -1))
	_refresh_connection_wait()
	board.get_node("IdentityInheritancePanel").refresh_context()
	board.get_node("NetworkChoices/Panel").refresh_submission_availability()
	board.get_node("Ops/EndButton").disabled = not input_available() or not session.read_actions().get("can_end", false)
	board.get_node("Top/LogButton").disabled = view.is_empty()
	board.get_node("Top/BoardButton").disabled = view.is_empty()
	board.get_node("Piles").visible = not view.is_empty()
	board.get_node("Piles/SituationPile").hide()
	if view.is_empty():
		board._on_close_opponent_drawer_pressed()
		board.get_node("CardBrowser").hide()
		board.get_node("LogBrowser").hide()
		board.get_node("Board").hide()
		return
	if view.seq == _sequence:
		if _hand_dirty:
			_bind_hand()
		return
	_sequence = view.seq
	board.get_node("Top/Center/RoundLabel").text = "第 %d 回合" % view.round
	board.get_node("Top/Center/NightLabel").text = "对局结束" if view.game_over else ("公共观战" if view.observer < 0 else "联机对局")
	var phases: Control = board.get_node("Top/Center/Phases")
	board._clear(phases)
	var tag: Control = board._spawn("PhaseOn", phases)
	board._set_text(tag, "Label", board._phase_cn(view.phase) + "阶段")
	var mine: Dictionary = {}
	var actor: Dictionary = {}
	var ranked: Array = view.players.duplicate()
	ranked.sort_custom(func(a, b): return a.score > b.score)
	for player in view.players:
		if player.id == view.observer:
			mine = player
		if player.id == view.current_player:
			actor = player
	board.get_node("Banner/Text").text = "对局结束" if view.game_over else ("%s 的行动" % actor.get("master", {}).get("name", actor.get("player_name", "")))
	board.get_node("Banner/Avatar").visible = not actor.is_empty()
	board._bind_avatar(board.get_node("Banner/Avatar"), actor.get("avatar", ""))
	_bind_rivals(view)
	_mine = mine
	if board._opponent_drawer.visible:
		update_drawer()
	board._set_text(board.get_node("Piles/EventPile"), "Count/Label", str(view.get("event_discard", []).size()))
	board._local_player_id = int(view.observer)
	_bind_areas(view)
	board._fly_armed = true
	_bind_situation(view.get("situation", {}))
	if mine.is_empty():
		board.get_node("Self").hide()
		board.get_node("Master").hide()
		_bind_hand()
		return
	board.get_node("Self").show()
	var stats: Control = board.get_node("Self/Stats")
	board._set_text(stats, "ScoreRow/Score", BaseNumber.display_text(mine.score))
	var rank := 1
	for player in ranked:
		if player.score > mine.score:
			rank += 1
	board._set_text(stats, "ScoreRow/Rank", "名次 %d" % rank)
	stats.get_node("MagicSigil").set_value(mine.magic, mine.magic_limit)
	stats.get_node("PowerRow").show()
	board._set_text(stats, "PowerRow/Power", BaseNumber.display_text(mine.total_power))
	var lines: Array[String] = power_lines(mine)
	stats.get_node("PowerRow/BreakScroll").visible = not lines.is_empty()
	board._set_text(stats, "PowerRow/BreakScroll/Break", "\n".join(lines))
	stats.get_node("PowerRow/Power").tooltip_text = "\n".join(lines)
	var servant: Control = board.get_node("Self/ServantCard")
	servant.visible = not mine.servant.is_empty()
	if servant.visible:
		board._bind_card(servant, mine.servant.get("image", ""))
		board.bind_zoom_for_card(servant, mine.servant)
		board._set_text(servant, "Class", mine.servant_class)
		servant.get_node("HiddenTag").hide()
	board.get_node("Master").visible = not mine.master.is_empty()
	board._set_img(board.get_node("Master"), "Frame/Img", mine.master.get("image", ""))
	board.bind_zoom_for_card(board.get_node("Master/Frame/Img"), mine.master)
	board._set_text(board.get_node("Master"), "Name", mine.master.get("name", ""))
	board._set_text(board.get_node("Ops"), "Deck/Count/Label", str(mine.deck_count))
	board._set_text(board.get_node("Ops"), "Discard/Count/Label", str(mine.discard.size()))
	_bind_spells()
	_bind_hand()

func _bind_situation(card: Dictionary) -> void:
	var box: Control = board.get_node("Situation")
	box.show()
	var slot: Control = box.get_node("SituCard")
	slot.visible = not card.is_empty()
	box.get_node("Empty").visible = card.is_empty()
	if not card.is_empty():
		board._bind_card(slot, card.get("image", "") if card.get("visible", false) and not card.get("concealed", true) else card.get("back_image", ""))
		board.bind_zoom_for_card(slot, card)
	else:
		board._disable_card_zoom(slot)

func _bind_rivals(view: Dictionary) -> void:
	var row: HBoxContainer = board.get_node("Rivals")
	row.show()
	board._breathing.clear()
	board._clear(row)
	# players 来自主机真实顺位，不根据 ID 重排。
	for index in view.players.size():
		var player: Dictionary = view.players[index]
		var own: bool = player.id == view.observer
		var card: Control = board._spawn("SelfSlot" if own else "RivalCard", row)
		card.set_meta("turn_order_player_id", player.id)
		card.set_meta("self_slot", own)
		board._set_text(card, "Order/Label", str(index + 1))
		board._set_acting_highlight(card, player.id == view.current_player and not view.game_over)
		if own:
			continue
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		for child in card.find_children("*", "Control", true, false):
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.gui_input.connect(board._on_opponent_gui_input.bind(card))
		board._bind_avatar(card.get_node("Avatar"), player.avatar)
		board._set_text(card, "Name", player.master.get("name", player.player_name))
		board._set_text(card, "Class", player.servant_class)
		var area_name := ""
		for area in view.areas:
			for location in area.locations:
				if location.id == player.location:
					area_name = area.name
		board._set_text(card, "Loc", area_name)
		card.get_node("MagicSigil").set_value(player.magic, player.magic_limit)
		board._set_text(card, "Stats/PowerStat/V", BaseNumber.display_text(player.total_power))
		card.get_node("Stats/PowerStat/V").tooltip_text = "\n".join(power_lines(player))
		board._set_text(card, "Stats/ScoreStat/V", BaseNumber.display_text(player.score))
		var spells: Control = card.get_node("Stats/Spells")
		board._clear(spells)
		var count: Control = board._spawn("SpellSummary", spells)
		count.tooltip_text = "令咒"
		board._set_text(count, "Count", "×%s" % BaseNumber.display_text(player.command_spell_count))

func _selection_changed() -> void:
	_hand_dirty = true
	_hand_revision += 1

func _end_action() -> void:
	if not input_available() or not session.read_actions().get("can_end", false):
		return
	board.get_node("Ops/EndButton").disabled = true
	session.request("match_command", {"view_seq": _sequence, "command": "end_action", "params": {}})

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
	var out_button: Button = board._opponent_drawer.get_node("VBox/BtnOutOfGame")
	if out_button.pressed.is_connected(open_out_of_game):
		out_button.pressed.disconnect(open_out_of_game)
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
	selection.bind_session(null)
	if selection.changed.is_connected(_selection_changed):
		selection.changed.disconnect(_selection_changed)
	board = null
	session = null

func playable_signature() -> String:
	return "%d:%d" % [_sequence, _hand_revision]

func input_available() -> bool:
	var view: Dictionary = session.read_match()
	return not view.is_empty() and view.observer >= 0 and not view.game_over and session.read_pending().is_empty() and session.match_commands_available() and not board._is_paused()

func is_selected(card: Dictionary) -> bool:
	return selection.snapshot().cards.has(card.id)

func card_playable(card: Dictionary) -> bool:
	return is_selected(card) or not selection.modes_for(card.id).is_empty()

func manual_effects_of(card: Dictionary) -> Array:
	var result: Array = []
	for effect in session.read_actions().get("effects", []):
		if card.get("effects", []).has(effect.id):
			result.append(effect)
	return result

func request_effect(effect: Dictionary) -> void:
	if not input_available():
		return
	for available in session.read_actions().get("effects", []):
		if available.id == effect.id:
			session.request("match_command", {"view_seq": _sequence, "command": "activate", "params": {"effect": effect.id}})
			return

func held_entry(id: int) -> Dictionary:
	for entry in _mine.get("held_cards", []):
		if entry.card.id == id:
			return entry
	return {}

func card_unpublished(card: Dictionary) -> bool:
	return bool(held_entry(card.id).get("unpublished", card.concealed))

func card_input(event: InputEvent, slot: Control) -> void:
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
				session.request("match_command", {"view_seq": _sequence, "command": "set_concealed", "params": {"card": card.id, "concealed": not card.concealed}})
				break
		slot.accept_event()

func bind_hand_card(slot: Control, card: Dictionary, unpublished: bool) -> void:
	var frame: Control = slot.get_node("Frame")
	var face: String = card.back_image if card.concealed else card.image
	board._bind_hand_face(frame, face, unpublished)
	var effects := manual_effects_of(card)
	var usable := card_playable(card) or not effects.is_empty()
	board._bind_hand_availability(slot, effects, usable, true, false)
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
	return -1

func area_input(event: InputEvent, strip: Control) -> void:
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if not input_available() or board._is_progress_blocked():
		return
	var area_id: int = strip.get_meta("area_id", 0)
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
	if action.get("type") not in ["deploy", "move"] or not input_available():
		return
	var targets: String = "deploy_areas" if action.type == "deploy" else "move_areas"
	if not session.read_actions().get(targets, []).has(action.get("area")):
		return
	session.request("match_command", {"view_seq": action.view_seq, "command": action.type, "params": {"area": action.area}})

func _bind_areas(view: Dictionary) -> void:
	var strips: Control = board._strips
	board._sync_items(board.get_node("Background"), "AreaBackdrop", view.areas.size())
	board._sync_items(strips, "Strip", view.areas.size())
	for i in view.areas.size():
		var area: Dictionary = view.areas[i]
		var strip: Control = strips.get_child(i)
		if not strip.has_node("Main"):
			var content: Control = board._main.duplicate()
			strip.add_child(content)
			content.show()
			board._clear(content.get_node("Groups/List"))
			strip.move_child(content, 2)
			var seats: Control = board._seats.duplicate()
			strip.add_child(seats)
			seats.position = Vector2.ZERO
			seats.show()
			for row_name in ["MeleeScroll", "SeatScroll"]:
				var sc: ScrollContainer = seats.get_node(row_name)
				sc.gui_input.connect(board._on_hscroll_wheel.bind(sc))
			strip.gui_input.connect(board._on_strip_gui_input.bind(strip))
			strip.position = board._scroll_target(i).position
			strip.size = board._scroll_target(i).size
		strip.set_meta("area_id", area.id)
		strip.set_meta("area_name", area.name)
		strip.set_meta("location_count", area.locations.size())
		board._set_text(strip, "Main/Name", area.name)
		board._set_text(strip, "Main/Latin", str(board.AREA_LATIN.get(area.name, "")))
		board._set_text(strip, "Col/Vertical", "\n".join(Array(area.name.split(""))))
		board._set_text(strip, "Col/Latin", str(board.AREA_LATIN.get(area.name, "")).left(6))
		strip.get_node("Background").hide()
		strip.get_node("Score").hide()
		var flow: Control = strip.get_node("FlowBorder")
		flow.visible = session.read_actions().get("deploy_areas", []).has(area.id) or session.read_actions().get("move_areas", []).has(area.id)
		board._bind_flow_border(flow)
		_bind_area_seats(strip, area, view)
		_bind_area_groups(strip, area, view)
		var events: Control = strip.get_node("EventIcons")
		board._bind_area_event_cards(events, area.events)
		board._layout_scroll(strip, float(strip.get_meta("open", 0.0)))

func _bind_area_seats(strip: Control, area: Dictionary, view: Dictionary) -> void:
	var fixed: Array = []
	var melee: Array = []
	for location in area.locations:
		if not location.has("capacity"):
			continue
		if location.capacity >= 0:
			fixed.append(location)
		else:
			for pid in location.players:
				melee.append({"id": pid, "location": location})
	var row: Control = strip.get_node("Seats/SeatScroll/Row")
	board._sync_items(row, "SeatSlot", fixed.size())
	strip.get_node("Seats/SeatScroll").visible = not fixed.is_empty()
	for i in fixed.size():
		var location: Dictionary = fixed[i]
		var slot: Control = row.get_child(i)
		var seat: Control = slot.get_node("Seat")
		slot.set_meta("compact", Vector2(13, 148 + area.locations.find(location) * 64))
		seat.get_node("Ring").mana = location.magic > 0
		for node_name in ["ValueNum", "ValueEmpty", "Avatar", "Badge"]:
			seat.get_node(node_name).hide()
		board._set_text(seat, "Label", "魔力席" if location.magic > 0 else ("地利 %s" % BaseNumber.display_text(location.benefit) if location.benefit > 0 else "席位"))
		if location.players.is_empty():
			var value: Label = seat.get_node("ValueNum")
			value.text = "+%s" % BaseNumber.display_text(location.magic) if location.magic > 0 else BaseNumber.display_text(location.benefit)
			value.theme_type_variation = "Mana" if location.magic > 0 else "Gold2"
			value.visible = location.magic > 0 or location.benefit > 0
			seat.get_node("ValueEmpty").visible = not value.visible
		else:
			_bind_seat_avatar(seat.get_node("Avatar"), location.players[0], view)
			if location.magic > 0 or location.benefit > 0:
				board._bind_badge(seat.get_node("Badge"), "+%s" % BaseNumber.display_text(location.magic) if location.magic > 0 else BaseNumber.display_text(location.benefit), "BadgeMana" if location.magic > 0 else "BadgeGold")
	row = strip.get_node("Seats/MeleeScroll/Row")
	board._sync_items(row, "MeleeSeat", melee.size())
	strip.get_node("Seats/MeleeScroll").visible = not melee.is_empty()
	for i in melee.size():
		var entry: Dictionary = melee[i]
		var slot: Control = row.get_child(i)
		_bind_seat_avatar(slot.get_node("Avatar"), entry.id, view)
		board._set_text(slot, "Label", "混战区")
		var offset: int = entry.location.players.find(entry.id)
		slot.set_meta("compact", Vector2(4 + (offset % 3) * 22, 148 + area.locations.find(entry.location) * 64 + (offset / 3) * 24))

func _bind_seat_avatar(avatar: Control, pid: int, view: Dictionary) -> void:
	avatar.show()
	for player in view.players:
		if player.id == pid:
			board._bind_avatar(avatar, player.avatar, "AvatarMana" if pid == view.observer else "AvatarGold2")
			return

func _bind_area_groups(strip: Control, area: Dictionary, view: Dictionary) -> void:
	var region: Control = strip.get_node("Main/Groups/List")
	var live: Array = []
	var occupants: Array = []
	for location in area.locations:
		occupants.append_array(location.players)
	for player in view.players:
		if not occupants.has(player.id) or player.played_cards.is_empty():
			continue
		var key := "Player_%d" % player.id
		live.append(key)
		var group: Control = region.get_node_or_null(key)
		if group == null:
			group = board._spawn("PlayGroup", region)
			group.name = key
			group.set_meta("player_id", player.id)
			group.modulate.a = 0.0
			var who: Control = group.get_node("Who")
			who.mouse_filter = Control.MOUSE_FILTER_STOP
			who.gui_input.connect(board._on_play_group_toggle.bind(group))
			who.get_node("Avatar/CollapseHint").gui_input.connect(board._on_play_group_toggle.bind(group))
		board._bind_avatar(group.get_node("Who/Avatar"), player.avatar, "AvatarMana" if player.id == view.observer else "AvatarGold3")
		board._set_text(group, "Who/Total/Text", BaseNumber.display_text(player.total_power))
		group.get_node("Who/Avatar/CollapseHint").visible = group.get_meta("expanded", false)
		board._bind_played_cards_row(group.get_node("Cards/Row"), player.played_cards, player.id, true)
	for group in region.get_children():
		if not live.has(str(group.name)):
			region.remove_child(group)
			group.queue_free()


func played_card_live(slot: Control) -> bool:
	return _mine.get("played_cards", []).any(func(card): return card.id == slot.get_meta("card", {}).get("id"))

func _bind_spells() -> void:
	var spells: Array = _mine.get("command_spells", [])
	var box: Control = board.get_node("Self/Spells")
	box.visible = not spells.is_empty()
	board.get_node("Self/CountBadge").visible = not spells.is_empty()
	board._set_text(board.get_node("Self"), "CountBadge/Label", BaseNumber.display_text(_mine.command_spell_count))
	if spells.is_empty():
		return
	_bind_spell_slot(box.get_node("SpellCard"), spells[0])
	var row: Control = box.get_node("SpecialScroll/Cards")
	board._sync_items(row, "SpellCard", spells.size() - 1)
	for i in row.get_child_count():
		_bind_spell_slot(row.get_child(i), spells[i + 1])
	box.get_node("SpecialScroll").visible = row.get_child_count() > 0

func _bind_spell_slot(slot: Control, card: Dictionary) -> void:
	slot.set_meta("card", card)
	board._bind_card(slot, card.get("image", ""))
	board.bind_zoom_for_card(slot, card)
	slot.modulate = Color.WHITE if not manual_effects_of(card).is_empty() else Color(0.55, 0.55, 0.55)
	if not slot.has_meta("network_spell_bound"):
		slot.set_meta("network_spell_bound", true)
		for child in slot.find_children("*", "Control", true, false):
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		board._bind_effect_button(slot)
		slot.gui_input.connect(board._on_local_special_spell_input.bind(slot))
