class_name GetAreaRoundWinners
extends RefCounted

#查「本回合某战区战斗的胜者名单」。战斗结果在 _record_battle 按参与者逐条记录，
#place 记的是区域名，所以同一场战斗每个参与者名下都有一条——按 place 筛 + winners 去重
#就能拿到完整的胜者名单。供「此战场胜者可…」这类效果在胜者判定之后（battle_end）查询用。
#map_area 为 null 或本回合该区域还没打过战斗时返回空数组
func exec(map_area:BaseMapArea) -> Array:

	if map_area == null:
		return []
	var winners:Array = []
	for entry in GameLog.query({"type" : "battle", "place" : str(map_area._area_name)}, 0):
		for winner in (entry.get("data", {}) as Dictionary).get("winners", []) as Array:
			if !winners.has(winner):
				winners.append(winner)
	return winners
