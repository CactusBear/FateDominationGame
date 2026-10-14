extends "res://newtests/scheduled-effect-origin_contract.gd"
# 专用故障注入：独占副本 register_effect 的 child 登记失败走公开 mark_guard_audit_failed。
# 只验证暂停归属和保留，不宣称当前没有的 scheduled_registration 尾部恢复 ABI。
func run() -> void:
	Observer.reset()
	_setup()
	var root := _root()
	var effects:int = GameData.effects.size()
	var objects:int = GameData.objects.size()
	_execute_schedule(root, [{"func_name":"edit_score", "parameters":[null, 1, -1]}])
	var status:Dictionary = EffectManager.runtime_guard_status()
	check(status.get("paused", false) and status.get("reason") == "audit_write_failed", "audit refusal remains pending under original guard owner")
	check(_scheduled().is_empty(), "pending registration is not published as success")
	check(root._self_vars.size() <= 2, "pending function does not install a successful return value")
	var retained:BaseEffect = null
	for effect in GameData.effects:
		if effect._name == "scheduled_effect":
			retained = effect
	check(retained != null and GameData.effects.size() == effects + 1 and GameData.objects.size() == objects + 1, "audit pending preserves exact unpublished effect identity")
	check(retained != null and retained.runtime_source_status().ok, "retained pending child keeps original context")
	Observer.finish(get_tree())
