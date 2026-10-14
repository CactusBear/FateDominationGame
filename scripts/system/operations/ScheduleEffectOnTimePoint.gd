class_name ScheduleEffectOnTimePoint
extends RefCounted

# 将当前激活效果的一组 funcs 克隆成新的通用效果，并登记给同一触发者；
# 何时执行由调用方传入，规则对象本身不关心令咒/战斗/卡牌名称。
func exec(time_points:Array, funcs:Array, priority:int = 0, require_all:bool = false, expire_time_points:Array = []) -> BaseEffect:
	# 五实参 ABI 不变；旧调用只继承已验函数帧，activating_eff 本身不能授予来源。
	var execution:Dictionary = EffectManager.execution_context()
	if not execution.get("ok", false):
		return null
	var context:SessionContext = execution.get("context") as SessionContext
	var source:BaseEffect = EffectManager.activating_eff
	if context == null or source == null or time_points.is_empty():
		return null
	var declaration:Dictionary = {
		"effect_name":"scheduled_effect", "time_points":time_points, "priority":priority,
		"is_pure_passive":true, "is_residue":false, "effect_numbers":[], "funcs":[],
		"require_all_time_points":require_all, "expire_time_points":expire_time_points
	}
	var produced:Array = LoadHelper.load_effects([declaration], null, context)
	if produced.size() != 1:
		return null
	var delayed:BaseEffect = produced[0]
	# 延迟结算沿原卡面文案、来源和完整数字环境，不复制次数/付款等发动规则。
	delayed._shown_name = source._shown_name
	delayed.from = source.from
	delayed._need_activate = false
	delayed._remove_after_trigger = true
	delayed._using_numbers = source._using_numbers
	delayed.numbers = source.numbers
	for func_data in funcs:
		if func_data is Dictionary:
			var parsed:Array = LoadHelper.load_funcs([func_data], delayed, context)
			if parsed.size() != 1:
				_discard_unpublished(delayed)
				return null
			delayed._funcs.append(parsed[0])
		elif func_data is BaseFunc:
			# runtime 对象只能继承自己的原来源，不能被新效果当作模板补票。
			if not func_data.runtime_source_status(delayed, context).get("ok", false):
				_discard_unpublished(delayed)
				return null
			var copied:Dictionary = CloneContext.new().copy_result(func_data, context)
			var cloned:BaseFunc = copied.get("object") as BaseFunc
			if not copied.get("ok", false) or cloned == null or not cloned.runtime_source_status(delayed, context).get("ok", false):
				_discard_unpublished(delayed)
				return null
			delayed._funcs.append(cloned)
	if not EffectManager.register_effect(delayed, source._trigger_player_id):
		_discard_unpublished(delayed)
		return null
	return delayed


# 仅清理本次未发布对象；审计暂停保留原 owner 恢复所需 identity，不做规则 undo。
func _discard_unpublished(delayed:BaseEffect) -> void:
	if not bool(EffectManager.runtime_guard_status().get("paused", false)):
		GameData.effects.erase(delayed)
		GameData.objects.erase(delayed)
