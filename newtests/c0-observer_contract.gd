extends "res://newtests/c0-observer_fixture.gd"

func run() -> void:
	fresh_observation([0], {"enabled":true,"steps":2,"seconds":0.0})
	var body:Array = [
		{"func_name":"query_log","parameters":[{"type":"time_point","tags":[TimePoints.SITUATION_ACTIVATED]},null],"var_index":1},
		{"func_name":"array_length","parameters":[{"self_var":1}]}
	]
	var declaration:Dictionary = sampling_declaration(body, [])
	var loaded:Array = LoadHelper.load_effects([declaration],null,observer_source)
	check(loaded.size() == 1, "现有登记两步查询由可信工厂构造")
	if loaded.is_empty():
		finish()
		return
	check(EffectManager.register_effect(loaded[0],0), "正规来源登记")
	EffectManager.activate_effect(loaded[0])
	check(EffectManager.runtime_guard_status().paused, "steps=2 两步查询确实在原预算暂停")
	var attempts:int = 0
	while EffectManager.runtime_guard_status().paused and attempts < 20:
		EffectManager.resume_runtime_guard()
		attempts += 1
	check(not EffectManager.runtime_guard_status().paused, "原20次恢复上限足够")
	var measured:Dictionary = OBSERVER.samples(observer_after,body,[])
	check(measured.values == [0,0,0] and measured.paths == [0,1,2] and measured.issues.is_empty(), "两步查询三轮原序列全部 executed")
	var original:Array = GameLog.all_func_calls()
	var facts:Array = GameLog.query({},null)
	var mutated:Array = GameLog.all_func_calls()
	mutated.clear()
	check(GameLog.all_func_calls() == original, "快照外部修改不影响真实追踪")
	OBSERVER.samples(observer_after,body,[])
	check(GameLog.all_func_calls() == original and GameLog.query({},null) == facts, "pull-only 观察不运行规则也不追加事实或追踪")
	var wrong:Array = [{"func_name":"array_length","parameters":[[]]}]
	var mismatched:Dictionary = OBSERVER.samples(observer_after,wrong,[])
	check(mismatched.values.is_empty() and not mismatched.issues.is_empty(), "同名非同参数记录不能冒充样本")
	# 只检查拒绝，不把非法回调交给执行器；回调账本不得发生变化。
	var illegal := BaseFunc.new(Callable(self,"sample"), [])
	var capability:Dictionary = illegal.execution_capability_status()
	check(not capability.ok and capability.reason == &"undeclared_interpreter_capability", "宿主 sample 回调能力仍拒绝")
	var illegal_template := BaseEffect.new("observer-illegal", [])
	illegal_template._funcs = [illegal]
	var cloner := CloneContext.new()
	check(cloner.configure_template(observer_source,[illegal_template]), "显式模板 identity 授权前置")
	var copied:Dictionary = cloner.copy_result(illegal_template,observer_source)
	check(not copied.ok and copied.reason == &"undeclared_interpreter_capability", "C0 模板身份授权不能颁发回调能力")
	check(samples.is_empty() and outside == 0, "拒绝回调未执行宿主账本副作用")
	print("CONTRACT_TRACE ",JSON.stringify(original))
	BaseFunc.seal_capability_domain()
	var sealed:Dictionary = BaseFunc.interpreter_entry_status("array_length")
	check(not sealed.ok and sealed.status == &"unknown" and sealed.reason == &"unproven_capability_closure", "封闭能力域仍 unknown 不偷开")
	finish()
