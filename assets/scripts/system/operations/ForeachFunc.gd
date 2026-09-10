class_name ForeachFunc
extends RefCounted

#遍历数组，把当前元素写入循环体第parameter_index个参数位置再执行。
#body同ForFunc，是JSON可表达的函数描述。每次迭代都duplicate一份body的parameters，
#避免污染原始描述(同一个body字典会被反复复用)
func exec(body, arr:Array, parameter_index:int = 0):
	var effect = EffectManager.activating_eff
	if effect == null:
		return

	var last_result = null
	for item in arr:
		var desc = body
		if body is Dictionary:
			desc = body.duplicate()
			var paras:Array = (body.get("parameters", []) as Array).duplicate()
			while paras.size() <= parameter_index:
				paras.append(null)
			paras[parameter_index] = item
			desc["parameters"] = paras

		var res = EffectManager.run_func_descriptor(desc, effect)
		if res[0]:
			last_result = res[1]

	return last_result
