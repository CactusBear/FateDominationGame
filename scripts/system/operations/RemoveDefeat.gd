class_name RemoveDefeat
extends RefCounted

#移除指定玩家的所有【败北】buff（含效果彻底摘除）。
#复用于"无视败北"类效果；败北可叠加多层，故移除全部层。
func exec(player_id:int = -1, context:Variant = null) -> bool:
	# 缺省仅继承真实已验函数帧，原来源交 buff 生命周期消费。
	context = RegisterObjectEffects.captured_context(context)
	var resolved:Dictionary = RegisterObjectEffects.resolved_player_id(player_id, context)
	if not resolved.ok:
		return false
	return DefeatBuff.remove(resolved.id, context)
