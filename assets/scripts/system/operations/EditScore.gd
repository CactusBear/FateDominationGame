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

	#先把这次的差值固定下来并记完日志，再派发时点：
	#时点里的效果还会再改战果，本条的 delta 必须仍是这一次自己的
	var delta = score.number - before
	GameLog.record_resource_change("score", player_id, before, score.number)

	if delta > 0:
		TimePointChecker.dynamic_time_point([TimePoints.SCORE_ADD], player_id)
	elif delta < 0:
		TimePointChecker.dynamic_time_point([TimePoints.SCORE_DECREASE], player_id)
