extends Node

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	seed(9173)
	var board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	board.set_script(load("res://tests/takeoff_refresh_board.gd"))
	get_tree().root.add_child(board)
	board.set_process(false)
	await get_tree().create_timer(0.7).timeout
	var ids: Array = GameData.player_data_library.keys()
	for i in range(ids.size()):
		var area = MapData.areas[i % MapData.areas.size()]
		var loc = area._locations.filter(func(item): return item._pl_num_limit < 0)[0]
		SetLocation.new().exec(loc, ids[i], false)
		var pl: Dictionary = GameData.player_data_library[ids[i]]
		for k in range(mini(3, pl.hand_cards.size())):
			pl.played_cards.append(pl.hand_cards.pop_back())
	board.refresh_all_ui()
	await get_tree().create_timer(2.0).timeout
	var route_before: Array = board.get_node("Route/Row").get_children()
	var begin := Time.get_ticks_usec()
	for i in range(100):
		board._bind_situation_and_piles()
	var route_reused: bool = route_before == board.get_node("Route/Row").get_children()
	print("BENCH route_100_us=", Time.get_ticks_usec() - begin)
	var frames: Array[float] = []
	var previous := Time.get_ticks_usec()
	for cycle in range(8):
		board._select_scroll(cycle % MapData.areas.size())
		var until := Time.get_ticks_msec() + 600
		while Time.get_ticks_msec() < until:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			frames.append(float(now - previous) / 1000.0)
			previous = now
			board._update_fly_sizes(1.0 / 60.0)
			board._update_power_badges()
	frames.sort()
	print("BENCH frame_ms_median=", frames[frames.size() / 2], " p95=", frames[int(frames.size() * 0.95)])
	board.refresh_all_ui()
	if DisplayServer.get_name() != "headless":
		await get_tree().create_timer(board.FADE_SECONDS + 0.1).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tests/runtime_reports/switch_performance.png")
	print("RESULT checks=1 failures=", [] if route_reused else ["route nodes were rebuilt"])
	get_tree().quit(0 if route_reused else 1)
