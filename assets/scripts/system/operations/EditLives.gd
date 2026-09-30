class_name EditLives
extends RefCounted

func exec(set_num:BaseNumber = null, vary_num:BaseNumber = BaseNumber.new(0), player_id:int = -1):

	var id = EffectManager.resolve_player_id(player_id)
	var player_data:Dictionary = GameDataManager.get_player_data(id)
	var lives = player_data["lives"] as BaseNumber
	var before = lives.number
	#就地改写玩家自己的数字，避免把效果自带的数字对象挂到玩家身上
	if set_num != null:
		lives.set_num(set_num)
	lives.add(vary_num)

	if lives.number > before:
		TimePointChecker.dynamic_time_point([TimePoints.LIVES_ADD], id)
	elif lives.number < before:
		TimePointChecker.dynamic_time_point([TimePoints.LIVES_DECREASE], id)

	if lives.number <= 0:
		#与高潮淘汰同一个"即将淘汰"询问：被取消时不出局，并派发"免于淘汰"。已经出局的不再询问
		if !player_data["is_out"] and EffectManager.begin_pending_action(TimePoints.BEFORE_ELIMINATE, id).get("cancelled", false):
			TimePointChecker.dynamic_time_point([TimePoints.SURVIVE_ELIMINATION], id)
			return
		player_data["is_out"] = true
		TimePointChecker.dynamic_time_point([TimePoints.ELIMINATED], id)
	elif lives.number == 1:
		TimePointChecker.dynamic_time_point([TimePoints.LAST_LIFE], id)
