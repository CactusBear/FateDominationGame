class_name ManageBuff
extends RefCounted

func exec(buff, player_id:int = GameData.player_id, add_or_del:bool = true):

	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	if add_or_del:
		var buffs:Array = player_data["buffs"]
		buffs.append(buff)
	else:
		var buffs:Array = player_data["buffs"]
		buffs.erase(buff)
