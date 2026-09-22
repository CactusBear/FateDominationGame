class_name RemoveFromBoard
extends RefCounted

#规则：回合结束时将每名御主的立牌移除版图。
#只做"离开版图"这一件事：位置置空，并同步从席位的 _players 里摘除——
#只清 location 不摘 _players 的话，席位人数永远只增不减，部署上限判定与展示都会失真。
#没有落点，所以不复用 SetLocation（那是"落到某个位置"）
#返回是否真的从版图上移除了（本来就不在版图上返回 false）
func exec(player_id:int = -1) -> bool:

	player_id = EffectManager.resolve_player_id(player_id)
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	var loc = player_data.get("location")
	if loc == null:
		return false
	(loc._players as Array).erase(player_id)
	var area := loc.get_from() as BaseMapArea
	player_data["location"] = null
	#日志：谁离开了哪个战区。供"上回合在哪""本回合是否上过版图"这类历史查询
	GameLog.record("leave_board", player_id, -1,
		str(area._area_name) if area != null else "", loc, ["leave_board"], {})
	return true
