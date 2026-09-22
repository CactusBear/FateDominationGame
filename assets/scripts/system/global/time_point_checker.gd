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
	#阶段整体轮转：上一阶段的持续窗口结算记录一并作废
	EffectManager.reset_phase_window_settlements()
	time_point_update()


#派发一个不属于任何玩家的时点(阶段开始/结束、回合开始/结束等)。
#所有玩家拿到的都是原始时点，没有self_/others_之分
func global_time_point(time_points:Array, source = null):
	for id in EffectManager.get_all_players_id():
		var pl_data = GameDataManager.get_player_data(id) as Dictionary
		var dtp_arr = pl_data["dynamic_time_points"] as Array
		for tp in time_points:
			dtp_arr.append(tp)
		pl_data["current_time_points"] = phase_time_points + dtp_arr
	#日志：全局时点（不属于任何玩家，actor 记 -1）
	GameLog.record("time_point", -1, -1, "", source, ["global"] + time_points.duplicate(),
		{"time_points": time_points.duplicate()})
	EffectManager.run_time_point(source)
	#Entry is a transient event, not a lasting phase window.
	if source != null:
		for id in EffectManager.get_all_players_id():
			var data:Dictionary = GameDataManager.get_player_data(id)
			for tp in time_points: data.dynamic_time_points.erase(tp)
		time_point_update()


#清掉所有玩家身上"玩家级"(self_/others_)的旧动态时点。
#这类时点表达的是"现在是谁的阶段"，含义随轮次整体改变，所以要按轮次重算：
#不清的话，上一个玩家的 self_action_phase / others_action_phase 会留到下一个玩家身上，
#同一个人会同时满足"自己的行动阶段"和"他人的行动阶段"两个互斥的效果窗口。
#只按前缀过滤，不写死具体时点名（BATTLE、PLAYED_CARD 这类由效果自己用完即清的时点不受影响）
func clear_player_scope_time_points():
	var pl_ids = EffectManager.get_all_players_id() as Array
	for id in pl_ids:
		var pl_data = GameDataManager.get_player_data(id) as Dictionary
		var dtp_arr = pl_data["dynamic_time_points"] as Array
		for i in range(dtp_arr.size() - 1, -1, -1):
			var tp := str(dtp_arr[i])
			if tp.begins_with(TimePoints.SELF_PREFIX) or tp.begins_with(TimePoints.OTHERS_PREFIX):
				dtp_arr.remove_at(i)
		pl_data["current_time_points"] = phase_time_points + dtp_arr
	#玩家级阶段窗口整体换人/换阶段：窗口内"已结算过"的记录随之清空，
	#下一个人的同一阶段窗口才能重新结算（否则第二个玩家的阶段能力会被当成已用过）
	EffectManager.reset_phase_window_settlements()


# 结算一条效果后只消费瞬时事件；当前玩家/其他玩家的阶段窗口持续到轮转时再统一清除。
# 阶段名从 GameProgress.phases 读取，不在这里写死 prepare/outpost/action/battle。
func consume_transient_time_points() -> void:
	for id in EffectManager.get_all_players_id():
		var pl_data:Dictionary = GameDataManager.get_player_data(id)
		var dtp_arr:Array = pl_data["dynamic_time_points"] as Array
		for i in range(dtp_arr.size() - 1, -1, -1):
			if not is_persistent_player_window(str(dtp_arr[i])):
				dtp_arr.remove_at(i)
		pl_data["current_time_points"] = phase_time_points + dtp_arr


## 这个时点是不是"持续窗口"（按当前阶段/行动者成立的 self_/others_ 阶段窗口或高潮标记）。
## 持续窗口与一次性事件不同：它派发后会一直留在玩家的时点表里，直到阶段轮转才被清掉，
## 所以"同一窗口内只结算一次"的去重必须基于这个判定。
## EffectManager 收集效果时也用它，因此这里是唯一口径
func is_persistent_player_window(time_point:String) -> bool:
	for phase_data in GameProgress.phases:
		var mid:String = str(phase_data.get("mid", ""))
		if time_point == TimePoints.SELF_PREFIX + mid or time_point == TimePoints.OTHERS_PREFIX + mid:
			return true
	for round_window in [TimePoints.CLIMAX, TimePoints.NON_CLIMAX]:
		if time_point == TimePoints.SELF_PREFIX + round_window or time_point == TimePoints.OTHERS_PREFIX + round_window:
			return true
	return false


#派发一个由玩家操作/效果引发的动态时点。
#触发者拿到"self_xx"，其他人拿到"others_xx"，这样同一个时点对不同玩家有不同含义，
#效果只要写self_/others_前缀就能自动区分是不是自己的回合
func dynamic_time_point(time_points:Array, current_player_id:int, source = null):
	var current_player_data:Dictionary = GameDataManager.get_player_data(current_player_id)
	var current_dtp_arr:Array = current_player_data["dynamic_time_points"] as Array
	for tp in time_points:
		current_dtp_arr.append(tp)
		current_dtp_arr.append(TimePoints.SELF_PREFIX + str(tp))
	current_player_data["current_time_points"] = phase_time_points + current_dtp_arr

	var pl_ids = EffectManager.get_all_players_id() as Array
	pl_ids.erase(current_player_id)
	for id in pl_ids:
		var other_player_data:Dictionary = GameDataManager.get_player_data(id)
		var other_dtp_arr:Array = other_player_data["dynamic_time_points"] as Array
		for tp in time_points:
			other_dtp_arr.append(tp)
			other_dtp_arr.append(TimePoints.OTHERS_PREFIX + str(tp))
		other_player_data["current_time_points"] = phase_time_points + other_dtp_arr

	#日志：谁在什么时点被派发（历史查询最基础的一条事实）
	GameLog.record("time_point", current_player_id, -1, "", source, time_points.duplicate(),
		{"time_points": time_points.duplicate()})
	EffectManager.run_time_point(source)


#时点表更新完后统一走这里。效果的发现、询问、结算全在EffectManager里
func time_point_check():
	EffectManager.run_time_point()


func time_point_update():
	var pl_ids = EffectManager.get_all_players_id() as Array
	for id in pl_ids:
		var pl_data = GameDataManager.get_player_data(id) as Dictionary
		pl_data["current_time_points"] = phase_time_points + pl_data["dynamic_time_points"]
