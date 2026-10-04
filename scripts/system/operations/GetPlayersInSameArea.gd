class_name GetPlayersInSameArea
extends RefCounted

#通用查询：与指定玩家处于同一地图区域(如深山町/新都/魔术工房/侦察)的其他在场玩家id。
#不依赖任何额外存储字段，实时按location现算，随时可查，不局限于战斗结算那一刻。
#include_self为true时结果包含自己，供"同区域所有玩家"类效果复用
func exec(player_id:int = -1, include_self:bool = false) -> Array:
	var id = EffectManager.resolve_player_id(player_id)
	var player_data:Dictionary = GameDataManager.get_player_data(id)
	var location:BaseLocation = player_data["location"]
	if location == null:
		return []

	var area:BaseMapArea = null
	for a:BaseMapArea in MapData.areas:
		if a._locations.has(location):
			area = a
			break
	if area == null:
		return []

	var result:Array = []
	for other_id in GameDataManager.get_active_player_ids():
		if other_id == id and !include_self:
			continue
		var other_data:Dictionary = GameDataManager.get_player_data(other_id)
		var other_location:BaseLocation = other_data["location"]
		if other_location != null and area._locations.has(other_location):
			result.append(other_id)
	return result
