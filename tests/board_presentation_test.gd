extends Node

var failures: Array = []
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
	print("CHECK ", label, " ", ok)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	get_tree().root.add_child(board)
	await get_tree().process_frame
	board.set_process(false)
	check(board.has_node("AreaTitle/Name"), "map title lives on root canvas")
	var portrait: TextureRect = board.get_node("Master/Frame/Img")
	check(portrait.texture is ImageTexture, "master crop has independent full-range UV")
	check(portrait.material is ShaderMaterial, "portrait has oval mask")
	if board.has_node("AreaTitle/Name"):
		for i in range(MapData.areas.size()):
			board._select_scroll(i)
			await get_tree().create_timer(0.1).timeout
			var title: Label = board.get_node("AreaTitle/Name")
			check(is_equal_approx(title.get_global_rect().get_center().x, board.get_global_rect().get_center().x), "title stays screen centered during transition %d" % i)
			check(title.text == MapData.areas[i]._area_name, "title follows selected area %d" % i)
	if DisplayServer.get_name() != "headless":
		await get_tree().create_timer(board.SCROLL_SECONDS + 0.1).timeout
		await RenderingServer.frame_post_draw
		var path := "res://tests/runtime_reports/board_presentation.png"
		check(get_viewport().get_texture().get_image().save_png(path) == OK, "presentation screenshot saved")
	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
