extends Node

## 临时探针：打印换人金框覆盖层的实际样式，确认它是不是"透明边框"还是"整卡填充"。

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	get_tree().root.add_child(board)
	await get_tree().process_frame
	await get_tree().process_frame
	var rules: Array = board._ordered_ids()
	print("=== rules=", rules)
	GameProgress.current_player_id = int(rules[1])
	board.refresh_all_ui()
	await get_tree().process_frame
	await get_tree().process_frame
	var ov: Panel = board._gold_frame_node
	if ov == null:
		print("=== overlay NULL")
	else:
		print("=== overlay visible=", ov.visible, " variation=", ov.theme_type_variation, " size=", ov.size, " pos=", ov.global_position, " mod=", ov.modulate)
		var sb = ov.get_theme_stylebox("panel")
		print("=== stylebox=", sb.get_class())
		if sb is StyleBoxFlat:
			var s := sb as StyleBoxFlat
			print("=== bg=", s.bg_color, " border=", s.border_color, " bw=", s.border_width_left, " shadow=", s.shadow_color, " shadow_size=", s.shadow_size, " radius=", s.corner_radius_top_left)
	# 对比卡片自身的 Breath 与 RivalCard 变体
	for child in (board.get_node("Rivals") as Control).get_children():
		var c := child as Control
		if int(c.get_meta("turn_order_player_id", -1)) == int(rules[0]):
			var b := c.get_node_or_null("Breath") as Control
			print("=== card0 variation=", c.theme_type_variation, " breath_visible=", b != null and b.visible)
			if b != null:
				var bs = b.get_theme_stylebox("panel")
				if bs is StyleBoxFlat:
					print("=== card0 breath bg=", (bs as StyleBoxFlat).bg_color, " border=", (bs as StyleBoxFlat).border_color)
	get_tree().quit()
