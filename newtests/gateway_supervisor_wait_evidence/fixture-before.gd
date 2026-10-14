extends "res://tests/match_journal_test.gd"

var worker_attach_wait_msec:int = 0

func run() -> void:
	GameStart.reset()
	var baseline = preload("res://scripts/match/net_ids.gd").new().snapshot({"players": GameData.player_data_library})
	var directory:String = _fixture_directory("server-match")
	if directory.is_empty():
		finish()
		return
	var gateway = preload("res://scripts/net/server/server_gateway.gd").new()
	_configure_gateway(gateway)
	var target:Dictionary = _start_gateway(gateway,directory)
	check(target.get("ok",false), "sole server entry starts full match fixture")
	if not target.get("ok",false):
		await cleanup(gateway, [], null)
		finish()
		return
	var port:int = target.port
	var address:String = target.address
	var agents: Array = []
	for index in range(2):
		var agent = preload("res://tests/net_process_full_game_test.gd").new()
		agent.session = preload("res://scripts/net/session/lobby_session.gd").new()
		agent.group = preload("res://scripts/net/ui/group_selection.gd").new()
		agent.session.blobs.cache.root = directory.path_join("client-cache")
		agents.append(agent)
		if not _configure_agent(agent.session,index):
			check(false,"隔离测试客户端配置失败")
			await cleanup(gateway,agents,null)
			finish()
			return
	var settings:Dictionary = _room_settings()
	settings["runtime_guard"] = {"enabled":true, "steps":9223372036854775807, "seconds":0.0}
	agents[0].session.join_server(address, port, "甲", "", "服务端完整对局", settings)
	var worker_wait_started:int = Time.get_ticks_msec()
	var startup_seconds:float = float(target.get("startup_seconds", gateway.manager.startup_seconds))
	var pump_ready:Callable = func():
		gateway.poll()
		for agent in agents: agent.session.poll(1.0 / 60.0)
	var attached:bool = await preload("res://tests/net_worker_ready_wait.gd").attached(get_tree(), pump_ready, agents[0].session, startup_seconds)
	worker_attach_wait_msec = Time.get_ticks_msec() - worker_wait_started
	check(attached, "按服务端明确 worker ready 等待，不用固定20秒截断 cache_seed")
	var deadline:int = Time.get_ticks_msec() + 5000
	while attached and agents[0].session.view.is_empty() and agents.all(func(agent): return agent.session.error.is_empty()) and Time.get_ticks_msec() < deadline:
		await pump(gateway, agents)
	if not attached or agents[0].session.view.is_empty():
		print("SERVER_JOIN_FAILURE ",agents[0].session.error)
		check(false, "room worker starts")
		await cleanup(gateway, agents, null)
		finish()
		return
	check(agents[0].session.view.get("settings", {}).get("runtime_guard", {}) == settings.runtime_guard, "网关及子进程明确携带完整预算到真实对局大厅")
	agents[1].session.join_server(address, port, "乙", agents[0].session.server_room_id)
	deadline = Time.get_ticks_msec() + 5000
	while agents[1].session.view.is_empty() and agents.all(func(agent): return agent.session.error.is_empty()) and Time.get_ticks_msec() < deadline:
		await pump(gateway, agents)
	if agents[1].session.view.is_empty() or agents.any(func(agent): return not agent.session.error.is_empty()):
		check(false,"第二位客户端首个入房失败立即终止："+str(agents.map(func(agent): return agent.session.error)))
		await cleanup(gateway,agents,null)
		finish()
		return
	if not await _after_room_joined(gateway,agents):
		await cleanup(gateway,agents,null)
		finish()
		return
	for index in range(2):
		var sync = preload("res://scripts/net/content/room_data_sync.gd").new()
		var root: String = directory.path_join("client-%s/data" % index)
		var sync_started:bool = sync.begin(agents[index].session, agents[index].session.room_files, root)
		check(sync_started, "client explicitly accepts actual server manifest")
		if not sync_started:
			await cleanup(gateway,agents,null)
			finish()
			return
		# 同步器声明的是单文件无进度期限，不是整个批准清单的总期限。
		# 夹具按已验证文件数声明有限总上界；单文件超时与完整安装断言均保留。
		var sync_wait_budget_msec:int = maxi(45000, int(ceil(sync.timeout_seconds * 1000.0)) * agents[index].session.room_files.size())
		deadline = Time.get_ticks_msec() + sync_wait_budget_msec
		while sync.running and sync.error.is_empty() and agents[index].session.error.is_empty() and Time.get_ticks_msec() < deadline:
			await pump(gateway, agents)
			sync.poll()
		var accepted: bool = sync.complete and sync.error.is_empty() and agents[index].session.error.is_empty() and agents[index].session.install_room_assets(root)
		if not accepted: sync.cancel()
		check(accepted, "all approved client files assemble and verify before ready")
		if not accepted:
			print("SYNC_ERROR ", sync.error, " session=", agents[index].session.error)
			await cleanup(gateway, agents, null)
			finish()
			return
		agents[index].session.request("data_ack", {"revision": agents[index].session.data_revision})
		agents[index].session.request("ready", {"ready": true})
	deadline = Time.get_ticks_msec() + 5000
	while not agents[0].session.view.get("can_start", false) and agents.all(func(agent): return agent.session.error.is_empty()) and Time.get_ticks_msec() < deadline:
		await pump(gateway, agents)
	var can_start:bool = agents[0].session.view.get("can_start", false)
	check(can_start, "real server data barrier opens only after both verified clients ack")
	if not can_start:
		await cleanup(gateway, agents, null)
		finish()
		return
	var board = await play_agents(gateway, agents)
	check(not GameStart._started and preload("res://scripts/match/net_ids.gd").new().snapshot({"players": GameData.player_data_library}) == baseline, "clients never execute local rule game or mutate local players")
	var baseline_passed:bool = failures.is_empty()
	if baseline_passed:
		await _after_baseline(gateway, agents)
	if not baseline_passed or not failures.is_empty():
		await cleanup(gateway, agents, board)
		finish()
		return
	_validate_board_after_baseline(board, agents)
	print("SERVER_MATCH decisions=", agents[0].decisions, ",", agents[1].decisions, " errors=", agents[0].session.error, "/", agents[1].session.error)
	await cleanup(gateway, agents, board)
	finish()

func play_agents(gateway, agents: Array):
	agents[0].session.request("start", {})
	var picked := [false, false]
	var began := false
	var bound := [false, false]
	var board
	var privacy_ok := true
	var match_budget_ms:int = 180000 if gateway.manager.record_matches else 90000
	var deadline := Time.get_ticks_msec() + match_budget_ms
	while Time.get_ticks_msec() < deadline:
		await pump(gateway, agents)
		if agents.any(func(agent): return not agent.session.error.is_empty()):
			check(false,"首个真实对局客户端错误立即停止："+str(agents.map(func(agent): return agent.session.error)))
			return board
		if _match_target_reached(agents): break
		for index in range(2):
			var session = agents[index].session
			if not picked[index] and not session.selection_view.get("choices", []).is_empty():
				var choice: Dictionary = session.selection_view.choices[0] if index == 0 else session.selection_view.choices.back()
				session.request("choose_master", {"seat": choice.seat, "name": choice.name})
				picked[index] = true
			if not bound[index] and not session.read_match().is_empty():
				agents[index].group.bind_session(session)
				bound[index] = true
				if index == 0 and OS.get_cmdline_user_args().has("window") and DisplayServer.get_name() != "headless":
					board = preload("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
					board.network_session = session
					add_child(board)
			agents[index].act()
			if _diagnostic_agent_stop(gateway,agents):
				check(false,"诊断精确持续同状态停止，不是业务PASS")
				return board
			for player in session.read_match().get("players", []):
				privacy_ok = privacy_ok and (player.own or player.hand_cards.is_empty())
		if not began and agents[0].session.selection_view.get("complete", false):
			agents[0].session.request("begin_match", {})
			began = true
		if _match_target_reached(agents):
			break
	check(_match_target_reached(agents), "actual authority and network clients reach declared match target")
	check(agents.all(func(agent): return agent.decisions > 0), "both human seats submit actual gameplay commands")
	check(privacy_ok, "other players private hands stay filtered throughout network match")
	return board

func pump(gateway, agents: Array) -> void:
	gateway.poll()
	for agent in agents:
		agent.session.poll(1.0 / 60.0)
	await get_tree().process_frame

func _validate_board_after_baseline(board,agents:Array) -> void:
	if is_instance_valid(board):
		check(board._strips.get_child_count() == agents[0].session.read_match().get("areas",[]).size(), "formal window renders actual authoritative server map through game end")
		RenderingServer.force_draw(true)
		get_viewport().get_texture().get_image().save_png("res://tests/runtime_reports/net_server_match.png")

func _configure_gateway(gateway) -> void:
	# 夹具按正式保存关闭协议收尾，显式启用真实录制，不伪造 saved。
	gateway.manager.record_matches = true

func _start_gateway(gateway,directory:String) -> Dictionary:
	var paths = preload("res://scripts/net/server/recovery_path_safety.gd")
	var data_root:String = paths.absolute(LoadHelper.resolve_path(LoadHelper.DATA_DIR_NAME))
	if data_root.is_empty() or not paths.checked(data_root,data_root) or not DirAccess.dir_exists_absolute(data_root):
		print("FIXTURE_PRECONDITION deployment data root unsafe or missing")
		return {"ok":false}
	if not paths.checked(directory,directory): return {"ok":false}
	gateway.manager.approved_data_root = data_root
	gateway.manager.storage_root = directory.path_join("workers")
	if DirAccess.make_dir_recursive_absolute(gateway.manager.storage_root) != OK or not paths.checked(directory,gateway.manager.storage_root):
		return {"ok":false}
	gateway.manager.internal_port_base = 60000 + int(OS.get_process_id() % 1000)
	var port:int = preload("res://tests/net_port_fixture.gd").available_range(42000,44000,1)
	var listening:bool = port > 0 and gateway.listen(port,"127.0.0.1",data_root) == OK
	# listen 先关闭旧监听；本机组合入口在成功监听后显式打开接入。
	if listening: gateway.accepting_rooms = true
	return {"address":"127.0.0.1","port":port,"ok":listening}

## 测试组合入口显式授权，原始路径不修复；环境由执行者配置为物理 scratch。
static func fixture_directory(label:String) -> Dictionary:
	var paths = preload("res://scripts/net/server/recovery_path_safety.gd")
	var approved:String = OS.get_environment("FATE_TEST_SCRATCH_ROOT")
	var args:PackedStringArray = OS.get_cmdline_user_args()
	if approved.is_empty() or args.is_empty():
		return {"ok":false,"error":"需要显式 FATE_TEST_SCRATCH_ROOT 及首个输出根参数"}
	var root:String = args[0]
	if paths.absolute(approved).is_empty() or paths.absolute(root).is_empty() or not paths.checked(approved,root) or not DirAccess.dir_exists_absolute(root):
		return {"ok":false,"error":"输出根必须是已批准物理scratch内已存在目录；不接受链接或非规范参数"}
	var output:String = root.path_join("%s-%s-%s" % [label,OS.get_process_id(),Time.get_ticks_usec()])
	if not paths.checked(approved,output,true) or DirAccess.dir_exists_absolute(output) or DirAccess.make_dir_absolute(output) != OK or not paths.checked(approved,output):
		return {"ok":false,"error":"独占输出目录创建/安全复查失败"}
	return {"ok":true,"directory":output}

func _fixture_directory(label:String) -> String:
	var result:Dictionary = fixture_directory(label)
	check(result.ok,"测试组合入口批准物理scratch："+str(result.get("error","")))
	return str(result.get("directory",""))

func _room_settings() -> Dictionary:
	return {"capacity":2,"minimum":2,"selection_mode":"unique_master_class_pool","ai_count":0,"spectator_limit":2}

func _after_room_joined(_gateway,_agents:Array) -> bool: return true

func _match_target_reached(agents:Array) -> bool:
	return agents.all(func(agent): return agent.session.read_match().get("game_over", false))

func _after_baseline(_gateway, _agents) -> void: pass

func _diagnostic_agent_stop(_gateway, _agents:Array) -> bool: return false

func cleanup(gateway, agents: Array, board) -> void:
	if is_instance_valid(board):
		board.queue_free()
		await get_tree().process_frame
	for agent in agents:
		agent.group.bind_session(null)
		agent.session.close()
		agent.free()
	var owned:Array = gateway.manager.rooms.values().map(func(room): return room.duplicate(true))
	if not owned.is_empty():
		var console = preload("res://scripts/net/server/server_console_channel.gd").new()
		var relay = preload("res://scripts/net/p2p/p2p_signal_server.gd").new()
		check(console.configure("",gateway,relay) == OK,"配置正式保存关闭入口")
		var shutdown = preload("res://scripts/net/server/server_shutdown.gd").new()
		shutdown.gateway = gateway
		shutdown.signaling = relay
		shutdown.console = console
		check(shutdown.start([]).ok,"发出正式保存关闭请求")
		var deadline:int = Time.get_ticks_msec() + 35000
		while shutdown.stage == "pending" and Time.get_ticks_msec() < deadline:
			gateway.poll()
			shutdown.poll()
			await get_tree().process_frame
		check(shutdown.stage == "complete","保存回执及原生EXITED确认后释放；失败不强杀："+str(shutdown.status([])))
		# 仅成功保存且句柄已release时撤销停止登记；UNKNOWN/失败不走stop。
		if shutdown.stage == "complete": gateway.manager.close()
	gateway.close()
	check(gateway.manager.rooms.is_empty(), "正常或失败结束均释放全部房间登记及进程所有权")
	for room in owned:
		var binding:Dictionary = {"room":room.id,"pid":room.pid,"instance_id":room.instance_id,"authority_host_mode":room.authority_host_mode}
		check(gateway.manager.process_state_for_binding(binding) != 1, "清理后公开实例查询不再报告工作进程存活")

func _configure_agent(_session,_index:int) -> bool:
	return true
