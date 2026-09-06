class_name SetPlayerData
extends RefCounted

func exec(key_name:String, value, player_id:int = GameData.player_id):

	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	player_data[key_name] = value
