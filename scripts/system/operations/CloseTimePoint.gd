class_name CloseTimePoint
extends RefCounted

#关闭一个时点(如结束他人的回合)。因该时点触发、且没有命中其他时点的效果会被打断，
#已经结算完的效果不回滚。player_id留空表示对当前效果的触发者生效，传-1的话由resolve_player_id解析
func exec(time_point:String, player_id:int = -1, all_players:bool = false):

	if all_players:
		EffectManager.close_time_point(time_point, -1)
		return
	var id = EffectManager.resolve_player_id(player_id)
	EffectManager.close_time_point(time_point, id)
