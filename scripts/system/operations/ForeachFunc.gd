class_name ForeachFunc
extends RefCounted

#遍历数组，把当前元素写入循环体第parameter_index个参数位置再执行。
#body同ForFunc，是JSON可表达的函数描述。每次迭代都duplicate一份body的parameters，
#避免污染原始描述(同一个body字典会被反复复用)
func exec(body, arr:Array, parameter_index:int = 0):
	var effect = EffectManager.activating_eff
	if effect == null:
		return

	var bodies:Array = body if body is Array else [body]
	var state := {"kind": "foreach", "iteration": 0, "body_index": 0, "last_result": null, "limit": arr.size(), "item": null, "bodies": bodies}
	state = EffectManager.record_loop_state(state, self)
	bodies = state.bodies
	for idx in range(int(state.iteration), int(state.limit)):
		state.iteration = idx
		# 空循环体没有内部检查点，仍须按原迭代游标检查协作预算。
		if bodies.is_empty() and not EffectManager.runtime_guard_checkpoint(state):
			return state.last_result
		state["item_present"] = idx < arr.size()
		state.item = arr[idx] if state.item_present else null
		GameLog.push_loop(idx)
		while int(state.body_index) < bodies.size():
			if not EffectManager.runtime_guard_checkpoint():
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

			var res = EffectManager.run_func_descriptor(desc, effect)
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
