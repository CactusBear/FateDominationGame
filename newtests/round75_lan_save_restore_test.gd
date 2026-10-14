extends Node

const Lobby = preload("res://scripts/net/session/lobby_session.gd")
const Host = preload("res://scripts/net/session/authority_host_client.gd")
const Sync = preload("res://scripts/net/content/room_data_sync.gd")
const Channel = preload("res://scripts/net/server/server_console_channel.gd")
const Journal = preload("res://scripts/match/match_journal.gd")
const Equivalence = preload("res://tests/round36_gateway_equivalence.gd")
const Ports = preload("res://tests/net_port_fixture.gd")
var host_client
var sessions:Array = []
var keys:Array = []
var root:String
var evidence:String
var stage:String = "preflight"
var checks:int = 0
var failures:Array = []
var first_failure:Dictionary = {}
var requests:Array = []
var command_results:Array = []
var locks:Array = [-1,-1]
var expected:Array = []
var before_seq:Array = []
var asset_hashes:Dictionary = {}
var source:String = ""
var source_hash:String = ""
var saved_identity:Dictionary = {}
var restoring_done:bool = false
var restoring_ok:bool = false
var closing:bool = false

func _ready() -> void:
	root = OS.get_environment("R75_RUNTIME_ROOT")
	evidence = OS.get_environment("R75_EVIDENCE_ROOT")
	call_deferred("run")

func _process(delta:float) -> void:
	if not sessions.is_empty():
		sessions[0].poll(delta)
		sessions[1].poll(delta)

func event(kind:String, data:Dictionary = {}) -> void:
	var item:Dictionary = {"stage":stage,"kind":kind,"ticks_msec":Time.get_ticks_msec(),"pid":OS.get_process_id(),"data":data}
	var path:String = evidence.path_join("stages.jsonl")
	var stream = FileAccess.open(path,FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if stream != null:
		stream.seek_end(); stream.store_line(JSON.stringify(item)); stream.close()
	print("R75_EVENT ",JSON.stringify(item))

func enter(value:String) -> void:
	stage = value
	event("enter")

func states() -> Array:
	return sessions.map(func(session): return {"connected":session.transport.is_connected_to_host(),"authenticated":session.identity_authenticated,"member":session.peer_id(),"error":session.error,"room_phase":session.view.get("phase"),"data_revision":session.data_revision,"view":session.read_match(),"pending":session.read_pending(),"actions":session.read_actions()})

func guard(value:bool, label:String) -> bool:
	checks += 1
	print("CHECK ",value," ",label)
	if not value:
		failures.append(label)
		if first_failure.is_empty():
			first_failure = {"stage":stage,"label":label,"ticks_msec":Time.get_ticks_msec(),"clients":states(),"host":host_client.diagnostics() if host_client != null else {},"manager_error":host_client.gateway.manager.error if host_client != null else "","commands":requests,"receipts":command_results}
			Channel.write_json(evidence.path_join("first-failure.json"),first_failure)
		event("failure",{"label":label})
	else: event("check",{"label":label})
	return value

func healthy() -> bool:
	if FileAccess.file_exists(evidence.path_join("stop-normal.request")): return false
	if host_client != null and not host_client.error.is_empty(): return false
	if host_client != null and not host_client.room_id.is_empty():
		var room:Dictionary = host_client.gateway.manager.rooms.get(host_client.room_id,{})
		if not str(room.get("error","")).is_empty(): return false
	return sessions.all(func(session): return session.error.is_empty())

func wait_for(predicate:Callable, budget:int) -> bool:
	var deadline:int = Time.get_ticks_msec()+budget
	while Time.get_ticks_msec()<deadline:
		if not healthy(): return false
		if predicate.call(): return true
		await get_tree().process_frame
	return false

func command(index:int, kind:String, args:Dictionary = {}) -> bool:
	var registration:Dictionary = {}
	var result:Error = sessions[index].request(kind,args,func(sequence:int): registration.sequence = sequence)
	var item:Dictionary = {"client":index,"kind":kind,"args":args,"send_error":result,"request":registration.get("sequence",-1),"ticks_msec":Time.get_ticks_msec()}
	requests.append(item)
	event("command",item)
	return guard(result == OK,"真实命令发送 "+kind)

func observe_result(sequence:int, ok:bool, reason:String, index:int) -> void:
	var item:Dictionary = {"client":index,"request":sequence,"ok":ok,"reason":reason,"seq":sessions[index].read_match().get("seq"),"ticks_msec":Time.get_ticks_msec()}
	command_results.append(item)
	event("command_result",item)

func open_round(label:String) -> bool:
	enter(label+"_host_join")
	host_client = Host.new()
	sessions = [Lobby.new(),Lobby.new()]
	for index in range(2):
		sessions[index].player_identity._key = keys[index]
		sessions[index].identity_profile = {"public_key":sessions[index].player_identity.public_key(),"username":"R75_Player_%d" % index,"nickname":"本轮客户端%d" % index}
		sessions[index].blobs.cache.root = root.path_join("cache-%d" % index)
		sessions[index].request_completed.connect(observe_result.bind(index))
		sessions[index].rejected.connect(func(reason:String): event("client_rejected",{"client":index,"reason":reason}))
		sessions[index].transport.peer_disconnected.connect(func(peer:int): event("native_disconnected",{"client":index,"peer":peer,"cleanup":closing}))
	sessions[0].record_matches = true
	var base:int = Ports.available_range(54000,58000,3)
	if not guard(base > 0,"实际 UDP 端口探测"): return false
	host_client.gateway.manager.internal_port_base = base+1
	host_client.gateway.manager.internal_port_count = 2
	var cfg = ConfigFile.new()
	if not guard(cfg.load("res://assets/config/server.cfg") == OK,"读取冻结正式配置"): return false
	var modes:Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LoadHelper.get_data_dir().path_join("selection_modes.json")))
	var settings:Dictionary = {"capacity":2,"minimum":2,"ai_count":0,"selection_mode":modes.default_mode,"spectator_limit":1,"random_sim_enabled":cfg.get_value("data","random_sim_enabled"),"random_sim_budget_sec":cfg.get_value("data","random_sim_budget_sec")}
	event("deployment",{"settings":settings,"worker_pool":ProjectSettings.get_setting("threading/worker_pool/max_threads"),"automatic_cleanup":"unconfigured/disabled","engine":OS.get_executable_path(),"project":ProjectSettings.globalize_path("res://"),"user":OS.get_user_data_dir(),"port":base})
	var result:Error = host_client.start(sessions[0],"R75-LAN-"+label,settings,"lan",base,"127.0.0.1",null,root.path_join(label+"/workers"))
	event("host.start",{"return":result})
	if not guard(result == OK,"生产房主入口启动 manager/worker"): return false
	sessions[0].authority_host = host_client
	if not guard(await wait_for(func(): return host_client.gateway.manager.is_ready(host_client.room_id) and sessions[0].view.get("owner") == sessions[0].peer_id() and host_client._identity_bridge.confirmed,45000),"房主 worker READY、真实成员及身份 IPC"): return false
	result = sessions[1].join("127.0.0.1",base,"非授权昵称")
	event("guest.join",{"return":result})
	if not guard(result == OK and await wait_for(func(): return sessions[1].identity_authenticated and sessions.all(func(session): return session.view.get("members",[]).size() == 2 and not session.room_files.is_empty()),20000),"客机真实 ENet/RSA 加入双成员"): return false
	var binding:Dictionary = host_client.gateway.manager.instance_binding(host_client.room_id)
	event("native_binding",{"binding":binding,"state":host_client.gateway.manager.process_state_for_binding(binding)})
	return guard(host_client.gateway.manager.binding_matches(binding,true) and host_client.gateway.manager.process_state_for_binding(binding) == 1,"原生句柄证明真实独立权威存活")

func sync_all(ready:bool) -> bool:
	for index in range(2):
		var session = sessions[index]
		var directory:String = root.path_join(stage+"/client-%d/revision-%d/data" % [index,session.data_revision])
		var sync = Sync.new()
		if not guard(sync.begin(session,session.room_files,directory),"正式清单逐文件同步开始"): return false
		var deadline:int = Time.get_ticks_msec()+90000
		while sync.running and sync.error.is_empty() and healthy() and Time.get_ticks_msec()<deadline:
			sync.poll(); await get_tree().process_frame
		event("sync",{"client":index,"complete":sync.complete,"error":sync.error,"files":session.room_files.size(),"completed_files":sync.completed_files})
		if not guard(sync.complete and sync.error.is_empty() and healthy(),"正式同步真实完成"): sync.cancel(); return false
		if not guard(session.install_room_assets(directory),"安装真实展示资产"): return false
		if not command(index,"data_ack",{"revision":session.data_revision}): return false
		if ready and not command(index,"ready",{"ready":true}): return false
	return true

func approve_content() -> bool:
	enter("original_content_approval")
	if not command(0,"server_data_catalog"): return false
	if not guard(await wait_for(func(): return not sessions[0].server_data.get("entries",[]).is_empty(),20000),"公开候选目录到达"): return false
	var selected:Array = []
	for entry in sessions[0].server_data.entries: selected.append({"provider":entry.provider,"key":entry.key})
	if not command(0,"server_data_prepare",{"catalog_revision":sessions[0].server_data.catalog_revision,"selected":selected}): return false
	if not guard(await wait_for(func(): return sessions[0].server_data.get("status",{}).get("stage") in ["ready","error"],180000) and sessions[0].server_data.get("status",{}).get("stage") == "ready","正式15秒随机预检与静态校验返回 ready"): return false
	var status:Dictionary = sessions[0].server_data.status
	event("preparation_status",status)
	if not command(0,"server_data_commit",{"request_id":status.request_id}): return false
	if not guard(await wait_for(func(): return sessions[0].server_data.get("status",{}).get("stage") in ["applied","error"],90000) and sessions[0].server_data.get("status",{}).get("stage") == "applied","正式候选批准 applied"): return false
	enter("original_sync_ready")
	if not await sync_all(true): return false
	return guard(await wait_for(func(): return sessions[0].view.get("can_start",false),20000),"双端数据 ACK 与准备屏障")

func select_and_begin() -> bool:
	enter("selection")
	if not command(0,"start"): return false
	for index in range(2):
		if not guard(await wait_for(func(): return not sessions[index].selection_view.get("choices",[]).is_empty(),30000),"真实选人选项到达"): return false
		var choice:Dictionary = sessions[index].selection_view.choices[0] if index == 0 else sessions[index].selection_view.choices.back()
		if not command(index,"choose_master",{"seat":choice.seat,"name":choice.name}): return false
		await get_tree().process_frame
	if not guard(await wait_for(func(): return sessions[0].selection_view.get("complete",false),30000),"正式选人完成"): return false
	enter("begin_match")
	if not command(0,"begin_match"): return false
	return guard(await wait_for(func(): return sessions.all(func(session): return not session.read_match().is_empty()),90000),"录制开局双方非空权威视图")

func advance() -> bool:
	enter("advance_beyond_round_one")
	var deadline:int = Time.get_ticks_msec()+90000
	while healthy() and Time.get_ticks_msec()<deadline:
		if sessions.all(func(session): return session.read_match().get("round",0) >= 2 and not session.read_match().get("game_over",true)): return guard(true,"双端真实状态超过第1回合")
		for index in range(2):
			var view:Dictionary = sessions[index].read_match()
			if view.is_empty() or view.get("game_over",false) or locks[index] == view.seq: continue
			var prompt:Dictionary = sessions[index].read_pending()
			var kind:String = ""
			var params:Dictionary = {}
			if not prompt.is_empty():
				params.effect = prompt.effect
				if prompt.get("allow_cancel",false): kind = "cancel_choice"
				else:
					kind = prompt.kind
					match kind:
						"active_choice":
							kind = "option_choice"; params.choices = []
							for option in prompt.options:
								if option.available:
									var chosen:Dictionary = {"index":option.index,"count":1}
									if option.has("quantity_range"): chosen.quantity = option.quantity_range[0]
									params.choices.append(chosen); break
						"card_choice":
							params.cards = prompt.required.duplicate()
							for card in prompt.cards:
								if params.cards.size() >= prompt.min: break
								if not params.cards.has(card): params.cards.append(card)
						"player_choice": params.players = prompt.players.slice(0,prompt.min)
						"location_choice":
							if not prompt.areas.is_empty(): params.area = prompt.areas[0]
			elif view.current_player == view.observer:
				var actions:Dictionary = sessions[index].read_actions()
				if not actions.get("deploy_areas",[]).is_empty(): kind = "deploy"; params.area = actions.deploy_areas[0]
				elif actions.get("can_end",false): kind = "end_action"
			if not kind.is_empty():
				locks[index] = view.seq
				if not command(index,"match_command",{"view_seq":view.seq,"command":kind,"params":params}): return false
		await get_tree().process_frame
	return guard(false,"真实合法命令未在有界阶段推进到第2回合")

func management(action:String) -> Dictionary:
	var manager = host_client.gateway.manager
	var binding:Dictionary = manager.instance_binding(host_client.room_id)
	var channel = Channel.new()
	channel.configure("",host_client.gateway,preload("res://scripts/net/p2p/p2p_signal_server.gd").new())
	var text:String = "room "+host_client.room_id+" "+action
	var receipt:Dictionary = channel.execute(text)
	event("management_command",{"command":text,"response":receipt,"binding":binding})
	var deadline:int = Time.get_ticks_msec()+35000
	var request_id:String = str(receipt.get("result",{}).get("request_id",receipt.get("request_id","")))
	while receipt.get("ok",false) and receipt.get("result",{}).get("status") == "pending" and healthy() and Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
		receipt = channel.execute("room "+host_client.room_id+" result "+request_id)
	event("management_receipt",{"action":action,"response":receipt})
	return receipt

func freeze_save() -> bool:
	enter("save")
	var pause:Dictionary = await management("pause")
	if not guard(pause.get("ok",false) and await wait_for(func(): return sessions.all(func(session): return session.read_actions().get("management_paused",false)),15000),"管理员暂停冻结两端权威视图"): return false
	var saved:Dictionary = await management("save")
	if not guard(saved.get("ok",false) and saved.get("result",{}).get("saved",false),"真实 worker saved 回执"): return false
	var matches:String = str(host_client.gateway.manager.rooms[host_client.room_id].directory).path_join("matches")
	var folders:PackedStringArray = DirAccess.get_directories_at(matches)
	if not guard(folders.size() == 1,"唯一真实存档"): return false
	source = matches.path_join(folders[0])
	var journal:Dictionary = Journal.new().read_all(source.path_join("match.log"))
	if not guard(journal.ok and not journal.truncated and journal.records.size()>1 and journal.records.back().after == saved.result.state_hash,"真实 journal 尾哈希对应 saved"): return false
	saved_identity = preload("res://scripts/net/server/lan_archive_restore.gd").read_metadata(source.path_join("restore-identity.json"))
	if not guard(saved_identity.get("bindings",{}).size() == 2,"生产存档双身份座位元数据"): return false
	expected = sessions.map(func(session): return position(session.read_match()))
	before_seq = sessions.map(func(session): return session.read_match().seq)
	var assets:Dictionary = Equivalence.new().capture_assets(expected)
	if not guard(assets.ok,"冻结真实展示资产 SHA"): return false
	asset_hashes = assets.hashes
	source_hash = FileAccess.get_sha256(source.path_join("match.log"))
	Channel.write_json(evidence.path_join("saved-public-state.json"),{"views":sessions.map(func(session): return session.read_match()),"seq":before_seq,"position":expected,"save_receipt":saved,"source":source,"journal_sha256":source_hash})
	return true

func position(view:Dictionary) -> Dictionary:
	var result:Dictionary = {}
	for key in ["round","phase","current_player","game_over","observer","players","areas","situation","event_discard"]: result[key] = view.get(key)
	var broadcast:Dictionary = view.get("battle_broadcast",{}).duplicate(true)
	broadcast.erase("batch_id"); result.battle_broadcast = broadcast
	return result

func normal_close() -> bool:
	closing = true
	var binding:Dictionary = host_client.gateway.manager.instance_binding(host_client.room_id)
	host_client.close()
	event("host.close",{"binding":binding,"request_id":host_client._close_request_id})
	var deadline:int = Time.get_ticks_msec()+35000
	while not host_client._closing_target.is_empty() and Time.get_ticks_msec()<deadline:
		host_client._drain_close(); await get_tree().process_frame
	var ok:bool = host_client.room_id.is_empty() and host_client._closing_target.is_empty()
	event("normal_close_result",{"confirmed":ok,"diagnostics":host_client.diagnostics()})
	if not ok: return false
	for session in sessions:
		session.authority_host = null; session.close()
	sessions.clear(); host_client = null
	closing = false
	return true

func submit_restore(selected:Dictionary) -> void:
	restoring_ok = await host_client.restore_local_match(source,selected)
	restoring_done = true
	event("restore_return",{"ok":restoring_ok})

func restore() -> bool:
	enter("restored_initial_sync")
	if not await sync_all(false): return false
	if not guard(await wait_for(func(): return sessions.all(func(session): return session.view.get("data_ready",false)),20000),"新大厅权威已确认当前数据"): return false
	var selected:Dictionary = {}
	for player in saved_identity.bindings:
		selected[player] = sessions[0].peer_id() if int(saved_identity.bindings[player]) == int(saved_identity.room.owner) else sessions[1].peer_id()
	enter("restore_request")
	var revision:int = sessions[0].data_revision
	event("restore_local_match",{"source":source,"selected":selected})
	submit_restore(selected)
	if not guard(await wait_for(func(): return restoring_done,180000) and restoring_ok,"正式私有 IPC 恢复回执"): return false
	if not guard(await wait_for(func(): return sessions.all(func(session): return session.view.get("phase") == "restoring" and session.data_revision > revision),20000),"双端恢复清单与 restoring"): return false
	enter("restore_sync_ack")
	if not await sync_all(false): return false
	if not guard(await wait_for(func(): return sessions.all(func(session): return session.view.get("phase") == "playing" and not session.read_match().is_empty()),30000),"恢复双 ACK 后 playing 非空镜像"): return false
	enter("compare")
	var actual:Array = sessions.map(func(session): return position(session.read_match()))
	var comparison:Dictionary = Equivalence.new().compare_batch(expected,actual,asset_hashes)
	var after_seq:Array = sessions.map(func(session): return session.read_match().seq)
	Channel.write_json(evidence.path_join("comparison.json"),{"before":expected,"after":actual,"comparison":comparison,"seq_before":before_seq,"seq_after":after_seq,"seq_equal":before_seq == after_seq,"raw_views":sessions.map(func(session): return session.read_match())})
	if not guard(comparison.ok,"行动者、玩家列表、完整卡区及资产语义逐字段等价"): return false
	if not guard(before_seq == after_seq,"视图序号原值一致，不静默忽略输送代际差异"): return false
	return guard(FileAccess.get_sha256(source.path_join("match.log")) == source_hash,"恢复后原档字节保持不变")

func run() -> void:
	if not guard(root.begins_with("E:/") and evidence.begins_with("E:/") and not DirAccess.dir_exists_absolute(root),"E盘全新独占运行目录"): finish(); return
	keys = [Crypto.new().generate_rsa(4096),Crypto.new().generate_rsa(4096)]
	if await open_round("original") and await approve_content() and await select_and_begin() and await advance() and await freeze_save():
		enter("saved_normal_close")
		if guard(await normal_close(),"保存后正常关闭及原生 EXITED/release"):
			if guard(FileAccess.get_sha256(source.path_join("match.log")) == source_hash,"正常关闭未修改冻结存档"):
				if await open_round("restored"): await restore()
	enter("cleanup_normal_close")
	if host_client != null:
		if not guard(await normal_close(),"首错后仅正常关闭，不强杀"):
			finish(false); return
	finish()

func finish(exit_process:bool = true) -> void:
	Channel.write_json(evidence.path_join("final.json"),{"checks":checks,"failures":failures,"first_stage":first_failure.get("stage"),"first_failure":first_failure,"commands":requests,"receipts":command_results,"exit_proven":exit_process})
	print("RESULT checks=",checks," failures=",JSON.stringify(failures))
	event("finished",{"exit_proven":exit_process})
	if exit_process: get_tree().quit(0 if failures.is_empty() else 1)
