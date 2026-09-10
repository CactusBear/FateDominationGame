extends Node


func get_player_data(id:int):
	#按需建立玩家数据，避免访问尚未初始化的玩家时拿到null
	if !GameData.player_data_library.has(id):
		GameData.player_data_library[id] = GameData.new_player_data()
	var player_data = GameData.player_data_library[id]
	return player_data


#返回本局仍在场的玩家，顺序与当前顺位一致
func get_active_player_ids() -> Array:
	var result:Array = []
	for id in EffectManager.get_player_order_ids():
		var player_data = get_player_data(id) as Dictionary
		if !player_data["is_out"]:
			result.append(id)
	return result
