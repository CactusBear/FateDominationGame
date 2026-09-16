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
	var last_result = null
	for idx in range(arr.size()):
		GameLog.push_loop(idx)
		for one in bodies:
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
			if res[0]:
				last_result = res[1]
		GameLog.pop_loop()

	return last_result
