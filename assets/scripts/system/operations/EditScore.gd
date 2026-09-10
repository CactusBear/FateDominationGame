class_name EditScore
extends RefCounted

func exec(set_num:BaseNumber = null, vary_num:BaseNumber = BaseNumber.new(0), player_id:int = -1):

	player_id = EffectManager.resolve_player_id(player_id)
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	var score = player_data["score"] as BaseNumber
	var before = score.number
	if set_num != null:
		score.set_num(set_num)
	score.add(vary_num)

	if score.number > before:
		player_data["score_gained_this_turn"] = (player_data["score_gained_this_turn"] as int) + (score.number - before)
		TimePointChecker.dynamic_time_point([TimePoints.SCORE_ADD], player_id)
	elif score.number < before:
		TimePointChecker.dynamic_time_point([TimePoints.SCORE_DECREASE], player_id)
