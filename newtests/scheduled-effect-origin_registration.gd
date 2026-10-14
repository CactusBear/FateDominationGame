extends "res://newtests/scheduled-effect-origin_contract.gd"
# 故障注入专用：runner 仅在独占副本令 register_effect 对 scheduled_effect 返回 false，
# 或令实际 LoadHelper/CloneContext 工厂返回拒绝；无注入运行应真红，不是独立绿色套件。

func run() -> void:
	Observer.reset()
	for branch in ["Dictionary", "BaseFunc"]:
		_setup()
		var root := _root()
		var descriptor:Dictionary = {"func_name":"edit_score", "parameters":[null, 1, -1], "var_index":-1}
		var body:Array = [descriptor] if branch == "Dictionary" else LoadHelper.load_funcs([descriptor], root, fixture_context)
		var effects:int = GameData.effects.size()
		var objects:int = GameData.objects.size()
		_execute_schedule(root, body)
		check(root._self_vars.size() > 2 and root._self_vars[2] == null, branch + " registration refusal returns no usable object")
		check(_scheduled().is_empty(), branch + " registration refusal publishes no pool entry")
		check(GameData.effects.size() == effects and GameData.objects.size() == objects, branch + " registration refusal consumes unpublished object")
	Observer.finish(get_tree())
