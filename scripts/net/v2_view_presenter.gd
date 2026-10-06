extends RefCounted

## 仅消费会话过滤视图；不得查询 GameData、EffectManager 或执行规则。
var board: Control
var session
var _sequence: int = -1
var selection = preload("res://scripts/net/group_selection.gd").new()
var _hand_dirty: bool = true
var _hand_revision: int = 0
var _mine: Dictionary = {}
var _guard_requested_seq: int = -1

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
	board.get_node("Ops/PlayButton").pressed.connect(selection.confirm)
	board.get_node("Ops/EndButton").pressed.connect(_end_action)
	board.get_node("NetworkChoices/Guard/Margin/Row/Actions/Skip").pressed.connect(_skip_guard)
	board.get_node("NetworkChoices/Guard/Margin/Row/Actions/Restart").pressed.connect(_show_restart_choices)
	board.get_node("NetworkChoices/Guard/Margin/Row/RestartChoices/Current").pressed.connect(_restart_guard)
	board.get_node("NetworkChoices/Guard/Margin/Row/RestartChoices/Lobby").pressed.connect(_return_guard_lobby)
	board.get_node("NetworkChoices/Guard/Margin/Row/RestartChoices/Cancel").pressed.connect(_cancel_restart_choices)
	session.rejected.connect(_guard_rejected)
	selection.bind_session(session)
	selection.changed.connect(_selection_changed)

func refresh() -> void:
	var view: Dictionary = session.read_match()
	_refresh_guard(view.get("seq", -1))
	if view.is_empty():
		return
	if view.seq == _sequence:
		if _hand_dirty:
			_bind_hand()
		return
	_sequence = view.seq
	board.get_node("Ops/EndButton").disabled = not session.read_actions().get("can_end", false)
	board.get_node("Top/Center/RoundLabel").text = "第 %d 回合" % view.round
	board.get_node("Top/Center/NightLabel").text = "对局结束" if view.game_over else "联机对局"
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
	board._local_player_id = int(view.observer)
	_bind_areas(view)
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
	stats.get_node("MagicSigil").set_value(int(mine.magic), int(mine.magic_limit))
	stats.get_node("PowerRow").show()
	board._set_text(stats, "PowerRow/Power", BaseNumber.display_text(mine.total_power))
	stats.get_node("PowerRow/BreakScroll").hide()
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
		board._bind_avatar(card.get_node("Avatar"), player.avatar)
		board._set_text(card, "Name", player.master.get("name", player.player_name))
		board._set_text(card, "Class", player.servant_class)
		var area_name := ""
		for area in view.areas:
			for location in area.locations:
				if location.id == player.location:
					area_name = area.name
		board._set_text(card, "Loc", area_name)
		card.get_node("MagicSigil").set_value(int(player.magic), int(player.magic_limit))
		board._set_text(card, "Stats/PowerStat/V", BaseNumber.display_text(player.total_power))
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
	if not session.read_actions().get("can_end", false):
		return
	board.get_node("Ops/EndButton").disabled = true
	session.request("match_command", {"view_seq": _sequence, "command": "end_action", "params": {}})

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
	_guard_requested_seq = _sequence
	_refresh_guard(_sequence)
	if session.request(action, {"view_seq": _sequence}) != OK:
		_guard_rejected("")

func _guard_rejected(_reason: String) -> void:
	_guard_requested_seq = -1
	_refresh_guard(_sequence)

func release() -> void:
	var skip:Button = board.get_node("NetworkChoices/Guard/Margin/Row/Actions/Skip")
	var restart:Button = board.get_node("NetworkChoices/Guard/Margin/Row/Actions/Restart")
	if skip.pressed.is_connected(_skip_guard): skip.pressed.disconnect(_skip_guard)
	if restart.pressed.is_connected(_show_restart_choices): restart.pressed.disconnect(_show_restart_choices)
	var choices = board.get_node("NetworkChoices/Guard/Margin/Row/RestartChoices")
	if choices.get_node("Current").pressed.is_connected(_restart_guard): choices.get_node("Current").pressed.disconnect(_restart_guard)
	if choices.get_node("Lobby").pressed.is_connected(_return_guard_lobby): choices.get_node("Lobby").pressed.disconnect(_return_guard_lobby)
	if choices.get_node("Cancel").pressed.is_connected(_cancel_restart_choices): choices.get_node("Cancel").pressed.disconnect(_cancel_restart_choices)
	if session.rejected.is_connected(_guard_rejected):
		session.rejected.disconnect(_guard_rejected)
	selection.bind_session(null)
	if selection.changed.is_connected(_selection_changed):
		selection.changed.disconnect(_selection_changed)
	board = null
	session = null

func playable_signature() -> String:
	return "%d:%d" % [_sequence, _hand_revision]

func input_available() -> bool:
	var view: Dictionary = session.read_match()
	return not view.is_empty() and view.observer >= 0 and not view.game_over and session.read_pending().is_empty() and not session.read_actions().get("guard", {}).get("paused", false)

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

func card_unpublished(card: Dictionary) -> bool:
	return bool(card.concealed) or (card.kind == "skill" and not _mine.get("servant_released", false))

func card_input(event: InputEvent, slot: Control) -> void:
	if not event is InputEventMouseButton or not event.pressed or not input_available():
		return
	var card: Dictionary = slot.get_meta("card")
	if event.button_index == MOUSE_BUTTON_LEFT:
		if is_selected(card):
			selection.remove(card.id)
		else:
			selection.add(card.id, card.concealed)
		slot.accept_event()
	elif event.button_index == MOUSE_BUTTON_RIGHT:
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
	board.bind_zoom_for_card(slot, card, "", "none")

func _bind_hand() -> void:
	_hand_dirty = false
	var hand: Control = board.get_node("Hand")
	var entries_by_zone: Dictionary = {"hand_cards": [], "master_skills": [], "servant_skills": []}
	var live: Array = []
	for zone in entries_by_zone:
		for card in _mine.get(zone, []):
			if not card.get("visible", false) or not card.has_all(["kind", "cost", "power", "back_image"]):
				continue
			live.append(card.id)
			entries_by_zone[zone].append({"card": card, "kind": "从者技能" if zone == "servant_skills" else ("御主技能" if zone == "master_skills" else "手牌"), "count": 1})
	for slot in hand.get_children():
		if not live.has(slot.get_meta("card", {}).get("id")):
			hand.remove_child(slot)
			slot.queue_free()
	hand.visible = not live.is_empty()
	var portrait: Rect2 = board.get_node("Master").get_rect()
	var center: float = portrait.get_center().x
	board._layout_held_group(entries_by_zone.servant_skills, "ZoneCard", board.get_node("Self").get_rect().end.x + board.HELD_GAP, portrait.position.x - board.HELD_GAP, "zone")
	board._layout_held_group(entries_by_zone.master_skills, "ZoneCard", portrait.end.x + board.HELD_GAP, board.get_node("Ops/PlayButton").get_global_rect().position.x - board.HELD_GAP, "zone")
	board._layout_held_group(entries_by_zone.hand_cards, "HandCard", center - portrait.size.x * 0.9, center + portrait.size.x * 0.9, "hand")
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
			group.set_meta("shown", true)
			var who: Control = group.get_node("Who")
			who.mouse_filter = Control.MOUSE_FILTER_STOP
			who.gui_input.connect(board._on_play_group_toggle.bind(group))
			who.get_node("Avatar/CollapseHint").gui_input.connect(board._on_play_group_toggle.bind(group))
		group.modulate.a = 1.0
		board._bind_avatar(group.get_node("Who/Avatar"), player.avatar, "AvatarMana" if player.id == view.observer else "AvatarGold3")
		board._set_text(group, "Who/Total/Text", BaseNumber.display_text(player.total_power))
		group.get_node("Who/Avatar/CollapseHint").visible = group.get_meta("expanded", false)
		board._bind_played_cards_row(group.get_node("Cards/Row"), player.played_cards, player.id)
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
