extends Node

var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
	print("CHECK ", label, " ", ok)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	seed(9173)
	var board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	board.set_script(load("res://tests/ui_refresh_cost_board.gd"))
	get_tree().root.add_child(board)
	board.set_process(false)
	GameProgress.current_player_id = board._local_player_id
	GameProgress.current_phase_index = 2
	board.refresh_all_ui()
	var iterations := 100
	var started := Time.get_ticks_usec()
	for i in range(iterations):
		for slot in board._hand.get_children():
			board._held_card_playable(slot.get_meta("card"))
	var repeated_rules_us := Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	for i in range(iterations):
		board._update_held_cards(1.0 / 60.0)
	print("COST iterations=", iterations, " repeated_rules_us=", repeated_rules_us, " optimized_animation_us=", Time.get_ticks_usec() - started)
	check(board._hand.get_children().any(func(slot): return bool(slot.get_meta("held_playable", false))), "fixture includes a playable card")
	var rivals: Array = board._rivals.get_children()
	var identities: Array = rivals.map(func(node): return node.get_instance_id())
	board.playable_queries = 0
	board.confirm_queries = 0
	# 状态不变：连跑 20 帧都不该重跑规则搜索（那是深度组合搜索，一轮约 4ms）
	for i in range(20):
		board._update_held_cards(1.0 / 60.0)
	check(board.playable_queries == 0, "unchanged state does not requery card legality per frame")
	check(board.confirm_queries == 20, "submission safety remains live on every frame")
	# 阶段变化：必须立刻重算，金色呼吸描边不能滞后
	var before_phase: int = board.playable_queries
	GameProgress.current_phase_index = 0
	board._update_held_cards(0.0)
	check(board.playable_queries > before_phase, "phase change recomputes hints immediately")
	GameProgress.current_phase_index = 2
	board._update_held_cards(0.0)
	# 选牌变化：同样必须立刻重算
	var before_pick: int = board.playable_queries
	var first_slot: Control = board._hand.get_child(0)
	board._selected_cards.append(first_slot.get_meta("card"))
	board._update_held_cards(0.0)
	check(board.playable_queries > before_pick, "selection change recomputes hints immediately")
	board._selected_cards.clear()
	board.refresh_all_ui()
	check(board.playable_queries > 0, "UI refresh recomputes card legality")
	check(board.confirm_queries > 0, "UI refresh recomputes submit legality")
	check(identities == board._rivals.get_children().map(func(node): return node.get_instance_id()), "unchanged players retain rival node identities")
	for slot in board._hand.get_children():
		check(bool(slot.get_meta("held_playable", false)) == board._held_card_playable(slot.get_meta("card")), "bound hint matches live rule")
	var button: Button = board._ops.get_node("PlayButton")
	board.get_node("LogBrowser").show()
	board._update_held_cards(0.0)
	check(button.disabled, "modal immediately disables submission")
	board.get_node("LogBrowser").hide()
	var me: Dictionary = GameData.player_data_library[board._local_player_id]
	me.magic.number = 0
	board.refresh_all_ui()
	for slot in board._hand.get_children():
		check(bool(slot.get_meta("held_playable", false)) == board._held_card_playable(slot.get_meta("card")), "resource change refreshes hints")
	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
