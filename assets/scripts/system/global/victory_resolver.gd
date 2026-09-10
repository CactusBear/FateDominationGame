class_name VictoryResolver
extends RefCounted


#返回最终获胜玩家。规则：第11天(最终回合)结束时战果最高者获胜；
#若并列，则以本回合深山町战斗的胜者作为决胜；决胜仍无法分出唯一胜者时，
#视为圣杯溢出，全员判负(返回空数组)。
#battle_result为战斗阶段结算(BattleResolver.exec)返回的结果字典，用于取深山町胜者
func exec(battle_result:Dictionary = {}) -> Array:
	var active_ids:Array = GameDataManager.get_active_player_ids()
	if active_ids.is_empty():
		return []

	#效果可以直接判定某玩家获胜(victory_override)，此时跳过战果比较，
	#直接以所有被覆盖为胜利的玩家作为结果(可能同时存在多个)
	var overridden_winners:Array = []
	for id in active_ids:
		var player_data = GameDataManager.get_player_data(id) as Dictionary
		if player_data.get("victory_override", false):
			overridden_winners.append(id)
	if !overridden_winners.is_empty():
		for id in active_ids:
			var player_data = GameDataManager.get_player_data(id) as Dictionary
			player_data["is_victory"] = overridden_winners.has(id)
		return overridden_winners

	var highest_score = null
	var winners:Array = []
	for id in active_ids:
		var player_data = GameDataManager.get_player_data(id) as Dictionary
		player_data["is_victory"] = false
		var score = (player_data["score"] as BaseNumber).number
		if highest_score == null or score > highest_score:
			highest_score = score
			winners = [id]
		elif score == highest_score:
			winners.append(id)

	if winners.size() > 1:
		winners = _resolve_tie_by_miyama_battle(winners, battle_result)

	for id in winners:
		var player_data = GameDataManager.get_player_data(id) as Dictionary
		player_data["is_victory"] = true
	return winners


#并列决胜：取本回合深山町战斗胜者与并列者的交集；交集恰为1人则其获胜，
#否则(无人交战、深山町本身平局、或胜者不在并列名单中)判定为圣杯溢出，全员判负
func _resolve_tie_by_miyama_battle(tied_ids:Array, battle_result:Dictionary) -> Array:
	var winners_by_area:Dictionary = battle_result.get("winners_by_area", {})
	var miyama_winners:Array = winners_by_area.get(MapData.miyama._area_name, [])
	var decisive_winners:Array = []
	for id in miyama_winners:
		if tied_ids.has(id):
			decisive_winners.append(id)
	if decisive_winners.size() == 1:
		return decisive_winners
	return []
