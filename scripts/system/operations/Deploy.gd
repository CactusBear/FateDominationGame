class_name Deploy
extends RefCounted

const operation_router = preload("res://scripts/system/operation_router.gd")

#把玩家部署到某个地点（前哨阶段抢席位的常规操作）。
#部署不是"常规移动"，固定 is_move = false：不受目标区域 _can_move_to 的限制。
#ignore_limit 透传落点的人数上限开关，由调用方决定要不要无视站位上限。
func exec(deploy_location:BaseLocation, player_id:int = -1, ignore_limit:bool = false, context:Variant = null) -> bool:
	# 旧 ABI 缺省只继承执行器已验证的函数帧；消费口不签发/刷新来源。
	context = RegisterObjectEffects.captured_context(context)
	if not RegisterObjectEffects.source_is_current(context):
		return false
	var resolved:Dictionary = RegisterObjectEffects.resolved_player_id(player_id, context)
	if not resolved.ok:
		return false
	player_id = resolved.id
	# 同一原来源分别用于路由资格与 SetLocation 第六个业务参数。
	var settled:bool = operation_router.exec_registered("set_location", [deploy_location, player_id, false, ignore_limit, false, context], context)
	#部署是独立的规则动作，由入口自己记一条；SetLocation 只记中性的位置变化，
	#它分不清"部署"和"效果搬运"。只在真正落位后才记，落位失败（位置满）不记
	if settled:
		var area := deploy_location.get_from() as BaseMapArea
		GameLog.record("deploy", player_id, -1,
			str(area._area_name) if area != null else "", deploy_location, ["deploy"], {})
	#把"有没有真的落位"交回调用方：席位满/不可落位时实际没动，
	#调用方（如 DeployRules.deploy_to_area）要据此决定是否结算部署收益
	return settled
