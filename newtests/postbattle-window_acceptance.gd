extends Node

# 真实三连接ENet回环；会话/source/commands/board与规则均为生产类。
# 测试服务器只递送权威实际签发的视图、待答、动作与submit返回，不造规则状态。
const Authority = preload("res://scripts/net/authority/match_authority.gd")
const Selection = preload("res://scripts/net/authority/selection_authority.gd")
const Mode = preload("res://scripts/selection/class_pool_selection.gd")
const Lobby = preload("res://scripts/net/session/lobby_session.gd")
const Transport = preload("res://scripts/net/transport/enet_transport.gd")
const Board = preload("res://assets/scenes/game_scene/battle_board_v2.tscn")
var checks := 0
var failures: Array = []
var server = Transport.new()
var sessions: Array = []
var peers: Array = []
var authority
var room = preload("res://scripts/net/session/room_state.gd").new()
var context: SessionContext
var board: Control
var boards: Dictionary = {}
var replies: Array = []
var selected_seat := -1
var window_mode := false
var finished := false
var serial := 0
var captures := 0
var output := "E:/scratch/continuous-next-wave/postbattle-window/window01"

func check(ok: bool, label: String) -> void:
	checks += 1
	print("CHECK ", label, " ", ok)
	if not ok: failures.append(label)

func _ready() -> void:
	window_mode = OS.get_cmdline_user_args().has("window")
	call_deferred("run")

func _process(_delta: float) -> void:
	if finished: return
	server.poll()
	for s in sessions: s.poll()

func frames(n: int = 5) -> void:
	for i in range(n): await get_tree().process_frame

func fatal(label: String) -> bool:
	if failures.is_empty(): return false
	print("STOP ", label)
	await finish()
	return true

func receive(sender: int, message: Dictionary) -> void:
	if authority == null or message.get("kind") != "match_command": return
	var args: Dictionary = message.get("args", {})
	var ok: bool = authority.submit(sender, args.get("view_seq", -1), args.get("command", ""), args.get("params", {}))
	var reason: String = authority.error
	replies.append({"peer":sender,"seat":authority.observer_for(sender),"request":message.seq,"kind":args.command,"ok":ok,"reason":reason})
	print("AUTHORITY_REPLY ", JSON.stringify(replies.back()))
	server.send(sender, {"kind":"match_command_result","result_version":Lobby.MATCH_COMMAND_RESULT_VERSION,"seq":message.seq,"ok":ok,"reason":reason})
	publish()

func publish() -> void:
	for peer in peers:
		var view: Dictionary = authority.view_for(peer)
		server.send(peer, {"kind":"match_view","state":view,"pending":authority.pending_for(peer),"actions":authority.actions_for(peer)})

func setup_connections() -> void:
	server.message_received.connect(receive)
	var port := 0
	for candidate in range(38670,38690):
		if server.listen(candidate, "127.0.0.1", 3) == OK:
			port = candidate
			break
	check(port > 0, "真实回环ENet监听")
	if port == 0: return
	for seat in range(3):
		var s = Lobby.new()
		sessions.append(s)
		check(s.transport.connect_to("127.0.0.1", port) == OK, "真实连接席位%d" % seat)
	for attempt in range(900):
		if sessions.all(func(s): return s.transport.is_connected_to_host()): break
		await frames(1)
	await frames(15)
	for s in sessions:
		peers.append(s.transport.peer_id())
	check(peers.size() == 3 and peers[0] > 1 and peers[1] > 1 and peers[2] > 1 and peers[0] != peers[1] and peers[1] != peers[2] and peers[0] != peers[2], "三席真实连接身份独立")
	print("ENET_PEERS ", peers)

func start_game() -> void:
	preload("res://scripts/match/rule_random.gd").start_seed(775041)
	var selection = Selection.new()
	var controllers := {0:peers[0],1:peers[1],2:peers[2]}
	check(room.configure(peers[0], {"capacity":3,"minimum":3,"ai_count":0,"selection_mode":"class_pool","spectator_limit":0}), "真实房间容量/零AI声明")
	for seat in range(3): check(room.join(peers[seat],"窗口玩家%d" % seat), "真实房间成员%d" % seat)
	for peer in peers: check(room.set_ready(peer,true), "真实房间成员准备")
	check(room.start(peers[0]), "真实房间进入选人")
	check(selection.setup(Mode.new(), controllers, GameStart.get_masters_can_use(), GameStart.get_servants_can_use(), {"regular_classes":["saber","assassin","lancer"],"per_class_count":1,"special_count":0,"randomize_initial_order":false}), "正式三玩家选人")
	check(selection.choose(peers[0],0,"emiya_shirou"), "席位0正式御主选择")
	check(selection.choose(peers[1],1,"kuzuki_souichirou"), "席位1正式御主选择")
	check(selection.choose(peers[2],2,"tohsaka_rin"), "席位2正式御主选择")
	authority = Authority.new()
	check(authority.declare_broadcast_confirmation(true), "权威组合根明确全部真人确认")
	check(authority.start(selection), "正式权威GameStart: " + authority.error)
	if not authority.started: return
	# 对应正式Session成功begin后的组合根提交；不注入客户机view或待答。
	room.phase = "playing"
	room.revision += 1
	var room_view: Dictionary = room.snapshot()
	var members: Array = []
	for peer in room_view.members:
		var member: Dictionary = room_view.members[peer].duplicate(true)
		member.id = peer
		members.append(member)
	room_view.members = members
	for peer in peers: server.send(peer,{"kind":"room","state":room_view})
	context = GameStart.startup_context()
	check(SessionGeneration.validate_context(context).ok, "保存真实开局原context")
	check(not EffectManager.is_waiting_for_choice(), "开局不存在未决效果")
	for seat in range(3):
		check(authority.observer_for(peers[seat]) == seat, "权威绑定本席%d不代答" % seat)
		authority.bind_notification_boundary(peers[seat])
		server.send(peers[seat], {"kind":"match_bind","observer":seat})
	publish()
	await frames(15)
	for seat in range(3): check(sessions[seat].read_match().get("observer",-1) == seat, "正式会话绑定观察席%d" % seat)

func prepare_battle(round_number: int) -> BaseEvent:
	# 原191可信夹具相同受控初始输入；本测试不重置生命周期/不造等待或战报。
	check(not GameProgress.has_battle_resolved, "第%d轮新战前flag=false" % round_number)
	check(EventResolver.new().clear_all(context).ok, "原context清除事件")
	check(SituationResolver.new().clear_all(context).ok, "原context清除局势")
	GameLog.reset()
	GameProgress.current_phase_index = 3
	GameProgress.current_phase_player_index = 0
	GameProgress.current_player_id = -1
	GameProgress.total_rounds.number = 11
	GameProgress.event_placements = []
	MapData.event_deck.clear()
	MapData.event_discard.clear()
	for seat in range(3):
		var p: Dictionary = GameDataManager.find_player_data(seat)
		p.is_out = false
		p.order.number = seat
		p.power.number = 0 if seat == 0 else 20
		p.command_spell_count.number = 0
		check(SetLocation.new().exec(MapData.miyama._locations[0],seat,false,true,true,context), "原context受控落位%d" % seat)
	var template: BaseEvent
	for item in LoadEvent.events:
		if item._name == "contain_third_party": template = item; break
	check(template != null, "正式contain_third_party模板")
	if template == null: return null
	var cloner := CloneContext.new()
	check(cloner.configure_template(context,[template]), "可信模板runtime创建边界")
	var copied: Dictionary = cloner.copy_result(template,context)
	var event: BaseEvent = copied.object as BaseEvent
	check(event != null, "正式原卡runtime实例")
	if event == null: return null
	AddMapAreaEvents.new().exec(MapData.miyama,event)
	check(EventResolver.new().register_entered(event,context), "原事件正常登记")
	GameProgress.begin_phase(context)
	publish()
	return event

func select_view(seat: int) -> void:
	selected_seat = seat
	if not window_mode and not OS.get_cmdline_user_args().has("board-preflight"): return
	if board != null:
		board.hide()
		board.process_mode = Node.PROCESS_MODE_DISABLED
	if not boards.has(seat):
		board = Board.instantiate()
		board.network_session = sessions[seat]
		boards[seat] = board
		add_child(board)
	else:
		board = boards[seat]
		board.process_mode = Node.PROCESS_MODE_INHERIT
		board.show()
		board.refresh_all_ui()
	await frames(180)
	check(board.is_visible_in_tree(), "正式V2可见本席%d" % seat)
	print("VISIBLE_OBSERVER ", seat, " session=", sessions[seat].read_match().get("observer",-1))

func gui_click(button: Button, label: String) -> void:
	check(button != null and button.is_visible_in_tree() and not button.disabled, "真实按钮可操作 " + label)
	if button == null or not button.is_visible_in_tree() or button.disabled: return
	var pressed := [0]
	var watch := func(): pressed[0] += 1
	button.pressed.connect(watch)
	var point := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	serial += 1
	get_viewport().push_input(motion,true)
	print("INPUT ",serial," Viewport.MouseMotion ",point," label=",label)
	await frames(2)
	check(get_viewport().gui_get_hovered_control() == button, "真实GUI命中 " + label)
	for down in [true,false]:
		var input := InputEventMouseButton.new()
		input.position = point
		input.button_index = MOUSE_BUTTON_LEFT
		input.pressed = down
		serial += 1
		get_viewport().push_input(input,true)
		print("INPUT ",serial," Viewport.Left ",down," point=",point," label=",label)
		await frames(1)
	await frames(10)
	check(pressed[0] == 1, "正式pressed一次 " + label)
	if is_instance_valid(button) and button.pressed.is_connected(watch): button.pressed.disconnect(watch)

func command(kind: String, args: Dictionary, label: String) -> void:
	var before := replies.size()
	if window_mode:
		var button: Button
		if kind == "end_action": button = board.get_node("Ops/EndButton")
		elif kind == "option_choice": button = board.get_node("ModalLayer/EffectChoice/Box/OptionsRow").get_child(args.choices[0].index) as Button
		elif kind == "confirm_broadcast": button = board.get_node("BattleBroadcast/ContinueBtn")
		await gui_click(button,label)
	else:
		if board != null:
			var target: Button
			if kind == "end_action": target = board.get_node("Ops/EndButton")
			elif kind == "option_choice": target = board.get_node("ModalLayer/EffectChoice/Box/OptionsRow").get_child(args.choices[0].index) as Button
			elif kind == "confirm_broadcast": target = board.get_node("BattleBroadcast/ContinueBtn")
			check(target != null and target.is_visible_in_tree() and not target.disabled, "headless真实V2按钮可见可用 " + label)
		var v: Dictionary = sessions[selected_seat].read_match()
		check(sessions[selected_seat].request("match_command",{"view_seq":v.seq,"command":kind,"params":args}) == OK, "正式会话发送 " + label)
	for attempt in range(180):
		if replies.size() > before: break
		await frames(1)
	check(replies.size() == before+1 and replies.back().ok and replies.back().seat == selected_seat and replies.back().kind == kind, "本席权威实际接受一次 " + label)

func scores() -> Array:
	var values: Array = []
	for seat in range(3): values.append(GameDataManager.find_player_data(seat).score.number)
	return values

func count_time(point: String) -> int:
	return GameLog.query({"type":"time_point","tags":[point]},null).size()

func battles() -> Array:
	return GameLog.query({"type":"battle","place":MapData.miyama._area_name},null)

func state(label: String) -> Dictionary:
	var p: BaseEffect = EffectManager.get_pending_active_effect()
	var d := {"label":label,"round":GameProgress.current_round,"phase":GameProgress.get_current_phase().name,"resolved":GameProgress.has_battle_resolved,"battle_state":GameProgress.battle_resolution_state(),"report_unsealed":GameProgress.last_battle_result.has("_score_before"),"pending_id":p.get_instance_id() if p != null else 0,"pending_seat":p._trigger_player_id if p != null else -1,"scores":scores(),"battle_facts":battles().size(),"BATTLE_END":count_time(TimePoints.BATTLE_END),"PHASE_END":count_time(TimePoints.PHASE_END),"DAY_END":count_time(TimePoints.DAY_END),"broadcast_pending":GameProgress.is_battle_broadcast_pending(),"selected_observer":selected_seat}
	print("PUBLIC_STATE ",JSON.stringify(d))
	return d

func waiting(event: BaseEvent, round_number: int, label: String) -> void:
	var d := state(label)
	check(d.round == round_number and d.phase == "battle" and d.resolved and d.battle_state == BattleResolver.ResultState.PENDING_POST_BATTLE, label + " settled但仍PENDING")
	check(d.report_unsealed and EffectManager.is_waiting_for_choice(), label + " 战报未封存且问题保留")
	check(MapData.miyama._events.has(event) and not MapData.event_discard.has(event), label + " 原事件仍在")
	check(d.battle_facts == 3 and d.BATTLE_END == 1 and d.PHASE_END == 0 and d.DAY_END == 0 and not d.broadcast_pending, label + " 唯一战斗/未收尾/未播报")

func capture(label: String) -> void:
	if not window_mode: return
	await RenderingServer.frame_post_draw
	var path := output + "/" + label + ".png"
	check(get_viewport().get_texture().get_image().save_png(path) == OK, "真实非headless截图 " + label)
	captures += 1
	print("SCREENSHOT ",path)

func run() -> void:
	await setup_connections()
	if await fatal("connections"): return
	await start_game()
	if await fatal("start"): return
	var previous_choice := 0
	for round_number in [1,2]:
		var event := prepare_battle(round_number)
		await frames(15)
		if await fatal("prepare"): return
		for seat in [0,1,2]:
			await select_view(seat)
			check(GameProgress.current_player_id == seat, "真实当前行动席%d" % seat)
			await command("end_action",{},"第%d轮席%d结束行动" % [round_number,seat])
			if await fatal("end action"): return
		var base_scores := scores()
		check(base_scores[0] == 0 and base_scores[1] > 0 and base_scores[1] == base_scores[2], "0败者/1与2真实并列分")
		for fact in battles(): check(fact.data.winners.size() == 2 and fact.data.winners.has(1) and fact.data.winners.has(2), "真实并列胜者排除0")
		var answered: Array = []
		for index in range(2):
			var pending: BaseEffect = EffectManager.get_pending_active_effect()
			check(pending != null, "真实战后问题%d" % index)
			if pending == null: await finish(); return
			var winner := pending._trigger_player_id
			check(winner in [1,2] and not answered.has(winner) and pending._name == "contain_third_party_restore_seal_choice", "原卡问题仅当前胜者")
			check(pending.get_instance_id() != previous_choice, "两轮问题身份不共享")
			await select_view(winner)
			waiting(event,round_number,"待答%d/%d" % [round_number,index])
			check(sessions[winner].read_pending().get("effect",-1) == authority.builder.ids.id_for(pending), "真实会话待答ID对应同一效果")
			for other in range(3):
				if other != winner: check(sessions[other].read_pending().is_empty(), "其它席%d不获代答" % other)
			await capture("r%d-%d-pending-seat%d" % [round_number,index+1,winner])
			for attempt in range(2):
				check(not GameProgress.end_current_player_action(context), "待答公共推进拒绝")
				GameProgress.end_phase(context)
				await frames(15)
				check(EffectManager.get_pending_active_effect() == pending and scores() == base_scores, "跨帧/重入身份奖励不重放")
				waiting(event,round_number,"跨帧%d/%d/%d" % [round_number,index,attempt])
			var option := (0 if winner == 1 else 1) if round_number == 1 else (1 if winner == 1 else 0)
			await command("option_choice",{"effect":authority.builder.ids.id_for(pending),"choices":[{"index":option,"count":1}]},"胜者%d选项%d" % [winner,option])
			answered.append(winner)
			previous_choice = pending.get_instance_id()
			if index == 0: waiting(event,round_number,"第一答后第二问题仍在")
			if await fatal("choice"): return
		check(answered.size() == 2 and not EffectManager.is_waiting_for_choice(), "两胜者都答完")
		for seat in range(3):
			var expected := 1 if (seat == 1 and round_number == 1) or (seat == 2 and round_number == 2) else 0
			check(GameDataManager.find_player_data(seat).command_spell_count.number == expected, "各胜者恢复结果独立%d" % seat)
		# 真实source若仍需完成战后续行，走合法当前行动席的结束按钮。
		publish(); await frames(15)
		if not GameProgress.is_battle_broadcast_pending():
			var current := GameProgress.current_player_id
			if current >= 0:
				await select_view(current)
				await command("end_action",{},"答完后正式续行")
		check(GameProgress.battle_resolution_state() == BattleResolver.ResultState.SEALED and not GameProgress.last_battle_result.has("_score_before"), "两答后才SEALED")
		check(count_time(TimePoints.PHASE_END) == 1 and count_time(TimePoints.DAY_END) == 0, "阶段尾一次且播报前DAY_END0")
		check(GameProgress.is_battle_broadcast_pending(), "真实声明播报等待全部确认")
		state("两答封存播报")
		for seat in range(3):
			await select_view(seat)
			await frames(150)
			if seat == 0: await capture("r%d-3-sealed-broadcast" % round_number)
			var batch := GameProgress.battle_broadcast_batch_id()
			check(GameProgress.can_confirm_battle_broadcast(seat,batch), "真实需要本席确认%d" % seat)
			await command("confirm_broadcast",{"batch_id":batch},"本席%d继续播报" % seat)
			if await fatal("broadcast"): return
		await frames(20)
		check(GameProgress.current_round == round_number+1 and GameProgress.get_current_phase().name == "prepare" and not GameProgress.has_battle_resolved, "下一轮prepare且flag复位")
		check(MapData.event_discard.count(event) == 1 and not MapData.miyama._events.has(event), "原事件仅弃一次")
		check(battles().size() == 3 and count_time(TimePoints.BATTLE_END) == 1 and count_time(TimePoints.PHASE_END) == 1 and count_time(TimePoints.DAY_END) == 1, "全过程事实与阶段/回合尾均一次")
		check(scores() == base_scores, "续行不重复奖励/不混阶段收益")
		state("下一轮prepare")
		await capture("r%d-4-next-round" % round_number)
		if await fatal("round close"): return
	await finish()

func finish() -> void:
	if finished: return
	for item in boards.values(): item.queue_free()
	boards.clear()
	board = null
	await frames(3)
	for s in sessions: s.close()
	sessions.clear()
	server.close()
	if authority != null: authority.close_archive()
	authority = null
	GameStart.end_session()
	finished = true
	print("WINDOW_RUN_COUNT ", 1 if window_mode else 0, " CAPTURES ",captures)
	print("RESULT checks=", checks, " failures=",JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
