extends "res://scripts/game_scene/battle_board_v2.gd"

# 继承生产组合根，全部资格来自真实 query/effect_pool；不注入 source/context，不造快照。
var ui_checks := 0
var ui_failures: Array = []
var ui_cards: Array = []
var ui_context: SessionContext
var ui_window := false
var ui_replies: Array = []
var ui_root := "E:/scratch/continuous-next-wave/ui-affordance-rings3"

func ui_check(ok: bool, label: String) -> void:
	ui_checks += 1
	print("CHECK ", label, " ", ok)
	if not ok: ui_failures.append(label)

func _ready() -> void:
	ui_checks = get_tree().get_meta("ui_previous_checks", 0)
	ui_failures = get_tree().get_meta("ui_previous_failures", [])
	ui_window = OS.get_cmdline_user_args().has("window")
	if OS.get_cmdline_user_args().has("os-hover"): ui_root += "/window04"
	ui_check(GameStart.game_start([0]), "real GameStart")
	ui_context = GameStart.startup_context()
	var p: Dictionary = GameData.player_data_library[0]
	GameProgress.current_phase_index = 2
	GameProgress.current_player_id = 0
	GameData.player_id = 0
	GameLog.reset()
	p.is_out = false
	p.magic.number = 8
	p.play_limit.number = 4
	p.regular_play_min.number = 1
	p.hand_cards.clear()
	p.played_cards.clear()
	p.master_skills.clear()
	p.servant_skills.clear()
	p.side.skills.clear()
	p.location = null
	MapData.active_situation = null
	for area in MapData.areas:
		area._events.clear()
		area._buffs.clear()
	ui_check(SetLocation.new().exec(MapData.areas[0]._locations[0], 0, false, false, true, ui_context), "trusted real initial battlefield placement")
	var pictures := ["mana_resistance", "cd", "excalibur", "wind_barrier"]
	for i in range(4):
		var effects: Array = []
		if i >= 2:
			effects.append({"effect_name":"环验收主动能力", "time_points":[TimePoints.SELF_PREFIX + TimePoints.ACTION_PHASE], "priority":0, "is_pure_passive":false, "is_residue":false, "effect_numbers":[], "funcs":[], "is_manual":true, "need_activate":false, "max_choices":1, "options":[{"shown_option_name":"确认真实发动", "funcs":[]}]})
		var descriptor := {"skill_name":"环状态%d" % i, "skill_card_img":"00001_artoria_pendragon_%s.png" % pictures[i], "attributes":[], "cost":{"number":99 if i in [0,2] else 1,"can_change":true,"is_pure_number":true}, "power":{"number":1,"can_change":true,"is_pure_number":true}, "ignore_limit":false, "effects":effects}
		var loaded: Array = LoadGame.load_skills([descriptor], "res://data/servants/00001_artoria_pendragon", null, "skill", ui_context)
		ui_check(loaded.size() == 1, "trusted ordinary runtime skill %d" % i)
		if loaded.is_empty(): ui_finish(); return
		ui_cards.append(loaded[0])
		p.hand_cards.append(loaded[0])
		RegisterObjectEffects.new().exec(loaded[0], 0, ui_context)
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.ACTION_PHASE, TimePoints.NON_CLIMAX], ui_context)
	super._ready()
	_battle_commands.result.connect(ui_reply)
	call_deferred("ui_run")

# 仅隔离自动推进，保留全部生产呈现帧、Tween、刷新与输入路由。
func _check_and_step_ai(_delta: float) -> void: pass

func ui_reply(id: int, ok: bool, reason: String) -> void:
	ui_replies.append({"id":id,"ok":ok,"reason":reason})

func ui_wait(frames: int = 4) -> void:
	for i in range(frames): await get_tree().process_frame

func ui_slot(card) -> Control:
	for node in _hand.get_children():
		if node.get_meta("card", null) == card: return node
	return null

func ui_color(node: Control, frame: String) -> Color:
	return (node.get_node(frame).get_theme_stylebox("panel") as StyleBoxFlat).border_color

func ui_state(card, play: bool, manual: bool, white_play: bool = false, white_effect: bool = false) -> void:
	var node := ui_slot(card)
	ui_check(node != null, "actual held slot " + card._name)
	if node == null: return
	ui_check(node.get_node("Breath").visible == play, "inner visible " + card._name)
	ui_check(node.get_node("EffectBreath").visible == manual, "outer visible " + card._name)
	ui_check(not node.get_node("Selected").visible, "no third white ring " + card._name)
	if play: ui_check(ui_color(node,"Breath").is_equal_approx(Color.WHITE if white_play else Color(0.9098,0.8039,0.5255,1)), "inner original node color " + card._name)
	if manual: ui_check(ui_color(node,"EffectBreath").is_equal_approx(Color.WHITE if white_effect else Color(0.72,0.46,1,1)), "outer independent color " + card._name)

func ui_motion(point: Vector2) -> void:
	if OS.get_cmdline_user_args().has("os-hover"):
		get_window().grab_focus()
		get_viewport().warp_mouse(point)
		await ui_wait(3)
		print("OS_HOVER ", point, " actual=",get_global_mouse_position(), " drawer=",_hand_drawer_open)
		return
	var motion := InputEventMouseMotion.new()
	motion.position = point
	get_viewport().push_input(motion, true)
	await ui_wait(2)

func ui_click(control: Control, button: int = MOUSE_BUTTON_LEFT) -> void:
	var point := control.get_global_rect().get_center()
	if control.has_meta("card"):
		point = control.get_global_transform_with_canvas() * Vector2(control.size.x * 0.94,control.size.y * 0.16)
	await ui_motion(point)
	await ui_wait(40)
	point = control.get_global_transform_with_canvas() * Vector2(control.size.x * 0.94,control.size.y * 0.16) if control.has_meta("card") else control.get_global_rect().get_center()
	await ui_motion(point)
	print("GUI_HOVER ", get_viewport().gui_get_hovered_control(), " target=",control)
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = button
	event.pressed = true
	get_viewport().push_input(event,true)
	await ui_wait(1)
	event.pressed = false
	get_viewport().push_input(event,true)
	await ui_wait(3)

func ui_capture(label: String) -> void:
	if not ui_window: return
	if OS.get_cmdline_user_args().has("os-hover") and not get_tree().has_meta("ui_submit_round"):
		var target := ui_slot(ui_cards[3])
		var point := target.get_global_transform_with_canvas() * Vector2(target.size.x * 0.94,target.size.y * 0.16)
		if not _source.read_pending().is_empty():
			point = Vector2(target.get_meta("rest_position").x + target.size.x * 0.5, size.y - 20)
		await ui_motion(point)
		await ui_wait(45)
		ui_check(_hand_drawer_open > 0.95, "visible hand drawer truly open " + label)
	await RenderingServer.frame_post_draw
	var path := ui_root + "/" + label + ".png"
	ui_check(get_viewport().get_texture().get_image().save_png(path) == OK, "native viewport screenshot " + label)
	print("SCREENSHOT ", path)

func ui_run() -> void:
	await ui_wait(160)
	ui_check(not _scroll_is_animating() and not _rival_anim_busy and not _phase_anim_busy, "production entry animations settled")
	ui_check(not EffectManager.execution_context().get("ok",false) and RegularPlay.payment_quote(0).is_empty(), "ordinary UI without effect frame or default payment grant")
	if get_tree().has_meta("ui_submit_round"):
		await ui_submit_round()
		return
	var group := _read_group_preview()
	print("REAL_GROUP ", JSON.stringify(group))
	ui_check(group.preview.candidates.size() == 2 and _held_card_playable(ui_cards[1]) and _held_card_playable(ui_cards[3]), "gold from authoritative two ordinary group candidates")
	ui_check(_manual_effects_of(ui_cards[2]).size() == 1 and _manual_effects_of(ui_cards[3]).size() == 1, "purple from authoritative manual candidates")
	# 抽屉由真实运动事件展开，随后等待生产悬浮布局收敛。
	var both := ui_slot(ui_cards[3])
	await ui_motion(Vector2(both.get_global_rect().get_center().x, size.y - 10))
	await ui_wait(70)
	await ui_motion(Vector2(size.x * 0.5, size.y - 12))
	await ui_wait(40)
	ui_state(ui_cards[0],false,false)
	ui_state(ui_cards[1],true,false)
	ui_state(ui_cards[2],false,true)
	ui_state(ui_cards[3],true,true)
	for card in ui_cards:
		var node := ui_slot(card)
		var inner := node.get_node("Breath") as Control
		var outer := node.get_node("EffectBreath") as Control
		ui_check(inner.mouse_filter == Control.MOUSE_FILTER_IGNORE and outer.mouse_filter == Control.MOUSE_FILTER_IGNORE and inner.z_index == 0 and outer.z_index == 0 and not inner.is_set_as_top_level() and not outer.is_set_as_top_level(), "decorations follow card and pass mouse " + card._name)
		var style := outer.get_theme_stylebox("panel") as StyleBoxFlat
		ui_check(inner.position.x - (outer.position.x + style.border_width_left) >= 3.0, "separated stroke gap " + card._name)
	await ui_capture("01-four-states")
	var inner_id := both.get_node("Breath").get_instance_id()
	if ui_window: await ui_click(both)
	else:
		var e := InputEventMouseButton.new(); e.button_index = MOUSE_BUTTON_LEFT; e.pressed = true
		_on_held_card_input(e,both)
	await ui_wait()
	ui_check(_selected_cards.has(ui_cards[3]) and _read_group_preview().preview.can_submit, "real selection remains submit legal")
	ui_state(ui_cards[3],true,true,true,false)
	ui_check(both.get_node("Breath").get_instance_id() == inner_id, "selection does not replace gold node")
	await ui_capture("02-gold-selected-white")
	if ui_window:
		await ui_motion(both.get_global_rect().get_center())
		await ui_wait(30)
		await ui_click(both.get_node("EffectButton"))
	else: _on_held_effect_pressed(both)
	await ui_wait(4)
	print("REAL_PENDING ",JSON.stringify(_source.read_pending()))
	ui_check(_source.read_pending().get("kind") == "active_choice", "actual activate command entered authority pending")
	ui_state(ui_cards[3],true,true,true,true)
	await ui_capture("03-both-selected-white")
	if ui_window: await ui_click(_effect_modal.get_node("Box/ButtonsRow/BtnCancel"))
	else: _on_effect_modal_cancel()
	await ui_wait(5)
	ui_check(_source.read_pending().is_empty(), "cancel clears real pending")
	ui_state(ui_cards[3],true,true,true,false)
	await ui_capture("04-cancel-restored-purple")
	# 真正拒绝：撤销效果资格后提交原效果ID，生产命令必须拒绝，不留白圈。
	var effect: BaseEffect = ui_cards[3]._effects[0]
	effect._disabled = true
	_submit_battle_command("activate", {"effect":_held_action_ids.id_for(effect)})
	await ui_wait()
	ui_check(not ui_replies.is_empty() and not ui_replies.back().ok and _end_command_attempt.is_empty() and _source.read_pending().is_empty(), "authority reject releases request intention")
	ui_state(ui_cards[3],true,false,true,false)
	effect._disabled = false
	refresh_all_ui()
	await ui_wait()
	ui_state(ui_cards[3],true,true,true,false)
	_on_held_effect_pressed(both)
	await ui_wait()
	ui_check(_source.read_pending().get("kind") == "active_choice", "retry actual activation after reject")
	if ui_window:
		await ui_click(_effect_modal.get_node("Box/OptionsRow").get_child(0))
	else: _on_effect_option_picked(0)
	await ui_wait()
	ui_check(_source.read_pending().is_empty() and ui_replies.back().ok, "actual effect completion clears pending")
	ui_state(ui_cards[3],true,true,true,false)
	await ui_capture("05-completed-restored-purple")
	# 取消选牌，白金恢复，随后重新选并从正式出牌按钮进入真实提交。
	_selected_cards.clear()
	refresh_all_ui()
	await ui_wait()
	ui_state(ui_cards[3],true,true,false,false)
	# 效果生命周期与正式提交各用真实新局，避免把已知检查点集合预算边界冒充UI红。
	get_tree().set_meta("ui_previous_checks", ui_checks)
	get_tree().set_meta("ui_previous_failures", ui_failures)
	get_tree().set_meta("ui_submit_round", true)
	GameStart.end_session()
	get_tree().reload_current_scene()

func ui_submit_round() -> void:
	EditCardPower.new().exec(ui_cards[3], BaseNumber.new(1), null, 0, ui_context)
	ui_check(not ui_cards[3].get_modification_details().is_empty(), "real EditCardPower produced modification history")
	_selected_cards.append(ui_cards[3])
	refresh_all_ui()
	await ui_wait()
	var checkpoint_probe = preload("res://scripts/match/effect_checkpoint.gd").new(null, true, ui_context)
	print("CHECKPOINT_DIAG ",checkpoint_probe.ready," ",checkpoint_probe.error)
	print("PRE_SUBMIT ",JSON.stringify(_read_group_preview()), " context=", SessionGeneration.validate_context(ui_context), " phase=", GameProgress.get_current_phase(), " effects=", EffectManager.is_waiting_for_choice())
	if ui_window: await ui_click(_ops.get_node("PlayButton"))
	else: _ops.get_node("PlayButton").pressed.emit()
	await ui_wait(160)
	var p: Dictionary = GameData.player_data_library[0]
	ui_check(RegularPlay.completed(0) and p.played_cards == [ui_cards[3]] and not p.hand_cards.has(ui_cards[3]) and p.magic.number == 7, "formal button submits same modified card once for one magic")
	print("REAL_SUBMIT ",JSON.stringify({"magic":p.magic.number,"played":p.played_cards.size(),"replies":ui_replies}), " guard=", EffectManager.runtime_guard_status(), " messages=", EffectManager.messages)
	var first: Control
	for grp in _play_group_nodes():
		if grp.is_visible_in_tree() and grp.get_node("Cards/Row").get_child_count() > 0:
			first = grp.get_node("Cards/Row").get_child(0)
			break
	ui_check(first != null, "actual played first slot exists")
	if first != null:
		var badge := first.get_node("CardModificationBadge") as Control
		var rect := badge.get_global_rect()
		var clipped: Array = []
		var ancestor := badge.get_parent()
		while ancestor is Control:
			if ancestor.clip_contents and not ancestor.get_global_rect().encloses(rect): clipped.append(str(ancestor.get_path()))
			ancestor = ancestor.get_parent()
		print("BADGE_GEOMETRY ", JSON.stringify({"badge":str(rect),"card":str(first.get_global_rect()),"row":str(first.get_parent().get_global_rect()),"clipped":clipped,"padding":first.position.x}))
		ui_check(badge.is_visible_in_tree() and rect.position.x < first.get_global_rect().position.x and absf(rect.get_center().y - first.get_global_rect().get_center().y) < 1.0 and clipped.is_empty(), "first played badge protrudes centered without any ancestor clipping")
		ui_check(first.position.x >= _played_badge_left_padding(first.size.x), "only minimum row left padding covers badge")
		await ui_capture("06-first-played-badge")
		# 同一真实布局单变量回退：首槽减去原有局部余量，验证父裁切确实截断外凸段。
		var position_before := first.position
		first.position.x -= _played_badge_left_padding(first.size.x)
		await ui_capture("07-badge-no-padding-control")
		var row_clip := first.get_parent().get_parent() as Control
		ui_check(badge.get_global_rect().position.x < row_clip.get_global_rect().position.x and row_clip.clip_contents, "removing local padding reproduces first badge crop")
		first.position = position_before
		await ui_capture("08-badge-padding-restored")
	ui_finish()

func ui_finish() -> void:
	print("RESULT ", JSON.stringify({"suite":"ui-affordance3-contract", "window":ui_window,"checks":ui_checks,"failures":ui_failures}))
	get_tree().quit(0 if ui_failures.is_empty() else 1)
