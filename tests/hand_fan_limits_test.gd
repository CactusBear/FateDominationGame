extends "res://tests/hand_fan_arc_test.gd"

func bounds(slot: Control) -> Rect2:
	var transform := slot.get_global_transform()
	var result := Rect2(transform * Vector2.ZERO, Vector2.ZERO)
	for corner in [Vector2(slot.size.x, 0), slot.size, Vector2(0, slot.size.y)]:
		result = result.expand(transform * corner)
	return result

func point_at(point: Vector2) -> void:
	get_viewport().warp_mouse(point)
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	get_viewport().push_input(event, true)

func run() -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP window pointer and rendered fan bounds require window renderer")
		print("RESULT checks=0 failures=[]")
		get_tree().quit()
		return
	board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	add_child(board)
	board.set_process(false)
	await get_tree().process_frame
	var pl: Dictionary = GameDataManager.get_player_data(GameData.player_id)
	var model = pl.hand_cards.front()
	for unique in [false, true]:
		for count in [30, 60, 120]:
			point_at(Vector2(10, 400))
			pl.hand_cards.clear()
			for i in range(count):
				var card = CloneObject.new().exec(model)
				if unique:
					card._name = "fan_limit_%d" % i
				pl.hand_cards.append(card)
			board.refresh_all_ui()
			await settle()
			var slots := hand_slots()
			check(slots.size() == count, "all cards preserved %d unique=%s" % [count, unique])
			var collapsed_out := 0
			for slot: Control in slots:
				var box := bounds(slot)
				if box.position.x < -0.5 or box.end.x > board.size.x + 0.5:
					collapsed_out += 1
			check(collapsed_out == 0, "collapsed horizontal bounds %d unique=%s" % [count, unique])
			point_at(Vector2(board.size.x * 0.5, board.size.y - 12))
			await settle()
			# 以真实旋转后的四角检查，不能用忽略旋转的 get_global_rect。
			check(board._hand_drawer_open > 0.99, "drawer fully opens")
			var expanded_out := 0
			for slot: Control in slots:
				if not Rect2(Vector2.ZERO, board.size).grow(0.5).encloses(bounds(slot)):
					expanded_out += 1
			check(expanded_out == 0, "expanded rotated bounds %d unique=%s outside=%d" % [count, unique, expanded_out])
	var top: Control = hand_slots().front()
	point_at(top.get_global_transform() * Vector2(top.size.x * 0.5, 30.0))
	await settle()
	check(top.scale.x > 1.5, "extreme fan card can still pop")
	check(Rect2(Vector2.ZERO, board.size).grow(0.5).encloses(bounds(top)), "popped rotated card stays in viewport")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tests/runtime_reports/hand_fan_120.png")
	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
