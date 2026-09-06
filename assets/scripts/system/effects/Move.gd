class_name Move
extends RefCounted

func exec(move_num:BaseNumber, player_id:int = GameData.player_id, ignore_limit:bool = false, ignore_battle:bool = false):

	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	if !ignore_battle and player_data["is_battle"] == true:
		#show("处于交战状态，无法移动")
		return
	var cost = MoveLocation.new().exec(move_num,player_id,ignore_limit)
	EditMagic.new().exec(null, 0 - cost, player_id)
