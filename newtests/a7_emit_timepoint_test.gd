extends "res://newtests/a1_30_router_context_test.gd"

# 原 A1-30 的 oracle 不改；只把动作创建处保存的原来源传给 Emit 业务入口。
# 老 ABI 用同一业务断言失败，不把 arity/解析错误当 RED。
func route(name:String, parameters:Array, context:Variant) -> Variant:
	if name == "emit_time_point":
		var emit_script:Script = preload("res://scripts/system/operations/EmitTimePoint.gd")
		for method in emit_script.get_script_method_list():
			if method.name == "exec" and method.args.size() >= 3:
				var args:Array = parameters.duplicate()
				args.append(context)
				return super.route(name, args, context)
	return super.route(name, parameters, context)
