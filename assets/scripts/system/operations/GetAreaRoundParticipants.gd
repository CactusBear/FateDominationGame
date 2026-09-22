class_name GetAreaRoundParticipants
extends RefCounted

#本回合某战区实际进入过 BattleResolver 的玩家。日志由每名参与者各记一条，故去重。
func exec(map_area:BaseMapArea) -> Array:
	if map_area == null:
		return []
	var participants:Array = []
	for entry in GameLog.query({"type": "battle", "place": str(map_area._area_name)}, 0):
		for player_id in (entry.get("data", {}) as Dictionary).get("players", []) as Array:
			if !participants.has(player_id):
				participants.append(player_id)
	return participants
