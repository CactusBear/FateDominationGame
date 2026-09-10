class_name Move
extends RefCounted

func exec(move_num:BaseNumber, player_id:int = -1, ignore_limit:bool = false, ignore_battle:bool = false):

	player_id = EffectManager.resolve_player_id(player_id)
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	#ignore_engagement_for_move(如言峰监督者中立)让玩家无视交战状态移动，不需要调用方额外传ignore_battle
	var ignore_engagement = player_data["ignore_engagement_for_move"] as bool
	if !ignore_battle and !ignore_engagement and player_data["is_battle"] == true:
		#show("处于交战状态，无法移动")
		return
	var cost = MoveLocation.new().exec(move_num,player_id,ignore_limit)
	EditMagic.new().exec(null, 0 - cost, player_id)
