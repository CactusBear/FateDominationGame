class_name AbilityRestrictions
extends RefCounted

# 阶段能力禁用记录：类别和目标来自数据；默认期限遵循规则156的两个终点取先到。
static var entries:Array = []

static func register(players:Array, phase_mids:Array, source:BaseHandCard, expire_round:bool, expire_source:bool) -> bool:
	if players.is_empty() or phase_mids.is_empty() or source == null:
		return false
	entries.append({"players":players.duplicate(), "phases":phase_mids.duplicate(), "source":weakref(source),
		"round":GameProgress.current_round, "expire_round":expire_round, "expire_source":expire_source})
	return true

static func source_deactivated(source:BaseHandCard) -> void:
	for entry in entries.duplicate():
		if entry.expire_source and entry.source.get_ref() == source:
			entries.erase(entry)

static func round_ended() -> void:
	for entry in entries.duplicate():
		if entry.expire_round: entries.erase(entry)

static func is_disabled(effect:BaseEffect) -> bool:
	if effect == null: return false
	for entry in entries.duplicate():
		var source = entry.source.get_ref()
		if source == null or (entry.expire_round and entry.round != GameProgress.current_round) \
			or (entry.expire_source and not source._is_activating):
			entries.erase(entry)
			continue
		if not entry.players.has(effect._trigger_player_id): continue
		for mid in entry.phases:
			for prefix in [TimePoints.SELF_PREFIX, TimePoints.OTHERS_PREFIX, ""]:
				if effect._time_points.has(prefix + str(mid)): return true
	return false
