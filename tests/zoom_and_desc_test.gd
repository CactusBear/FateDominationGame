extends Node

## 放大卡图 + 右键说明：悬浮放大、卡图右键说明、展示位右键语义（翻面优先）、牌面不带文字
var board: Control
var checks := 0
var failures: Array[String] = []

func _ready() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
	print("CHECK ", label, " ", ok)


## 看门狗：任何一处取值出错导致协程中止时也能拿到结果，而不是整场挂住
func _watchdog() -> void:
	await get_tree().create_timer(45.0).timeout
	print("RESULT checks=", checks, " failures=", failures + ["watchdog timeout"])
	get_tree().quit(1)

func frames(count := 3) -> void:
	for i in range(count):
		await get_tree().process_frame
		if is_instance_valid(board):
			# 冻结规则推进但继续实际 UI 动画；出牌组的可见性与布局由此生产回调更新。
			board._update_power_badges()
			board._update_fly_sizes(1.0 / 60.0)
			board._update_event_fan(1.0 / 60.0, board.get_global_mouse_position())
			board._update_held_cards(1.0 / 60.0)
			board._update_hover_zoom_keepalive(1.0 / 60.0)

func point_at(point: Vector2, hold_frames := 40) -> void:
	get_viewport().warp_mouse(point)
	var ev := InputEventMouseMotion.new()
	ev.position = point
	ev.global_position = point
	get_tree().root.push_input(ev, true)
	await frames(hold_frames)

func click_at(point: Vector2, button := MOUSE_BUTTON_RIGHT) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.position = point
		ev.global_position = point
		ev.button_index = button
		ev.pressed = pressed
		get_tree().root.push_input(ev, true)
	await frames(3)

func hand_slots() -> Array:
	var slots: Array = board.get_node("Hand").get_children().filter(func(s): return s.get_meta("held_group", "") == "hand")
	slots.sort_custom(func(a, b): return (a.get_meta("rest_position") as Vector2).x < (b.get_meta("rest_position") as Vector2).x)
	return slots

func zone_slots() -> Array:
	return board.get_node("Hand").get_children().filter(func(s): return s.get_meta("held_group", "") == "zone")

func run() -> void:
	_watchdog()
	board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	get_tree().root.add_child(board)
	board.set_process(false)
	await frames(6)
	check(board._hover_zoom != null and board._hover_desc != null, "zoom panels exist")
	var hand: Array = hand_slots()
	check(not hand.is_empty(), "hand cards present")
	if hand.is_empty():
		finish()
		return
	var slot: Control = hand.front()
	var frame := slot.get_node("Frame") as Control
	for gone in ["CapBg", "Name", "Attr"]:
		check(frame.get_node_or_null(gone) == null, "card face carries no text node " + gone)
	check(slot.has_meta("zoom_desc"), "held card declares description")
	check(slot.get_meta("zoom_right_action", "") == "none", "held card keeps right click for conceal")
	check(frame.mouse_filter == Control.MOUSE_FILTER_IGNORE, "card face stays mouse transparent")
	check(not board.get_node("Background").has_meta("zoom_bound"), "background excluded")
	for target in [board.get_node("Self/ServantCard"), board.get_node("Master/Frame/Img")]:
		check(target.has_meta("zoom_bound"), "static card bound " + target.name)
	check(board.get_node("Self/Spells/SpellCard").has_meta("zoom_bound"), "local complete command-spell card declares preview")
	for rival in board._rivals.get_children():
		if rival.has_node("Stats/Spells"):
			check(not rival.get_node("Stats/Spells").get_child(0).has_meta("zoom_bound"), "rival decorative icon remains excluded from card preview")
	var unknown = CloneObject.new().exec(slot.get_meta("card"))
	unknown._zoom_kind = ""
	unknown._zoom_kinds.clear()
	board.bind_zoom_for_card(slot, unknown)
	check(slot.get_meta("zoom_disabled", false) and not slot.has_meta("zoom_img"), "undeclared kind clears stale preview")
	board.refresh_all_ui()
	if DisplayServer.get_name() == "headless":
		# headless 不派发 GUI 命中测试，只能直接验证放大与说明入口本身可用
		board._show_zoom_for(slot)
		check(board._hover_zoom.visible and board._hover_zoom_source == slot, "headless verifies preview entry")
		check(board._show_desc_for(slot), "shared description builder available")
		finish()
		return

	# 悬浮放大：鼠标落在卡位可见区域
	await point_at(Vector2(5, 400))
	check(not board._hover_zoom.visible, "zoom hidden when pointer leaves")
	var point := slot.get_global_transform() * Vector2(slot.size.x * 0.5, 8.0)
	await point_at(point, 8)
	check(not board._hover_zoom.visible, "brief hover does not enlarge")
	await point_at(Vector2(5, 400))
	check(not board._hover_zoom.visible, "leaving cancels pending preview")
	await point_at(slot.get_global_transform() * Vector2(slot.size.x * 0.5, 8.0))
	check(board._hover_zoom.visible, "hover shows enlarged card after delay")
	var hint := board._hover_zoom.get_node_or_null("Hint") as Control
	var hint_icon := hint.get_node_or_null("Icon") as TextureRect
	var hint_cap := hint.get_node_or_null("DefaultHint") as Label
	check(hint != null and hint.visible and hint_icon != null and hint_icon.texture != null, "enlarged card shows the right-click icon hint")
	# 固定小字挂在图标左侧，且自身不画背景
	check(hint_cap != null and hint_cap.text == "右键大图查看文字说明", "icon carries the fixed right-click caption")
	check(hint_cap != null and not hint_cap.has_theme_stylebox_override("normal"), "fixed caption draws no background")
	var zoom_rect: Rect2 = board._hover_zoom.get_global_rect()
	# 图标中心必须落在放大卡图的右上顶点上（固定小字只向左扩展，不带偏图标）
	var corner := Vector2(zoom_rect.end.x, zoom_rect.position.y)
	var icon_center: Vector2 = hint_icon.get_global_rect().get_center()
	check(icon_center.distance_to(corner) <= 2.0, "icon hint centres on the top-right corner (%.1f)" % icon_center.distance_to(corner))
	check(hint_cap != null and hint_cap.get_global_rect().end.x <= hint_icon.get_global_rect().position.x + 1.0, "fixed caption sits left of the icon")
	# 小字整行都在放大卡图的顶边以上，不压在卡面上
	check(hint_cap != null and hint_cap.get_global_rect().end.y <= zoom_rect.position.y + 0.5, "fixed caption stays above the enlarged card")
	check(hint_icon.size.x >= 36.0, "icon hint is large enough to read")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tests/runtime_reports/zoom_hint_corner.png")
	check(board._hover_zoom.get_node("BigCard").texture != null, "enlarged card carries its art")

	# 移到放大卡图上仍保持显示，并在卡图上右键调出说明
	var zoom_point: Vector2 = board._hover_zoom.get_global_rect().get_center()
	await point_at(zoom_point)
	check(board._hover_zoom.visible, "zoom stays while pointer is over it")
	check(hint_icon != null and hint_icon.texture != null and hint.visible, "icon hint persists on the enlarged card")
	check(hint_cap.visible and hint_cap.text == "右键大图查看文字说明", "fixed caption persists on the enlarged card")
	check(not (hint.get_node("Text") as Label).visible, "declared hint text stays hidden when the slot declares none")
	await click_at(zoom_point)
	check(board._hover_desc.visible, "right click on enlarged card opens description")
	check(board._hover_desc.get_node("VBox/Title").text != "", "description has a title")
	var desc_text: String = board._hover_desc.get_node("VBox/Body/Desc").text
	check(desc_text.contains("魔力消耗"), "description lists magic cost")
	check(not desc_text.contains("效果："), "description keeps effect lines without prefix")
	check(not board._hover_desc.get_global_rect().intersects(board._hover_zoom.get_global_rect()), "description does not cover preview")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tests/runtime_reports/zoom_desc.png")
	await click_at(zoom_point)
	check(not board._hover_desc.visible, "second right click closes description")
	await click_at(zoom_point)
	check(board._hover_desc.visible, "third right click reopens description")
	# 指针停在说明面板上算仍在看这张牌：放大图与说明都保持，可以滚动阅读
	await point_at(board._hover_desc.get_global_rect().get_center())
	check(board._hover_desc.visible and board._hover_zoom.visible, "description and preview stay while pointer reads the panel")
	await click_at(board._hover_desc.get_node("Close").get_global_rect().get_center(), MOUSE_BUTTON_LEFT)
	check(not board._hover_desc.visible, "description closes with close button")
	# 说明与放大图共生：指针离开源卡、放大图与说明面板后，两者一起收起
	await point_at(Vector2(5, 400))
	await point_at(slot.get_global_transform() * Vector2(slot.size.x * 0.5, 8.0))
	check(board._hover_zoom.visible, "hover reopens the preview")
	var zoom_point2: Vector2 = board._hover_zoom.get_global_rect().get_center()
	await point_at(zoom_point2)
	await click_at(zoom_point2)
	check(board._hover_desc.visible and board._hover_zoom.visible, "description reopens on the preview")
	await point_at(Vector2(5, 400))
	check(not board._hover_desc.visible and not board._hover_zoom.visible, "description disappears together with the preview")

	# 手牌右键仍是明置/暗置，不弹说明
	var card = slot.get_meta("card")
	var concealed_before: bool = card._is_concealed
	await point_at(slot.get_global_transform() * Vector2(slot.size.x * 0.5, 8.0))
	await click_at(slot.get_global_transform() * Vector2(slot.size.x * 0.5, 8.0))
	check(card._is_concealed != concealed_before, "held card right click still flips")
	check(not board._hover_desc.visible, "held card right click does not open description")

	# 真正的地图出牌区：先部署并展开，不能因找不到槽位跳过测试。
	await point_at(Vector2(5, 400))
	var pl: Dictionary = board._pl(board._local_player_id)
	var area: BaseMapArea = MapData.miyama
	var loc: BaseLocation = area._locations.filter(func(l): return l._pl_num_limit < 0)[0]
	SetLocation.new().exec(loc, board._local_player_id, false)
	var played = CloneObject.new().exec(card)
	played._is_concealed = false
	pl.played_cards.append(played)
	board._select_scroll(MapData.areas.find(area))
	board.refresh_all_ui()
	await frames(70)
	board.refresh_all_ui()
	await frames(70)
	var played_slot: Control
	for grp in board._play_group_nodes():
		for child in grp.get_node("Cards/Row").get_children():
			if child.get_meta("card") == played:
				played_slot = child
	check(played_slot != null, "real battlefield played slot exists")
	if played_slot == null:
		finish()
		return
	await verify_target(played_slot, "played")
	await verify_target(board.get_node("Self/ServantCard"), "servant")
	await verify_target(board.get_node("Master/Frame/Img"), "master")
	var spell: Control = board.get_node("Self/Spells").get_child(0)
	board.refresh_all_ui()
	check(board.get_node("Self/Spells").get_child(0) == spell, "refresh preserves the complete local command-spell card")
	board._hide_event_zoom(true)
	await point_at(spell.get_global_rect().get_center(), 50)
	check(board._hover_zoom.visible, "real hover enlarges the complete local command-spell card")
	if MapData.active_situation != null:
		await verify_target(board._situation.get_node("SituCard"), "situation")
	while area._events.size() < 2:
		area._events.append(CloneObject.new().exec(LoadEvent.events.front()))
	area._events.front()._is_concealed = false
	board.refresh_all_ui()
	await frames(10)
	var events: Node = board._strips.get_child(MapData.areas.find(area)).get_node("EventIcons")
	check(events.get_child_count() > 0, "actual event fixture exists")
	if events.get_child_count() > 0:
		var event_source: Control = events.get_children().filter(func(n): return n.get_meta("event_index", -1) == 0)[0]
		await verify_target(event_source, "event")
		area._events.front()._is_concealed = true
		board.refresh_all_ui()
		check(event_source.get_meta("zoom_disabled", false) and not event_source.has_meta("zoom_desc"), "hidden event clears private art and text")
		check(not board._show_desc_for(event_source), "hidden event refuses description")
		area._events.front()._is_concealed = false
		board.refresh_all_ui()
	var zones := zone_slots()
	zones.sort_custom(func(a, b): return (a.get_meta("rest_position") as Vector2).x < (b.get_meta("rest_position") as Vector2).x)
	check(not zones.is_empty(), "fixture has zone cards")
	if not zones.is_empty():
		await verify_target(zones.front(), "zone")
	board._show_card_browser("事件弃牌", [area._events.front()])
	await frames(5)
	check(board._hover_zoom.z_index > board.get_node("CardBrowser").z_index, "preview draws above card browser backdrop")
	await verify_target(board.get_node("CardBrowser/Panel/CardScroll/Row").get_child(0), "card browser")
	board.get_node("CardBrowser").hide()
	board._close_card_desc()
	played_slot.set_meta("zoom_desc", "测试说明\n".repeat(80))
	board._show_desc_for(played_slot)
	# 指针停在说明面板上（保活冻结）再检查长说明：面板不会在阅读途中被收走
	await point_at(board._hover_desc.get_global_rect().get_center(), 6)
	var body := board._hover_desc.get_node("VBox/Body") as ScrollContainer
	check(board._hover_desc.visible, "long description stays while pointer rests on the panel")
	check(body.get_v_scroll_bar().max_value > body.size.y, "long description can scroll")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	get_tree().root.push_input(esc, true)
	check(not board._hover_desc.visible, "Escape closes description")
	await point_at(Vector2(5, 400))
	await point_at(played_slot.get_global_transform() * (played_slot.size * 0.5))
	check(board._hover_zoom.visible, "preview active before removal")
	pl.played_cards.erase(played)
	board.refresh_all_ui()
	await frames(4)
	check(not board._hover_zoom.visible, "freed source safely clears preview")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tests/runtime_reports/zoom_clean_hand.png")
	finish()

func verify_target(target: Control, label: String) -> void:
	board._close_card_desc()
	await point_at(Vector2(5, 400))
	await frames(45)
	await point_at(target.get_global_transform() * (target.size * 0.5))
	check(board._hover_zoom.visible and board._hover_zoom_source == target, label + " real hover previews exact source")
	if not board._hover_zoom.visible:
		return
	var pt: Vector2 = board._hover_zoom.get_global_rect().get_center()
	await point_at(pt)
	await click_at(pt)
	check(board._hover_desc.visible, label + " preview right-click description")
	check(board._hover_desc.get_node("VBox/Title").text == target.get_meta("zoom_title", ""), label + " description matches")
	board._close_card_desc()


func finish() -> void:
	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
