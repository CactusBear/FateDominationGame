extends "res://newtests/scheduled-effect-origin_contract.gd"
# 故障注入专用：runner 在隔离 Schedule 入口已验帧后从公开 tags 注入坏数据。
# 不改 BaseFunc 外层来源门，不伪造执行帧；普通全链无法把旧对象越过外层 callable 门。
func run() -> void:
	Observer.reset()
	_setup()
	var old_root := _root()
	var old:BaseFunc = LoadHelper.load_funcs([{"func_name":"edit_score", "parameters":[null, 1, -1]}], old_root, fixture_context)[0]
	for body in [[{"func_name":"unregistered_scheduled_origin_probe", "parameters":[]}], [BaseFunc.new(Callable(), [])], [old]]:
		_setup()
		var root := _root()
		root.tags = body
		var effects:int = GameData.effects.size()
		var objects:int = GameData.objects.size()
		root._funcs = LoadHelper.load_funcs([{"func_name":"schedule_effect_on_time_point", "parameters":[["origin_probe"], [], 0, false, []], "var_index":0}], root, fixture_context)
		EffectManager.add_to_activation_pool(root)
		EffectManager.run_pipeline()
		check(root._self_vars.size() == 1 and root._self_vars[0] == null, "injected invalid factory input returns no usable object")
		check(_scheduled().is_empty() and GameData.effects.size() == effects and GameData.objects.size() == objects, "invalid input is consumed without unpublished object")
	Observer.finish(get_tree())
