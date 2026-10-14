class_name ForeachFunc
extends RefCounted

#遍历数组，把当前元素写入循环体第parameter_index个参数位置再执行。
#body同ForFunc，是JSON可表达的函数描述。每次迭代都duplicate一份body的parameters，
#避免污染原始描述(同一个body字典会被反复复用)
func exec(body, arr:Array, parameter_index:int = 0):
	# 来源只继承 EM 已验函数帧；activating_eff 本身不能给裸调用补票。
	var captured:Dictionary = EffectManager.execution_context()
	if not captured.ok:
		return captured
	var context:SessionContext = captured.context
	var effect = EffectManager.activating_eff
	if effect == null:
		return {"ok":false, "context":context, "reason":&"unbound_origin"}

	var bodies:Array = body if body is Array else [body]
	var state := {"kind": "foreach", "iteration": 0, "body_index": 0, "last_result": null, "limit": arr.size(), "item": null, "bodies": bodies}
	state = EffectManager.record_loop_state(state, self)
	# 空字典是拒绝，不是可读游标；恢复时也必须保留原帧的同一 context。
	if state.is_empty() or not is_same(state.get("context"), context):
		return {"ok":false, "context":context, "reason":&"unbound_origin"}
	bodies = state.bodies
	for idx in range(int(state.iteration), int(state.limit)):
		# 在游标写入、arr.size/arr[idx] 的首次读取前验原来源，空体同样适用。
		var source:Dictionary = _loop_source_status(context)
		if not source.ok:
			return source
		state.iteration = idx
		# 空循环体没有内部检查点，仍须按原迭代游标检查协作预算。
		if bodies.is_empty() and not EffectManager.runtime_guard_checkpoint(state):
			return state.last_result
		state["item_present"] = idx < arr.size()
		state.item = arr[idx] if state.item_present else null
		GameLog.push_loop(idx)
		while int(state.body_index) < bodies.size():
			var boundary:Dictionary = _loop_source_status(context)
			if not boundary.ok:
				GameLog.pop_loop()
				return boundary
			if not EffectManager.runtime_guard_checkpoint(state):
				GameLog.pop_loop()
				return state.last_result
			var one = bodies[int(state.body_index)]
			var desc = one
			if one is Dictionary:
				desc = one.duplicate()
				var paras:Array = (one.get("parameters", []) as Array).duplicate()
				#只填空槽：循环体里其他func如果已经写了参数，不被当前元素覆盖
				while paras.size() <= parameter_index:
					paras.append(null)
				if paras[parameter_index] == null:
					paras[parameter_index] = arr[idx]
				desc["parameters"] = paras

			var res = EffectManager.run_func_descriptor(desc, effect, context)
			# 同步回调可以换局；先验捕获来源，再读暂停投影、结果或推进旧游标。
			var returned:Dictionary = _loop_source_status(context)
			if not returned.ok:
				GameLog.pop_loop()
				return returned
			if EffectManager.runtime_guard_status().paused:
				GameLog.pop_loop()
				return state.last_result
			if res[0]:
				state.last_result = res[1]
			state.body_index += 1
		GameLog.pop_loop()
		state.iteration = idx + 1
		state.body_index = 0
	return state.last_result

# 纯查询共享来源门，不读取 current、不绑定，也不把来源拒绝构造成可恢复暂停。
func _loop_source_status(context:SessionContext) -> Dictionary:
	var valid:Dictionary = SessionGeneration.validate_context(context)
	if not valid.ok:
		return {"ok":false, "context":context, "reason":valid.reason}
	var frame:Dictionary = EffectManager.execution_context()
	if not frame.ok:
		return {"ok":false, "context":context, "reason":frame.reason}
	if not is_same(frame.context, context):
		return {"ok":false, "context":context, "reason":&"unbound_origin"}
	return {"ok":true, "context":context, "reason":&"current"}
