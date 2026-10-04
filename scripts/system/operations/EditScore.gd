class_name EditScore
extends RefCounted

func exec(set_num:BaseNumber = null, vary_num:BaseNumber = BaseNumber.new(0), player_id:int = -1):

	player_id = EffectManager.resolve_player_id(player_id)
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	var score = player_data["score"] as BaseNumber
	var before = score.number
	var target = (set_num.number if set_num != null else before) + (vary_num.number if vary_num != null else 0)
	#即将获得战果：效果可以取消，或改写这次获得的数量（减半、翻倍、设上限）
	if target > before:
		var action:Dictionary = EffectManager.begin_pending_action(TimePoints.BEFORE_SCORE_ADD, player_id,
			{"amount": BaseNumber.new(target - before)})
		if action.get("cancelled", false):
			return
		target = before + (action.values.amount as BaseNumber).number
	score.set_num(BaseNumber.new(target))
	#战果下限由玩家数据声明（score_min），没声明就不夹取
	var floor_num = player_data.get("score_min")
	if floor_num is BaseNumber and score.number < floor_num.number:
		score.set_num(floor_num)

	#先把这次的差值固定下来并记完日志，再派发时点：
	#时点里的效果还会再改战果，本条的 delta 必须仍是这一次自己的
	var delta = score.number - before
	GameLog.record_resource_change("score", player_id, before, score.number)

	if delta > 0:
		TimePointChecker.dynamic_time_point([TimePoints.SCORE_ADD], player_id)
	elif delta < 0:
		TimePointChecker.dynamic_time_point([TimePoints.SCORE_DECREASE], player_id)
