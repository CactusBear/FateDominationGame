extends Node

var failures: Array[String] = []
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
	print("CHECK ", label, " ", ok)

func _ready() -> void:
	call_deferred("run")

func _card(row: Control, id: int) -> Control:
	for child in row.get_children():
		if int(child.get_meta("turn_order_player_id", -1)) == id:
			return child as Control
	return null

func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	# res:// 在运行模式下只读，save_png 会静默失败；写到项目目录的绝对路径
	var dir := ProjectSettings.globalize_path("res://tests/runtime_reports")
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))

func run() -> void:
	var board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	get_tree().root.add_child(board)
	board.set_process(false)
	await get_tree().process_frame
	var row := board.get_node("Rivals") as Control
	var rules: Array = board._ordered_ids()
	check(board._rival_shift_tween == null, "initial layout has no animation")
	var target_id := int(rules[1])
	var outgoing := _card(row, int(rules[0]))
	var target := _card(row, target_id)
	var original_x := target.position.x
	var banner := board.get_node("Banner") as Control
	var text := board.get_node("Banner/Text") as Label
	var banner_pos := banner.position
	var text_pos := text.position
	await shot("actor_queue_before")
	GameProgress.current_player_id = target_id
	board.refresh_all_ui()
	await get_tree().process_frame
	var overlay: Panel = board._gold_frame_node
	check(overlay != null and overlay.visible, "gold frame detaches and starts flying")
	check(board._rival_shift_tween == null, "conveyor waits until gold frame lands")
	check(is_equal_approx(target.position.x, original_x), "actor card holds its old slot while gold frame flies")
	var prev_card := _card(row, int(rules[0]))
	check(prev_card != null and overlay.global_position.distance_to(prev_card.global_position) < 1.0, "gold frame takes off from outgoing actor")
	# 金框还在飞时新行动者不得提前亮起（呼吸框与高亮变体都要等落位）
	check(not target.get_node("Breath").visible, "new actor stays unlit while gold frame flies")
	check(str(target.theme_type_variation) != "RivalActing", "new actor does not wear the acting border while gold frame flies")
	board.refresh_all_ui()
	check(not target.get_node("Breath").visible and str(target.theme_type_variation) != "RivalActing", "periodic refresh cannot light actor before frame lands")
	var fly_start := overlay.global_position
	await get_tree().process_frame
	await get_tree().process_frame
	check(overlay.global_position.distance_to(fly_start) > 0.1, "gold frame travels across the row")
	check(is_equal_approx(target.position.x, original_x), "cards stay put during gold frame flight")
	# 飞行中段截图；用补偿式等待保持后续时序不变（否则传送带会提前跑完，逐帧断言假失败）
	var half_fly: float = board.GOLD_FRAME_FLY_SECONDS * 0.5
	await get_tree().create_timer(half_fly).timeout
	await shot("actor_queue_goldfly")
	await get_tree().create_timer(board.GOLD_FRAME_FLY_SECONDS + 0.05 - half_fly).timeout
	check(not overlay.visible, "gold frame lands and hides")
	check(target.get_node("Breath").visible, "new actor breathes after gold frame lands")
	check(board._rival_shift_tween != null and board._rival_shift_tween.is_running(), "whole player cards start moving after gold frame")
	check(row.get_child(0) == target and row.get_child(row.get_child_count() - 1) == outgoing, "actor first and previous actor last")
	check(board._rival_wrap_tweens.size() == 1, "only outgoing card crosses row boundary")
	check(target.position.x > 0.0, "actor does not teleport to front")
	var previous_x := target.position.x
	var changed_frames := 0
	var mid_slide := 0
	var outgoing_min_x := outgoing.position.x
	for i in range(10):
		await get_tree().process_frame
		if not is_equal_approx(previous_x, target.position.x):
			changed_frames += 1
		previous_x = target.position.x
		# 「中间位置」＝已离开原位、又没到队首。换人时长是表现参数（可以调快），
		# 所以这里只证明整排卡是连续滑过去的、不是一帧跳到位，不绑定具体时长。
		if target.position.x < original_x and target.position.x > 0.0:
			mid_slide += 1
		outgoing_min_x = minf(outgoing_min_x, outgoing.position.x)
	check(changed_frames >= 3, "horizontal travel changes over multiple frames")
	check(mid_slide >= 3, "remaining cards slide left together")
	check(outgoing_min_x < 0.0, "previous actor exits at left edge")
	await shot("actor_queue_mid")
	var active_tween: Tween = board._rival_shift_tween
	board.refresh_all_ui()
	check(board._rival_shift_tween == active_tween, "refresh does not restart movement")
	await get_tree().create_timer(board.RIVAL_SHIFT_SECONDS + 0.1).timeout
	check(target.position.is_equal_approx(Vector2.ZERO), "actor settles at left edge")
	check(outgoing.position.x > _card(row, int(rules.back())).position.x, "outgoing card reappears at right tail")
	check(outgoing.position.x + outgoing.size.x <= row.size.x + 1.0, "returned card stays within row")
	check(board._ordered_ids() == rules, "presentation does not modify rule order")
	for id in rules:
		var c := _card(row, int(id))
		check(str(c.get_node("Order/Label").text) == str(rules.find(id) + 1), "real order number preserved for %s" % id)
		check(c.scale == Vector2.ONE and c.z_index == 0, "no bounce or leftover elevated layer %s" % id)
	check(banner.position == banner_pos and text.position == text_pos, "banner stays stationary")
	await shot("actor_queue_end")
	GameProgress.current_player_id = int(rules[2])
	board.refresh_all_ui()
	await get_tree().process_frame
	GameProgress.current_player_id = board._local_player_id
	board.refresh_all_ui()
	await get_tree().create_timer(board.GOLD_FRAME_FLY_SECONDS + board.RIVAL_SHIFT_SECONDS + 0.2).timeout
	check(row.get_child(0) == _card(row, board._local_player_id), "local placeholder moves to front")
	check(_card(row, board._local_player_id).position.x < 1.0, "rapid handoff settles at latest actor")
	check(row.get_children().all(func(c): return (c as Control).z_index == 0), "interruption restores drawing layers")
	ChangePlOrder.new().exec(null, BaseNumber.new(1))
	board.refresh_all_ui()
	await get_tree().create_timer(board.GOLD_FRAME_FLY_SECONDS + board.RIVAL_SHIFT_SECONDS + 0.2).timeout
	var rotated: Array = board._ordered_ids()
	check(rotated[0] == rules.back() and rotated[1] == rules[0], "original round rotation is restored")
	check(row.get_child(0) == _card(row, GameProgress.current_player_id), "round rotation keeps actor at front")
	check(str(row.get_child(0).get_node("Order/Label").text) == str(rotated.find(GameProgress.current_player_id) + 1), "actor badge is actual order not display index")
	var rin := -1
	for id in rules:
		if board._player_name(int(id)).contains("远坂凛"):
			rin = int(id)
	check(rin >= 0, "Rin exists in real fixture")
	GameProgress.current_player_id = rin
	GameProgress.current_phase_index = 0
	board._refresh_accum = 0.0
	board._process(0.016)
	check(board._banner_actor_id == rin and GameProgress.current_player_id == rin, "Rin captured and held before automatic progress")
	await get_tree().create_timer(board.GOLD_FRAME_FLY_SECONDS + board.RIVAL_SHIFT_SECONDS + 0.2).timeout
	check(text.text.contains("远坂凛") and banner.visible, "Rin prompt remains visible")
	check(row.get_child(0) == _card(row, rin) and _card(row, rin).position.x < 1.0, "Rin info card reaches front")
	check(board._turn_read_remaining > 0.0, "reading time is reserved")
	await shot("actor_queue_rin")
	board.queue_free()
	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
