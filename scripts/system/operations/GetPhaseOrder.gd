class_name GetPhaseOrder
extends RefCounted

#玩家在阶段里的行动顺位（0 是第一个行动）。按当前顺位现算，不读任何快照字段：
#原实现读 player_data["phase_order"]，而玩家数据里从来没有这个键，调用即报错。
#不在顺位里的条目（已被移除、分身棋子、NPC）返回 null
func exec(player_id:int = -1):

	player_id = EffectManager.resolve_player_id(player_id)
	var index:int = EffectManager.get_player_order_ids().find(player_id)
	if index == -1:
		return null
	return BaseNumber.new(index)
