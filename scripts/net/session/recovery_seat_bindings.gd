extends RefCounted

## 接受日志读取器解码后的整数键；不从当前房间顺序、昵称或成员数量推测座位。
const Seats = preload("res://scripts/match/seat_controller.gd")

static func _invalid(reason:String) -> Dictionary:
	return {"ok":false, "required":[], "error":reason}

## members=null 仅用于权威层结构校验；会话层必须传入真实成员表。
static func validate(header:Dictionary, bindings:Dictionary, members = null) -> Dictionary:
	if not header.get("players") is Array or header.players.is_empty() or not header.get("seat_kinds") is Dictionary or not header.get("assignments") is Dictionary:
		return _invalid("存档缺少完整玩家、阵容或座位类型声明")
	if members != null and not members is Dictionary:
		return _invalid("恢复成员表格式无效")
	var players:Array = header.players
	if bindings.size() != players.size() or header.seat_kinds.size() != players.size() or header.assignments.size() != players.size():
		return _invalid("绑定、阵容和座位类型必须与存档玩家集合完全一致")
	var seen:Dictionary = {}
	var required:Array = []
	for pid in players:
		if not pid is int or pid < 0 or seen.has(pid):
			return _invalid("存档玩家 ID 无效或重复")
		seen[pid] = true
		if not bindings.has(pid) or not header.seat_kinds.has(pid) or not header.assignments.has(pid) or not header.assignments[pid] is Dictionary:
			return _invalid("存档阵容和绑定必须逐座完整声明")
		var member = bindings[pid]
		if not member is int or member < 0 or member > preload("res://scripts/net/session/recovery_seat_json.gd").MAX_MEMBER:
			return _invalid("连接绑定必须为非负整数成员 ID")
		var kind = header.seat_kinds[pid]
		if kind == Seats.AI:
			if member != 0:
				return _invalid("存档 AI 座位只能显式绑定 0")
		elif kind == Seats.REMOTE:
			if member <= 0 or required.has(member):
				return _invalid("真人座位必须绑定唯一的正整数成员 ID")
			if members != null and not _is_player(members, member):
				return _invalid("原真人绑定成员不存在、角色缺失或已经变为观战者")
			required.append(member)
		else:
			return _invalid("存档座位类型未明确声明为网络真人或 AI，拒绝猜测")
	required.sort()
	return {"ok":true, "required":required, "error":""}

static func _is_player(members:Dictionary, member:int) -> bool:
	return members.get(member) is Dictionary and members[member].get("spectator") is bool and not members[member].spectator

## 空 required 只有校验成功才能放行；每次读取当前成员状态和当前版本 ACK。
static func ready(validation:Dictionary, members:Dictionary, confirmed:Dictionary, revision:int) -> bool:
	if not validation.get("ok", false) or revision < 0:
		return false
	for member in validation.required:
		if not _is_player(members, member) or not members[member].get("connected") is bool or not members[member].connected:
			return false
		if revision > 0 and (not confirmed.get(member) is int or confirmed[member] != revision):
			return false
	return true
