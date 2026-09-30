extends Node
var failures: Array[String] = []
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	print("CHECK ", label, " ", ok)
	if not ok:
		failures.append(label)

func _ready() -> void:
	call_deferred("run")

func press(button: Button) -> void:
	if DisplayServer.get_name() == "headless":
		button.pressed.emit()
	else:
		var point := button.get_global_rect().get_center()
		for down in [true, false]:
			var event := InputEventMouseButton.new()
			event.position = point
			event.global_position = point
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = down
			get_viewport().push_input(event, true)
	await get_tree().process_frame

func run() -> void:
	var board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	get_tree().root.add_child(board)
	board.set_process(false)
	await get_tree().process_frame
	check(board.has_node("Piles/EventPile/Open"), "event discard entrance exists")
	if not board.has_node("Piles/EventPile/Open"):
		finish()
		return
	EventResolver.new().clear_all()
	MapData.event_discard.clear()
	var cards: Array = []
	for area in [MapData.shinto, MapData.miyama, MapData.scout]:
		var event: BaseEvent = CloneObject.new().exec(LoadEvent.events[0])
		AddMapAreaEvents.new().exec(area, event)
		cards.append(event)
	EventResolver.new().clear_all()
	await press(board.get_node("Piles/EventPile/Open"))
	check(board.get_node("EventDiscardMenu").visible, "entrance opens second-level menu")
	for key in ["Shinto", "Miyama", "Other"]:
		check(board.get_node("EventDiscardMenu/Choices/" + key).visible, "category exists " + key)
	var keys := ["Shinto", "Miyama", "Other"]
	for i in range(keys.size()):
		if not board.get_node("EventDiscardMenu").visible:
			await press(board.get_node("Piles/EventPile/Open"))
		await press(board.get_node("EventDiscardMenu/Choices/" + keys[i]))
		var browser: Control = board.get_node("CardBrowser")
		var row: Node = browser.get_node("Panel/CardScroll/Row")
		check(browser.visible and not board.get_node("EventDiscardMenu").visible, "category opens browser " + keys[i])
		check(row.get_child_count() == 1 and row.get_child(0).get_meta("card") == cards[i], "category filters source identity " + keys[i])
		await press(browser.get_node("Panel/Close"))
		check(not browser.visible, "browser close " + keys[i])
	MapData.event_discard.erase(cards[0])
	await press(board.get_node("Piles/EventPile/Open"))
	await press(board.get_node("EventDiscardMenu/Choices/Shinto"))
	check(board.get_node("CardBrowser/Panel/CardScroll/Row").get_child_count() == 0 and board.get_node("CardBrowser/Panel/Empty").visible, "reopening reads current discard data and shows empty state")
	check(MapData.event_discard.size() == 2, "browser never modifies discard data")
	for i in range(MapData.areas.size()):
		var scroll: Control = board.get_node("Strips").get_child(i)
		var bg: TextureRect = scroll.get_node("Background")
		# 使用原始动漫素材，不通过插值放大满足虚假的高清阈值。
		check(bg.texture != null and bg.texture.get_width() >= 1024 and bg.texture.get_height() >= 600, "native-size anime background " + str(i))
		check(bg.modulate.a > 0 and bg.modulate.a < 1, "translucent background " + str(i))
	if DisplayServer.get_name() != "headless":
		await press(board.get_node("CardBrowser/Panel/Close"))
		await press(board.get_node("Piles/EventPile/Open"))
		await press(board.get_node("EventDiscardMenu/Choices/Miyama"))
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		check(get_viewport().get_texture().get_image().save_png("res://tests/runtime_reports/battle_event_discard.png") == OK, "browser screenshot saved")
	finish()

func finish() -> void:
	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
