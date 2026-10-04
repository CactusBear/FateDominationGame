class_name CancelPendingAction
extends RefCounted

#在 before_* 时点里取消这次即将发生的动作（淘汰、败北、关闭、移出游戏、获得战果/魔力、
#使用令咒、局势牌生效……）。只做"取消"这一件事：取消之后改成做什么，由同一条效果后续的步骤写。
#没有正在发生的动作时返回 false
func exec() -> bool:

	var action:Dictionary = EffectManager.current_pending_action()
	if action.is_empty():
		return false
	action["cancelled"] = true
	return true
