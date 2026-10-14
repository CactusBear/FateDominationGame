extends Node
# 本局原来源取自 reset_runtime 回执；夹具对 operation 显式传入，不从全局补票。
var ctx: SessionContext = null
func _reset_ctx() -> SessionContext:
	var reset: Dictionary = EffectManager.reset_runtime()
	return reset.get("context") if reset.get("ok", false) else null

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
	# 窗口分支必须由runner显式请求；headless只作同源码结构/业务回归。
	print("VISIBLE_MODE ", JSON.stringify({"display": DisplayServer.get_name(), "args": OS.get_cmdline_user_args()}))
	if DisplayServer.get_name() != "headless" and not OS.get_cmdline_user_args().has("window"):
		check(false, "window fixture requires explicit window argument")
		finish()
		return
	var board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	get_tree().root.add_child(board)
	# 只冻结规则推进的座位所有权，保留真实帧更新及 Tween 生命周期。
	for pid in GameData.player_data_library:
		board._seat_controller.set_kind(int(pid), SeatController.REMOTE)
	# 旧回合等待协程不属于board处理；在任何布局前结束其会话代际。
	GameProgress.reset_progress()
	ctx = _reset_ctx()
	GameLog.reset()
	GameLog.set_context(1, "action")
	GameProgress.current_round = 1
	GameProgress.current_phase_index = GameProgress.phases.find(GameProgress.phases.filter(func(p): return p.get("name") == "action")[0])
	GameProgress.current_player_id = int(GameData.player_data_library.keys()[0])
	await get_tree().create_timer(0.6).timeout
	MapData.active_situation = null
	var area: BaseMapArea = MapData.miyama
	var unlimited: BaseLocation = area._locations.filter(func(loc): return loc._pl_num_limit < 0)[0]
	var ids: Array = GameData.player_data_library.keys()
	for pid in ids:
		SetLocation.new().exec(unlimited, int(pid), false, false, true, ctx)
		GameData.player_data_library[pid].played_cards.clear()
	board._select_scroll(MapData.areas.find(area))
	board.refresh_all_ui()
	await get_tree().create_timer(0.4).timeout
	var scroll: Control = board.get_node("Strips").get_child(MapData.areas.find(area))
	var region: Control = scroll.get_node("Main/Groups/List")
	check(region.get_child_count() == 0, "empty battlefield has no groups")
	var me: Dictionary = GameData.player_data_library[ids[0]]
	# 残留分区是公开快照合同；不把所有 played_cards 都假设成当前出牌。
	var residue_control := ordinary_card("layout-residue-control")
	residue_control._effects.append(BaseEffect.new("layout-residue", [], 0, false, true))
	me.played_cards.append(residue_control)
	board.refresh_all_ui()
	check(region.get_child_count() == 0, "explicit residue card is excluded from current play groups")
	var residue_view := projected_player(board, int(ids[0]))
	check(residue_view.get("residue_cards", []).size() == 1, "public snapshot declares explicit residue partition")
	me.played_cards.clear()
	# 复用规则测试的显式普通攻击原语，真实公开增量出牌，不伪造合法性。
	ctx = _reset_ctx()
	GameLog.reset()
	GameLog.set_context(1, "action")
	GameProgress.is_game_over = false
	GameProgress.current_round = 1
	GameProgress.current_phase_index = GameProgress.phases.find(GameProgress.phases.filter(func(p): return p.get("name") == "action")[0])
	GameProgress.current_player_id = int(ids[0])
	var first := ordinary_card("layout-first")
	var second := ordinary_card("layout-second")
	me.hand_cards.append_array([first, second])
	var accepted := RegularPlay.add(int(ids[0]), first, false)
	check(accepted, "public authority accepts legal first ordinary card")
	if not accepted:
		finish()
		return
	board.refresh_all_ui()
	await get_tree().create_timer(0.4).timeout
	first_evidence(board, area, me.played_cards[0], int(ids[0]), region)
	check(region.get_child_count() == 1, "single player who played cards receives one group")
	if region.get_child_count() != 1:
		finish()
		return
	var single: Control = region.get_child(0)
	check(single.has_meta("player_id"), "group carries player id metadata")
	check(single.get_node_or_null("Who/Avatar/Img") != null, "group has mini master portrait")
	check(single.get_node_or_null("DecoBar") != null, "group has decorative bar template")
	var row_single: Control = single.get_node("Cards").get_node("Row")
	check(row_single.get_child_count() == 1, "single player single card row")
	if row_single.get_child_count() != 1:
		finish()
		return
	var same_group := single.get_instance_id()
	var same_slot := row_single.get_child(0).get_instance_id()
	var before_seq: int = board._source.read_view().seq
	board.refresh_all_ui()
	check(int(board._source.read_view().seq) > before_seq, "public refresh begins a new source snapshot cycle")
	check(single.get_instance_id() == same_group and row_single.get_child(0).get_instance_id() == same_slot, "unchanged refresh preserves group and card node identities")
	var other: Dictionary = GameData.player_data_library[ids[1]]
	# 以下只布置任意牌数的布局输入，不声称六牌属于普通出牌合法组。
	other.played_cards.append(ordinary_card("layout-other"))
	var third: Dictionary = GameData.player_data_library[ids[2]]
	third.played_cards.append(ordinary_card("layout-third"))
	accepted = RegularPlay.add(int(ids[0]), second, false)
	check(accepted and RegularPlay.completed(int(ids[0])), "public authority completes ordinary group with second card")
	if not accepted:
		finish()
		return
	board.refresh_all_ui()
	await get_tree().create_timer(0.4).timeout
	check(region.get_child_count() == 3, "three players who played cards yield three rows")
	if region.get_child_count() != 3:
		finish()
		return
	for ch in region.get_children():
		var rrow: Control = ch.get_node("Cards").get_node("Row")
		var meta_pid := int(ch.get_meta("player_id"))
		var pl: Dictionary = GameData.player_data_library[meta_pid]
		var owned: Array = pl.played_cards
		var matched := 0
		for card in owned:
			for cc in rrow.get_children():
				if board._held_action_card_id(cc.get_meta("card", null)) == board._held_action_card_id(card):
					matched += 1
					break
		check(matched == owned.size(), "row holds exactly the player's played cards (%d)" % owned.size())
		if rrow.get_child_count() >= 2:
			var seq_ok := true
			for idx in range(owned.size()):
				if idx < rrow.get_child_count() and board._held_action_card_id(rrow.get_child(idx).get_meta("card", null)) != board._held_action_card_id(owned[idx]):
					seq_ok = false
					break
			check(seq_ok, "row preserves engine order")
	var concealed_card = me.played_cards[0]
	concealed_card.set_concealed(true)
	board.refresh_all_ui()
	await get_tree().create_timer(0.4).timeout
	var me_group: Control = null
	for ch in region.get_children():
		if int(ch.get_meta("player_id")) == ids[0]:
			me_group = ch
			break
	check(me_group != null, "concealed player's group still exists")
	if me_group == null:
		finish()
		return
	var me_row: Control = me_group.get_node("Cards").get_node("Row")
	var concealed_slot: Control = null
	for cc in me_row.get_children():
		if board._held_action_card_id(cc.get_meta("card", null)) == board._held_action_card_id(concealed_card):
			concealed_slot = cc
			break
	check(concealed_slot != null, "concealed card has its slot")
	if concealed_slot == null:
		finish()
		return
	var img_node: TextureRect = concealed_slot.get_node("Img")
	var concealed_img_path := img_node.texture.resource_path if img_node.texture != null else ""
	var face_path := str(concealed_card.get("_card_img"))
	check(concealed_img_path != face_path, "concealed card does not show face image")
	concealed_evidence(board, concealed_slot, concealed_card, int(ids[0]), "first-concealed-bind")
	var seen_cards: Array = []
	for ch in region.get_children():
		for cc in ch.get_node("Cards").get_node("Row").get_children():
			check(not seen_cards.has(cc), "no card appears in two rows")
			seen_cards.append(cc)
	var many: Dictionary = GameData.player_data_library[ids[3]]
	for k in range(6):
		many.played_cards.append(ordinary_card("layout-many-%d" % k))
	board.refresh_all_ui()
	var settled: bool = await settle_presentation(board, region)
	check(region.get_child_count() == 4, "four rows after adding many-cards player")
	if region.get_child_count() != 4:
		finish()
		return
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
				if board._held_action_card_id(cc.get_meta("card", null)) == board._held_action_card_id(card):
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
	check(uniform and settled, "all displayed cards share a uniform width (%s)" % str(widths))
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
	var miyama_visible: bool = settled and await expand_and_verify(board, region, "miyama")
	check(miyama_visible, "miyama all ten cards including six-card group visibly separated after avatar GUI input")
	concealed_evidence(board, concealed_slot, concealed_card, int(ids[0]), "miyama-final")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		check(get_viewport().get_texture().get_image().save_png("res://tests/runtime_reports/battle_play_groups.png") == OK, "window four-group screenshot saved")
	var other_area := MapData.magic_workshop
	for pid in GameData.player_data_library.keys():
		SetLocation.new().exec(other_area._locations.filter(func(loc): return loc._pl_num_limit < 0)[0], int(pid), false, false, true, ctx)
	# 只刷新布局输入；卷轴选择由真实移动/点击入口触发，结束后不强制刷新。
	board.refresh_all_ui()
	var other_scroll: Control = board.get_node("Strips").get_child(MapData.areas.find(other_area))
	var other_region: Control = other_scroll.get_node("Main/Groups/List")
	var scroll_hit: bool = await gui_click(other_scroll.get_node("Col/Vertical").get_global_rect().get_center(), other_scroll, "destination-scroll")
	check(scroll_hit and board._main_area_index == MapData.areas.find(other_area), "destination scroll selected by real GUI motion and click")
	if not await acknowledge_tactical_alert(board, other_region):
		finish()
		return
	var destination_settled: bool = await settle_presentation(board, other_region)
	# 旧引用刻意核验玩家搬走后的旧区清空；另查新卷轴防止只测空区。
	check(region.get_child_count() == 0, "switching area clears old groups")
	check(other_region.get_child_count() == 4 and destination_settled, "destination area contains all four relocated groups")
	var workshop_visible: bool = destination_settled and await expand_and_verify(board, other_region, "workshop")
	check(workshop_visible, "workshop all ten cards including six-card group visibly separated after avatar GUI input")
	for group: Control in other_region.get_children():
		for slot: Control in group.get_node("Cards/Row").get_children():
			if board._held_action_card_id(slot.get_meta("card", null)) == board._held_action_card_id(concealed_card):
				concealed_evidence(board, slot, concealed_card, int(ids[0]), "workshop-final")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		check(get_viewport().get_texture().get_image().save_png("res://tests/runtime_reports/battle_play_groups_destination.png") == OK, "window destination screenshot saved")
	finish()


## 父组/祖先才是可见合同；叶节点alpha=1不能证明画到了屏幕上。
## 仅观察Tween、正式source刷新、真实裁切及几何收敛，不调用生产私有刷新。
func settle_presentation(board, region: Control, all_cards := false) -> bool:
	var strip: Control = region.get_parent().get_parent().get_parent()
	var completed_seq := -1
	var previous_geometry := ""
	var stable_frames := 0
	print("VISIBLE_FIRST ", JSON.stringify(presentation_state(board, region, all_cards)))
	for frame in range(600):
		await get_tree().process_frame
		var animating: bool = board._scroll_tween != null and board._scroll_tween.is_running()
		if not animating and float(strip.get_meta("open", 0.0)) >= 0.99 and completed_seq < 0:
			completed_seq = int(board._source.read_view().seq)
			print("SCROLL_COMPLETE ", JSON.stringify({"frame": frame, "seq": completed_seq, "strip": str(strip.get_path())}))
		var state := presentation_state(board, region, all_cards)
		var refreshed: bool = completed_seq >= 0 and int(state.seq) > completed_seq
		# 完成过渡后的正式绑定仍未shown：立即保留首个业务RED，不补等待或私有绑定。
		if refreshed and not bool(state.parents_shown):
			print("VISIBLE_ASSERTRED ", JSON.stringify(state))
			await failure_shot("parent-not-shown")
			return false
		var geometry: String = str(state.geometry)
		stable_frames = stable_frames + 1 if geometry == previous_geometry else 0
		previous_geometry = geometry
		if refreshed and bool(state.ready) and stable_frames >= 2:
			print("VISIBLE_COMPLETE ", JSON.stringify({"frames": frame, "post_transition_seq": completed_seq, "state": state}))
			return true
	print("VISIBLE_ASSERTRED ", JSON.stringify(presentation_state(board, region, all_cards)))
	await failure_shot("not-visible-or-clipped")
	return false


## self_modulate不传给子节点，modulate传给整条子树；裁切取viewport与所有clip祖先交集。
func visual_state(node: Control) -> Dictionary:
	var rect := node.get_global_rect()
	var clip := get_viewport().get_visible_rect()
	var alpha := node.self_modulate.a
	var chain: Array = []
	var ancestor: Node = node
	while ancestor != null:
		if ancestor is CanvasItem:
			alpha *= ancestor.modulate.a
			var material: Material = ancestor.material
			chain.append({"path": str(ancestor.get_path()), "visible": ancestor.visible, "modulate_alpha": ancestor.modulate.a,
				"modulate": str(ancestor.modulate), "self_modulate": str(ancestor.self_modulate),
				"use_parent_material": ancestor.use_parent_material, "material_class": material.get_class() if material != null else "",
				"material_path": material.resource_path if material != null else "",
				"shader_path": material.shader.resource_path if material is ShaderMaterial and material.shader != null else ""})
		if ancestor != node and ancestor is Control and ancestor.clip_contents:
			clip = clip.intersection(ancestor.get_global_rect())
		ancestor = ancestor.get_parent()
	return {"path": str(node.get_path()), "rect": str(rect), "clip": str(clip), "alpha": alpha,
		"visible_in_tree": node.is_visible_in_tree(), "contained": clip.grow(0.5).encloses(rect),
		"ok": node.is_visible_in_tree() and alpha >= 0.99 and rect.size.x > 0.0 and rect.size.y > 0.0 and clip.grow(0.5).encloses(rect), "chain": chain}


func presentation_state(board, region: Control, all_cards: bool) -> Dictionary:
	var strip: Control = region.get_parent().get_parent().get_parent()
	var blocking := visible_blocking_modals(board)
	var ready: bool = board.is_processing() and region.get_child_count() == 4 and board._main_area_index == strip.get_index()
	ready = ready and blocking.is_empty()
	ready = ready and float(strip.get_meta("open", 0.0)) >= 0.99 and board._fly_layer.get_child_count() == 0
	for queue in board._fly_queues.values():
		ready = ready and queue.is_empty()
	for busy in board._fly_busy.values():
		ready = ready and not bool(busy)
	var parents_shown: bool = region.get_child_count() == 4
	var groups: Array = []
	var geometry: Array = []
	var slots: Array[Control] = []
	for group: Control in region.get_children():
		var parent_state := visual_state(group)
		var shown := bool(group.get_meta("shown", false))
		parents_shown = parents_shown and shown and bool(parent_state.visible_in_tree) and float(parent_state.alpha) >= 0.99
		ready = ready and shown and bool(parent_state.ok) and bool(visual_state(group.get_node("Who/Avatar")).ok)
		var cards: Array = []
		var row: Control = group.get_node("Cards/Row")
		ready = ready and (not all_cards or row.get_child_count() <= 1 or bool(group.get_meta("expanded", false)))
		for slot: Control in row.get_children():
			var card_state := visual_state(slot.get_node("Img"))
			cards.append(card_state)
			slots.append(slot)
			ready = ready and slot.is_visible_in_tree() and bool(card_state.ok)
			geometry.append(str(slot.get_global_rect()))
		for child: Control in [group, group.get_node("Who"), group.get_node("Who/Avatar"), group.get_node("Cards")] + row.get_children():
			geometry.append(str(child.get_global_rect()))
			for key in child.get_meta_list():
				var value = child.get_meta(key)
				if value is Tween and value.is_valid() and value.is_running():
					ready = false
		groups.append({"pid": group.get_meta("player_id"), "shown": shown, "expanded": group.get_meta("expanded", false), "parent": parent_state, "cards": cards})
	if all_cards:
		ready = ready and slots.size() == 10 and region.get_children().any(func(g): return g.get_node("Cards/Row").get_child_count() == 6)
		for i in slots.size():
			var rect := slots[i].get_global_rect()
			for j in range(i + 1, slots.size()):
				ready = ready and not rect.intersects(slots[j].get_global_rect())
			for obstacle: Control in [board.get_node("Master"), strip.get_node("Seats/SeatScroll"), strip.get_node("Seats/MeleeScroll"), board.get_node("Hint")]:
				if obstacle.is_visible_in_tree() and float(visual_state(obstacle).alpha) > 0.01:
					ready = ready and not rect.intersects(obstacle.get_global_rect())
	return {"ready": ready, "blocking_modals": blocking, "parents_shown": parents_shown, "seq": board._source.read_view().seq,
		"processing": board.is_processing(), "active_strip": board._main_area_index, "strip": str(strip.get_path()),
		"open": strip.get_meta("open", 0.0), "fly_count": board._fly_layer.get_child_count(), "groups": groups, "geometry": geometry}


## 正式GUI分发：移动独立一帧，核验hover链与实际gui_input，不emit信号。
func gui_click(point: Vector2, receiver: Control, label: String) -> bool:
	var receipt := {"downs": 0}
	var observe := func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			receipt.downs += 1
	receiver.gui_input.connect(observe)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	motion.relative = Vector2(1, 0)
	get_viewport().push_input(motion, true)
	await get_tree().process_frame
	var hovered := get_viewport().gui_get_hovered_control()
	var hit: bool = hovered == receiver or (hovered != null and receiver.is_ancestor_of(hovered))
	var hover_path := str(hovered.get_path()) if hovered != null else "<none>"
	if hit:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = true
		get_viewport().push_input(event, true)
		event.pressed = false
		get_viewport().push_input(event, true)
	receiver.gui_input.disconnect(observe)
	print("GUI_CLICK ", JSON.stringify({"label": label, "point": str(point), "hover": hover_path, "hit": hit, "downs": receipt.downs}))
	return hit and int(receipt.downs) == 1


func expand_and_verify(board, region: Control, label: String) -> bool:
	for group: Control in region.get_children():
		if group.get_node("Cards/Row").get_child_count() <= 1:
			continue
		var hit: bool = await gui_click(group.get_node("Who/Avatar").get_global_rect().get_center(), group.get_node("Who"), label + "-avatar-" + str(group.get_meta("player_id")))
		check(hit and bool(group.get_meta("expanded", false)), label + " avatar GUI click really expands player " + str(group.get_meta("player_id")))
		if not hit or not bool(group.get_meta("expanded", false)):
			print("VISIBLE_ASSERTRED ", JSON.stringify(presentation_state(board, region, true)))
			await failure_shot(label + "-avatar-missed")
			return false
		if not await settle_presentation(board, region):
			return false
	# 移出头像避免tooltip遮牌；仍保持鼠标位于当前卷轴内，不改UI状态。
	var strip: Control = region.get_parent().get_parent().get_parent()
	var point := strip.get_global_rect().position + Vector2(strip.size.x * 0.5, 48)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	motion.relative = Vector2(1, 0)
	get_viewport().push_input(motion, true)
	return await settle_presentation(board, region, true)


## 全部正式ModalLayer子面板，并兼顾网络/身份/浏览器阻挡；不是只看叶槽alpha。
func visible_blocking_modals(board) -> Array:
	var candidates: Array = board.get_node("ModalLayer").get_children()
	for path in ["NetworkChoices/Panel", "NetworkChoices/ConnectionWait", "NetworkChoices/Guard", "IdentityInheritancePanel", "CardBrowser", "LogBrowser", "EventDiscardMenu"]:
		var node = board.get_node_or_null(path)
		if node != null:
			candidates.append(node)
	var visible: Array = []
	for node in candidates:
		if node is Control and node.is_visible_in_tree() and float(visual_state(node).alpha) > 0.01:
			visible.append(visual_state(node))
	for node in board.find_children("*", "Window", true, false):
		if node.visible:
			visible.append({"path": str(node.get_path()), "window_visible": true})
	return visible


## 只消费真实规则拒绝，不hide、不emit、不调用生产私有cancel。
func acknowledge_tactical_alert(board, region: Control) -> bool:
	var modal: Control = board.get_node("ModalLayer/TacticalConfirm")
	if not modal.is_visible_in_tree():
		print("TACTICAL_ALERT ", JSON.stringify({"appeared": false, "blocking_modals": visible_blocking_modals(board)}))
		return true
	await get_tree().process_frame
	var button: Button = modal.get_node("Box/ButtonsRow/BtnCancelAction")
	var before := presentation_state(board, region, false)
	print("TACTICAL_ALERT_BEFORE ", JSON.stringify({"description": modal.get_node("Box/ConfirmDesc").text, "button_text": button.text, "state": before}))
	check(not before.ready and not before.blocking_modals.is_empty() and button.text == "知道了", "visible tactical rejection is detected as blocking before acknowledgement")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tests/runtime_reports/round68-tactical-before.png")
	# 只观察原目标区；不能在关闭后重新选区来掩盖底层悬停切图。
	var target_index: int = board._main_area_index
	var receipt := {"pressed": 0, "motion_index": -1}
	var observe_motion := func(event: InputEvent):
		if event is InputEventMouseMotion:
			receipt.motion_index = board._main_area_index
	button.gui_input.connect(observe_motion)
	var observe := func(): receipt.pressed += 1
	button.pressed.connect(observe)
	var hit := false
	if button.text == "知道了":
		hit = await gui_click(button.get_global_rect().get_center(), button, "tactical-acknowledge")
	button.pressed.disconnect(observe)
	button.gui_input.disconnect(observe_motion)
	if DisplayServer.get_name() != "headless":
		check(int(receipt.motion_index) == target_index, "modal acknowledge GUI motion keeps original destination area")
	for frame in 600:
		await get_tree().process_frame
		if not modal.is_visible_in_tree():
			break
	var dismissed: bool = hit and int(receipt.pressed) == 1 and not modal.is_visible_in_tree()
	check(dismissed, "existing acknowledge button GUI press dismisses tactical rejection")
	if DisplayServer.get_name() != "headless":
		check(board._main_area_index == target_index, "modal pressed close keeps original destination without reselection")
	print("TACTICAL_ALERT_AFTER ", JSON.stringify({"hit": hit, "pressed": receipt.pressed, "visible": modal.is_visible_in_tree(), "blocking_modals": visible_blocking_modals(board), "target_index": target_index, "active_strip": board._main_area_index, "motion_index": receipt.motion_index}))
	return dismissed


## known-object仅在本地fixture对照；绝不写进网络视图或传输对象。
func concealed_evidence(board, slot: Control, known: BaseCard, pid: int, label: String) -> void:
	var view: Dictionary = board._source.read_view()
	var player := projected_player(board, pid)
	var projected: Dictionary = {}
	for card: Dictionary in player.get("played_cards", []):
		if card.get("id") == board._held_action_card_id(known):
			projected = card
	var image: TextureRect = slot.get_node("Img")
	var overlays: Array = []
	for child in slot.find_children("*", "Control", true, false):
		if child != image:
			var detail := visual_state(child)
			if child is ColorRect:
				detail["color"] = str(child.color)
			overlays.append(detail)
	var local_known: Dictionary = {}
	if board._source_is_local and board.network_session == null:
		local_known = {"scope": "local_fixture_only_not_network", "concealed": known._is_concealed, "declared_back_image": known._card_back_img, "face_matches_texture": image.texture != null and image.texture.resource_path == str(known._card_img)}
	var textured: bool = image.texture != null and not image.texture.resource_path.is_empty()
	print("CONCEALED_EVIDENCE ", JSON.stringify({"label": label, "source_local": board._source_is_local, "observer": view.get("observer"), "owner_id": pid,
		"own": player.get("own"), "visible": projected.get("visible"), "concealed": projected.get("concealed"), "back_image": projected.get("back_image"),
		"projected_keys": projected.keys(), "texture_nonempty": image.texture != null, "texture_resource_path": image.texture.resource_path if image.texture != null else "",
		"image": visual_state(image), "overlays": overlays, "known_object": local_known}))
	# 用户已确认所有牌使用自身声明背面；不把非face或null纹理当通过。
	var declared_back: String = str(projected.get("back_image", ""))
	var actual_back: String = image.texture.resource_path if image.texture != null else ""
	var declared_texture: Texture2D = load(declared_back) if not declared_back.is_empty() else null
	var passed: bool = textured and declared_texture != null and actual_back == declared_texture.resource_path and actual_back == declared_back and actual_back != known._card_img
	print("VISUAL_GATE ", JSON.stringify({"label": label, "passed": passed, "source_back_image": declared_back, "texture_resource_path": actual_back, "face_hidden": actual_back != known._card_img, "status": "declared_back_exact_native_review_required" if passed else "FAIL_declared_back_texture_contract"}))


func failure_shot(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var path := "res://tests/runtime_reports/round68-first-red.png"
	if FileAccess.file_exists(path):
		return
	await RenderingServer.frame_post_draw
	print("FIRST_RED_SCREENSHOT ", label, " status=", get_viewport().get_texture().get_image().save_png(path))


func ordinary_card(label: String) -> BaseAttack:
	var card := BaseAttack.new(label, "res://data/attacks/basic/luck/luck.png", [], BaseNumber.new(0), BaseNumber.new(1), [])
	card._card_back_img = "res://data/card_backs/attack_card_back.png"
	card._zoom_kind = "card"
	return card


func projected_player(board, pid: int) -> Dictionary:
	for entry in board._source.read_view().get("players", []):
		if entry.id == pid:
			return entry
	return {}


func first_evidence(board, area: BaseMapArea, card: BaseCard, pid: int, region: Control) -> void:
	var view: Dictionary = board._source.read_view()
	var projected: Dictionary = {}
	for entry in view.get("players", []):
		if entry.id == pid:
			projected = entry
	var index := MapData.areas.find(area)
	var occupants: Array = []
	for location in view.areas[index].locations:
		occupants.append_array(location.players)
	var effects: Array = []
	for effect in card._effects:
		effects.append({"residue": effect._is_residue})
	print("FIRST_EVIDENCE ", JSON.stringify({"card_id": board._held_action_card_id(card),
		"effects": effects, "closed": card._is_closed, "concealed": card._is_concealed,
		"game_played": GameData.player_data_library[pid].played_cards.map(func(c): return board._held_action_card_id(c)),
		"game_occupants": GameData.player_data_library[pid].location._players,
		"source_occupants": occupants, "source_player": {"id": projected.get("id"), "location": projected.get("location"), "played_cards": projected.get("played_cards", []), "residue_cards": projected.get("residue_cards", [])},
		"source_local": board._source_is_local, "seq": view.seq, "group_count": region.get_child_count()}))


func finish() -> void:
	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
