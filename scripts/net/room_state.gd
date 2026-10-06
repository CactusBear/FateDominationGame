class_name MatchRoomState
extends RefCounted

## 权威端房间状态。actor 必须由认证后的连接映射产生，不能取自客机声明。
var owner: int = 0
var phase: String = "lobby"
var settings: Dictionary = {}
var members: Dictionary = {}
var revision: int = 0
var error: String = ""

func configure(owner_id: int, declared: Dictionary) -> bool:
	if owner != 0 or owner_id <= 0:
		return _reject("房间已初始化或房主无效")
	if not _valid_settings(declared, 0):
		return false
	owner = owner_id
	settings = declared.duplicate(true)
	revision += 1
	return true

func join(id: int, name: String, spectator: bool = false) -> bool:
	if id <= 0 or members.has(id) or name.strip_edges().is_empty():
		return _reject("成员身份无效或重复")
	if not spectator and phase != "lobby":
		return _reject("选人后不能增加玩家")
	if spectator:
		var limit: int = int(settings.get("spectator_limit", 0))
		if _spectators() >= limit:
			return _reject("观战席已满")
	elif _humans() + int(settings.ai_count) >= int(settings.capacity):
		return _reject("房间没有空座位")
	members[id] = {"name": name, "spectator": spectator, "ready": false, "connected": true}
	_invalidate_ready()
	return true

func set_settings(actor: int, changes: Dictionary) -> bool:
	if not _is_owner(actor) or phase != "lobby":
		return _reject("无权修改或设置已冻结")
	var candidate := settings.duplicate(true)
	for key in changes:
		if key not in ["ai_count", "selection_mode", "spectator_limit", "runtime_guard"]:
			return _reject("此字段须通过主机规则配置更新")
		candidate[key] = changes[key]
	if not _valid_settings(candidate, _humans()) or int(candidate.get("spectator_limit", 0)) < _spectators():
		return _reject("设置与当前成员不兼容")
	settings = candidate
	_invalidate_ready()
	return true

func configure_rules(changes: Dictionary) -> bool:
	if phase != "lobby":
		return _reject("主机规则配置已冻结")
	var candidate := settings.duplicate(true)
	for key in changes:
		if key not in ["capacity", "minimum"]:
			return _reject("不是主机规则配置字段")
		candidate[key] = changes[key]
	if not _valid_settings(candidate, _humans()):
		return _reject("所选数据容量与当前成员或 AI 数量不兼容")
	settings = candidate
	_invalidate_ready()
	return true

func set_ready(actor: int, ready: bool) -> bool:
	if phase != "lobby" or not _connected(actor) or members[actor].spectator:
		return _reject("当前不能准备")
	members[actor].ready = ready
	revision += 1
	return true

func can_start() -> bool:
	if phase != "lobby" or not _connected(owner) or _humans() + int(settings.ai_count) < int(settings.minimum):
		return false
	for id in members:
		if not members[id].spectator and (not members[id].connected or not members[id].ready):
			return false
	return true

func start(actor: int) -> bool:
	if not _is_owner(actor) or not can_start():
		return _reject("房间尚未准备完成")
	phase = "selecting"
	revision += 1
	return true

func transfer_owner(actor: int, target: int) -> bool:
	if not _is_owner(actor) or not _connected(target) or members[target].spectator:
		return _reject("不能转让房主")
	owner = target
	revision += 1
	return true

func return_to_lobby(actor:int) -> bool:
	if not _is_owner(actor) or phase != "playing":
		return _reject("无权返回大厅或没有正在进行的对局")
	phase = "lobby"
	_invalidate_ready()
	return true

func mark_disconnected(id: int) -> void:
	if members.has(id):
		members[id].connected = false
		members[id].ready = false
		revision += 1

func kick(actor: int, target: int) -> bool:
	if not _is_owner(actor) or target == owner or not members.has(target):
		return _reject("不能移除该成员")
	members.erase(target)
	_invalidate_ready()
	return true

func snapshot() -> Dictionary:
	return {"owner": owner, "phase": phase, "revision": revision, "settings": settings.duplicate(true), "members": members.duplicate(true)}

func _connected(id: int) -> bool:
	return members.has(id) and bool(members[id].connected)

func _is_owner(id: int) -> bool:
	return id == owner and _connected(id)

func _humans() -> int:
	return members.values().filter(func(member): return not member.spectator).size()

func _spectators() -> int:
	return members.size() - _humans()

func _invalidate_ready() -> void:
	for id in members:
		members[id].ready = false
	revision += 1

func _valid_settings(value: Dictionary, humans: int) -> bool:
	for key in ["capacity", "minimum", "ai_count"]:
		if not value.get(key) is int:
			return _reject("人数配置必须显式提供整数")
	if not value.get("selection_mode") is String or value.selection_mode.is_empty():
		return _reject("缺少选人模式")
	if value.capacity < 1 or value.minimum < 1 or value.minimum > value.capacity or value.ai_count < 0 or humans + value.ai_count > value.capacity:
		return _reject("人数配置无效")
	if value.has("spectator_limit") and (not value.spectator_limit is int or value.spectator_limit < 0):
		return _reject("观战席配置无效")
	if value.has("runtime_guard"):
		if not value.runtime_guard is Dictionary or not preload("res://scripts/match/rule_budget.gd").new().configure(value.runtime_guard):
			return _reject("规则执行预算无效")
	return true

func _reject(reason: String) -> bool:
	error = reason
	return false
