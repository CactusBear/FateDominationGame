extends RefCounted

signal completed
var gateway
var signaling
var console
var timeout_seconds:float = 30.0
var stage:String = "idle"
var failures:Dictionary = {}
var _requests:Dictionary = {}
var _closed:Dictionary = {}
var _deadline:int = 0

func start(_args:PackedStringArray) -> Dictionary:
	if stage == "pending": return status([])
	if not is_finite(timeout_seconds) or timeout_seconds <= 0 or timeout_seconds >= float((9223372036854775807-Time.get_ticks_msec())/1000):
		return {"ok":false,"error":"关闭等待时限无效"}
	gateway.accepting_rooms = false
	gateway.broadcast_notice("服务端正在保存并关闭，请等待保存结果")
	signaling.accepting_rooms = false
	failures.clear()
	# 重试保留未决请求；超时不是撤销，也不能另发 close 覆盖晚到回执。
	for id in gateway.manager.rooms:
		if _requests.has(id):
			var pending:Dictionary = _requests[id]
			if gateway.manager.retired_binding_for_request(id,pending.request_id).is_empty() or gateway.manager.instance_binding(id).get("instance_id") == pending.instance_id: continue
			# 旧实例 EXITED 且已入只读回执档案；重试应关闭新实例，不等旧回执永远占槽。
			_requests.erase(id)
		var room:Dictionary = gateway.manager.rooms[id]
		var prior:Dictionary = _closed.get(id,{})
		if not prior.is_empty() and (gateway.manager.closed_binding_for_request(id,str(prior.get("request_id",""))) == prior or (gateway.manager.retired_binding_for_request(id,str(prior.get("request_id",""))) == prior and room.pid == -1 and room.instance_id == prior.instance_id)): continue
		var binding:Dictionary = gateway.manager.instance_binding(id)
		var process_state:int = gateway.manager.process_state_for_binding(binding)
		if process_state != 1:
			failures[id] = "原生进程句柄不可用，无法确认本次保存" if process_state < 0 else "房间此前已经退出，无法确认本次保存"
			continue
		var response:Dictionary = console.execute("room "+str(id)+" close")
		if not response.get("ok",false): failures[id] = response.get("error","关闭请求被拒绝")
		else: _requests[id] = {"request_id":response.result.request_id,"room":id,"binding":binding,"pid":int(room.pid),"instance_id":str(room.instance_id),"authority_host_mode":str(room.authority_host_mode),"confirmed":false}
	_deadline = Time.get_ticks_msec()+int(timeout_seconds*1000)
	stage = "pending"
	return status([])

func status(_args:PackedStringArray) -> Dictionary:
	return {"ok":true,"result":{"stage":stage,"failures":failures.duplicate(true),"pending_rooms":_requests.keys(),"stopped":stage == "complete"}}

func poll() -> void:
	if stage not in ["pending","failed"]: return
	console._poll_room_closes()
	for id in _requests.keys():
		var request:Dictionary = _requests[id]
		if not request.confirmed:
			var response:Dictionary = console._room_result(PackedStringArray([id,request.request_id]))
			# Channel 的 pending 无实例字段，必须先等待，不能误判为旧回执。
			if response.get("result",{}).get("status","") == "pending": continue
			if response.get("room") != request.room or response.get("pid") != request.pid or response.get("instance") != request.instance_id or response.get("authority_host_mode") != request.authority_host_mode or response.get("request_id") != request.request_id:
				failures[id] = response.get("error","关闭回执属于旧请求或旧实例，未确认退出")
				if not gateway.manager.retired_binding_for_request(id,request.request_id).is_empty() and stage != "failed":
					stage = "failed"
					print("SERVER_STOP_FAILED ",JSON.stringify(failures))
				continue
			if response.get("ok") == false:
				failures[id] = response.get("error","关闭被拒绝")
				gateway.manager.cancel_process_supervision(request.binding,request.request_id)
				_requests.erase(id)
				continue
			if response.get("ok") == true and response.get("result",{}).get("closing",false): request.confirmed = true
		if request.confirmed:
			var historical:Dictionary = request.binding.merged({"request_id":request.request_id})
			var released:bool = gateway.manager.closed_binding_for_request(id,request.request_id) == historical or gateway.manager.retired_binding_for_request(id,request.request_id) == historical
			var process_state:int = 0 if released else gateway.manager.process_state_for_binding(request.binding)
			if process_state < 0:
				failures[id] = "原生进程句柄不可用，未确认退出"
				continue
			if process_state == 0:
				if not released and not gateway.manager.release_process_for_binding(request.binding,request.request_id):
					failures[id] = "原生进程已退出但所有权释放失败，未确认完整关闭"
					continue
				var closed:Dictionary = request.binding.duplicate(true)
				closed["request_id"] = request.request_id
				_closed[id] = closed
				if gateway.manager.instance_binding(id).get("instance_id") == request.instance_id:
					failures.erase(id)
				else:
					failures[id] = "旧实例关闭已确认，但当前恢复实例尚未关闭；请重试关服"
				_requests.erase(id)
	if stage == "pending" and not _requests.is_empty() and Time.get_ticks_msec() >= _deadline:
		for id in _requests: failures[id] = "关闭等待超时，未强制终止，原请求可能仍待执行"
		stage = "failed"
		print("SERVER_STOP_FAILED ",JSON.stringify(failures))
	if not _requests.is_empty(): return
	if not failures.is_empty():
		if stage != "failed": print("SERVER_STOP_FAILED ",JSON.stringify(failures))
		stage = "failed"
		return
	stage = "complete"
	print("SERVER_STOP_COMPLETE")
	completed.emit()
