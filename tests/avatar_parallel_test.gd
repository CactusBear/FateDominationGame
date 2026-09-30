extends "res://tests/_probe_head_fade.gd"

var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)

func _process(_delta: float) -> void:
	pass

func _ready() -> void:
	super._ready()
	call_deferred("run")

func frames(count: int) -> void:
	for i in range(count):
		await get_tree().process_frame
		board.refresh_all_ui()
		board._update_power_badges()

func run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	board.set_process(false)
	_setup_first()
	var other: BaseMapArea
	for area in MapData.areas:
		if area != MapData.miyama:
			other = area
			break
	var other_pid := -1
	for pid in GameData.player_data_library:
		if pid != board._local_player_id:
			other_pid = pid
			break
	SetLocation.new().exec(other._locations[0], other_pid, false)
	var pl: Dictionary = board._pl(other_pid)
	pl.played_cards.append(pl.hand_cards.pop_back())
	board.refresh_all_ui()
	await get_tree().process_frame
	var front: Control
	var back: Control
	for grp in board._play_group_nodes():
		if int(grp.get_meta("player_id")) == board._local_player_id:
			front = grp
		if int(grp.get_meta("player_id")) == other_pid:
			back = grp
	check(front != null and back != null, "both battlefields have groups")
	if front == null or back == null:
		finish()
		return
	check(not front.has_meta("shown"), "front waits for full expansion")
	check(not back.has_meta("shown"), "background waits for same start")
	for i in range(120):
		await frames(1)
		if front.has_meta("shown"):
			break
	check(board._slot_battlefield_open(front), "start after fully expanded")
	check(back.has_meta("shown"), "background starts alongside front")
	var a := front.get_node("Who/Avatar") as Control
	var b := back.get_node("Who/Avatar") as Control
	await frames(10)
	check(b.scale.x > 0.04 and b.scale.x < 0.99, "background advances partway")
	check(absf(a.scale.x - b.scale.x) < 0.03, "parallel progress")
	var previous := b.scale.x
	board._select_scroll(MapData.areas.find(other))
	if board._scroll_tween != null:
		board._scroll_tween.custom_step(2.0)
	await frames(3)
	check(b.scale.x >= previous, "switch preserves elapsed animation")
	await frames(65)
	check(b.scale.is_equal_approx(Vector2.ONE), "background animation completes")
	board._select_scroll(MapData.areas.find(MapData.miyama))
	var clipped_frames := 0
	for i in range(8):
		await frames(1)
		var av_rect := a.get_global_rect()
		var clip_rect := (front.get_parent() as Control).get_global_rect()
		# 检查头像不会从内部列表的左侧裁切线滑入。
		if av_rect.position.x < clip_rect.position.x - 0.5:
			clipped_frames += 1
	check(clipped_frames == 0, "avatar does not emerge through left list clip")
	check(board._scroll_is_animating(), "sample during expansion")
	check(a.scale.is_equal_approx(Vector2.ONE), "scroll reveal does not restart turn")
	check(a.scale.is_equal_approx(Vector2.ONE), "finished turn stays complete during expansion")
	var moving_position := a.global_position
	await frames(8)
	check(a.global_position.distance_to(moving_position) > 0.1, "avatar follows expanding scroll")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tests/runtime_reports/avatar_expanding.png")
	await frames(65)
	check(a.scale.is_equal_approx(Vector2.ONE), "expired animation does not replay")
	check(is_equal_approx((front.get_node("Who/Total") as Control).modulate.a, 1.0), "expired badge visible")
	board._select_scroll(MapData.areas.find(other))
	var left_cut_frames := 0
	var fading_frames := 0
	var visible_before_end := false
	for i in range(35):
		await frames(1)
		var av_rect := b.get_global_rect()
		var alpha: float = (back.get_node("Who") as Control).modulate.a
		if alpha > 0.0 and alpha < 1.0:
			fading_frames += 1
			visible_before_end = visible_before_end or board._scroll_is_animating()
			if fading_frames == 4 and DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("res://tests/runtime_reports/avatar_clip_fade.png")
		var bounds := av_rect
		var ancestor: Node = back.get_parent()
		while ancestor is Control:
			if (ancestor as Control).clip_contents:
				bounds = bounds.intersection((ancestor as Control).get_global_rect())
			ancestor = ancestor.get_parent()
		if not bounds.grow(0.5).encloses(av_rect) and (back.get_node("Who") as Control).modulate.a > 0.01:
			left_cut_frames += 1
	check(left_cut_frames == 0, "left-to-right expansion keeps complete avatar inside play area")
	check(fading_frames >= 3, "complete portrait fades in over multiple frames")
	check(visible_before_end, "fade begins during expansion rather than after it")
	await frames(30)
	check(is_equal_approx((back.get_node("Who") as Control).modulate.a, 1.0), "fade reaches full opacity")
	finish()

func finish() -> void:
	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
