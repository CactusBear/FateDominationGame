class_name Defeat
extends RefCounted

func exec(player_id:int = GameData.player_id):

	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	player_data["is_battle_lose"] = true
	player_data["is_battle_win"] = false
