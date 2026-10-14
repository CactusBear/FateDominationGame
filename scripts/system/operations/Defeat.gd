class_name Defeat
extends RefCounted


#给目标玩家附加【败北】buff，并派发 BATTLE_LOSE 时点。
#具体的战斗胜负标记（is_battle_win / is_battle_lose）由 BattleResolver 在结算时自行管理。
func exec(player_id:int = -1, context:Variant = null) -> bool:
	# 缺省仅继承真实已验函数帧；显式原来源原样透传，不领取当前票。
	context = RegisterObjectEffects.captured_context(context)
	var resolved:Dictionary = RegisterObjectEffects.resolved_player_id(player_id, context)
	if not resolved.ok:
		return false
	player_id = resolved.id
	var player_data:Dictionary = GameDataManager.find_player_data(player_id)
	if player_data.is_empty():
		return false
	# 即将败北仍同步结算；保取消与原生等待边界，不借 Queue 续行能力。
	var pending:Dictionary = EffectManager.begin_pending_action(TimePoints.BEFORE_DEFEAT, player_id)
	if pending.get("cancelled", false) or pending.get("invalidated", false):
		return false
	if not RegisterObjectEffects.source_is_current(context) or not is_same(player_data, GameDataManager.find_player_data(player_id)):
		return false
	var installed:DefeatBuff = DefeatBuff.apply(player_id, context)
	if installed == null:
		return false
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_LOSE], player_id, null, context)
	return true
