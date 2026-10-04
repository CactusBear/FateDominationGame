class_name RemoveDefeat
extends RefCounted

#移除指定玩家的所有【败北】buff（含效果彻底摘除）。
#复用于"无视败北"类效果；败北可叠加多层，故移除全部层。
func exec(player_id:int = -1):
	player_id = EffectManager.resolve_player_id(player_id)
	DefeatBuff.remove(player_id)
