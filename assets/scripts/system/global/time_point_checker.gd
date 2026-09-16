extends Node


#时点表的维护者：负责把时点写进各玩家的current_time_points，
#写完后交给EffectManager去检查效果池。它自己不再做任何效果筛选。


var global_signals:Dictionary
#当前阶段的固定时点，整个阶段内对所有玩家都成立
var phase_time_points:Array


#阶段推进时由GameProgress设置。换阶段会清掉上一阶段残留的动态时点
func set_phase_time_points(time_points:Array):
	phase_time_points = time_points.duplicate()
	for id in EffectManager.get_all_players_id():
		var pl_data = GameDataManager.get_player_data(id) as Dictionary
		(pl_data["dynamic_time_points"] as Array).clear()
	time_point_update()


#派发一个不属于任何玩家的时点(阶段开始/结束、回合开始/结束等)。
#所有玩家拿到的都是原始时点，没有self_/others_之分
func global_time_point(time_points:Array):
	for id in EffectManager.get_all_players_id():
		var pl_data = GameDataManager.get_player_data(id) as Dictionary
		var dtp_arr = pl_data["dynamic_time_points"] as Array
		for tp in time_points:
			dtp_arr.append(tp)
		pl_data["current_time_points"] = phase_time_points + dtp_arr
	#日志：全局时点（不属于任何玩家，actor 记 -1）
	GameLog.record("time_point", -1, -1, "", null, ["global"] + time_points.duplicate(),
		{"time_points": time_points.duplicate()})
	time_point_check()


#派发一个由玩家操作/效果引发的动态时点。
#触发者拿到"self_xx"，其他人拿到"others_xx"，这样同一个时点对不同玩家有不同含义，
#效果只要写self_/others_前缀就能自动区分是不是自己的回合
func dynamic_time_point(time_points:Array, current_player_id:int):
	var current_player_data:Dictionary = GameDataManager.get_player_data(current_player_id)
	var current_dtp_arr:Array = current_player_data["dynamic_time_points"] as Array
	for tp in time_points:
		current_dtp_arr.append(tp)
		current_dtp_arr.append("self_" + tp)
	current_player_data["current_time_points"] = phase_time_points + current_dtp_arr

	var pl_ids = EffectManager.get_all_players_id() as Array
	pl_ids.erase(current_player_id)
	for id in pl_ids:
		var other_player_data:Dictionary = GameDataManager.get_player_data(id)
		var other_dtp_arr:Array = other_player_data["dynamic_time_points"] as Array
		for tp in time_points:
			other_dtp_arr.append(tp)
			other_dtp_arr.append("others_" + tp)
		other_player_data["current_time_points"] = phase_time_points + other_dtp_arr

	#日志：谁在什么时点被派发（历史查询最基础的一条事实）
	GameLog.record("time_point", current_player_id, -1, "", null, time_points.duplicate(),
		{"time_points": time_points.duplicate()})
	time_point_check()


#时点表更新完后统一走这里。效果的发现、询问、结算全在EffectManager里
func time_point_check():
	EffectManager.run_time_point()


func time_point_update():
	var pl_ids = EffectManager.get_all_players_id() as Array
	for id in pl_ids:
		var pl_data = GameDataManager.get_player_data(id) as Dictionary
		pl_data["current_time_points"] = phase_time_points + pl_data["dynamic_time_points"]
