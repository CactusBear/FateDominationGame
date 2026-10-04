class_name GetPendingActionValue
extends RefCounted

#读取这次即将发生的动作携带的值（before_* / effect_start 时点里用）：
#即将开始结算的效果（effect）、即将被关闭/移出的牌（card）、即将获得的数量（amount）……
#键名由发起动作的一方声明（见 begin_pending_action 的 values），本操作不认识任何键。
#与 edit_pending_action 的区别：那个只改数值，这里只读，任何类型都原样返回。
#没有正在发生的动作或键不存在时返回 null
func exec(key:String):

	var action:Dictionary = EffectManager.current_pending_action()
	if action.is_empty():
		return null
	return (action.get("values", {}) as Dictionary).get(key)
