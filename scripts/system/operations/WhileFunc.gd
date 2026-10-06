class_name WhileFunc
extends RefCounted

#condition传裸bool时值是固定的，每轮不会重新判断，所以那种用法只应配合外部
#已经保证有限次数的场景。真正需要"每轮重新判断"的循环，condition应传函数描述
#(同body的写法)，这样每轮都会通过EffectManager重新求值，而不是读一次性的快照。
#max_iterations是保底熔断，避免condition写错导致死循环卡死游戏
const MAX_ITERATIONS:int = 1000

func exec(body, condition, max_iterations:int = MAX_ITERATIONS):
	var effect = EffectManager.activating_eff
	if effect == null:
		return

	var state := {"kind": "while", "iteration": 0, "last_result": null, "limit": max_iterations, "phase": "condition"}
	state = EffectManager.record_loop_state(state, self)
	while int(state.iteration) < int(state.limit):
		if not EffectManager.runtime_guard_checkpoint():
			return state.last_result
		if state.phase == "condition":
			var cond_value = condition
			if condition is Dictionary or condition is BaseFunc:
				var cond_res = EffectManager.run_func_descriptor(condition, effect)
				if EffectManager.runtime_guard_status().paused:
					return state.last_result
				if !cond_res[0]:
					break
				cond_value = cond_res[1]
			if cond_value is BaseNumber:
				cond_value = cond_value.number != 0
			if !bool(cond_value):
				break
			state["condition_result"] = cond_value
			state.phase = "body"
		GameLog.push_loop(int(state.iteration))
		var res = EffectManager.run_func_descriptor(body, effect)
		GameLog.pop_loop()
		if EffectManager.runtime_guard_status().paused:
			return state.last_result
		if res[0]:
			state.last_result = res[1]
		state.iteration += 1
		state.phase = "condition"
	return state.last_result
