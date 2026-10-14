extends "res://newtests/round74_shared_out_of_game_test.gd"
## 仅复用创建、认证、输入、截图工具；不执行93/78或此前完整检查组。

func layer_fact(node: CanvasItem) -> Dictionary:
	var ancestors: Array = []
	var parent := node.get_parent()
	while parent != null:
		if parent is CanvasLayer: ancestors.append({"name":parent.name,"layer":parent.layer})
		parent = parent.get_parent()
	return {"path":str(node.get_path()),"z":node.z_index,"relative":node.z_as_relative,"top_level":node.is_set_as_top_level(),"canvas_layers":ancestors,"visible":node.is_visible_in_tree(),"alpha":node.modulate.a}

func inspect_layers(label: String) -> void:
	var browser: Control = board.get_node("CardBrowser")
	var banner: Control = board.get_node("Banner")
	var phase: Control = board._phase_banner_node()
	print("LAYER_FACT ", JSON.stringify({"label":label,"banner":layer_fact(banner),"phase":layer_fact(phase),"browser":layer_fact(browser),"modal_visible":board._native_modal_visible()}))
	check(not banner.is_set_as_top_level() and not browser.is_set_as_top_level(), label + " 横幅浏览器非top_level")
	check(layer_fact(banner).canvas_layers.is_empty() and layer_fact(browser).canvas_layers.is_empty(), label + " 同主画布无CanvasLayer")
	check(board.ROUND_LIFTED_Z < board.BANNER_Z and board.BANNER_Z < browser.z_index, label + " 顺位动画<横幅<浏览器")
	check(phase.z_index < browser.z_index and browser.z_index < board.get_node("BattleBroadcast").z_index, label + " 阶段提示<浏览器<原播报")
	check(not board._modal_blockers.has(browser), label + " 浏览器不加入悬浮阻断名单")

func shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	check(image.save_png("res://tests/runtime_reports/round75-" + label + ".png") == OK, label + " 原生viewport截图")

func current_banner() -> bool:
	var id: int = GameProgress.current_player_id
	var text: String = board.get_node("Banner/Text").text
	var expected: String = "%s 的行动" % ("我方" if id == board._local_player_id else board._player_name(id))
	return id >= 0 and text == expected

func banner_opaque() -> bool:
	return board._banner.visible and board._banner.modulate.a > 0.95 and current_banner()

func window_settle() -> void:
	## 不强refresh；仅等正式process/source及生产动画完成。
	check(await window_wait(func(): return not board._is_progress_blocked() and (board._scroll_tween == null or not board._scroll_tween.is_running())), "正式过场自然完成 %d" % checks)
	await get_tree().process_frame
	await get_tree().process_frame

func open_gui(label: String) -> void:
	check(await window_click("ModalLayer/OpponentDrawer/VBox/BtnOutOfGame", label + "-open"), label + " 正式浏览按钮mouse/pressed")
	check(board.get_node("CardBrowser").is_visible_in_tree(), label + " 浏览器打开")

func close_gui(label: String) -> void:
	check(await window_click("CardBrowser/Panel/Close", label + "-close"), label + " 正式关闭mouse/pressed")
	check(not board.get_node("CardBrowser").visible, label + " 浏览器关闭")

func gui_removed(pid: int, label: String) -> void:
	var target := drawer_target(pid)
	check(target != null, label + " 正式玩家入口存在")
	if target == null: return
	check(await window_click(str(board.get_path_to(target)), label + "-drawer"), label + " 正式玩家入口mouse命中")
	check(board._opponent_drawer.visible and board._selected_opponent_id == pid, label + " 抽屉打开")
	inspect_layers(label)
	if host != null:
		var before := state(true)
		var sequences: Array = [host._seq, guest._seq]
		await open_gui(label)
		expect_removed(selected_cards(board._source.read_view(), pid), label)
		await shot(label + "-open")
		var slots: Array = board.get_node("CardBrowser/Panel/CardScroll/Row").get_children()
		for slot in slots:
			var card: Dictionary = slot.get_meta("card")
			if card.get("concealed", true) or not card.get("visible", false):
				await window_motion(slot.get_global_rect().get_center(), label + "-hidden")
				window_button(slot.get_global_rect().get_center(), MOUSE_BUTTON_RIGHT, label + "-hidden-right")
				check(not board._hover_zoom.visible and not board._hover_desc.visible, label + " 原卡背guard无回归")
				break
		await close_gui(label)
		check(state(true) == before and [host._seq, guest._seq] == sequences, label + " 无规则变化/网络命令")
		return

	## 真实本地规则公开推进入口产生横幅；不直接show、不停process、不写actor/phase。
	check(GameProgress.can_end_current_player_action(), "当前正式阶段允许结束")
	check(GameProgress.end_current_player_action(), "公开结束行动产生下一actor")
	check(await window_wait(banner_opaque), "当前行动横幅自然淡入")
	var before := state(true)
	await shot("local-before")
	await open_gui("local-stable")
	check(board._banner.visible and current_banner(), "浏览期间不隐藏/替换行动提示")
	inspect_layers("local-stable-open")
	await shot("local-stable-open")
	await close_gui("local-stable")
	check(board._banner.visible and current_banner(), "关闭揭示仍有效当前提示")
	await shot("local-stable-close")
	check(state(true) == before, "浏览开关无规则变化")

	await open_gui("local-actor-change")
	var old_actor: int = GameProgress.current_player_id
	var old_text: String = board.get_node("Banner/Text").text
	check(GameProgress.can_end_current_player_action() and GameProgress.end_current_player_action(), "浏览期间公开推进actor")
	check(GameProgress.current_player_id != old_actor, "规则真实换actor")
	check(await window_wait(banner_opaque), "正式process换成新actor横幅")
	check(board.get_node("Banner/Text").text != old_text, "旧actor文案已失效")
	await shot("local-actor-change-open")
	await close_gui("local-actor-change")
	check(board._banner.visible and current_banner(), "关闭没有恢复旧actor")
	await shot("local-actor-change-close")

	await open_gui("local-phase-change")
	var old_phase: int = GameProgress.current_phase_index
	var steps := 0
	while GameProgress.current_phase_index == old_phase and steps < GameData.player_data_library.size() + 1:
		check(GameProgress.can_end_current_player_action() and GameProgress.end_current_player_action(), "公开推进至阶段边界%d" % steps)
		steps += 1
		await get_tree().process_frame
	check(GameProgress.current_phase_index != old_phase, "浏览期间真实换phase")
	check(await window_wait(func(): return board._phase_anim_busy and board._phase_banner != null and board._phase_banner.modulate.a > 0.95), "当前阶段横幅自然淡入")
	check(board._phase_banner.z_index < board.get_node("CardBrowser").z_index, "phase横幅也在浏览器下")
	await shot("local-phase-change-open")
	check(await window_wait(func(): return not board._phase_anim_busy and banner_opaque()), "阶段完成回调读取当前actor")
	await close_gui("local-phase-change")
	check(board._banner.visible and current_banner(), "换phase后关闭揭示当前actor非旧提示")
	await shot("local-phase-change-close")

	await open_gui("local-expired")
	check(await window_wait(func(): return not board._banner.visible), "浏览期间原提示自然过期")
	await close_gui("local-expired")
	check(not board._banner.visible, "关闭不盲show过期横幅")
	await shot("local-expired-close")

func run() -> void:
	GameStart.reset()
	board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	add_child(board)
	for pid in GameData.player_data_library: board._seat_controller.set_kind(int(pid), SeatController.REMOTE)
	inspect_layers("headless-local")
	var browser: Control = board.get_node("CardBrowser")
	var before := state(true)
	board._show_card_browser("层级专项", [])
	check(browser.visible and not board._native_modal_visible(), "只读浏览show不改变modal guard")
	board._close_card_browser()
	check(not browser.visible and state(true) == before, "close不改变规则")
	board.queue_free()
	await get_tree().process_frame
	board = null
	await finish()
