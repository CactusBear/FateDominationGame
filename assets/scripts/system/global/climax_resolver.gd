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
	TimePointChecker.dynamic_time_point([TimePoints.ELIMINATED], player_id)
	return true
