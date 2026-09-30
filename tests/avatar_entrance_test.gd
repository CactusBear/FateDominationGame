extends "res://tests/_probe_head_fade.gd"

var checks := 0
var failures: Array[String] = []
var widths: Array[float] = []
var observed: Control
var initial_position := Vector2.ZERO
var captured := false

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)

func _process(delta: float) -> void:
	if board == null or not board.is_inside_tree():
		return
	t += delta
	if phase == 0 and t > 1.0:
		phase = 1
		_setup_first()
	for grp in board._play_group_nodes():
		if not grp.has_meta("shown"):
			continue
		var av := grp.get_node("Who/Avatar") as Control
		var badge := grp.get_node("Who/Total") as Control
		if observed == null:
			observed = av
			initial_position = av.position
		if av != observed:
			continue
		widths.append(av.scale.x)
		if widths.size() == 2:
			check(av.scale.x < 0.6, "starts side-on")
			check(badge.modulate.a == 0.0, "badge waits for turn")
		if not captured and av.scale.x > 0.45 and av.scale.x < 0.85:
			captured = true
			_capture("avatar_turn_middle")
		if widths.size() == 65:
			var changed := 0
			var receded := false
			for i in range(1, widths.size()):
				if not is_equal_approx(widths[i], widths[i - 1]):
					changed += 1
				if widths[i] < widths[i - 1] - 0.0001:
					receded = true
			check(changed >= 3, "multi-frame turn")
			check(receded, "gentle return swing")
			check(av.scale.is_equal_approx(Vector2.ONE), "settles at original scale")
			check(is_equal_approx(badge.modulate.a, 1.0), "badge revealed")
			board.refresh_all_ui()
			check(av.scale.is_equal_approx(Vector2.ONE), "refresh does not replay")
			check(is_equal_approx(av.modulate.a, 1.0), "no second fade")
			await _capture("avatar_turn_final")
			print("RESULT checks=", checks, " failures=", failures)
			get_tree().quit(0 if failures.is_empty() else 1)
	if t > 12.0:
		print("RESULT checks=", checks, " failures=[no completed entrance]")
		get_tree().quit(1)

func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tests/runtime_reports/" + label + ".png")
