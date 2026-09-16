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
	var last_result = null
	for i in range(times):
		GameLog.push_loop(i)
		for one in bodies:
			var res = EffectManager.run_func_descriptor(one, effect)
			if res[0]:
				last_result = res[1]
		GameLog.pop_loop()

	return last_result
