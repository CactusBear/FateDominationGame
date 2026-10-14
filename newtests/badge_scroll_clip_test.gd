extends "res://newtests/card_modification_history_v2_test.gd"

var groups: ScrollContainer
var group: Control
var row: Control
var scroll: ScrollContainer
var checkpoint := "single"
var original_state := ""
var command_path := "E:/scratch/continuous-next-wave/ui-badge-clip/command.txt"
var evidence_path := "E:/scratch/continuous-next-wave/ui-badge-clip/live-state.json"

func _ready() -> void:
	get_tree().create_timer(600.0).timeout.connect(func():
		check(false, "window watchdog")
		finish_probe())
	call_deferred("run")

func run() -> void:
	EffectManager.reset_runtime()
	GameProgress.reset_progress()
	GameLog.reset()
	GameData.player_data_library.clear()
	data = GameData.new_player_data()
	GameData.player_data_library[0] = data
	GameData.player_data_library[1] = GameData.new_player_data()
	LoadAttack.load_all()
	card = LoadAttack.resolve("strength:2")
	other = LoadAttack.resolve("strength:2")
	skill = BaseSkill.new("fixture", "", [], BaseNumber.new(1), BaseNumber.new(1))
	CostOperation.new().exec(BaseNumber.new(1), null, card)
	data.played_cards.append(card)
	builder = preload("res://scripts/match/view_builder.gd").new()
	board = Scene.instantiate()
	board.set_script(BoardProbe)
	add_child(board)
	board._local_player_id = 0
	board._source_is_local = true
	board._held_action_ids = builder.ids
	board._source = LocalBattleSource.new(0, builder, MatchSeatQuery.new(builder))
	for child in board.get_children():
		if child is CanvasItem and child.name != "Templates" and child.name != "CardModificationHistory": child.hide()
	var strip := Control.new()
	strip.position = Vector2(250, 260)
	strip.size = Vector2(900, 240)
	board.add_child(strip)
	var seats := Control.new()
	seats.name = "Seats"
	strip.add_child(seats)
	for title in ["MeleeScroll", "SeatScroll"]:
		var seat := ScrollContainer.new()
		seat.name = title
		seats.add_child(seat)
		seat.hide()
	var holder := Control.new()
	strip.add_child(holder)
	groups = ScrollContainer.new()
	groups.name = "Groups"
	groups.set_meta("max_groups_per_row", 3)
	holder.add_child(groups)
	var list := Control.new()
	list.name = "List"
	groups.add_child(list)
	group = board._spawn("PlayGroup", list)
	group.set_meta("player_id", 0)
	group.set_meta("expanded", true)
	group.set_meta("expanded_columns", 1)
	group.set_meta("expanded_visible_rows", 1)
	scroll = group.get_node("Cards")
	row = scroll.get_node("Row")
	board._master = Control.new()
	board.add_child(board._master)
	board._master.position = Vector2(250, 1200)
	board._master.size = Vector2(900, 100)
	await bind_layout()
	var tag := badge(row.get_child(0))
	check(tag.visible and tag.get_meta("mod_target_card") == card, "formal small played binder consumes real operation history")
	check(scroll.clip_contents and groups.clip_contents and list.clip_contents, "all production clipping stays enabled")
	check(scroll.get_global_rect().encloses(tag.get_global_rect()), "first played card outer badge is not clipped")
	check(tag.get_global_rect().position.x < (row.get_child(0) as Control).get_global_rect().position.x, "badge remains outside card left edge")
	original_state = state()
	print("CLIP_GEOMETRY ", JSON.stringify(geometry()))
	if not OS.get_cmdline_user_args().has("window"):
		finish_probe()
	else:
		set_process(true)
		write_state()

func bind_layout() -> void:
	board._source.invalidate()
	board._bind_played_cards_row(row, board._source.read_view().players[0].played_cards, 0)
	group.remove_meta("shown")
	groups.remove_meta("layout_sig")
	board._layout_play_groups(groups)
	group.modulate.a = 1.0
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.6).timeout

func geometry() -> Dictionary:
	var slots: Array = []
	for slot: Control in row.get_children():
		var tag := badge(slot)
		slots.append({"card": rect_array(slot.get_global_rect()), "badge": rect_array(tag.get_global_rect()), "visible": tag.visible})
	return {"slots": slots, "scroll": rect_array(scroll.get_global_rect()), "groups": rect_array(groups.get_global_rect()), "clip": scroll.clip_contents, "scroll_vertical": scroll.scroll_vertical, "row_size": [row.size.x, row.size.y]}

func rect_array(rect: Rect2) -> Array:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]

func write_state() -> void:
	var file := FileAccess.open(evidence_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"checkpoint": checkpoint, "geometry": geometry(), "history_open": reader().visible, "history_text": text(), "checks": checks, "failures": failures, "readonly": state() == original_state, "pid": OS.get_process_id()}))

func _process(_delta: float) -> void:
	if not FileAccess.file_exists(command_path): return
	var command := FileAccess.get_file_as_string(command_path).strip_edges()
	if command.is_empty(): return
	var file := FileAccess.open(command_path, FileAccess.WRITE)
	file.store_string("")
	set_process(false)
	await act(command)
	if command == "finish": return
	set_process(true)
	write_state()

func act(command: String) -> void:
	match command:
		"openverify":
			check(reader().visible and text().contains(card.get_modification_details()[0].detail), "OS badge click opens actual history")
			check(state() == original_state, "OS badge click does not play flip select activate or mutate")
			checkpoint = "history-open"
		"closeverify":
			check(not reader().visible, "OS Escape closes history")
			check(state() == original_state, "OS close is readonly")
			checkpoint = "history-closed"
		"many":
			for i in range(11):
				var added := LoadAttack.resolve("strength:2")
				CostOperation.new().exec(BaseNumber.new(1), null, added)
				data.played_cards.append(added)
			group.set_meta("expanded_columns", 3)
			group.set_meta("expanded_visible_rows", 2)
			await bind_layout()
			check(row.get_child_count() == 12, "multi-card production binding")
			for i in range(6):
				var slot := row.get_child(i) as Control
				check(scroll.get_global_rect().encloses(badge(slot).get_global_rect()), "expanded visible badge fits " + str(i))
				if i % 3 != 0:
					check(slot.position.x > (row.get_child(i - 1) as Control).position.x, "expanded columns retain order " + str(i))
			checkpoint = "many-top"
			original_state = state()
		"scrollverify":
			check(scroll.scroll_vertical > 0, "OS wheel scrolls played row")
			check(state() == original_state, "OS scrolling does not mutate game")
			var last := row.get_child(11) as Control
			check(scroll.get_global_rect().encloses(badge(last).get_global_rect()), "last row badge visible after OS scroll")
			checkpoint = "many-scrolled"
		"collapsed":
			scroll.scroll_vertical = 0
			group.set_meta("expanded", false)
			await bind_layout()
			check(scroll.get_global_rect().encloses(badge(row.get_child(0)).get_global_rect()), "collapsed first badge fits")
			check(scroll.get_global_rect().encloses((row.get_child(11) as Control).get_global_rect()), "collapsed last card fits")
			checkpoint = "collapsed"
		"finish": finish_probe()

func finish_probe() -> void:
	print("RESULT badge_scroll_clip checks=", checks, " failures=", JSON.stringify(failures))
	board.free()
	EffectManager.reset_runtime()
	get_tree().quit(0 if failures.is_empty() else 1)
