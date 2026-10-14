class_name EditScore
extends RefCounted

func exec(set_num:BaseNumber = null, vary_num:BaseNumber = BaseNumber.new(0), player_id:int = -1):
	# 资源操作只能承接当前执行帧捕获的来源；不按相同整数 ID 向新局补票。
	var execution:Dictionary = EffectManager.execution_context()
	if not execution.get("ok", false):
		return
	var context:SessionContext = execution.get("context") as SessionContext
	if context == null:
		return

	player_id = EffectManager.resolve_player_id(player_id)
	var player_data:Dictionary = GameDataManager.find_player_data(player_id)
	if player_data.is_empty():
		return
	var score = player_data.get("score") as BaseNumber
	if score == null:
		return
	var players:Dictionary = GameData.player_data_library
	var before = score.number
	var target = (set_num.number if set_num != null else before) + (vary_num.number if vary_num != null else 0)
	#即将获得战果：效果可以取消，或改写这次获得的数量（减半、翻倍、设上限）
	if target > before:
		var action:Dictionary = EffectManager.begin_pending_action(TimePoints.BEFORE_SCORE_ADD, player_id,
			{"amount": BaseNumber.new(target - before)})
		#同步监听可能重置会话或替换资源；同编号不能授权旧动作写入新对象。
		var after_execution:Dictionary = EffectManager.execution_context()
		if not after_execution.get("ok", false) or not is_same(after_execution.get("context"), context):
			return
		var current:Dictionary = GameDataManager.find_player_data(player_id)
		if not is_same(players, GameData.player_data_library) or not is_same(player_data, current) or not is_same(score, current.get("score")):
			return
		if action.get("cancelled", false):
			return
		#同一对象的余额可被监听合法改变，本次只追加最终声明的 amount。
		before = score.number
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
