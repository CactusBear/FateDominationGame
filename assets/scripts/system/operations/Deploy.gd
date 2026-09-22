class_name Deploy
extends RefCounted

#把玩家部署到某个地点（前哨阶段抢席位的常规操作）。
#部署不是"常规移动"，固定 is_move = false：不受目标区域 _can_move_to 的限制。
#ignore_limit 透传落点的人数上限开关，由调用方决定要不要无视站位上限。
func exec(deploy_location:BaseLocation, player_id:int = -1, ignore_limit:bool = false):

	player_id = EffectManager.resolve_player_id(player_id)
	var settled:bool = SetLocation.new().exec(deploy_location, player_id, false, ignore_limit)
	#部署是独立的规则动作，由入口自己记一条；SetLocation 只记中性的位置变化，
	#它分不清"部署"和"效果搬运"。只在真正落位后才记，落位失败（位置满）不记
	if settled:
		var area := deploy_location.get_from() as BaseMapArea
		GameLog.record("deploy", player_id, -1,
			str(area._area_name) if area != null else "", deploy_location, ["deploy"], {})
	#把"有没有真的落位"交回调用方：席位满/不可落位时实际没动，
	#调用方（如 DeployRules.deploy_to_area）要据此决定是否结算部署收益
	return settled
