extends Node

## 临时探针：阶段更迭时播横幅动画，动画期间冻结行动（_phase_anim_busy），演完后补上行动者提示。

func _ready() -> void:
	call_deferred("run")

func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var dir := ProjectSettings.globalize_path("res://tests/runtime_reports")
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join("phase_" + name + ".png"))

func run() -> void:
	var board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	get_tree().root.add_child(board)
	await get_tree().process_frame
	board.set_process(false)
	await get_tree().process_frame
	var log: Array = []
	GameProgress.current_phase_index += 1   # 模拟阶段推进
	board.refresh_all_ui()
	log.append("phase+1  busy=%s text='%s' visible=%s" % [str(board._phase_anim_busy), str(board._phase_banner_label.text), str(board._phase_banner.visible)])
	for i in range(110):
		await get_tree().process_frame
		if i in [8, 40, 75, 100]:
			log.append("f%03d busy=%s text='%s' a=%.2f scale=%.2f" % [i, str(board._phase_anim_busy), str(board._phase_banner_label.text), board._phase_banner.modulate.a, board._phase_banner.scale.x])
			await shot("%03d" % i)
	for l in log:
		print(l)
	print("DONE")
	get_tree().quit()
