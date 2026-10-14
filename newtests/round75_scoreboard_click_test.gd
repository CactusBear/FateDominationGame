extends "res://newtests/round74_scoreboard_toggle_test.gd"
## 复用原局部 source fixture；只以 viewport GUI 输入开关正式按钮。
var input_trace: Array = []
var visual_trace: Array = []
var pressed_count := 0
var down_count := 0
var up_count := 0
var serial := 0
var motion_count := 0

class ObservedLobby extends "res://scripts/net/session/lobby_session.gd":
	var rule_calls := 0
	func request(kind: String, args: Dictionary, registered: Callable = Callable()) -> Error:
		rule_calls += 1
		return super.request(kind, args, registered)

## 只接入正式 transport 已声明信号；Session 自行执行来源门、绑定和镜像校验。
## 受控投递不是 ENet 传输验收，也不直接写 Session 镜像或 presenter。
func deliver_match(session, view: Dictionary, label: String) -> void:
	session.transport.message_received.emit(1, {"kind":"match_view", "state":view, "pending":{}, "actions":{}})
	check(session.read_match() == view, label + " 正式会话接收完整投影")

func observed_press() -> void:
	pressed_count += 1
	input_trace.append({"serial":serial,"event":"pressed","visible":board.get_node("Board").visible})

func observed_gui(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed: down_count += 1
		else: up_count += 1
		input_trace.append({"serial":serial,"event":"gui_down" if event.pressed else "gui_up"})

func click_scoreboard(label: String) -> void:
	var button := board.get_node("Top/BoardButton") as Button
	var point := button.get_global_rect().get_center()
	var old_pressed := pressed_count
	var old_down := down_count
	var old_up := up_count
	check(button.is_visible_in_tree() and not button.disabled, label + " 正式按钮可用")
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	motion.relative = Vector2(1, 0)
	serial += 1
	get_viewport().push_input(motion, true)
	await get_tree().process_frame
	check(get_viewport().gui_get_hovered_control() == button, label + " motion命中正式按钮")
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		event.pressed = down
		serial += 1
		get_viewport().push_input(event, true)
		await get_tree().process_frame
	check(pressed_count == old_pressed + 1 and down_count == old_down + 1 and up_count == old_up + 1, label + " 一次down/up一次真实pressed")

func watch_button(label: String) -> void:
	owner(label)
	board.get_node("Top/BoardButton").pressed.connect(observed_press)
	board.get_node("Top/BoardButton").gui_input.connect(observed_gui)

func row_ids() -> Array:
	var result: Array = []
	for row in board.get_node("Board/Rows").get_children(): result.append(row.get_instance_id())
	return result

func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var panel := board.get_node("Board") as Control
	var geometry: Array = []
	check(not board._native_modal_visible(), label + " 无原生modal遮挡")
	for row in board.get_node("Board/Rows").get_children():
		for field in ["Rank", "Name", "Score"]:
			var node := row.get_node(field) as Label
			var rect := node.get_global_rect()
			check(node.is_visible_in_tree() and rect.size.x > 0 and rect.size.y > 0 and get_viewport().get_visible_rect().encloses(rect), label + " " + field + " 可见几何")
			geometry.append({"field":field,"text":node.text,"rect":str(rect),"font_size":node.get_theme_font_size("font_size")})
	var path := "res://tests/runtime_reports/" + label + ".png"
	check(get_viewport().get_texture().get_image().save_png(path) == OK, label + " 实际窗口渲染截图")
	visual_trace.append({"label":label,"display_server":DisplayServer.get_name(),"panel_rect":str(panel.get_global_rect()),"geometry":geometry,"screenshot":path})

func run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().has("window"):
		check(false, "必须非headless -- window")
		get_tree().quit(1)
		return
	GameStart.reset()
	board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	add_child(board)
	board.set_process(false)
	EffectManager.reset_runtime()
	GameLog.reset()
	GameData.player_data_library.clear()
	for pid in range(2):
		var data: Dictionary = GameData.new_player_data()
		data.player_name = "投影玩家%d" % pid
		data.order.set_num(BaseNumber.new(pid))
		data.score.set_num(BaseNumber.new(3 if pid == 0 else 8))
		GameData.player_data_library[pid] = data
	GameProgress.reset_progress()
	var builder = preload("res://scripts/match/view_builder.gd").new()
	var trap := ReadTrap.new()
	board._source = preload("res://scripts/game_scene/battle_io/local_battle_source.gd").new(0, builder, trap)
	board._source_is_local = true
	board.get_node("Board").hide()
	watch_button("本地")
	await get_tree().process_frame
	var before := state()
	await click_scoreboard("本地打开")
	expect(board._source.read_view(), "本地打开")
	await capture("local-open")
	var ids := row_ids()
	await click_scoreboard("本地关闭")
	check(not board.get_node("Board").visible, "本地真实关闭")
	check(state() == before and trap.calls == 0, "本地输入无规则副作用")
	GameData.player_data_library[0].score.set_num(BaseNumber.new(11))
	GameData.player_data_library[0].player_name = "同ID更新"
	board._source.invalidate()
	before = state()
	await click_scoreboard("本地重新打开")
	expect(board._source.read_view(), "本地同ID刷新")
	check(row_ids() == ids, "本地同ID排序变化复用节点但重绑内容")
	await capture("local-reopen")
	check(state() == before and trap.calls == 0, "本地重新打开无规则副作用")
	board.queue_free()
	await get_tree().process_frame
	var lobby = preload("res://scripts/net/session/lobby_session.gd").new()
	board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	board.network_session = lobby
	add_child(board)
	board.set_process(false)
	board._source.close()
	var session := SourceSession.new()
	board._source = preload("res://scripts/game_scene/battle_io/network_battle_source.gd").new(session)
	board._network_presenter._mine = {"id":0,"score":999,"master":{"name":"不得读取旧mine"}}
	session.view = builder.build(0)
	board.get_node("Board").hide()
	watch_button("网络")
	await get_tree().process_frame
	before = state()
	await click_scoreboard("网络打开")
	expect(session.view, "网络打开")
	await capture("network-open")
	ids = row_ids()
	await click_scoreboard("网络关闭")
	check(not board.get_node("Board").visible, "网络真实关闭")
	session.view.players[1].score = 41
	session.view.players[1].player_name = "网络同ID更新"
	await click_scoreboard("网络重新打开")
	expect(session.view, "网络同seq同ID重新打开")
	check(row_ids() == ids, "网络同ID排序变化复用节点但重绑内容")
	await capture("network-reopen")
	var seq: Variant = session.view.seq
	session.view = {"seq":seq,"observer":0,"players":[]}
	board._bind_board()
	expect(session.view, "网络empty刷新")
	await click_scoreboard("网络empty关闭")
	check(not board.get_node("Board").visible, "empty真实关闭")
	await click_scoreboard("网络empty打开")
	expect(session.view, "网络empty重新打开")
	check(state() == before and session.rule_calls == 0 and trap.calls == 0, "网络GUI和empty无规则副作用")
	print("GUIINPUT ", JSON.stringify(input_trace))
	print("VISUAL ", JSON.stringify(visual_trace))
	print("TRACE ", JSON.stringify(traces))
	board.queue_free()
	await get_tree().process_frame
	lobby.close()
	lobby = null
	GameStart.reset()
	print("RESULT ", JSON.stringify({"suite":"round75_scoreboard_click","checks":checks,"failures":failures,"pressed":pressed_count,"gui_down":down_count,"gui_up":up_count,"input_path":"Viewport.push_input motion/frame/down/frame/up/frame; no warp, emit or toggle call","window":true}))
	get_tree().quit(0 if failures.is_empty() else 1)
