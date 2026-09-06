class_name EditScore
extends RefCounted

func exec(set_num:BaseNumber = null, vary_num:BaseNumber = BaseNumber.new(0), player_id:int = GameData.player_id):

	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	if set_num != null:
		player_data["score"] = set_num
	var score = player_data["score"] as BaseNumber
	score.add(vary_num)
