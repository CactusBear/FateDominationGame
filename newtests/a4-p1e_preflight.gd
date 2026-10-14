extends "res://newtests/c0-observer_fixture.gd"
## P1-E 未接线前的真实 RED 边界；不是受信生产 participant 或能力证明。
## 只在 P0 prepare 中读取，不让未证明闭包执行，不写 live 或签输入资格。
const Plan = preload("res://scripts/system/atomic_action_plan.gd")
const Domain = preload("res://scripts/system/atomic_execution_domain.gd")

class ReadProbe extends RefCounted:
	var source:SessionContext
	var private_pool:Array = []
	var private_points:Array = []
	var observed:Dictionary = {}
	func _init(context:SessionContext) -> void:
		source = context
	func validate_original_context(context:Variant) -> Dictionary:
		return {"status":"COMPLETED" if is_same(source, context) and SessionGeneration.validate_context(context).ok else "REJECTED", "reason":"preflight_source"}
	func open_domain(domain, _context:Variant, _closure:Variant, _manifest:Dictionary) -> Dictionary:
		for outcome in [domain.bind_root(&"effect_runtime", {"effect_pool":private_pool}), domain.bind_root(&"time_point_runtime", {"phase_time_points":private_points}), domain.bind_dependency(EffectManager.effect_pool, private_pool), domain.bind_dependency(TimePointChecker.phase_time_points, private_points)]:
			if outcome.status != "COMPLETED": return outcome
		return {"status":"COMPLETED", "reason":"diagnostic_roots_only"}
	func prepare(_domain, _closure:Variant, context:Variant) -> Dictionary:
		var frame:Dictionary = Domain.current_frame()
		var plan:Dictionary = Plan.inspect(frame.plan_identity)
		observed = {
			"real_plan":plan.state == "PREPARING" and is_same(plan.original_context, context),
			"em_memo":is_same(Domain.rebind_dependency(EffectManager.effect_pool).value, private_pool),
			"tpc_memo":is_same(Domain.rebind_dependency(TimePointChecker.phase_time_points).value, private_points),
			"em_facade":is_same(EffectManager.effect_pool, private_pool),
			"tpc_facade":is_same(TimePointChecker.phase_time_points, private_points),
			"entry":BaseFunc.interpreter_entry_status("array_length")}
		# 显式拒绝缺证明；不得拿原 live 队列或仅 bind_dependency 当已认证 P-owned graph。
		return {"status":"REJECTED", "reason":"unproven_effect_domain_closure"}
	func resume(_domain, _owned:Variant, _input:Variant, _context:Variant) -> Dictionary:
		return {"status":"REJECTED", "reason":"no_owned_effect_continuation"}
	func seal(_domain, _context:Variant) -> Dictionary:
		return {"status":"REJECTED", "reason":"preflight_never_publishes"}

func run() -> void:
	fresh_observation([0], {"enabled":true,"steps":2,"seconds":0.0})
	var loaded:Array = LoadHelper.load_effects([observation_declaration([{"func_name":"array_length","parameters":[[]]}], [])], null, observer_source)
	check(loaded.size() == 1, "PRE 合法效果从真实工厂创建")
	if loaded.is_empty():
		finish()
		return
	var f:BaseFunc = loaded[0]._funcs[0]
	check(f.runtime_source_status(loaded[0], observer_source).ok, "PRE 原函数来源真实有效")
	check(f.execution_capability_status().ok, "PRE 原非 sealed 正规能力可用")
	var pool:Array = EffectManager.effect_pool
	var points:Array = TimePointChecker.phase_time_points
	var facts:Array = GameLog.query({}, null)
	BaseFunc.seal_capability_domain()
	check(not BaseFunc.interpreter_entry_status("array_length").ok, "sealed 未证明入口仍失败关闭")
	check(not f.execution_capability_status().ok, "sealed 原合法函数不冒充 D admitted")
	check(not f.runtime_callable(loaded[0], observer_source).is_valid(), "sealed 不产可执行 Callable")
	var probe:ReadProbe = ReadProbe.new(observer_source)
	var registration:Dictionary = Plan.register_participant_manifest({"adapter":probe,"support_manifest":{
		"abi_version":1,"status":"supported","proof":"owner_registered_closed_domain",
		"required_roots":["diagnostic_reads_only"],"required_adapters":["preflight"],
		"state_domains":["diagnostic"],"participants":["diagnostic_read_probe_not_production"]}})
	check(registration.status == "COMPLETED", "PRE 仅登记诊断读 participant")
	var created:Dictionary = Plan.begin(observer_source, {"kind":"diagnostic_reads_only"}, registration.participant_manifest)
	check(created.status == "COMPLETED" and created.state == "NEW", "真实 P0 创建身份")
	var rejected:Dictionary = Plan.prepare(created.plan_identity)
	check(probe.observed.real_plan, "真实 P0 受控 prepare 帧")
	check(probe.observed.em_memo and probe.observed.tpc_memo, "P0 identity memo 真绑定但不自动路由服务")
	check(probe.observed.em_facade, "P1-E EM 同一服务应解析私有域而非 live pool")
	check(probe.observed.tpc_facade, "P1-E TPC 同一服务应解析私有域而非 live 时点表")
	check(rejected.status == "REJECTED" and rejected.state == "ABORTED", "缺证明明确 REJECTED 不假 PENDING")
	check(rejected.receipt.state != "COMMITTED", "局部结果没有 P0 COMMITTED 行动回执")
	check(Domain.current_frame().status == "REJECTED" and not Domain.publication_is_open(), "拒绝后退出帧且不开发布窗")
	check(is_same(pool, EffectManager.effect_pool) and is_same(points, TimePointChecker.phase_time_points), "诊断全程保留 live backing identity")
	check(GameLog.query({}, null) == facts, "读诊断不运行原效果不追加规则事实")
	print("P1E_PREFLIGHT ", JSON.stringify({"entry":probe.observed.entry,"rejected_state":rejected.state,"user_dir":OS.get_user_data_dir()}))
	finish()
