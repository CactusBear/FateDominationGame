class_name EditPendingAction
extends RefCounted

#在 before_* 时点里改写这次即将发生的动作携带的数值（如获得战果/魔力的数量 amount、使用令咒的数量）。
#键名由发起动作的一方声明（见各发起处传给 begin_pending_action 的 values），本操作不认识任何键；
#用法与 edit_data_number 一致：set_num 覆盖、vary_num 叠加。返回改写后的数值，键不存在或不是数字时返回 null
func exec(key:String, set_num = null, vary_num = null):

	var action:Dictionary = EffectManager.current_pending_action()
	if action.is_empty():
		return null
	var num = (action.get("values", {}) as Dictionary).get(key)
	if !(num is BaseNumber):
		return null
	if set_num != null:
		num.set_num(BaseNumber.new(set_num.number if set_num is BaseNumber else set_num))
	if vary_num != null:
		num.add(BaseNumber.new(vary_num.number if vary_num is BaseNumber else vary_num))
	return num
