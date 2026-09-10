class_name Defeat
extends RefCounted


#给目标玩家附加【败北】buff，并派发 BATTLE_LOSE 时点。
#具体的战斗胜负标记（is_battle_win / is_battle_lose）由 BattleResolver 在结算时自行管理。
func exec(player_id:int = -1):
	player_id = EffectManager.resolve_player_id(player_id)
	DefeatBuff.apply(player_id)
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_LOSE], player_id)
