extends Node

var failures: Array = []
var checks := 0
var ui
const PODIUM := "Bottom_PlayerDock/TacticalDeskLayout/Section_CommandPodium/VBox/UpperRow/ServantCardBox/Label"
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
	print("CHECK ", label, " ", ok)
func _ready() -> void:
	call_deferred("run")
## 真实鼠标点击：按下 + 释放都派发到 Window 级（get_viewport().push_input 不走完整 GUI 派发链，
## gui_input 收不到，会得出"链路不通"的错误结论）。
func _click_control(ctrl: Control) -> void:
	if ctrl == null or not ctrl.is_visible_in_tree():
		return
	# 先等布局完成再取矩形：Container 的布局下一帧才更新，刚填充完面板就取 rect
	# 会拿到旧位置，点击坐标随之偏掉（落到面板空白处，还会被当成拖动起点）
	await frames(2)
	if ctrl == null or not ctrl.is_visible_in_tree():
		return
	var pos: Vector2 = ctrl.get_global_rect().get_center()
	# 先把指针挪到目标上并等一帧：Viewport 的 GUI 命中测试读的是当前鼠标位置，
	# 只 push_input 而不改鼠标位置时，命中的仍是上一次的位置（点击会落到别的控件上）
	Input.warp_mouse(pos)
	await frames(1)
	_push_mouse_button(pos, true)
	_push_mouse_button(pos, false)
	await frames(1)


func _push_mouse_button(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	get_tree().root.push_input(ev, true)


func frames(n := 3) -> void:
	for i in range(n): await get_tree().process_frame
func slot_for(pid: int) -> Control:
	for c in ui.get_node(ui.ORDER_BOX_PATH).get_children():
		if c is Control and int(c.get_meta("turn_order_player_id", -1)) == pid: return c
	return null
func check_prompt_geometry(prompt: Control, slot: Control, label: String) -> void:
	var bounds: Rect2 = ui.get_viewport_rect()
	var target := slot.get_global_rect()
	var rect := prompt.get_global_rect()
	var expected_x := clampf(target.get_center().x - rect.size.x * 0.5, bounds.position.x, maxf(bounds.position.x, bounds.end.x - rect.size.x))
	print("GEOMETRY ", label, " viewport=", bounds, " target=", target, " prompt=", rect)
	check(absf(rect.position.x - expected_x) < 1.0, label)
	check(bounds.encloses(rect), label + " stays inside viewport")
func run() -> void:
	ui = load("res://assets/scenes/game_scene/tactical_board_ui.tscn").instantiate()
	add_child(ui)
	ui.set_process(false)
	GameProgress.is_game_over = true
	EffectManager.reset_runtime()
	GameLog.reset()
	await frames()
	var ids: Array = GameData.player_data_library.keys()
	ids.erase(ui._local_player_id)
	var pid: int = -1
	ui.refresh_all_ui()
	await frames()
	var spell_scroll := ui.get_node_or_null("Bottom_PlayerDock/TacticalDeskLayout/Section_CommandPodium/VBox/LowerCommandSpellRow/InfoV/DescScroll") as ScrollContainer
	if spell_scroll != null:
		var spell_desc := spell_scroll.get_node_or_null("Desc") as Label
		print("SPELL_LAYOUT scroll=", spell_scroll.get_global_rect(), " desc=", spell_desc.get_global_rect() if spell_desc != null else "missing", " limit=", spell_scroll.get_v_scroll_bar().max_value)
	check(spell_scroll != null and spell_scroll.size.y > 0 and spell_scroll.size.y < 60, "command spell description stays within a fixed-height viewport")
	check(spell_scroll != null and spell_scroll.get_v_scroll_bar().max_value > spell_scroll.size.y, "command spell full text can scroll")
	check(spell_scroll != null and spell_scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_SHOW_NEVER,
		"command spell scrollbar is structurally hidden")
	check(spell_scroll != null and not spell_scroll.get_v_scroll_bar().visible,
		"command spell scrollbar is not visible")
	if spell_scroll != null:
		spell_scroll.scroll_vertical = 10
		await frames(1)
		check(spell_scroll.scroll_vertical > 0, "hidden command spell scrollbar still allows scrolling")
	var report_fact := {"type":"effect", "actor":0, "round":1, "phase":"action",
		"data":{"applied":true, "shown_effect":"具体效果文案", "source_name":"来源卡",
		"trigger_time_points":[TimePoints.SELF_ACTION_PHASE]}}
	var report_line: String = ui._format_game_log_line(report_fact)
	check(report_line.contains("来源卡") and report_line.contains("具体效果文案") and report_line.contains("行动阶段"),
		"player report identifies trigger, source and concrete effect")
	report_fact.data.applied=false
	check(ui._format_game_log_line(report_fact)=="", "unapplied effect is absent from player report")
	check(ui._format_game_log_line({"type":"time_point", "round":1})=="", "internal timepoint stays out of player report")
	var secret_draw := BaseAttack.new("secret_hidden_draw", "", [], BaseNumber.new(0), BaseNumber.new(1))
	var draw_line: String = ui._format_game_log_line({"type":"draw", "actor":0, "round":1, "phase":"prepare", "object":secret_draw})
	check(draw_line.contains("抽牌") and not draw_line.contains("secret_hidden_draw"),
		"player report never reveals the drawn card")
	var viewport: Rect2 = ui.get_viewport_rect()
	for id in ids:
		var candidate := slot_for(int(id))
		if candidate != null and viewport.encloses(candidate.get_global_rect()) and candidate.get_global_rect().get_center().x > 150:
			pid = int(id)
			break
	check(pid >= 0, "real visible opponent selected")
	var data: Dictionary = GameDataManager.get_player_data(pid)
	GameProgress.current_player_id = pid
	ui.refresh_all_ui()
	await frames()
	var card = BaseAttack.new("prompt", "", [], BaseNumber.new(0), BaseNumber.new(1))
	data.played_cards = [card]
	ui._set_ai_play_prompt(pid, card)
	await frames()
	var prompt: Control = ui._ai_play_prompt_node
	var slot: Control = slot_for(pid)
	check(prompt != null and prompt.visible, "AI play immediately schedules its visible prompt without a later full refresh")
	# RED 阶段仍让后续几何断言继续执行；生产修复后不会进入这个兼容分支。
	if prompt == null:
		ui._refresh_ai_play_prompt()
		await frames()
		prompt = ui._ai_play_prompt_node
	print("GEOMETRY initial viewport=", ui.get_viewport_rect(), " ui=", ui.get_global_rect(), " slot=", slot.get_global_rect(), " prompt=", prompt.get_global_rect())
	check(prompt.visible, "prompt visible")
	check_prompt_geometry(prompt, slot, "prompt centered on player")
	var scroll: ScrollContainer = ui.get_node("TopPanel_AllPlayers/AllPlayersOrderScroll")
	var old_min := scroll.custom_minimum_size
	scroll.custom_minimum_size.x = 0
	scroll.size.x = 700
	var order_box: Control = ui.get_node(ui.ORDER_BOX_PATH)
	var old_order_min := order_box.custom_minimum_size
	order_box.custom_minimum_size.x = 2500
	await frames()
	scroll.scroll_horizontal = 80
	await frames()
	check(scroll.scroll_horizontal == 80, "scroll actually moved")
	ui._process(0.0)
	check_prompt_geometry(prompt, slot, "prompt follows scroll without content refresh")
	var old_scale := slot.scale
	slot.scale = Vector2(0.7, 0.8)
	ui._update_ai_play_prompt_geometry()
	check_prompt_geometry(prompt, slot, "prompt follows scaled target")
	check(prompt.get_global_rect().position.y <= slot.get_global_rect().position.y, "prompt stays above the battlefield title strip")
	slot.scale = old_scale
	slot.hide()
	ui._process(0.0)
	check(not prompt.visible, "hidden target hides prompt")
	slot.show()
	ui._update_ai_play_prompt_geometry()
	check(prompt.visible, "shown target restores prompt without refresh")
	var old_position := slot.position
	slot.global_position.x = scroll.get_global_rect().end.x + 20
	ui._update_ai_play_prompt_geometry()
	check(not prompt.visible, "fully clipped target hides prompt")
	slot.position = old_position
	ui._update_ai_play_prompt_geometry()
	check(prompt.visible, "unclipped target restores prompt without refresh")
	slot.global_position.x = 0
	ui._update_ai_play_prompt_geometry()
	check_prompt_geometry(prompt, slot, "left edge clamp")
	slot.position = old_position
	ui._update_ai_play_prompt_geometry()
	if DisplayServer.get_name() != "headless":
		scroll.scroll_horizontal = 0
		await frames()
		ui._update_ai_play_prompt_geometry()
		check_prompt_geometry(prompt, slot, "rendered prompt alignment")
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tests/reported_ui_prompt.png")
	scroll.scroll_horizontal = 0
	scroll.custom_minimum_size = old_min
	order_box.custom_minimum_size = old_order_min
	ui.refresh_all_ui()
	await frames()
	ui._update_drawer_visuals(slot_for(pid))
	ui.opponent_drawer.show()
	var servant: TextureRect = ui.opponent_drawer.get_node("VBox/CardsContentRow/Col_MasterServant/CardsH/ServantCard")
	data.servant_skills = []
	ui._update_drawer_visuals(slot_for(pid))
	check(bool(servant.get_meta("zoom_disabled", false)), "empty skills do not reveal servant")
	var skill = BaseSkill.new("visible skill", "", [])
	skill._is_concealed = false
	data.servant_skills = [skill]
	ui._update_drawer_visuals(slot_for(pid))
	check(bool(servant.get_meta("zoom_disabled", false)), "face-up skill does not imply release")
	ReleaseTrueName.new().exec(pid)
	ui.refresh_all_ui()
	check(not bool(servant.get_meta("zoom_disabled", true)), "open drawer refreshes release")
	var hint: Label = ui.opponent_drawer.get_node("VBox/HeaderBar/IdentityHint")
	check(hint.text == "真名解放", "drawer release label")
	check(hint.get_theme_color("font_color") == Color(1.0, 0.84, 0.3), "drawer release gold")
	var top: Label = slot_for(pid).get_node_or_null("HBox/Info/TrueNameStatus")
	check(top != null and top.text == "真名解放", "top release label")
	ReleaseTrueName.new().exec(ui._local_player_id)
	ui.refresh_all_ui()
	check(ui.get_node(PODIUM).text.contains("真名解放"), "local release label")
	# Force the old slot to represent another player; refresh must retain the selected ID.
	var original: Control = slot_for(pid)
	original.set_meta("turn_order_player_id", int(ids[0]))
	ui.refresh_all_ui()
	check(str(ui._selected_opponent_id) == str(pid), "drawer stores stable player identity")
	check(hint.text == "真名解放", "drawer does not switch player after slot rebind")
	HideTrueName.new().exec(pid)
	HideTrueName.new().exec(ui._local_player_id)
	ui.refresh_all_ui()
	check(bool(servant.get_meta("zoom_disabled", false)) and hint.text == "真名未解放", "hide refreshes open drawer")
	check(hint.get_theme_color("font_color") == Color(0.6, 0.64, 0.7), "hidden status gray")
	check(ui.get_node(PODIUM).text.contains("真名未解放"), "local hidden label")
	ui.opponent_drawer.hide()
	var detail := {"players": ids, "effective_players": ids, "winners": ids, "is_draw": true, "highest_power": 12, "score_gained": {}}
	for id in ids: detail.score_gained[id] = 2
	var report := {"details_by_area": {"A": detail, "B": detail, "C": detail, "D": detail}}
	ui._show_battle_report(report)
	ui._show_battle_report(report)
	var backdrop:ColorRect = ui._battle_report_backdrop
	check(backdrop != null and backdrop.visible, "report backdrop is visible")
	check(backdrop.z_index < ui.battle_report_modal.z_index and backdrop.z_index >= 25, "report backdrop is between board and report")
	ui._on_close_battle_report()
	check(not ui.battle_report_modal.visible and not backdrop.visible, "closing report hides backdrop")
	ui._show_battle_report(report)
	# 右侧常驻入口的命中顺序：Godot 按场景树子节点倒序测试，按钮必须排在它压住的战区之后，
	# 否则点击先落到侦察战区，按钮永远收不到（z_index 只管绘制，救不了命中）
	var entry := ui.get_node_or_null("BtnBattleReport") as Button
	var playground: Node = ui.get_node_or_null("Middle_MainPlayground")
	check(entry != null and playground != null and entry.get_index() > playground.get_index(), "report entry is hit-tested after the board")
	# 入口按钮要在战报关闭时点：遮罩可见时它是被模态屏蔽的对象，不能拿来判入口是否可用
	ui._on_close_battle_report()
	var entry_clicked := [false]
	if entry != null:
		entry.pressed.connect(func(): entry_clicked[0] = true)
	var blocked_clicked := [false]
	var scout: Node = ui.get_node_or_null("Middle_MainPlayground/Battlefields_CenterContainer/Area_Scout")
	if scout != null:
		scout.gui_input.connect(func(_ev): blocked_clicked[0] = true)
	await _click_control(entry)
	check(entry_clicked[0], "report entry receives a real click")
	check(not blocked_clicked[0], "clicking the report entry does not reach the scout area")
	# 关闭按钮：按在按钮上不能启动拖动——启动了面板就跟着手抖位移，
	# 释放时指针已在按钮外、pressed 不发出（按钮看起来点不了，面板还漏出下层）
	ui._show_battle_report(report)
	var close_btn := ui.battle_report_modal.get_node_or_null("Box/VBox/BtnCloseReport") as Button
	var offset_before := Vector2(ui.battle_report_modal.offset_left, ui.battle_report_modal.offset_top)
	await _click_control(close_btn)
	check(not ui.battle_report_modal.visible, "close button click closes the report")
	check(Vector2(ui.battle_report_modal.offset_left, ui.battle_report_modal.offset_top) == offset_before, "clicking the close button does not drag the report")

	# 回归验证：战报作为对局日志查看器，没有战斗结算时打开也能展示历史日志
	ui._show_battle_report({}, true)
	check(ui.battle_report_modal.visible, "battle report modal opens for game logs")
	var log_list: VBoxContainer = ui.battle_report_modal.get_node("Box/VBox/ReportScroll/ReportList")
	check(log_list.get_child_count() > 0, "battle report log list contains log rows")
	ui._on_close_battle_report()

	# 回归验证：即时威力浮层
	var total_pw_lbl: Label = ui.total_power_label
	check(total_pw_lbl != null and total_pw_lbl.has_meta("instant_power_bound"), "total power label has instant power tooltip bound")
	if total_pw_lbl != null:
		total_pw_lbl.emit_signal("mouse_entered")
		var pw_panel := ui.get_node_or_null("InstantPowerTooltipPanel") as PanelContainer
		check(pw_panel != null and pw_panel.visible, "instant power tooltip panel appears immediately on mouse enter")
		var pw_desc := pw_panel.get_node_or_null("VBox/Desc") as Label
		check(pw_desc != null and pw_desc.text != "", "instant power tooltip has breakdown text")
		total_pw_lbl.emit_signal("mouse_exited")
		check(not pw_panel.visible, "instant power tooltip hides on mouse exit")

	# 回归验证：卡牌被修改后显示【改】字持久提示
	var test_atk := BaseAttack.new("测试攻击", "quick.png", ["quick"], BaseNumber.new(3), BaseNumber.new(6))
	EditCardCost.new().exec(BaseNumber.new(2), null, test_atk)
	check(test_atk.has_modifications(), "card records cost modification")
	var test_slot := TextureRect.new()
	ui._render_card_face(test_slot, test_atk, true)
	var badge = test_slot.get_node_or_null("CardModificationBadge")
	check(badge != null and badge.visible, "card modification badge appears on modified card")
	test_slot.queue_free()

	# 回归验证：令咒移动不能移到魔术工房与侦察的无限格
	var scout_area = MapData.scout
	var workshop_area = MapData.magic_workshop
	var scout_loc = ui._first_effect_location_target(scout_area, {"target_slot": "unlimited"})
	check(scout_loc == null or scout_loc._pl_num_limit != -1, "command spell move cannot target unlimited slot in scout")
	var ws_loc = ui._first_effect_location_target(workshop_area, {"target_slot": "unlimited"})
	check(ws_loc == null or ws_loc._pl_num_limit != -1, "command spell move cannot target unlimited slot in workshop")

	# 回归验证：出牌区撤销按钮不再出现（改为左键点击出牌区的牌直接回手）
	var undo_btn := ui.get_node_or_null("Bottom_PlayerDock/TacticalDeskLayout/Section_PlayBattleZone/VBox/ZoneHeader/BtnUndoRegularPlay") as Button
	ui.refresh_all_ui()
	check(undo_btn != null and not undo_btn.visible, "undo selection button stays hidden")

	# 回归验证：不可见的卡位不会弹出放大图（"突然蹦出大图挡住UI"的守卫）
	var hidden_card := TextureRect.new()
	hidden_card.texture = ImageTexture.create_from_image(Image.create(8, 8, false, Image.FORMAT_RGBA8))
	hidden_card.visible = false
	ui.add_child(hidden_card)
	ui._on_zoom_card_entered(hidden_card)
	check(ui.event_zoom_preview == null or not ui.event_zoom_preview.visible, "an invisible card never pops the zoom preview")
	hidden_card.queue_free()

	# 回归验证：被弹窗覆盖时不弹放大图（同一守卫的另一半）。
	# 守卫读的是真实鼠标位置，而 headless 下 Input.warp_mouse 不生效，
	# 所以"鼠标确实压在弹窗上"这个场景只在非 headless 窗口里验；
	# headless 下先验守卫依赖的那半个判据本身成立
	ui._show_battle_report({}, true)
	await frames(2)
	var modal_center: Vector2 = ui.battle_report_modal.get_global_rect().get_center()
	var probe_card := TextureRect.new()
	probe_card.texture = ImageTexture.create_from_image(Image.create(8, 8, false, Image.FORMAT_RGBA8))
	probe_card.size = Vector2(40, 40)
	ui.add_child(probe_card)
	probe_card.global_position = modal_center - Vector2(20, 20)
	await frames(1)
	check(ui._is_mouse_covered_by_modal(modal_center, probe_card), "an open modal covers the cards underneath")
	if DisplayServer.get_name() != "headless":
		Input.warp_mouse(modal_center)
		await frames(1)
		ui._on_zoom_card_entered(probe_card)
		check(not ui.event_zoom_preview.visible, "a covered card never pops the zoom preview")
	probe_card.queue_free()
	ui._on_close_battle_report()

	# 回归验证：技能卡位不可出时金框必须立刻收回（否则会留到下一个阶段还亮着）
	var skill_slot := TextureRect.new()
	ui.add_child(skill_slot)
	ui._apply_clickable_indicator(skill_slot, Color(1.0, 0.85, 0.3, 1.0))
	var unplayable := BaseSkill.new("不可出技能", "", [], BaseNumber.new(1), BaseNumber.new(0))
	ui._fill_skill_slot(skill_slot, unplayable, true, true)
	var skill_glow := skill_slot.get_node_or_null("ClickableGlow") as Control
	check(skill_glow == null or not skill_glow.visible, "skill slot glow is withdrawn as soon as the skill is unplayable")
	skill_slot.queue_free()

	# 回归验证：卡位是"卡图 + 牌名"的容器时，金框只圈卡图，不把下面的牌名一起圈进去
	var card_box := VBoxContainer.new()
	card_box.position = Vector2(360, 240)
	card_box.size = Vector2(110, 175)
	var box_art := TextureRect.new()
	box_art.name = "Tex"
	box_art.custom_minimum_size = Vector2(110, 155)
	box_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card_box.add_child(box_art)
	var box_name := Label.new()
	box_name.name = "Lbl"
	box_name.text = "牌名不该在框里"
	box_name.custom_minimum_size = Vector2(0, 18)
	card_box.add_child(box_name)
	ui.add_child(card_box)
	await frames(1)
	ui._apply_clickable_indicator(card_box, Color(1.0, 0.85, 0.3, 1.0), ui._card_art_of(card_box))
	check(card_box.get_node_or_null("ClickableGlow") == null, "the frame is not drawn around the whole card slot")
	var box_glow := box_art.get_node_or_null("ClickableGlow") as Control
	check(box_glow != null, "the frame is drawn around the card art layer")
	if box_glow != null and box_art.global_position.y > 0.0 and box_name.global_position.y > box_art.global_position.y:
		var frame_bottom: float = box_glow.global_position.y + box_glow.size.y
		check(frame_bottom <= box_name.global_position.y + 1.0, "the frame stops above the card name label")
	# 节流扫描是按卡位再调一次的：不能因此在卡位里长出第二个框
	ui._apply_clickable_indicator(card_box, Color(1.0, 0.85, 0.3, 1.0))
	check(box_art.get_child_count() == 1 and card_box.get_node_or_null("ClickableGlow") == null,
		"the scan pass reuses the existing frame instead of adding a second one")
	# 收回金框仍然按卡位生效（宿主记在卡位上，不是卡图上）
	ui._set_clickable_active(card_box, false)
	check(box_glow != null and not box_glow.visible, "the frame on the card art is still withdrawn from the slot")
	card_box.queue_free()

	# 真实技能区卡位（场景节点 Sk1 = VBox{Tex, Lbl}）也必须解析出卡图层：
	# 解析不出就会静默退回"框满整个卡位"，牌名又被圈进去（正是这次要修的表现）
	var real_slot := ui.get_node_or_null(
		"Bottom_PlayerDock/TacticalDeskLayout/Section_SkillsAndPhantasms/VBox/CardsScroll/H/Sk1") as Control
	check(real_slot != null, "the skill rack slot is present in the scene")
	if real_slot != null:
		var real_art: Control = ui._card_art_of(real_slot)
		check(real_art != null and str(real_art.name) == "Tex", "the real skill rack slot resolves its card art layer")
		# 真实卡位上走一遍：金框落在卡图层，卡位本身没有框，牌名标签不在框里
		ui._apply_clickable_indicator(real_slot, Color(1.0, 0.85, 0.3, 1.0), real_art)
		check(real_slot.get_node_or_null("ClickableGlow") == null, "the real skill slot is not framed as a whole")
		check(real_art != null and real_art.get_node_or_null("ClickableGlow") != null,
			"the real skill slot frames its card art")
		ui._set_clickable_active(real_slot, false)

	# 回归验证：确认出牌前底栏就应显示"打完是多少威力"。
	# 待确认的常规出牌并入预览（与魔力预览账本同一套做法），暗置牌不计入
	var preview_base: int = GetPlayerTotalPower.new().exec(ui._local_player_id)
	var face_preview = BaseAttack.new("预览明置", "", ["strength"], BaseNumber.new(1), BaseNumber.new(4))
	var hidden_preview = BaseAttack.new("预览暗置", "", ["strength"], BaseNumber.new(1), BaseNumber.new(7))
	ui._regular_play_pending_cards = [face_preview]
	ui._regular_play_pending_hidden = [false]
	ui.refresh_all_ui()
	check(ui.total_power_label != null and ui.total_power_label.text == "当前合计威力: %d" % (preview_base + 4),
		"the pending face up card is already counted before confirming")
	ui._regular_play_pending_cards = [face_preview, hidden_preview]
	ui._regular_play_pending_hidden = [false, true]
	ui.refresh_all_ui()
	check(ui.total_power_label.text == "当前合计威力: %d" % (preview_base + 4),
		"a pending concealed card is not counted")
	check(int(ui.total_power_label.get_meta("instant_power_preview", 0)) == 4,
		"the hover breakdown carries the pending increment")
	ui._regular_play_pending_cards = []
	ui._regular_play_pending_hidden = []
	ui.refresh_all_ui()
	check(ui.total_power_label.text == "当前合计威力: %d" % preview_base,
		"undoing the pending play takes the preview away")

	# 回归验证：被效果更改的牌点击【改】能查看更改明细
	var mod_card := BaseAttack.new("被改的牌", "quick.png", ["quick"], BaseNumber.new(3), BaseNumber.new(6))
	EditCardCost.new().exec(BaseNumber.new(2), null, mod_card)
	EditCardAttributes.new().exec(["宝具"], [], [""], mod_card)
	check(mod_card.get_modification_details().size() == 2, "power cost and attribute changes are all recorded")
	var mod_slot := TextureRect.new()
	ui.add_child(mod_slot)
	ui._render_card_face(mod_slot, mod_card, true)
	var mod_badge := mod_slot.get_node_or_null("CardModificationBadge") as Button
	if mod_badge != null:
		mod_badge.pressed.emit()
	var mod_desc := ui.tactical_confirm_modal.get_node_or_null("Box/VBox/ConfirmDesc") as Label
	check(ui.tactical_confirm_modal.visible and mod_desc != null and mod_desc.text.contains("魔力消耗"), "clicking the modification badge opens the change detail")
	check(mod_desc != null and not mod_desc.text.contains("（") and not mod_desc.text.contains("("), "change detail text carries no parentheses")
	ui._on_tactical_confirm_cancel()
	mod_slot.queue_free()

	ui._show_battle_report(report)
	await get_tree().create_timer(2.0).timeout
	var list: VBoxContainer = ui.battle_report_modal.get_node("Box/VBox/ReportScroll/ReportList")
	var bottom := -1.0
	for row in list.get_children():
		check(row.position.y >= bottom, "report row non-overlap " + str(row.get_index()))
		bottom = row.position.y + row.size.y
		check(is_equal_approx(row.modulate.a, 1.0), "report row visible " + str(row.get_index()))
		for label in row.find_children("*", "Label", true, false):
			check(label.autowrap_mode != TextServer.AUTOWRAP_OFF, "report line wraps " + str(row.get_index()))
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tests/reported_ui_report.png")
		ui.battle_report_modal.hide()
		ReleaseTrueName.new().exec(pid)
		ReleaseTrueName.new().exec(ui._local_player_id)
		ui.refresh_all_ui()
		ui._update_drawer_visuals(slot_for(pid))
		ui.opponent_drawer.show()
		await frames()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tests/reported_ui_status.png")
	var result := {"checks": checks, "failures": failures}
	FileAccess.open("res://tests/reported_ui_result.json", FileAccess.WRITE).store_string(JSON.stringify(result))
	print("RESULT ", JSON.stringify(result))
	get_tree().quit(0 if failures.is_empty() else 1)
