class_name Deploy
extends RefCounted

func exec(deploy_location:BaseLocation, player_id:int = -1, ignore_limit:bool = false):

	player_id = EffectManager.resolve_player_id(player_id)
	SetLocation.new().exec(deploy_location, player_id, ignore_limit)
