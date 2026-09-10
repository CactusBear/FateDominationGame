class_name GetPlayersField
extends RefCounted

#收集每名玩家player_data里同一个键的值。可用来列出在场从者、御主、位置。
#skip_null为true时丢掉空值，不把"没有从者"算进列表。
func exec(key:String, include_out:bool = false, skip_null:bool = true) -> Array:

	var ids:Array = GameDataManager.get_active_player_ids() if !include_out else GameData.player_data_library.keys()
	var result:Array = []
	for id in ids:
		var player_data:Dictionary = GameDataManager.get_player_data(int(id))
		if !player_data.has(key):
			continue
		var value = player_data[key]
		if skip_null and value == null:
			continue
		result.append(value)
	return result
