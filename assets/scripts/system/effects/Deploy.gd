class_name Deploy
extends RefCounted

func exec(deploy_location:BaseLocation, player_id:int = GameData.player_id, ignore_limit:bool = false):

	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	SetLocation.new().exec(deploy_location, player_id, ignore_limit)
