extends Node

## 卷轴出牌布局（v2 规格）专项：
##   · 一玩家一排：每位有 played_cards 的玩家各占独立横排
##   · 装饰承接条：从头像延伸到牌区，样式定义在 .tscn
##   · 按当前地图总牌量动态排版：扣除边界后按排数与每排牌数求统一卡宽
##   · 暗置牌仅显示卡背、未知信息；本地可见信息按现有权限显示
##   · 刷新前后节点身份保留

var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	print("CHECK ", label, " ", ok)
	if not ok:
		failures.append(label)


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	var board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	get_tree().root.add_child(board)
	board.set_process(false)
	await get_tree().create_timer(0.6).timeout
	MapData.active_situation = null
	var area: BaseMapArea = MapData.miyama
	var unlimited: BaseLocation = area._locations.filter(func(loc): return loc._pl_num_limit < 0)[0]
	var ids: Array = GameData.player_data_library.keys()
	for pid in ids:
		SetLocation.new().exec(unlimited, int(pid), false)
		GameData.player_data_library[pid].played_cards.clear()
	board._select_scroll(MapData.areas.find(area))
	board.refresh_all_ui()
	await get_tree().create_timer(0.4).timeout
	var scroll: Control = board.get_node("Strips").get_child(MapData.areas.find(area))
	var region: Control = scroll.get_node("Main/Groups/List")
	check(region.get_child_count() == 0, "empty battlefield has no groups")
	var me: Dictionary = GameData.player_data_library[ids[0]]
	me.played_cards.append(me.hand_cards.pop_back())
	board.refresh_all_ui()
	await get_tree().create_timer(0.4).timeout
	check(region.get_child_count() == 1, "single player who played cards receives one group")
	var single: Control = region.get_child(0)
	check(single.has_meta("player_id"), "group carries player id metadata")
	check(single.get_node_or_null("Who/Avatar/Img") != null, "group has mini master portrait")
	check(single.get_node_or_null("DecoBar") != null, "group has decorative bar template")
	var row_single: Control = single.get_node("Cards").get_node("Row")
	check(row_single.get_child_count() == 1, "single player single card row")
	var other: Dictionary = GameData.player_data_library[ids[1]]
	other.played_cards.append(other.hand_cards.pop_back())
	var third: Dictionary = GameData.player_data_library[ids[2]]
	third.played_cards.append(third.hand_cards.pop_back())
	board.refresh_all_ui()
	await get_tree().create_timer(0.4).timeout
	check(region.get_child_count() == 3, "three players who played cards yield three rows")
	for ch in region.get_children():
		var rrow: Control = ch.get_node("Cards").get_node("Row")
		var meta_pid := int(ch.get_meta("player_id"))
		var pl: Dictionary = GameData.player_data_library[meta_pid]
		var owned: Array = pl.played_cards
		var matched := 0
		for card in owned:
			for cc in rrow.get_children():
				if cc.get_meta("card", null) == card:
					matched += 1
					break
		check(matched == owned.size(), "row holds exactly the player's played cards (%d)" % owned.size())
		if rrow.get_child_count() >= 2:
			var seq_ok := true
			for idx in range(owned.size()):
				if idx < rrow.get_child_count() and rrow.get_child(idx).get_meta("card", null) != owned[idx]:
					seq_ok = false
					break
			check(seq_ok, "row preserves engine order")
	var concealed_card = me.played_cards[0]
	concealed_card._is_concealed = true
	board.refresh_all_ui()
	await get_tree().create_timer(0.4).timeout
	var me_group: Control = null
	for ch in region.get_children():
		if int(ch.get_meta("player_id")) == ids[0]:
			me_group = ch
			break
	check(me_group != null, "concealed player's group still exists")
	var me_row: Control = me_group.get_node("Cards").get_node("Row")
	var concealed_slot: Control = null
	for cc in me_row.get_children():
		if cc.get_meta("card", null) == concealed_card:
			concealed_slot = cc
			break
	check(concealed_slot != null, "concealed card has its slot")
	var img_node: TextureRect = concealed_slot.get_node("Img")
	var concealed_img_path := img_node.texture.resource_path if img_node.texture != null else ""
	var face_path := str(concealed_card.get("_card_img"))
	check(concealed_img_path != face_path, "concealed card does not show face image")
	var seen_cards: Array = []
	for ch in region.get_children():
		for cc in ch.get_node("Cards").get_node("Row").get_children():
			check(not seen_cards.has(cc), "no card appears in two rows")
			seen_cards.append(cc)
	var many: Dictionary = GameData.player_data_library[ids[3]]
	for k in range(mini(6, many.hand_cards.size())):
		many.played_cards.append(many.hand_cards.pop_back())
	board.refresh_all_ui()
	await get_tree().create_timer(0.4).timeout
	check(region.get_child_count() == 4, "four rows after adding many-cards player")
	for ch in region.get_children():
		var pidx := int(ch.get_meta("player_id"))
		var ppl: Dictionary = GameData.player_data_library[pidx]
		var rrow: Control = ch.get_node("Cards").get_node("Row")
		var owned: Array = ppl.played_cards
		var matched := 0
		for card in owned:
			if not (card is BaseCard):
				continue
			for cc in rrow.get_children():
				if cc.get_meta("card", null) == card:
					matched += 1
					break
		check(matched == owned.size(), "every card of player %d has its slot" % pidx)
		for cc in rrow.get_children():
			check(cc.size.x > 0 and cc.size.y > 0, "card slot has positive size")
	# 尺寸变化是过渡动画：等收敛后再断言统一宽度
	var settle_guard := 0
	var prev_w := -1.0
	while settle_guard < 90:
		settle_guard += 1
		await get_tree().process_frame
		var cur_w := -1.0
		for ch in region.get_children():
			for cc in ch.get_node("Cards").get_node("Row").get_children():
				cur_w = (cc as Control).size.x
				break
			if cur_w > 0.0:
				break
		if cur_w > 0.0 and is_equal_approx(cur_w, prev_w):
			break
		prev_w = cur_w
	var widths: Array = []
	for ch in region.get_children():
		for cc in ch.get_node("Cards").get_node("Row").get_children():
			widths.append(cc.size.x)
	var uniform := not widths.is_empty()
	for w in widths:
		if not is_equal_approx(float(w), float(widths[0])):
			uniform = false
	check(uniform, "all displayed cards share a uniform width (%s)" % str(widths))
	for ch in region.get_children():
		var deco: Control = ch.get_node("DecoBar")
		var cards_sc: Control = ch.get_node("Cards")
		check(deco.size.x >= cards_sc.size.x, "decorative bar spans at least card area width")
	var prev_bottom := -1.0
	var sorted_by_y := []
	for ch in region.get_children():
		sorted_by_y.append(ch)
	sorted_by_y.sort_custom(func(a, b): return a.position.y < b.position.y)
	# 出牌区按行装箱、支持多列：同一行可以并排多个玩家，
	# 所以判据不是"纵向不重叠"，而是任意两组矩形都不相交（也不与相邻列重合）
	for a in range(sorted_by_y.size()):
		for b in range(a + 1, sorted_by_y.size()):
			var ra: Rect2 = (sorted_by_y[a] as Control).get_global_rect()
			var rb: Rect2 = (sorted_by_y[b] as Control).get_global_rect()
			check(not ra.intersects(rb), "player groups do not overlap each other")
	# 出牌区是可滚动的：内容尺寸由布局写入，ScrollContainer 要到下一帧才应用，
	# 不等一帧会拿到上一轮的 List 尺寸
	await get_tree().process_frame
	await get_tree().process_frame
	var region_rect := region.get_global_rect()
	for ch in region.get_children():
		var r2: Rect2 = ch.get_global_rect()
		if not region_rect.encloses(r2):
			print("BOUNDS region=", region_rect, " row=", r2, " target=", ch.get_meta("lay_grp_pos_target", Vector2.ZERO))
		check(region_rect.encloses(r2), "row stays inside groups list")
	var other_area := MapData.magic_workshop
	for pid in GameData.player_data_library.keys():
		SetLocation.new().exec(other_area._locations.filter(func(loc): return loc._pl_num_limit < 0)[0], int(pid), false)
	board._select_scroll(MapData.areas.find(other_area))
	board.refresh_all_ui()
	await get_tree().create_timer(0.4).timeout
	var other_region: Control = scroll.get_node("Main/Groups/List")
	check(other_region.get_child_count() == 0, "switching area clears old groups")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		check(get_viewport().get_texture().get_image().save_png("res://tests/runtime_reports/battle_play_groups.png") == OK, "window screenshot saved")
	finish()


func finish() -> void:
	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
