class_name GetPlayerIdsByDataValue
extends RefCounted

#找出player_data某键等于给定值的玩家id。用于"场上是否已有某御主"这类查询。
func exec(key:String, value, include_out:bool = false) -> Array:

	var ids:Array = GameDataManager.get_active_player_ids() if !include_out else GameData.player_data_library.keys()
	var result:Array = []
	for id in ids:
		var player_data:Dictionary = GameDataManager.get_player_data(int(id))
		if !player_data.has(key):
			continue
		if player_data[key] == value:
			result.append(id)
	return result
