extends Node

var failures: Array[String] = []
var checks := 0
var samples: Array = []

func check(ok: bool, label: String) -> void:
	checks += 1
	print("CHECK ", label, " ", ok)
	if not ok:
		failures.append(label)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	get_tree().root.add_child(board)
	await get_tree().process_frame
	board.set_process(false)
	check(board._main_area_index == MapData.areas.find(MapData.magic_workshop), "undeployed player defaults to magic workshop")
	var background: TextureRect = board.get_node("Background")
	var initial_background: TextureRect = background.get_child(board._main_area_index)
	check(background.texture == null and initial_background.texture == LoadHelper.load_texture(board._area_image(board._main_area_index)), "area background replaces original screen texture")
	await get_tree().create_timer(board.SCROLL_SECONDS + 0.05).timeout
	check(initial_background.get_global_rect().is_equal_approx(board.get_global_rect()) and initial_background.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_COVERED, "area background covers entire screen without stretching")
	board._select_scroll(-1)
	check(is_equal_approx(initial_background.modulate.a, 1.0), "closing all scrolls retains area background")
	await get_tree().create_timer(board.SCROLL_SECONDS + 0.05).timeout
	check(board.get_node("Strips").get_child_count() == MapData.areas.size(), "one persistent scroll per area")
	var first: Node = board.get_node("Strips").get_child(0)
	board.refresh_all_ui()
	check(is_instance_valid(first) and first.get_parent() == board.get_node("Strips"), "refresh preserves scroll identity")
	var strips: Control = board.get_node("Strips")
	check(first.has_node("Seats/SeatScroll/Row"), "scroll reuses two seat rows")
	if not first.has_node("Seats/SeatScroll/Row"):
		print("RESULT checks=", checks, " failures=", failures)
		get_tree().quit(1)
		return
	var icon: Control = first.get_node("Seats/SeatScroll/Row").get_child(0)
	var compact_icon := icon.global_position
	var initial: Rect2 = first.get_rect()
	await screenshot("closed")
	hover(board, initial.get_center())
	check(board._main_area_index == 0, "mouse motion opens hovered scroll")
	var first_background: TextureRect = background.get_child(0)
	check(first_background.texture == first.get_node("Background").texture, "fullscreen background matches hovered scroll")
	check(first.get_rect().is_equal_approx(initial), "input does not teleport scroll")
	await sample_frames(board, 12, "opening")

	check(first.size.x > initial.size.x and first.size.x < board._scroll_target(0).size.x, "opening has intermediate width")
	check(first.position.x < initial.position.x and first.get_rect().end.x > initial.end.x, "scroll opens on both sides of original strip")
	check(icon.global_position.distance_to(compact_icon) > 1, "same icon moves with scroll")
	await screenshot("opening")
	var before_refresh: Rect2 = first.get_rect()
	board.refresh_all_ui()
	check(first.get_rect().is_equal_approx(before_refresh) and icon == first.get_node("Seats/SeatScroll/Row").get_child(0), "refresh preserves geometry and icon identity mid-animation")
	await sample_frames(board, 24, "opened")
	await screenshot("opened")
	check(first.get_rect().is_equal_approx(board._scroll_target(0)), "opening reaches target")
	check(first_background.get_rect().is_equal_approx(Rect2(Vector2.ZERO, board.size)) and is_equal_approx(first_background.modulate.a, 1.0), "background expansion reaches full screen")
	check(is_zero_approx(first.get_node("Background").modulate.a), "expanded scroll does not duplicate fullscreen image")
	var seat_sc: ScrollContainer = first.get_node("Seats/SeatScroll")
	var melee_sc: ScrollContainer = first.get_node("Seats/MeleeScroll")
	check(first.get_global_rect().encloses(seat_sc.get_global_rect()), "expanded seats stay inside their scroll")
	check(is_equal_approx(melee_sc.size.x, 5 * board.SEAT_SCROLL_STEP - 12), "upper row displays five players")
	check(melee_sc.global_position.y < seat_sc.global_position.y, "unseated players are in the upper row")
	check(melee_sc.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_SHOW_NEVER, "upper row hides scrollbar")
	var last: Control = strips.get_child(strips.get_child_count() - 1)
	check(is_equal_approx(last.get_rect().end.x, board.size.x - board.SCROLL_MARGIN), "remaining maps line up at screen edge")
	var before_switch: Rect2 = first.get_rect()
	hover(board, last.get_rect().get_center())
	check(is_equal_approx(first_background.modulate.a, 1.0), "switching does not instantly replace fullscreen background")
	check(first.get_rect().is_equal_approx(before_switch), "switch begins from current geometry")
	await sample_frames(board, 12, "switching")
	var last_background: TextureRect = background.get_child(last.get_index())
	check(last_background.modulate.a > 0.0 and last_background.modulate.a < 1.0 and last_background.size.x < board.size.x, "background expands and fades through intermediate frames")
	check(first_background.modulate.a > 0.0 and first_background.modulate.a < 1.0, "previous background fades out smoothly")
	check(first.size.x < before_switch.size.x and first.size.x > initial.size.x, "previous map rolls up progressively")
	await screenshot("switching")
	var interrupted: Rect2 = first.get_rect()
	var interrupted_background := first_background.get_rect()
	var interrupted_alpha := first_background.modulate.a
	hover(board, first.get_rect().get_center())
	check(first_background.get_rect().is_equal_approx(interrupted_background) and is_equal_approx(first_background.modulate.a, interrupted_alpha), "rapid background reversal preserves geometry and opacity")
	check(first.get_rect().is_equal_approx(interrupted), "rapid reversal has no jump")
	await sample_frames(board, 32, "reversed")
	var area: BaseMapArea = MapData.areas[0]
	var saved_events := area._events.duplicate()
	var saved_score = area._score.number
	area._events.clear()
	for i in range(3):
		area._events.append(CloneObject.new().exec(LoadEvent.events[0]))
	board.refresh_all_ui()
	for openness in [0.0, 0.5, 1.0]:
		board._layout_scroll(first, openness)
		var cards := first.get_node("EventIcons").get_children()
		# 树序按"最左在最上"重排过，不能再用下标代表左右；按位置取左右两张。
		var by_x := cards.duplicate()
		by_x.sort_custom(func(a, b): return (a as Control).position.x < (b as Control).position.x)
		for i in range(1, by_x.size()):
			check((by_x[i - 1] as Control).z_index > (by_x[i] as Control).z_index, "left event draws above right at " + str(openness))
			check((by_x[i - 1] as Control).position.x < (by_x[i] as Control).position.x and (by_x[i - 1] as Control).position.y < (by_x[i] as Control).position.y, "right event offsets down at " + str(openness))
		# 命中按子树逆序测试：最后一张子节点必须就是画在最上面的那张，否则悬浮会命中被压住的牌
		check(cards[cards.size() - 1] == by_x[0], "topmost drawn event is tested first for input at " + str(openness))
		if is_equal_approx(openness, 1.0):
			# 事件牌堆（含 3.5 倍缩放与贴图阴影）不许压到混战区：量真实四角矩形
			var lowest := -INF
			for card in cards:
				lowest = maxf(lowest, global_box(card as Control).end.y)
			var melee := first.get_node("Seats/MeleeScroll") as Control
			var gap: float = melee.get_global_rect().position.y - lowest
			check(gap >= board.EVENT_STACK_GAP - 0.5, "event stack keeps clear of the melee row (gap %.1f)" % gap)
	check(first.get_theme_stylebox("panel").bg_color.a <= 0.6, "scroll base lets background show through")
	check(first.get_node("Background").modulate.a <= 0.25, "map image remains subtle")
	check(first.get_node("CapTop").get_theme_stylebox("panel").bg_color.a <= 0.6, "scroll edges are translucent")
	check(is_equal_approx(first.modulate.a, 1.0) and is_equal_approx(first.get_node("EventIcons").get_child(0).modulate.a, 1.0), "foreground cards keep full opacity")
	# 事件堆默认上缘只留 EVENT_STACK_TOP 的留白，紧贴战区上边缘
	board._layout_scroll(first, 1.0)
	# 取整堆最靠上那张的位置（树序已被重排，不能按 child 下标当序号）
	var three_top := stack_top(first.get_node("EventIcons"))
	check(is_equal_approx(three_top, board.EVENT_STACK_TOP), "small stack keeps the default top margin (%.1f)" % three_top)
	area._events.clear()
	# 回推只在牌堆会压到混战区时才触发：堆高超过可用高度才把起点顶上去
	for i in range(20):
		area._events.append(CloneObject.new().exec(LoadEvent.events[0]))
	board.refresh_all_ui()
	board._layout_scroll(first, 1.0)
	var many_top := stack_top(first.get_node("EventIcons"))
	check(many_top < three_top, "a stack tall enough to hit the melee row is pushed up (three=%.1f many=%.1f)" % [three_top, many_top])
	var many_lowest := -INF
	for card in first.get_node("EventIcons").get_children():
		many_lowest = maxf(many_lowest, global_box(card as Control).end.y)
	var many_gap: float = (first.get_node("Seats/MeleeScroll") as Control).get_global_rect().position.y - many_lowest
	check(many_gap >= board.EVENT_STACK_GAP - 0.5, "pushed-up stack still keeps clear of the melee row (gap %.1f)" % many_gap)
	area._events.clear()
	for i in range(3):
		area._events.append(CloneObject.new().exec(LoadEvent.events[0]))
	board.refresh_all_ui()
	board._layout_scroll(first, 1.0)
	await screenshot("event_stack")
	area._events.clear()
	area._score.number = 0
	board.refresh_all_ui()
	check(not first.get_node("EventIcons").visible and first.get_node("EventIcons").get_child_count() == 0, "empty events have no card or placeholder when open")
	check(not first.get_node("Score").visible, "zero score has no badge or title when open")
	await screenshot("empty_open")
	board._select_scroll(-1)
	await sample_frames(board, 32, "closing")
	check(first.get_rect().is_equal_approx(initial), "closing returns to original strip")
	check(icon.global_position.is_equal_approx(compact_icon), "same icon returns to original position")
	check(not first.get_node("EventIcons").visible and not first.get_node("Score").visible, "empty events and score stay hidden when closed")
	await screenshot("empty_closed")
	area._events.assign(saved_events)
	area._score.number = saved_score
	board.refresh_all_ui()
	check(first.get_node("EventIcons").visible == not saved_events.is_empty(), "event visibility restores from data")
	check(first.get_node("Score").visible == (board._area_score(area) != 0), "score visibility restores from data")
	# 窗口模式检验真实输入派发和离开后的自动回卷，不手动调用收起函数。
	if DisplayServer.get_name() != "headless":
		hover(board, initial.get_center())
		await sample_frames(board, 32, "window_input")
		hover(board, Vector2(5, 5))
		board.set_process(true)
		await get_tree().create_timer(board.SCROLL_LEAVE_SECONDS + board.SCROLL_SECONDS + 0.15).timeout
		board.set_process(false)
		check(board._main_area_index == MapData.areas.find(MapData.magic_workshop) and is_equal_approx(float(first.get_meta("open")), 1.0), "pointer leave restores default workshop in window mode")
	MapData.active_situation = null
	var unlimited: BaseLocation = MapData.miyama._locations.filter(func(loc): return loc._pl_num_limit < 0)[0]
	for pid in GameData.player_data_library.keys():
		SetLocation.new().exec(unlimited, int(pid), false)
	board.refresh_all_ui()
	var own_index: int = MapData.areas.find(board._player_area(GameData.player_id))
	check(own_index >= 0 and board._default_area_index() == own_index, "deployed player defaults to their own battlefield")
	board._select_scroll(own_index)
	await sample_frames(board, 32, "deployed")
	var own_scroll: Control = strips.get_child(own_index)
	var upper: ScrollContainer = own_scroll.get_node("Seats/MeleeScroll")
	check(upper.get_node("Row").get_child_count() > 5, "fixture has more than five unseated players")
	check(upper.get_node("Row").size.x > upper.size.x and not upper.get_h_scroll_bar().visible, "overflow row is scrollable without scrollbar")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	upper.gui_input.emit(wheel)
	await get_tree().process_frame
	check(upper.scroll_horizontal > 0, "wheel scrolls upper player row")
	var saved_scroll := upper.scroll_horizontal
	board.refresh_all_ui()
	await get_tree().process_frame
	check(upper.scroll_horizontal == saved_scroll, "refresh preserves upper row scroll offset")
	check(own_scroll.get_global_rect().encloses(upper.get_global_rect()), "upper row stays inside its scroll")
	for i in range(strips.get_child_count()):
		if i != own_index:
			check(not (strips.get_child(i) as Control).get_global_rect().intersects(upper.get_global_rect()), "upper row does not cover another strip")
	await screenshot("deployed_rows")
	if DisplayServer.get_name() != "headless":
		hover(board, first.get_rect().get_center())
		await sample_frames(board, 32, "hover_other")
		hover(board, Vector2(5, 5))
		board.set_process(true)
		await get_tree().create_timer(board.SCROLL_LEAVE_SECONDS + board.SCROLL_SECONDS + 0.2).timeout
		board.set_process(false)
		check(board._main_area_index == own_index, "pointer leave restores deployed battlefield")
	var f := FileAccess.open("res://tests/runtime_reports/battle_scroll_samples.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(samples))
	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func hover(board: Control, point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = Vector2(1, 0)
	if DisplayServer.get_name() == "headless":
		board._input(event)
	else:
		get_viewport().warp_mouse(point)
		get_viewport().push_input(event, true)

func sample_frames(board: Control, count: int, phase: String) -> void:
	var valid := true
	for frame in range(count):
		await get_tree().process_frame
		var right := 0.0
		var rects: Array = []
		for strip: Control in board.get_node("Strips").get_children():
			var rect := strip.get_rect()
			valid = valid and rect.position.x >= right and rect.end.x <= board.size.x
			right = rect.end.x
			rects.append([rect.position.x, rect.size.x, float(strip.get_meta("open"))])
		samples.append({"phase": phase, "frame": frame, "rects": rects})
	check(valid, phase + " all frames ordered, in bounds and non-overlapping")

func screenshot(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var path := "res://tests/runtime_reports/battle_scroll_" + label + ".png"
	check(get_viewport().get_texture().get_image().save_png(path) == OK, "screenshot " + label)


## 含缩放/旋转的真实全局矩形（Control.get_global_rect 不含 scale，量事件牌堆必须用它）
func global_box(c: Control) -> Rect2:
	var t := c.get_global_transform()
	var r := Rect2(t * Vector2.ZERO, Vector2.ZERO)
	for corner in [Vector2(c.size.x, 0.0), c.size, Vector2(0.0, c.size.y)]:
		r = r.expand(t * corner)
	return r


## 事件牌堆最靠上那张的 y（树序按“最左在最上”重排过，不能用 child 下标当序号）
func stack_top(icons: Node) -> float:
	var top := INF
	for card in icons.get_children():
		top = minf(top, (card as Control).position.y)
	return top
