class_name Deploy
extends RefCounted

#把玩家部署到某个地点（前哨阶段抢席位的常规操作）。
#部署不是"常规移动"，固定 is_move = false：不受目标区域 _can_move_to 的限制。
#ignore_limit 透传落点的人数上限开关，由调用方决定要不要无视站位上限。
func exec(deploy_location:BaseLocation, player_id:int = -1, ignore_limit:bool = false):

	player_id = EffectManager.resolve_player_id(player_id)
	SetLocation.new().exec(deploy_location, player_id, false, ignore_limit)
