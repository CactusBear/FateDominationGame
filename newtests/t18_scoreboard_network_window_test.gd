extends "res://newtests/round75_scoreboard_click_test.gd"
## T18：继承已有单路窗口样板；正式 Session 接收与生产 presenter，不替换 source。
var lobby
var return_pressed := 0
var received_motion := 0

class WindowLobby extends "res://scripts/net/session/lobby_session.gd":
	var rule_calls := 0
	var request_kinds: Array = []
	func request(kind: String, args: Dictionary, registered: Callable = Callable()) -> Error:
		rule_calls += 1
		request_kinds.append(kind)
		return super.request(kind, args, registered)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		received_motion += 1

func send_message(sender: int, message: Dictionary) -> void:
	lobby.transport.message_received.emit(sender, message)

func publish(view: Dictionary, label: String) -> void:
	deliver_match(lobby, view, label)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	check(board._source.read_view() == lobby.read_match(), label + " source与presenter同一Session")

func settle(label: String) -> void:
	for frame in range(600):
		if not board._scroll_is_animating() and not board._phase_anim_busy and not board._rival_anim_busy:
			await get_tree().process_frame
			check(true, label + " 生产动画完成")
			return
		await get_tree().process_frame
	check(false, label + " 生产动画完成")

func mouse_at(point: Vector2, button_index: int = 0) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	motion.relative = Vector2(1, 0)
	serial += 1
	get_viewport().push_input(motion, true)
	await get_tree().process_frame
	input_trace.append({"serial":serial,"event":"motion","point":str(point),"hovered":str(get_viewport().gui_get_hovered_control()),"area":board._main_area_index})
	if button_index == 0:
		return
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = button_index
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down and button_index == MOUSE_BUTTON_LEFT else 0
		event.pressed = down
		serial += 1
		get_viewport().push_input(event, true)
		await get_tree().process_frame

func key(code: Key, physical: Key = KEY_NONE) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = physical
		event.pressed = down
		serial += 1
		get_viewport().push_input(event, true)
		await get_tree().process_frame
	input_trace.append({"serial":serial,"event":"key","key":code,"physical":physical,"scoreboard":board.get_node("Board").visible,"pause":board._is_paused()})

func blocked_button(button: Button, label: String) -> void:
	var old := pressed_count
	await mouse_at(button.get_global_rect().get_center(), MOUSE_BUTTON_LEFT)
	check(pressed_count == old and not board.get_node("Board").visible, label + " disabled真实点击无pressed/不开榜")

func capture(label: String) -> void:
	await super.capture(label)
	if OS.get_environment("FD_T18_NATIVE_WINDOW") != "1" or label not in ["t18-network-open", "t18-network-after-input"]:
		return
	var prefix := "res://tests/runtime_reports/" + label
	var marker := FileAccess.open(prefix + ".native-ready.json", FileAccess.WRITE)
	marker.store_string(JSON.stringify({"pid":OS.get_process_id(),"filename":label + ".png"}))
	marker.close()
	for frame in range(600):
		if FileAccess.file_exists(prefix + ".native-ack.json"):
			var result: Variant = JSON.parse_string(FileAccess.get_file_as_string(prefix + ".native-ack.json"))
			check(result is Dictionary and result.get("ok", false), label + " 自有HWND原生OS客户区截图")
			return
		await get_tree().process_frame
	check(false, label + " 原生OS截图握手超时")

func run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().has("window"):
		check(false, "必须真实非headless -- window")
		get_tree().quit(1)
		return
	print("WINDOW ", JSON.stringify({"display_server":DisplayServer.get_name(),"pid":OS.get_process_id(),"user_data":OS.get_user_data_dir(),"input":"single Viewport.push_input motion/frame/down/frame/up/frame; no warp/emit/direct toggle"}))
	GameStart.reset()
	EffectManager.reset_runtime()
	GameLog.reset()
	GameData.player_data_library.clear()
	for pid in range(2):
		var data: Dictionary = GameData.new_player_data()
		data.player_name = "网络投影玩家%d" % pid
		data.order.set_num(BaseNumber.new(pid))
		data.score.set_num(BaseNumber.new(3 if pid == 0 else 8))
		GameData.player_data_library[pid] = data
	GameProgress.reset_progress()
	var builder = preload("res://scripts/match/view_builder.gd").new()
	var view: Dictionary = builder.build(0)
	view.seq = 1
	lobby = WindowLobby.new()
	board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	board.network_session = lobby
	add_child(board)
	watch_button("T18网络")
	await settle("初始")
	check(board.is_processing() and board.is_processing_input(), "保留正式帧循环和网络_input")
	var button := board.get_node("Top/BoardButton") as Button
	check(button.disabled and lobby.read_match().is_empty(), "无视图使能门关闭")
	await blocked_button(button, "无视图")
	send_message(2, {"kind":"match_bind", "observer":0})
	send_message(1, {"kind":"match_view", "state":view, "pending":{}, "actions":{}})
	await get_tree().process_frame
	check(lobby.read_match().is_empty() and button.disabled, "伪来源bind不能建立绑定；未绑定view拒收")
	send_message(1, {"kind":"match_bind", "observer":0})
	send_message(2, {"kind":"match_view", "state":view, "pending":{}, "actions":{}})
	await get_tree().process_frame
	check(lobby.read_match().is_empty() and button.disabled, "非主机sender2视图拒收")
	await publish(view, "主机来源绑定后合法视图")
	await settle("合法视图")
	check(not button.disabled, "非空视图使能不依赖行动者/阶段")
	var before := state()
	await click_scoreboard("T18网络打开")
	expect(lobby.read_match(), "T18网络打开")
	await capture("t18-network-open")
	var ids := row_ids()
	var frozen: Dictionary = lobby.read_match()
	var next: Dictionary = view.duplicate(true)
	next.seq = 2
	next.players[1].score = 41
	next.players[1].player_name = "主机更新后的玩家"
	send_message(2, {"kind":"match_view", "state":next, "pending":{}, "actions":{}})
	await get_tree().process_frame
	check(lobby.read_match() == frozen and output().rows[0].score == "8", "伪来源更新不能污染打开榜单")
	var invalid: Dictionary = next.duplicate(true)
	invalid.players[1].erase("score")
	send_message(1, {"kind":"match_view", "state":invalid, "pending":{}, "actions":{}})
	await get_tree().process_frame
	check(lobby.read_match() == frozen, "必需score缺失拒收")
	invalid = next.duplicate(true)
	invalid.observer = 1
	send_message(1, {"kind":"match_view", "state":invalid, "pending":{}, "actions":{}})
	await get_tree().process_frame
	check(lobby.read_match() == frozen, "错误observer拒收")
	invalid = next.duplicate(true)
	invalid.seq = 1
	send_message(1, {"kind":"match_view", "state":invalid, "pending":{}, "actions":{}})
	await get_tree().process_frame
	check(lobby.read_match() == frozen, "重复seq更新拒收")
	await publish(next, "合法新序号更新")
	expect(next, "打开态收到正式更新")
	check(row_ids() == ids, "同ID更新复用行而重绑内容")
	var row := board.get_node("Board/Rows").get_child(0) as Control
	var point := row.get_global_rect().get_center()
	var calls_before: int = lobby.rule_calls
	await mouse_at(point, MOUSE_BUTTON_LEFT)
	await mouse_at(point, MOUSE_BUTTON_RIGHT)
	await mouse_at(point, MOUSE_BUTTON_WHEEL_DOWN)
	await key(KEY_QUOTELEFT, KEY_QUOTELEFT)
	check(not board.is_debug_console_enabled(), "网络波浪号不得启用本地规则调试")
	check(lobby.rule_calls == calls_before and state() == before and lobby.read_match() == next, "榜内左右键/滚轮/非法调试键均无规则命令或状态副作用")
	var old_area: int = board._main_area_index
	var other := 0 if old_area != 0 else 1
	var strip := board.get_node("Strips").get_child(other) as Control
	await mouse_at(strip.get_global_rect().get_center())
	check(board._main_area_index == old_area, "打开榜单阻断底层地图motion")
	await capture("t18-network-after-input")
	await key(KEY_ESCAPE)
	check(board.get_node("Board").visible and board._is_paused(), "Escape合同是暂停菜单不是关闭榜单")
	await key(KEY_ESCAPE)
	check(board.get_node("Board").visible and not board._is_paused(), "第二次Escape恢复榜单输入")
	await click_scoreboard("T18网络关闭")
	check(not board.get_node("Board").visible, "正式按钮真实关闭")
	await settle("关闭")
	strip = board.get_node("Strips").get_child(other) as Control
	await mouse_at(strip.get_global_rect().get_center())
	check(board._main_area_index == other, "关闭后首个合法motion恢复导航")
	await settle("恢复导航")
	await click_scoreboard("T18网络重开")
	expect(next, "重新打开当前Session投影")
	await capture("t18-network-reopen")
	check(lobby.rule_calls == calls_before and state() == before, "开关/键鼠不提交网络规则命令")
	var lobby_return := board.get_node("Board/ReturnActions/ReturnToLobby") as Button
	check(not lobby_return.visible, "未终局返回大厅按钮不显示")
	var ended: Dictionary = next.duplicate(true)
	ended.seq = 3
	ended.game_over = true
	await publish(ended, "正式终局投影")
	await settle("终局")
	check(lobby_return.is_visible_in_tree() and lobby_return.disabled, "非房主终局只读可见但返回大厅禁用")
	lobby_return.pressed.connect(func(): return_pressed += 1)
	var ended_calls: int = lobby.rule_calls
	await mouse_at(lobby_return.get_global_rect().get_center(), MOUSE_BUTTON_LEFT)
	print("END_INPUT ", JSON.stringify({"pressed":return_pressed,"requests_before":ended_calls,"requests_after":lobby.rule_calls,"request_kinds":lobby.request_kinds,"state_unchanged":state() == before,"disabled":lobby_return.disabled}))
	check(return_pressed == 0 and lobby.rule_calls == ended_calls, "非房主非法返回点击无pressed/无match_finished_lobby")
	await capture("t18-network-ended-refused")
	send_message(1, {"kind":"match_reset"})
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	print("RESET_OBSERVATION ", JSON.stringify({"empty":lobby.read_match().is_empty(),"disabled":button.disabled,"scoreboard_visible":board.get_node("Board").visible,"processing":board.is_processing(),"state_before":str(before),"state_after":str(state()),"request_kinds":lobby.request_kinds}))
	check(lobby.read_match().is_empty() and button.disabled and not board.get_node("Board").visible, "正式reset撤销视图并关闭榜单/禁用按钮")
	await blocked_button(button, "reset后")
	check(state() == before and lobby.request_kinds.all(func(kind): return kind == "preview_group"), "所有输入/拒收无本地规则副作用；仅正式投影刷新preview查询")
	send_message(1, {"kind":"match_bind", "observer":-1})
	var spectator: Dictionary = builder.build(-1)
	spectator.seq = 4
	await publish(spectator, "正式观战过滤投影")
	await settle("观战")
	check(not button.disabled and lobby.read_match().observer == -1, "观战者无行动权限仍可只读开榜")
	var spectator_calls: int = lobby.rule_calls
	await click_scoreboard("T18观战打开")
	expect(spectator, "T18观战榜")
	await click_scoreboard("T18观战关闭")
	check(not board.get_node("Board").visible and lobby.rule_calls == spectator_calls and state() == before, "观战开关无规则请求/副作用")
	# 单独边界回归保留生产空数组故障，不污染观战/核心输入结果。
	if OS.get_cmdline_user_args().has("empty-edge"):
		var previous_ids: Array = board._rival_order_snapshot.duplicate()
		var empty_rows: Dictionary = spectator.duplicate(true)
		empty_rows.seq = 5
		empty_rows.players = []
		await publish(empty_rows, "合法非空零玩家投影")
		await settle("零玩家")
		print("EDGE_CAUSE ", JSON.stringify({"accepted":lobby.read_match() == empty_rows,"previous_ids":previous_ids,"expected_ids":board._rival_order_snapshot,"rival_anim_busy":board._rival_anim_busy,"source_seq":lobby.read_match().seq}))
		check(not button.disabled, "零行但非空view允许只读开关")
		var empty_calls: int = lobby.rule_calls
		await click_scoreboard("T18零行打开")
		expect(empty_rows, "T18零行榜")
		await capture("t18-network-empty-rows")
		await click_scoreboard("T18零行关闭")
		check(not board.get_node("Board").visible and lobby.rule_calls == empty_calls, "零行榜真实关闭且不发命令")
	check(received_motion > 0, "根窗口确有MouseMotion分发")
	print("GUIINPUT ", JSON.stringify(input_trace))
	print("VISUAL ", JSON.stringify(visual_trace))
	print("TRACE ", JSON.stringify(traces))
	board.queue_free()
	await get_tree().process_frame
	board = null
	lobby.close()
	lobby = null
	GameStart.reset()
	print("RESULT ", JSON.stringify({"suite":"T18_scoreboard_network_window","checks":checks,"failures":failures,"pressed":pressed_count,"gui_down":down_count,"gui_up":up_count,"motions":received_motion,"window":true,"transport":"controlled actual LobbySession transport signal; NOT ENet/multi-machine/hardware"}))
	get_tree().quit(0 if failures.is_empty() else 1)
