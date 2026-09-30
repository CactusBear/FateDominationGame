class_name EndGame
extends RefCounted

#立刻结束对局并以给定玩家作为胜者（"立即获得游戏胜利"）。
#与 set_player_data("victory_override", true) 的区别：那个只在终局判定时生效，这里是现在就结束。
#胜者写进各玩家的 is_victory，结局事实与提示由 GameProgress.end_game 统一记录——与正常终局同一条路径。
#winner_ids 为空表示无人获胜（全员判负）。已经结束的对局不再重复结束，返回 false
func exec(winner_ids:Array = []) -> bool:

	if GameProgress.is_game_over:
		return false
	var winners:Array = []
	for raw in winner_ids:
		if raw != null and GameData.player_data_library.has(int(raw)) and !winners.has(int(raw)):
			winners.append(int(raw))
	for id in GameData.player_data_library.keys():
		(GameData.player_data_library[id] as Dictionary)["is_victory"] = winners.has(int(id))
	GameProgress.end_game(winners)
	return true
