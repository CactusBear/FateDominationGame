class_name ForFunc
extends RefCounted

#按次数重复执行循环体。body用JSON可表达的函数描述
#{"func_name":.., "parameters":[..], "var_index":-1, "condition":null}，
#通过EffectManager.run_func_descriptor执行，这样循环体内部也能用self_var/number_index。
#count支持BaseNumber或裸int，兼容效果自带数字直接传入的写法
func exec(body, count):
	var effect = EffectManager.activating_eff
	if effect == null:
		return

	var times = count.number if count is BaseNumber else int(count)
	var bodies:Array = body if body is Array else [body]
	var state := {"kind": "for", "iteration": 0, "body_index": 0, "last_result": null, "limit": times, "bodies": bodies}
	state = EffectManager.record_loop_state(state, self)
	bodies = state.bodies
	while int(state.iteration) < int(state.limit):
		var i:int = state.iteration
		# 空循环体没有内部检查点，仍须按原迭代游标检查协作预算。
		if bodies.is_empty() and not EffectManager.runtime_guard_checkpoint(state):
			return state.last_result
		GameLog.push_loop(i)
		while int(state.body_index) < bodies.size():
			if not EffectManager.runtime_guard_checkpoint():
				GameLog.pop_loop()
				return state.last_result
			var res = EffectManager.run_func_descriptor(bodies[int(state.body_index)], effect)
			if EffectManager.runtime_guard_status().paused:
				GameLog.pop_loop()
				return state.last_result
			if res[0]:
				state.last_result = res[1]
			state.body_index += 1
		GameLog.pop_loop()
		state.iteration = i + 1
		state.body_index = 0
	return state.last_result
