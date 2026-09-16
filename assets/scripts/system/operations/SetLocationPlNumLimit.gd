class_name SetLocationPlNumLimit
extends RefCounted

#改地点的席位人数上限，并在该地点第一次被改时记下印刷基线。
#_pl_num_limit 的印刷值是地图数据声明的事实；局势牌(如"魔术工房仅限一人部署")
#回合结束弃置时由 RestoreLocationPlNumLimits 按基线还原。
#只记录一次基线：同回合多张局势牌叠加改动时，基线始终是改动前的原值。
#locations 传数组时逐个设置（同一张局势牌改多个席位），limit 由调用方传入
func exec(location:BaseLocation, limit:int = -1):

	if location == null:
		return
	if location._printed_pl_num_limit == null:
		location._printed_pl_num_limit = location._pl_num_limit
	location._pl_num_limit = limit
