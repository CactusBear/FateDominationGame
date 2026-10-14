extends RefCounted

## 仅本机 dedicated worker 使用；room.members 是真人/观战，AI 在 settings.ai_count。
var config:Dictionary = {}
var since_msec:int = -1
var phase:String = ""
var epoch:int = 0

static func valid_config(value:Variant) -> bool:
	if not value is Dictionary: return false
	for key in value:
		if key == "shared_cache":
			if not value[key] is bool: return false
			continue
		if key == "online_spectators":
			if value[key] != "retain": return false
			continue
		if key not in ["idle_lobby_seconds","idle_match_seconds"]: return false
		if typeof(value[key]) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value[key])) or value[key] < 0 or value[key] > 9007199254740.0: return false
	# 未确认观战口径时不能启用自动回收；只支持显式 retain，不猜释放策略。
	if float(value.get("idle_lobby_seconds",0)) > 0 or float(value.get("idle_match_seconds",0)) > 0:
		if value.get("online_spectators") != "retain": return false
	return true

func configure(value:Variant) -> bool:
	if not valid_config(value): return false
	config = value.duplicate(true)
	reset()
	return true

func reset() -> void:
	since_msec = -1
	phase = ""

func vacant(session) -> bool:
	if session.room.phase not in ["lobby","selecting","playing","restoring"]: return false
	if session._restore_in_progress or session._begin_in_progress or session.match_authority._archive_pulse_running: return false
	# 缺失/非法 connected 不能推断为无人，在线观战者同样保房间。
	return session.room.members.values().all(func(member): return member is Dictionary and member.get("connected") is bool and member.connected == false)

func observe(session, now:int) -> void:
	if not vacant(session):
		since_msec = -1
		phase = ""
		return
	if since_msec < 0 or phase != session.room.phase or now < since_msec:
		since_msec = now
		phase = session.room.phase
		epoch += 1

func expired(session, now:int) -> bool:
	if since_msec < 0 or phase != session.room.phase or not vacant(session): return false
	var key:String = "idle_lobby_seconds" if phase == "lobby" else "idle_match_seconds"
	var seconds:float = float(config.get(key,0.0))
	# 不向下取整毫秒，避免正的极小等待被误当成立即回收。
	return seconds > 0 and now >= since_msec and float(now - since_msec) >= seconds * 1000.0
