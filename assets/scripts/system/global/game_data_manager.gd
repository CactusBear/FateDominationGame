extends Node




func get_player_data(id:int):
	#按需建立玩家数据，避免访问尚未初始化的玩家时拿到null
	if !GameData.player_data_library.has(id):
		GameData.player_data_library[id] = GameData.new_player_data()
	var player_data = GameData.player_data_library[id]
	return player_data
	
