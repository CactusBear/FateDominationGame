class_name RestoreLocationPlNumLimits
extends RefCounted

#把所有地点的席位人数上限恢复到印刷基线。局势牌(如"魔术工房仅限一人部署")弃置时调用——
#席位上限改动只在本回合有效，回合结束必须还原，否则一个回合的限员会永久生效。
#没有基线(从未被改过)的地点不动
func exec():

	for area:BaseMapArea in MapData.areas:
		for loc:BaseLocation in area._locations:
			if loc._printed_pl_num_limit != null:
				loc._pl_num_limit = loc._printed_pl_num_limit
				loc._printed_pl_num_limit = null
