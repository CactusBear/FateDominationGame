extends "res://tests/full_game_test.gd"

## 复用现有完整对局驱动器，不在 v2 UI 中新增规则或 AI 行为。
## 旧控制器只负责测试中的行动推进，窗口始终显示真实数据绑定的 v2 卷轴界面。
var visual_board: Control

func render_window_state(capture_name: String = ""):
	if visual_board == null:
		scene.hide()
		visual_board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
		get_tree().root.add_child(visual_board)
		visual_board.set_process(false)
	visual_board.refresh_all_ui()
	visual_board._select_scroll(visual_board._default_area_index())
	if DisplayServer.get_name() == "headless":
		return
	await get_tree().process_frame
	await get_tree().process_frame
	if not capture_name.is_empty():
		await get_tree().create_timer(visual_board.SCROLL_SECONDS + 0.05).timeout
		await RenderingServer.frame_post_draw
		var path := "res://tests/runtime_reports/scroll_" + capture_name + ".png"
		check(get_viewport().get_texture().get_image().save_png(path) == OK, "v2 window screenshot saved " + capture_name)
