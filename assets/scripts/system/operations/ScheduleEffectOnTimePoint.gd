class_name ScheduleEffectOnTimePoint
extends RefCounted

# 将当前激活效果的一组 funcs 克隆成新的通用效果，并登记给同一触发者；
# 何时执行由调用方传入，规则对象本身不关心令咒/战斗/卡牌名称。
func exec(time_points:Array, funcs:Array, priority:int = 0, require_all:bool = false, expire_time_points:Array = []) -> BaseEffect:
	var source:BaseEffect = EffectManager.activating_eff
	if source == null or time_points.is_empty():
		return null
	var delayed := BaseEffect.new("scheduled_effect", time_points, priority, true, false)
	#延迟效果仍是原卡面能力的后续结算：对玩家展示原文案与原来源，
	#内部调度名 scheduled_effect 只用于引擎识别，不得泄露到界面。
	delayed._shown_name = source._shown_name
	delayed.from = source.from
	delayed._time_points_require_all = require_all
	delayed._expire_time_points = expire_time_points.duplicate()
	delayed._need_activate = false
	delayed._remove_after_trigger = true
	# 延迟 funcs 仍可引用调用效果的 number_index；把数值上下文带过去，但不把规则写死为任意卡。
	delayed._using_numbers = source._using_numbers
	delayed._funcs = []
	for func_data in funcs:
		if func_data is Dictionary:
			delayed._funcs.append(LoadHelper.load_funcs([func_data], delayed)[0])
		elif func_data is BaseFunc:
			delayed._funcs.append(func_data.clone_data(CloneContext.new()))
	EffectManager.register_effect(delayed, source._trigger_player_id)
	return delayed
