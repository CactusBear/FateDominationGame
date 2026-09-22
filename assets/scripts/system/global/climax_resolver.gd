class_name ClimaxResolver
extends RefCounted


#高潮按战果排名淘汰玩家。保留线上的同分玩家全部保留。
func exec(keep_count:BaseNumber) -> Array:
	var active_ids:Array = GameDataManager.get_active_player_ids()
	if active_ids.is_empty():
		return []
	if keep_count == null or keep_count.number <= 0:
		for id in active_ids:
			eliminate_player(id)
		return []
	if keep_count.number >= active_ids.size():
		return active_ids

	var ranked:Array = active_ids.duplicate()
	ranked.sort_custom(func(a, b):
		var a_score = (GameDataManager.get_player_data(a)["score"] as BaseNumber).number
		var b_score = (GameDataManager.get_player_data(b)["score"] as BaseNumber).number
		if a_score != b_score:
			return a_score > b_score
		return int(a) < int(b)
	)
	var cutoff_score = (GameDataManager.get_player_data(ranked[keep_count.number - 1])["score"] as BaseNumber).number
	var kept:Array = []
	for id in ranked:
		var score = (GameDataManager.get_player_data(id)["score"] as BaseNumber).number
		if score >= cutoff_score:
			kept.append(id)
		else:
			eliminate_player(id)
	return kept


func eliminate_player(player_id:int) -> bool:
	if !GameData.player_data_library.has(player_id):
		return false
	var player_data = GameDataManager.get_player_data(player_id) as Dictionary
	if player_data["is_out"]:
		return false
	player_data["is_out"] = true
	#日志：谁被淘汰（供"当时场上有被淘汰的玩家吗"这类历史查询）。
	#带上当时的战果：事后核对"为什么是他被淘汰"不必再翻别的记录
	var score:int = (player_data["score"] as BaseNumber).number
	GameLog.record("eliminated", player_id, -1, "", null, ["eliminated"], {"score": score})
	#被淘汰的玩家离开版图：只置is_out不摘席位，他仍会占着位置、也仍显示在战区上。
	#复用回合结束用的同一个原语，不在这里另写一套摘除逻辑
	RemoveFromBoard.new().exec(player_id)
	#提示全员：谁被淘汰了。文案由显示名接口生成，不按id编号示人
	var shown:String = _player_shown_name(player_id)
	EffectManager.push_message("%s 被淘汰，战果 %d" % [shown, score])
	TimePointChecker.dynamic_time_point([TimePoints.ELIMINATED], player_id)
	return true


#玩家的示人名字：走御主的显示名接口，取不到才回退玩家编号
func _player_shown_name(player_id:int) -> String:
	var player_data = GameDataManager.get_player_data(player_id) as Dictionary
	var master = player_data.get("master")
	if master != null:
		var shown:String = str(master.get_shown_name())
		if shown != "":
			return shown
	return "玩家 %d" % player_id
