extends Node

## battle_board_v2 结构探针：用真实引擎数据把七人开局摆到版图上，检查各分区是否按数据生成，
## 并在非 headless 下截图到 user://battle_board_v2.png 供画面检查。
## 运行：Godot --path . tests/battle_board_v2_test.tscn（加 --headless 只跑断言，不截图）

var failures: Array = []
var checks: int = 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
	print("CHECK ", label, " ", ok)


func _ready() -> void:
	call_deferred("run")


func _labels_with(root: Node, needle: String) -> int:
	var n := 0
	for child in root.find_children("*", "Label", true, false):
		if str((child as Label).text).contains(needle):
			n += 1
	return n


func run() -> void:
	var board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	get_tree().root.add_child(board)
	await get_tree().process_frame
	board.set_process(false)
	board._select_scroll(0)
	await get_tree().create_timer(board.SCROLL_SECONDS + 0.05).timeout
	check(GameStart._started, "game started by board")
	check(GameData.player_data_library.size() == 7, "seven players loaded")
	# 用引擎部署规则把所有玩家摆上版图（本地玩家 6 进工房、其余按可部署战区轮流）
	GameProgress.current_round = 1
	GameProgress.current_phase_index = 2
	# 阶段横幅只在真正阶段推进时播；这里直接改下标是为了固定测试场景，
	# 同步记录避免把它误当成一次阶段更迭（否则横幅停在"行动阶段"、挤掉行动者提示）
	board._last_phase_index = 2
	var areas: Array = DeployRules.deployable_areas()
	check(not areas.is_empty(), "has deployable areas")
	var i := 0
	for id in GameData.player_data_library.keys():
		var pl: Dictionary = GameData.player_data_library[id]
		if pl["is_out"]:
			pl["is_out"] = false
		var target: BaseMapArea = MapData.magic_workshop if int(id) == GameData.player_id else areas[i % areas.size()]
		var loc = DeployRules.deploy_to_area(target, int(id))
		if loc == null:
			loc = DeployRules.deploy_to_area(areas[(i + 1) % areas.size()], int(id))
		i += 1
	check(board._player_area(GameData.player_id) != null, "local player deployed")
	# 造两组出牌：本地玩家两张明置，玩家 0 一张暗置
	var me: Dictionary = GameData.player_data_library[GameData.player_id]
	for k in range(2):
		if me["hand_cards"].size() > 0:
			var c = me["hand_cards"].pop_back()
			me["played_cards"].append(c)
	var p0: Dictionary = GameData.player_data_library[0]
	if p0["hand_cards"].size() > 0:
		var hidden = p0["hand_cards"].pop_back()
		hidden._is_concealed = true
		p0["played_cards"].append(hidden)
	GameProgress.current_player_id = 0
	board.refresh_all_ui()
	await get_tree().process_frame

	var stage: Control = board
	var tpl: Control = board.get_node("Templates")
	check(not tpl.visible and tpl.get_child_count() >= 20, "templates hidden in tscn (%d)" % tpl.get_child_count())
	check(_labels_with(stage, "第 1 回合") == 1, "round label")
	check(_labels_with(stage, "行动阶段") >= 1, "phase tag from GameProgress.phases")
	check(_labels_with(stage, "我方") == 2, "self placeholder in rival row (template + clone)")
	var rivals: Control = stage.get_node("Rivals")
	check(rivals.get_child_count() == 7, "seven rival slots incl self (%d)" % rivals.get_child_count())
	# 我方占位与此处非行动的其它玩家用同一套边框色；行动中的玩家另有高亮变体，不参与比较
	var self_slot: Control = null
	var other_slot: Control = null
	for child in rivals.get_children():
		var c := child as Control
		if bool(c.get_meta("self_slot", false)):
			self_slot = c
		elif not board._is_acting(int(c.get_meta("turn_order_player_id", -1))):
			other_slot = c
	check(self_slot != null and other_slot != null, "rival row has self and a non-acting other slot")
	if self_slot != null and other_slot != null:
		var self_box := self_slot.get_theme_stylebox("panel") as StyleBoxFlat
		var other_box := other_slot.get_theme_stylebox("panel") as StyleBoxFlat
		check(self_box != null and other_box != null, "both slots carry a panel stylebox")
		check(self_box.border_color == other_box.border_color, "self placeholder border color matches other players")
		check(is_equal_approx(self_box.border_color.a, other_box.border_color.a), "self placeholder border alpha matches")
	# “我方”两字与此处其它玩家名同色，并用粗体中文字面（原先是青色常规字）
	var self_label: Label = null
	if self_slot != null:
		for l in self_slot.find_children("*", "Label", true, false):
			if (l as Label).text == "我方":
				self_label = l
	var rival_name: Label = null
	if other_slot != null:
		rival_name = other_slot.get_node_or_null("Name") as Label
	check(self_label != null and rival_name != null, "self text and rival name labels exist")
	if self_label != null and rival_name != null:
		check(self_label.get_theme_color("font_color") == rival_name.get_theme_color("font_color"), "self text color matches other players")
		var self_font := self_label.get_theme_font("font") as FontVariation
		var rival_font := rival_name.get_theme_font("font") as FontVariation
		check(self_font != null and self_font.variation_opentype.values().has(700), "self text uses a bold face")
		check(self_font != rival_font, "self text face differs from the rival name face")
	# 轮到我方时，“我方”占位要和其它玩家行动时一样高亮（换高亮变体 + 亮呼吸框）
	if self_slot != null:
		var self_breath := self_slot.get_node_or_null("Breath") as Control
		check(self_breath != null, "self slot carries a breath outline")
		check(self_breath != null and not self_breath.visible, "self slot stays dim while another player acts")
		var local_id: int = board._local_player_id
		var previous_player: int = GameProgress.current_player_id
		GameProgress.current_player_id = local_id
		board.refresh_all_ui()
		await get_tree().create_timer(board.GOLD_FRAME_FLY_SECONDS + 0.1).timeout
		var lit: Control = null
		for child in rivals.get_children():
			if bool((child as Control).get_meta("self_slot", false)):
				lit = child
		check(lit != null and (lit.get_node_or_null("Breath") as Control) != null and (lit.get_node("Breath") as Control).visible, "self slot lights up on the local turn")
		if lit != null:
			var lit_box := lit.get_theme_stylebox("panel") as StyleBoxFlat
			check(lit_box != null and lit_box.border_color.a > 0.9, "self slot uses the acting highlight border")
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("res://tests/runtime_reports/self_turn_highlight.png")
		GameProgress.current_player_id = previous_player
		board.refresh_all_ui()
		await get_tree().process_frame
	check(_labels_with(stage, "正在行动") == 1 and board.get_node("Banner").visible and str(board.get_node("Banner/Text").text).ends_with("的行动"), "enemy acting hint + banner")
	var ops: Control = stage.get_node("Ops")
	var end_btn: Button = null
	for b in ops.find_children("*", "Button", true, false):
		if (b as Button).text == "结束阶段":
			end_btn = b
	check(end_btn != null, "end phase button exists")
	check(end_btn != null and end_btn.disabled, "end phase disabled when enemy acts")
	var strips: Control = stage.get_node("Strips")
	check(strips.get_children().filter(func(c): return c is Panel).size() == MapData.areas.size(), "persistent scroll for every area")
	var hand: Control = stage.get_node("Hand")
	check(hand.get_child_count() == me["hand_cards"].size() + board._zone_hand_entries(me).size(), "hand fan card count (%d)" % hand.get_child_count())
	# 出牌区不再挂"?"威力圆标（用户要求删除牌旁的提示圆）；暗置牌只显示卡背
	check(_labels_with(strips.get_child(board._main_area_index).get_node("Main"), "?") == 0, "played cards have no ? badge")
	var main_area: BaseMapArea = MapData.areas[board._main_area_index]
	var active_scroll: Control = strips.get_child(board._main_area_index)
	var seat_row: Node = active_scroll.get_node("Seats/SeatScroll/Row")
	var fixed: Array = main_area._locations.filter(func(loc): return loc._pl_num_limit >= 0)
	check(seat_row.get_child_count() == fixed.size(), "fixed seat row mirrors locations")
	var melee_count := 0
	for loc: BaseLocation in main_area._locations:
		if loc._pl_num_limit < 0:
			melee_count += loc._players.size()
	check(active_scroll.get_node("Seats/MeleeScroll/Row").get_child_count() == melee_count, "upper row mirrors unseated players")
	check(not board.has_node("Main/Disc"), "no central disc")
	check(active_scroll.get_node("EventIcons").visible == not main_area._events.is_empty(), "events hidden when area has no events")
	var hovered: Control = strips.get_child(1)
	var motion := InputEventMouseMotion.new()
	motion.position = hovered.get_rect().get_center()
	motion.relative = Vector2.ONE
	board._input(motion)
	await get_tree().create_timer(board.SCROLL_SECONDS + 0.05).timeout
	check(board._main_area_index == 1 and strips.get_child(1) == hovered, "hover opens same persistent scroll without chain switching")
	var hover_idx: int = board._main_area_index
	check(hovered.get_node("EventIcons").visible == not (MapData.areas[hover_idx] as BaseMapArea)._events.is_empty(), "events follow hovered area")
	# 切主图到玩家 0 所在战区
	var a0: BaseMapArea = board._player_area(0)
	var idx := MapData.areas.find(a0)
	board._select_scroll(idx)
	board.refresh_all_ui()
	await get_tree().create_timer(board.SCROLL_SECONDS + 0.05).timeout
	check(_labels_with(strips.get_child(idx).get_node("Main"), a0._area_name) >= 1, "main title follows hovered area")
	# 轮到自己：按钮启用、御主卡「你的行动」标签
	GameProgress.current_player_id = GameData.player_id
	board.refresh_all_ui()
	await get_tree().process_frame
	check(board.get_node("Master/OvalFrame").texture != null, "master oval deco frame")
	check(_labels_with(stage, "轮到你行动") == 1, "own turn hint")
	for b in ops.find_children("*", "Button", true, false):
		if (b as Button).text == "结束阶段":
			check(not b.disabled, "end phase enabled on own turn")
	check(board._main_area_index == idx, "hover index kept across refresh")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("user://battle_board_v2.png")
		print("SCREENSHOT ", ProjectSettings.globalize_path("user://battle_board_v2.png"))
	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit()
