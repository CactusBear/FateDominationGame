extends Node

var board: Control
var failures: Array = []
var checks := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
	print("CHECK ", label, " ", value)

func _ready() -> void:
	call_deferred("run")

func frames(count := 3) -> void:
	for i in range(count):
		await get_tree().process_frame

func point_at(point: Vector2) -> void:
	get_viewport().warp_mouse(point)
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	get_tree().root.push_input(event, true)
	await frames(24)

func click(slot: Control, button := MOUSE_BUTTON_LEFT) -> void:
	var point := slot.get_global_transform() * (Vector2(slot.size.x - 5.0, slot.size.y * 0.5) if slot.has_meta("held_group") else slot.size * 0.5)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = button
		event.pressed = pressed
		get_tree().root.push_input(event, true)
	await frames()

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tests/runtime_reports/held_" + label + ".png")

func run() -> void:
	board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	get_tree().root.add_child(board)
	await frames()
	var id := GameData.player_id
	var pl: Dictionary = GameDataManager.get_player_data(id)
	GameProgress.current_player_id = id
	GameProgress.current_phase_index = 2
	MapData.active_situation = null
	pl.location = null
	pl.magic.set_num(BaseNumber.new(12))
	var original_master = pl.master
	var masters: Array = GameData.player_data_library.values().map(func(data): return data.master)
	for master in masters:
		pl.master = master
		board.refresh_all_ui()
		await frames()
		var image: TextureRect = board.get_node("Master/Frame/Img")
		check(image.texture != null, "master portrait texture " + board._player_name(id))
		check(is_equal_approx(image.texture.get_width() / float(image.texture.get_height()), image.size.x / image.size.y) or absf(image.texture.get_width() / float(image.texture.get_height()) - image.size.x / image.size.y) < 0.01, "master common crop aspect")
		await capture("master_" + str(master.get_instance_id()))
	pl.master = original_master
	for master in masters:
		if not master._other_things.is_empty():
			pl.master = master
			break
	board.refresh_all_ui()
	var title: Control = board.get_node("AreaTitle/Name")
	var strip: Control = board.get_node("Strips").get_child(0)
	for width in [420.0, 900.0, 1450.0]:
		strip.position.x = width * 0.13
		strip.size.x = width
		board._layout_scroll(strip, 1.0)
		await frames()
		check(is_equal_approx(title.get_global_rect().get_center().x, board.get_global_rect().get_center().x), "title screen centered width " + str(width))
	board.refresh_all_ui()
	for slot: Control in board.get_node("Hand").get_children():
		var rest: Vector2 = slot.get_meta("rest_position")
		check(not Rect2(rest, slot.size).intersects(board.get_node("Master").get_rect()), "collapsed card avoids oval")
	check(not board.has_node("HeldFrames"), "red blue frame removed")
	await capture("collapsed")
	GameProgress.current_phase_index = 0
	var temporary_cards: Array = []
	for i in range(30):
		var extra = CloneObject.new().exec(pl.hand_cards.front())
		extra._name = "overflow_%d" % i
		pl.hand_cards.append(extra)
		temporary_cards.append(extra)
	board.refresh_all_ui()
	await frames()
	await capture("overflow_fan")
	for extra in temporary_cards:
		pl.hand_cards.erase(extra)
	GameProgress.current_phase_index = 2
	board.refresh_all_ui()
	await frames()
	if DisplayServer.get_name() != "headless":
		var examples: Dictionary = {}
		for slot: Control in board.get_node("Hand").get_children():
			# 牌上的类别文字已移除：用槽位记录的分组 + 卡来源还原同一套分组语义
			var kind: String = "手牌" if str(slot.get_meta("held_group", "hand")) == "hand" else ""
			if kind == "":
				var slot_card = slot.get_meta("card", null)
				kind = "从者技能" if (slot_card != null and slot_card.get_from() == pl.get("servant")) else "御主牌"
			if not examples.has(kind):
				examples[kind] = slot
		for kind: String in examples:
			var slot: Control = examples[kind]
			await point_at(Vector2(10, 400))
			var rest: Vector2 = slot.get_meta("rest_position")
			if kind == "手牌":
				await point_at(rest + Vector2(slot.size.x * 0.5, board.HELD_VISIBLE_HEIGHT * 0.5))
				check(board._hand_drawer_open > 0.9 and slot.scale.x < 1.1, "whole drawer rises before card pop")
				await point_at(rest + Vector2(slot.size.x - 8.0, -board.HELD_GAP * 2.0))
				check(slot.scale.x > 1.5, "hand pops after entering raised card")
				check(slot.get_global_rect().has_point(board.get_global_mouse_position()), "popped card stays under pointer")
			else:
				await point_at(rest + Vector2(slot.size.x - 5.0, slot.size.y * 0.5))
				check(slot.position.y < rest.y - 10, "side card rises " + kind)
				check(slot.scale.x < 1.1, "side card does not enlarge " + kind)
			var card = slot.get_meta("card")
			var hidden: bool = card._is_concealed
			await click(slot, MOUSE_BUTTON_RIGHT)
			check(card._is_concealed != hidden, "real right click flips " + kind)
			await click(slot, MOUSE_BUTTON_RIGHT)
			await click(slot)
			check(board._selected_cards.has(card), "real left click selects " + kind)
			check(slot.get_node("Selected").visible, "white breathing selection " + kind)
			await capture("hover_" + str(slot.get_instance_id()))
			await click(slot)
		var group := RegularPlay.find_group(id)
		check(not group.is_empty(), "window legal group exists")
		for i in range(group.get("cards", []).size()):
			var card = group.cards[i]
			var slot: Control = board._held_slot(card, "HandCard")
			await point_at(Vector2(10, 400))
			await point_at(slot.get_meta("rest_position") + Vector2(slot.size.x * 0.5, board.HELD_VISIBLE_HEIGHT * 0.5))
			await point_at(slot.get_meta("rest_position") + Vector2(slot.size.x - 8.0, -board.HELD_GAP * 2.0))
			if card._is_concealed != bool(group.hidden[i]):
				await click(slot, MOUSE_BUTTON_RIGHT)
			await click(slot)
		check(board._can_confirm_held_cards(), "window selected group legal")
		await capture("legal_selected")
		for card in group.cards:
			check(board._held_slot(card, "HandCard").get_node("Selected").visible, "window selection white frame visible")
		GameProgress.current_phase_index = 0
		await frames()
		for card in group.cards:
			check(not board._held_slot(card, "HandCard").get_node("Breath").visible, "window phase change removes gold")
		await capture("illegal_selected")
		GameProgress.current_phase_index = 2
		await frames()
		var button: Button = board.get_node("Ops/PlayButton")
		await point_at(button.get_global_rect().get_center())
		await click(button)
		check(RegularPlay.completed(id), "real confirm submits")
		var remaining_left := INF
		var remaining_right := -INF
		for card in pl.hand_cards:
			if not card is BaseHandCard:
				continue
			var held: Control = board._held_slot(card, "HandCard")
			var rest: Vector2 = held.get_meta("rest_position")
			check(held.position.distance_to(rest) < 0.01, "window submit rearranges remaining hand immediately")
			remaining_left = minf(remaining_left, rest.x)
			remaining_right = maxf(remaining_right, rest.x + held.size.x)
		if remaining_left < INF:
			check(absf((remaining_left + remaining_right) * 0.5 - board.get_node("Master").get_rect().get_center().x) < 0.01, "window remaining hand centered")
		for i in range(group.get("cards", []).size()):
			check(group.cards[i]._is_concealed == bool(group.hidden[i]), "submit keeps actual face state")
		await capture("submitted")
		# 第二组通过真实右键暗置；重置回合事实，不改提交规则或费用入口。
		GameLog.reset()
		var concealed_cards: Array = []
		for i in range(RegularPlay.minimum(id)):
			DrawCardFromPlDeckToHand.new().exec(0, id)
		for card in pl.hand_cards:
			if card is BaseAttack and not card._need_extra_play:
				concealed_cards.append(card)
				if concealed_cards.size() == RegularPlay.minimum(id):
					break
		board.refresh_all_ui()
		await frames()
		for card in concealed_cards:
			var slot: Control = board._held_slot(card, "HandCard")
			await point_at(Vector2(10, 400))
			await point_at(slot.get_meta("rest_position") + Vector2(slot.size.x * 0.5, board.HELD_VISIBLE_HEIGHT * 0.5))
			await point_at(slot.get_meta("rest_position") + Vector2(slot.size.x - 8.0, -board.HELD_GAP * 2.0))
			if not card._is_concealed:
				await click(slot, MOUSE_BUTTON_RIGHT)
			await click(slot)
		check(board._can_confirm_held_cards(), "window concealed group legal")
		var magic_before: float = pl.magic.number
		await capture("concealed_selected")
		await point_at(button.get_global_rect().get_center())
		await click(button)
		check(RegularPlay.completed(id), "real concealed confirm submits")
		for card in concealed_cards:
			check(card._is_concealed and pl.played_cards.has(card), "concealed submit keeps card concealed")
		check(pl.magic.number == magic_before, "concealed submit uses engine zero cost")
	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
