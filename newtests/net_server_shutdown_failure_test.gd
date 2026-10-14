extends "res://newtests/match_journal_test.gd"

const Channel = preload("res://scripts/net/server/server_console_channel.gd")
var gateway
var relay
var console
var root:String
var owned:Array[Dictionary] = []

func run() -> void:
	gateway = preload("res://scripts/net/server/server_gateway.gd").new()
	relay = preload("res://scripts/net/p2p/p2p_signal_server.gd").new()
	console = Channel.new()
	root = OS.get_environment("HERMES_SHUTDOWN_TEST_ROOT")
	if root.is_empty() or not root.is_absolute_path():
		check(false,"必须显式提供 scratch 下的 HERMES_SHUTDOWN_TEST_ROOT")
		finish()
		return
	root = root.path_join("stop-owned-%d" % Time.get_ticks_usec())
	check(console.configure(root.path_join("console"),gateway,relay) == OK,"真实管理通道配置成功")
	# 不可用就是验收失败，不注入恒真 verify/is_ready/state 替身。
	if not gateway.manager.process_ownership_available():
		check(false,"FateProcessOwner 原生所有权不可用；本专项未执行")
		finish()
		return
	var shutdown_source:String = FileAccess.get_file_as_string("res://scripts/net/server/server_shutdown.gd")
	var host_source:String = FileAccess.get_file_as_string("res://scripts/net/session/authority_host_client.gd")
	check(not shutdown_source.contains("OS.is_process_running") and not host_source.contains("OS.is_process_running"),"两条关闭路径禁止裸 PID 判活")
	check(gateway.manager.process_state_for_binding({}) == -1,"错误绑定为 UNKNOWN，不能等同退出")
	_watchdog()
	var good:Dictionary = await _spawn("idle")
	var unsaved:Dictionary = await _spawn("unsaved")
	var blocked:Dictionary = await _spawn("persist_fail")
	if good.is_empty() or unsaved.is_empty() or blocked.is_empty():
		await _cleanup()
		finish()
		return
	var stop = _stopper()
	var completed:Array = []
	stop.completed.connect(func(): completed.append(true))
	check(stop.start([]).result.stage == "pending","三房间安全关闭提交为 pending")
	check(not gateway.accepting_rooms and not relay.accepting_rooms,"关闭后禁止新建及新加入")
	for room in [good,unsaved,blocked]: _allow(room,"poll")
	for room in [good,unsaved,blocked]:
		var request:Dictionary = stop._requests.get(room.id,{})
		if request.is_empty():
			check(false,"真实拥有房间应收到 close 请求："+room.id)
			continue
		await _wait_file(str(room.directory).path_join("control").path_join(str(request.request_id)+".response.json"))
	stop.poll()
	check(stop.stage == "pending" and completed.is_empty(),"成功房间仅有回执仍在运行时不能完成关服")
	check(stop.failures.has(unsaved.id) and str(stop.failures[unsaved.id]).contains("未启用录制"),"真实未录制对局拒绝保存")
	check(stop.failures.has(blocked.id) and str(stop.failures[blocked.id]).contains("写入失败"),"真实恢复状态文件写入失败拒绝关闭")
	for room in [unsaved,blocked]:
		check(_alive(room) and not FileAccess.file_exists(str(room.directory).path_join("prepared.json")),"保存失败不退出、不发 shutdown_ready："+room.id)
	check(stop._requests.has(good.id) and stop._requests[good.id].confirmed,"失败房间不污染成功房间的独立回执")
	check(FileAccess.file_exists(str(good.directory).path_join("recovery.json")),"成功房间实际保存恢复状态")
	_allow(good,"exit")
	await _wait_exit(good)
	stop.poll()
	check(stop.stage == "failed" and completed.is_empty() and stop._closed.has(good.id),"成功房间已退出仍不能覆盖其他房间保存失败")
	check(_alive(unsaved) and _alive(blocked),"聚合关服失败未强杀任一失败房间")
	await _cleanup()

	# 超时无回执：持有原生句柄保持 running，不拿本测试 PID 冒充 owned worker。
	var waiting:Dictionary = await _spawn("idle")
	if not waiting.is_empty():
		stop = _stopper()
		stop.timeout_seconds = 0.05
		stop.start([])
		var deadline:int = Time.get_ticks_msec() + 100
		while Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		stop.poll()
		check(stop.stage == "failed" and str(stop.failures.get(waiting.id,"")).contains("超时"),"未处理请求超时明确失败")
		check(_alive(waiting) and not gateway.accepting_rooms,"超时不强杀，句柄仍运行且停止接纳")
	await _cleanup()

	# 仅句柄退出，没有保存回执不得成功。
	var early:Dictionary = await _spawn("idle")
	if not early.is_empty():
		stop = _stopper()
		stop.start([])
		_allow(early,"exit")
		await _wait_exit(early)
		stop.poll()
		check(stop.stage == "failed" and stop.failures.has(early.id) and not stop._closed.has(early.id),"自然退出而未确认保存回执不得声明关闭成功")
	await _cleanup()

	# 正例：真实回执与真实所有权句柄退出，两项均成立才 completed。
	var final_room:Dictionary = await _spawn("idle")
	if not final_room.is_empty():
		stop = _stopper()
		completed.clear()
		stop.completed.connect(func(): completed.append(true))
		stop.start([])
		stop.poll()
		check(stop.stage == "pending" and stop.failures.is_empty(),"真实 Channel pending 不含绑定字段时继续等待")
		var request_id:String = stop._requests[final_room.id].request_id
		var response_path:String = str(final_room.directory).path_join("control").path_join(request_id+".response.json")
		# 回执匹配由真实 Channel 消费者校验，每次只破坏四元组一个字段。
		for field in ["room","pid","instance","authority_host_mode","request_id"]:
			var response:Dictionary = {"ok":true,"result":{"closing":true},"room":final_room.id,"pid":final_room.pid,"instance":final_room.instance_id,"authority_host_mode":final_room.authority_host_mode,"request_id":request_id}
			response[field] = int(final_room.pid)+1 if field == "pid" else "wrong"
			check(Channel.write_json(response_path,response) == OK,"反例回执发布："+field)
			check(not console._room_result(PackedStringArray([final_room.id,request_id])).ok,"四元组回执单字段错误必须拒绝："+field)
			DirAccess.remove_absolute(response_path)
		_allow(final_room,"poll")
		await _wait_file(response_path)
		stop.poll()
		check(stop.stage == "pending" and completed.is_empty() and _alive(final_room),"只有真实成功回执，句柄未退出仍 pending")
		var final_pid:int = final_room.pid
		var final_token:String = final_room.process_token
		_allow(final_room,"exit")
		await _wait_exit(final_room)
		gateway.manager.poll()
		check(final_room.pid == final_pid and final_room.process_token == final_token,"manager.poll 不抢先 release，保持最终回执 PID")
		stop.poll()
		check(stop.stage == "complete" and completed == [true] and stop.failures.is_empty(),"四元组成功回执加原生句柄退出后恰好完成一次")
		check(final_room.pid == -1 and final_room.process_token == "","确认关闭后真实 release 清空当前 PID/token")
		check(gateway.manager._process_owner.call("state",final_token,final_pid) == -1,"release 后原生令牌失效")
		check(console._room_result(PackedStringArray([final_room.id,request_id])).ok,"release 改 PID 后最终回执仍按已确认旧绑定可读取")
		check(gateway.manager.process_state_for_binding(stop._closed[final_room.id]) == -1,"历史回执绑定不能作为判活证据")
		check(gateway.manager.closed_binding_for_request(final_room.id,"0".repeat(32)).is_empty(),"历史绑定只适用于已确认的请求编号")
		stop.poll()
		check(completed == [true] and stop.status([]).result.stopped,"完成信号不重复且状态查询已停止")
		check(stop.start([]).result.stage == "pending","已关闭实例允许重新查询协调")
		stop.poll()
		check(stop.stage == "complete" and stop.failures.is_empty(),"PID 已变 -1 的已确认关闭不会被重试当作未保存")
		var instance:String = final_room.instance_id
		final_room.instance_id = "b".repeat(32) if instance != "b".repeat(32) else "c".repeat(32)
		check(gateway.manager.closed_binding_for_request(final_room.id,request_id).is_empty(),"更换实例后旧 release 回执绑定必须失效")
		check(not console._room_result(PackedStringArray([final_room.id,request_id])).ok,"最终回执不能跨实例继承")
		final_room.instance_id = instance
	await _cleanup()
	await _host_close_case("lan")
	await _host_close_case("p2p")
	finish()

func _stopper():
	var stop = preload("res://scripts/net/server/server_shutdown.gd").new()
	stop.gateway = gateway
	stop.signaling = relay
	stop.console = console
	return stop

func _spawn(mode:String, host_mode:String = "dedicated") -> Dictionary:
	var id:String = Crypto.new().generate_random_bytes(16).hex_encode()
	var instance:String = Crypto.new().generate_random_bytes(16).hex_encode()
	var directory:String = root.path_join(id)
	DirAccess.make_dir_recursive_absolute(directory)
	var args:PackedStringArray = ["--headless","--audio-driver","Dummy","--fixed-fps","60","--path",ProjectSettings.globalize_path("res://"),"--log-file",directory.path_join("worker.log"),"--scene","res://newtests/net_shutdown_owned_worker.tscn","--",directory,id,instance,mode,host_mode]
	var spawned:Dictionary = gateway.manager._process_owner.call("spawn",OS.get_executable_path(),preload("res://scripts/net/server/server_bootstrap.gd").process_arguments(args))
	if int(spawned.get("pid",-1)) <= 0 or str(spawned.get("token","")).is_empty():
		check(false,"原生所有者创建测试子进程失败")
		return {}
	var room:Dictionary = {"id":id,"name":"owned-fixture","pid":int(spawned.pid),"process_token":str(spawned.token),"instance_id":instance,"authority_host_mode":host_mode,"directory":directory,"ready":true,"error":"","port":1}
	owned.append(room)
	gateway.manager.rooms[id] = room
	await _wait_file(directory.path_join("ready.json"))
	var ready = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("ready.json")))
	if not ready is Dictionary or ready.get("id") != id or ready.get("pid") != room.pid or ready.get("instance") != instance or ready.get("authority_host_mode") != host_mode:
		check(false,"真实子进程四元组报告未就绪")
		return {}
	check(gateway.manager.is_ready(id) and _alive(room),"真实 token/PID 验证及原生句柄 running")
	check(not gateway.manager._process_owner.call("verify",room.process_token,int(room.pid)+1),"同一真实 token 配错 PID 必须拒绝，不是恒真所有权")
	var binding:Dictionary = gateway.manager.instance_binding(id)
	check(not gateway.manager.release_process_for_binding(binding,"0".repeat(32)),"真实 running 句柄不能由关闭 API 提前 release")
	check(gateway.manager.process_state_for_binding(binding) == 1,"拒绝提前 release 后真实句柄仍 running")
	var token:String = room.process_token
	room.process_token = "invalid-token"
	check(gateway.manager.process_state_for_binding(binding) == -1,"真实 owner 拒绝错误 token，UNKNOWN 不回退 PID 判活")
	room.process_token = token
	return room

func _alive(room:Dictionary) -> bool:
	return gateway.manager._process_state(room) == 1 and gateway.manager.process_identity_verified(gateway.manager.instance_binding(room.id))

func _allow(room:Dictionary,gate:String) -> void:
	check(Channel.write_json(str(room.directory).path_join(gate+".allow"),{"allowed":true}) == OK,"发布子进程时序门："+gate)

func _wait_file(file:String) -> void:
	var deadline:int = Time.get_ticks_msec()+600000
	while not FileAccess.file_exists(file) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(FileAccess.file_exists(file),"实际文件屏障："+file.get_file())

func _wait_exit(room:Dictionary) -> void:
	var deadline:int = Time.get_ticks_msec()+600000
	while gateway.manager._process_state(room) == 1 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(gateway.manager._process_state(room) == 0,"持有原生句柄确认实际退出")

func _cleanup() -> void:
	# 只自然退出自己的 fixture；不执行 manager.close / OS.kill / terminate。
	for room in owned:
		if gateway.manager._process_state(room) == 1: _allow(room,"exit")
		if not str(room.get("process_token","")).is_empty():
			await _wait_exit(room)
			check(gateway.manager._release_process(room),"未由关闭消费者释放的夹具，退出后释放原生句柄")
			room.process_token = ""
			room.pid = -1
		else:
			check(room.pid == -1,"消费者已 release 的夹具不重复释放")
	owned.clear()
	gateway.manager.rooms.clear()

func _watchdog() -> void:
	var deadline:int = Time.get_ticks_msec() + 600000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(false,"关服专项看门狗超时；未视为测试通过")
	await _cleanup()
	finish()

func _host_close_case(host_mode:String) -> void:
	var room:Dictionary = await _spawn("idle",host_mode)
	if room.is_empty():
		await _cleanup()
		return
	var host = preload("res://scripts/net/session/authority_host_client.gd").new()
	host.gateway = gateway
	host.room_id = room.id
	host.close()
	# 手动驱动真实关闭消费者，避免 process_frame 自动 drain 与退出屏障竞争。
	var tree = Engine.get_main_loop() as SceneTree
	check(tree.process_frame.is_connected(host._drain_close),"房主实际连接关闭泵送回调")
	if tree.process_frame.is_connected(host._drain_close): tree.process_frame.disconnect(host._drain_close)
	var request_id:String = host._close_request_id
	var pid:int = room.pid
	var token:String = room.process_token
	host.close()
	check(host._close_request_id == request_id,"房主重复 close 不覆盖等待中的请求")
	host._drain_close()
	check(host.room_id == room.id and not host._closing_target.is_empty(),"无回执时房主保留旧实例")
	var path:String = host._close_response
	for field in ["room","pid","instance","authority_host_mode","request_id"]:
		var response:Dictionary = {"ok":true,"result":{"closing":true},"room":room.id,"pid":pid,"instance":room.instance_id,"authority_host_mode":room.authority_host_mode,"request_id":request_id}
		response[field] = pid+1 if field == "pid" else "wrong"
		check(Channel.write_json(path,response) == OK,"房主反例发布："+field)
		host._drain_close()
		check(host.room_id == room.id and not host._closing_target.is_empty(),"房主拒绝错绑定："+field)
		DirAccess.remove_absolute(path)
	_allow(room,"poll")
	await _wait_file(path)
	var saved_response = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(saved_response is Dictionary and Channel.saved_close_receipt(saved_response),"SAVED：真实 RoomControl 回执满足生产保存成功判据："+host_mode)
	# RoomControl 先发布回执再 emit shutdown_ready；等两个独立真实屏障，不用延时猜测。
	await _wait_file(str(room.directory).path_join("prepared.json"))
	check(FileAccess.file_exists(str(room.directory).path_join("prepared.json")) and FileAccess.file_exists(str(room.directory).path_join("recovery.json")),"SAVED：真实 LobbySession 已落盘且触发 shutdown_ready："+host_mode)
	host._drain_close()
	check(host.room_id == room.id and _alive(room),"真实回执加 running 仍不算房主关闭")
	_allow(room,"exit")
	await _wait_exit(room)
	gateway.manager.poll()
	check(room.pid == pid and room.process_token == token,"房主退出回执校验前 manager 保留原 PID/token")
	host._drain_close()
	check(host.room_id.is_empty() and host._closing_target.is_empty(),"房主真实回执、退出和 release 后清空关闭目标")
	check(not gateway.manager.closed_binding_for_request(room.id,request_id).is_empty(),"SAVED：成功保存及实际退出登记已确认关闭绑定："+host_mode)
	check(room.pid == -1 and room.process_token == "" and gateway.manager._process_owner.call("state",token,pid) == -1,"房主 release 真实句柄且令牌失效")
	check(console._room_result(PackedStringArray([room.id,request_id])).ok,"房主 release 后最终回执仍可核对")
	await _cleanup()
