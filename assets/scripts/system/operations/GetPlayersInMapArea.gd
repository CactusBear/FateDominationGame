class_name GetPlayersInMapArea
extends RefCounted

#列出位于指定地图区域的玩家id。GetPlayersInSameArea以玩家为锚点，这里以区域为锚点。
#include_self仅在传入anchor_player_id时有意义；不传则返回该区域全部在场玩家。
func exec(map_area:BaseMapArea, include_out:bool = false, anchor_player_id:int = -2, include_self:bool = true) -> Array:

	if map_area == null:
		return []
	var ids:Array = GameDataManager.get_active_player_ids() if !include_out else GameData.player_data_library.keys()
	var result:Array = []
	for id in ids:
		if !include_self and int(id) == anchor_player_id:
			continue
		var player_data:Dictionary = GameDataManager.get_player_data(int(id))
		var loc:BaseLocation = player_data["location"]
		if loc != null and map_area._locations.has(loc):
			result.append(id)
	return result
