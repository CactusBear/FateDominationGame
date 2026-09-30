extends Node

## 临时性能探针：分离"空闲基线帧率"与"换人动画帧率"，并打印渲染驱动。

func _ready() -> void:
	call_deferred("run")

func _measure(seconds: float, board, rules: Array, handoff: bool) -> void:
	var t0 := Time.get_ticks_msec()
	var n := 0
	var k := 0
	while Time.get_ticks_msec() - t0 < int(seconds * 1000.0):
		await get_tree().process_frame
		n += 1
		if handoff and n % 30 == 1:
			GameProgress.current_player_id = int(rules[(k + 1) % rules.size()])
			board.refresh_all_ui()
			k += 1
	var tag := "HANDOFF" if handoff else "IDLE   "
	print("=== %s fps=%.1f  frames=%d" % [tag, float(n) / seconds, n])

func run() -> void:
	var board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	get_tree().root.add_child(board)
	print("=== adapter=", RenderingServer.get_video_adapter_name())
	print("=== driver=", OS.get_video_adapter_driver_info())
	print("=== renderer=", ProjectSettings.get_setting("rendering/renderer/rendering_method"))
	print("=== vsync=", DisplayServer.window_get_vsync_mode())
	await get_tree().process_frame
	await get_tree().process_frame
	var rules: Array = board._ordered_ids()
	await _measure(4.0, board, rules, false)
	await _measure(6.0, board, rules, true)
	await _measure(4.0, board, rules, false)
	print("DONE")
	get_tree().quit()
