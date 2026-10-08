extends RefCounted

## 仅解码私有恢复文件的显式座位声明；不承担运行屏障或身份认证。
const Seats = preload("res://scripts/match/seat_controller.gd")
const MAX_MEMBER:int = 2147483647
const MAX_SAFE_JSON_INTEGER:float = float(9007199254740991)

static func _invalid(reason:String) -> Dictionary:
	return {"ok":false, "error":reason, "bindings":{}, "seat_kinds":{}}

## Variant int 不经过 float，保留完整 int64；JSON float 必须有限、精确且在安全范围内。
static func integer(value:Variant, maximum:int) -> Dictionary:
	if value is int:
		if value >= 0 and value <= maximum: return {"ok":true, "value":value}
	elif value is float:
		if is_finite(value) and value >= 0 and value <= MAX_SAFE_JSON_INTEGER and value <= maximum and floor(value) == value:
			return {"ok":true, "value":int(value)}
	return {"ok":false}

## JSON 对象键须为规范十进制；拒绝 +1、01、负数、空白及溢出，不做修复。
static func player_key(raw:Variant) -> Dictionary:
	if not raw is String or not raw.is_valid_int(): return {"ok":false}
	var value:int = raw.to_int()
	if value < 0 or str(value) != raw: return {"ok":false}
	return {"ok":true, "value":value}

static func decode(state:Dictionary) -> Dictionary:
	if not state.get("room") is Dictionary or not state.room.get("members") is Dictionary:
		return _invalid("恢复成员表缺失或错型")
	if not state.get("bindings") is Dictionary:
		return _invalid("恢复座位绑定缺失或错型")
	var active:bool = state.room.get("phase") in ["playing", "restoring"]
	if not state.has("seat_kinds"):
		if active or not state.bindings.is_empty(): return _invalid("恢复文件缺少显式座位类型，拒绝推断原真人")
		return {"ok":true, "error":"", "bindings":{}, "seat_kinds":{}}
	if not state.seat_kinds is Dictionary:
		return _invalid("恢复座位类型错型")
	if state.bindings.size() != state.seat_kinds.size() or (active and state.bindings.is_empty()):
		return _invalid("绑定与座位类型须为同一非空座位全集")
	var bindings:Dictionary = {}
	var kinds:Dictionary = {}
	var humans:Dictionary = {}
	for raw in state.bindings:
		var key:Dictionary = player_key(raw)
		if not key.ok or bindings.has(key.get("value")) or not state.seat_kinds.has(raw):
			return _invalid("恢复绑定玩家键无效、重复或缺少类型")
		var member:Dictionary = integer(state.bindings[raw], MAX_MEMBER)
		if not member.ok: return _invalid("恢复成员绑定须为范围内的精确整数")
		var kind = state.seat_kinds[raw]
		if not kind is String or kind not in [Seats.AI, Seats.REMOTE]:
			return _invalid("恢复座位类型不支持，拒绝推断")
		if kind == Seats.AI:
			if member.value != 0: return _invalid("AI 座位只能显式绑定 0")
		else:
			var declared = state.room.members.get(str(member.value))
			if member.value <= 0 or humans.has(member.value) or not declared is Dictionary or not declared.get("spectator") is bool or declared.spectator:
				return _invalid("原真人须绑定唯一且明确非观战的既有成员")
			humans[member.value] = true
		bindings[key.value] = member.value
		kinds[key.value] = kind
	# 不允许额外坏键被忽略，即便其值看似合法。
	for raw in state.seat_kinds:
		if not player_key(raw).ok or not state.bindings.has(raw): return _invalid("恢复座位类型含非法或额外玩家键")
	return {"ok":true, "error":"", "bindings":bindings, "seat_kinds":kinds}
