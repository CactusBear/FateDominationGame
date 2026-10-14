extends "res://newtests/net_server_shutdown_failure_test.gd"

func run() -> void:
	gateway = preload("res://scripts/net/server/server_gateway.gd").new()
	relay = preload("res://scripts/net/p2p/p2p_signal_server.gd").new()
	console = Channel.new()
	var scratch_root:String = OS.get_environment("HERMES_SHUTDOWN_TEST_ROOT")
	if not scratch_root.begins_with("E:/") or not scratch_root.is_absolute_path():
		check(false,"必须显式提供 E 盘 HERMES_SHUTDOWN_TEST_ROOT")
		finish()
		return
	root = scratch_root.path_join("host-save-guard-%d" % Time.get_ticks_usec())
	check(console.configure(root.path_join("console"),gateway,relay) == OK,"E 独占真实 console")
	_watchdog()
	if not gateway.manager.process_ownership_available():
		check(false,"真实 native 所有者不可用"); finish(); return
	var room:Dictionary = await _spawn("idle","lan")
	if room.is_empty(): await _cleanup(); finish(); return
	var host = preload("res://scripts/net/session/authority_host_client.gd").new()
	host.gateway = gateway
	host.room_id = room.id
	host.close()
	if get_tree().process_frame.is_connected(host._drain_close): get_tree().process_frame.disconnect(host._drain_close)
	var binding:Dictionary = gateway.manager.instance_binding(room.id)
	var request:String = host._close_request_id
	var path:String = host._close_response
	check(not request.is_empty(),"真实 host.close 已提交绑定请求")
	# 不开放 poll 门：真实 worker 未执行保存；只开放独立自然退出门。
	_allow(room,"exit")
	await _wait_exit(room)
	check(not FileAccess.file_exists(str(room.directory).path_join("prepared.json")),"真实子进程未准备保存关闭")
	var response:Dictionary = {"ok":true,"result":{"closing":true},"room":binding.room,"pid":binding.pid,"instance":binding.instance_id,"authority_host_mode":binding.authority_host_mode,"request_id":request}
	check(Channel.write_json(path,response) == OK,"发布绑定正确但缺保存证据的 closing 回执")
	host._drain_close()
	check(host.room_id == room.id and not host._closing_target.is_empty() and host._close_request_id == request and gateway.manager.closed_binding_for_request(room.id,request).is_empty(),"NOT-SAVED：真实 EXITED 加 closing 而无保存回执不得判已保存关闭")
	response.result = {"closing":true,"saved":false,"room_state_saved":false}
	check(Channel.write_json(path,response) == OK,"发布绑定正确但明确保存失败的 closing 回执")
	host._drain_close()
	check(host.room_id == room.id and not host._closing_target.is_empty() and host._close_request_id == request and gateway.manager.closed_binding_for_request(room.id,request).is_empty(),"NOT-SAVED：保存标志明确为 false 不得判已保存关闭")
	check(DirAccess.remove_absolute(path) == OK,"移除回执以验证真实退出后的缺回执分支")
	host._drain_close()
	check(host.room_id == room.id and not host._closing_target.is_empty() and host._close_request_id == request and gateway.manager.closed_binding_for_request(room.id,request).is_empty(),"NOT-SAVED：真实 EXITED 且回执完全缺失不得判已保存关闭")
	# 测试收尾只断开自己的泵送；自然退出的句柄由既有 fixture cleanup 释放。
	if get_tree().process_frame.is_connected(host._drain_close): get_tree().process_frame.disconnect(host._drain_close)
	await _cleanup()
	await _host_save_failure_case("unsaved")
	await _host_save_failure_case("persist_fail")
	# 既有正例使用真实 RoomControl/LobbySession 保存结果，兼验 LAN/P2P。
	await _host_close_case("lan")
	await _host_close_case("p2p")
	check(owned.is_empty() and gateway.manager.rooms.is_empty(),"本次 ownprocess0；未访问旧 PID 17120/28100")
	finish()

func _host_save_failure_case(mode:String) -> void:
	var room:Dictionary = await _spawn(mode,"lan")
	if room.is_empty():
		await _cleanup()
		return
	var host = preload("res://scripts/net/session/authority_host_client.gd").new()
	host.gateway = gateway
	host.room_id = room.id
	host.close()
	if get_tree().process_frame.is_connected(host._drain_close): get_tree().process_frame.disconnect(host._drain_close)
	var request:String = host._close_request_id
	var path:String = host._close_response
	_allow(room,"poll")
	await _wait_file(path)
	var response = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(response is Dictionary and response.get("ok") == false and not Channel.saved_close_receipt(response),"真实保存被拒的回执没有保存成功证据："+mode)
	host._drain_close()
	check(host.room_id == room.id and gateway.manager.closed_binding_for_request(room.id,request).is_empty() and _alive(room),"NOT-SAVED：真实保存失败保留房间及运行句柄："+mode)
	check(not FileAccess.file_exists(str(room.directory).path_join("prepared.json")) and not FileAccess.file_exists(str(room.directory).path_join("recovery.json")),"保存失败没有 shutdown_ready 或恢复文件："+mode)
	await _cleanup()
