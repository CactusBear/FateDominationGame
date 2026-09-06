class_name GetPlayerTimePoints
extends RefCounted

func exec(player_id:int = GameData.player_id):

	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["current_time_points"]
