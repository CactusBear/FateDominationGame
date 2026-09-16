class_name GetRoundBattleWins
extends RefCounted

#查「某玩家本回合已经赢得几场战斗」。战斗事实统一记在日志里（battle 条目的 winners 含自己），
#这里只是把这一种查询包成 operation，供「每赢得一场战斗…」这类效果按次结算用。
#player_id 传 -1 表示当前效果的触发者，与其它 operation 一致
func exec(player_id:int = -1) -> int:

	var id:int = EffectManager.resolve_player_id(player_id)
	var wins:int = 0
	for entry in GameLog.query({"type" : "battle", "actor" : id}, 0):
		var winners:Array = (entry.get("data", {}) as Dictionary).get("winners", []) as Array
		if winners.has(id):
			wins += 1
	return wins
