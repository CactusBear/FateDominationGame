class_name MatchViewMirror
extends RefCounted

## 镜像只存基础类型副本；调用者必须只接收主机来源消息。
var error: String = ""
var _view: Dictionary = {}
var _observer: int = -1
const ROOT := ["v", "seq", "observer", "round", "phase", "current_player", "game_over", "players", "areas", "situation", "public_log", "event_discard"]
const PLAYER := ["id", "controller", "player_name", "avatar", "own", "magic", "magic_limit", "score", "lives", "power", "power_breakdown", "total_power", "order", "command_spell_count", "command_spells", "is_out", "is_battle", "is_victory", "master", "servant", "servant_class", "servant_released", "deck_count", "hand_count", "hand_cards", "discard", "buffs", "out_of_game_cards", "played_cards", "master_skills", "servant_skills", "held_cards", "location"]
const ROOT_TYPES := {"v": TYPE_INT, "seq": TYPE_INT, "observer": TYPE_INT, "round": TYPE_INT, "phase": TYPE_STRING, "current_player": TYPE_INT, "game_over": TYPE_BOOL, "players": TYPE_ARRAY, "areas": TYPE_ARRAY, "situation": TYPE_DICTIONARY}
const PLAYER_TYPES := {"id": TYPE_INT, "controller": TYPE_INT, "player_name": TYPE_STRING, "avatar": TYPE_STRING, "own": TYPE_BOOL, "is_out": TYPE_BOOL, "is_battle": TYPE_BOOL, "is_victory": TYPE_BOOL, "servant_class": TYPE_STRING, "deck_count": TYPE_INT, "hand_count": TYPE_INT, "location": TYPE_INT}

## 切换房间/观察者只能由本地会话管理调用，不从收到的视图猜身份。
func reset(observer: int = -1) -> void:
	_observer = observer
	_view.clear()
	error = ""

func accept(view: Dictionary) -> bool:
	error = ""
	if not _keys(view, ROOT) or not _primitive(view) or not _types(view, ROOT_TYPES) or view.v != 1:
		return reject("视图格式无效")
	if int(view.seq) <= int(_view.get("seq", 0)):
		return reject("视图序号重复或回退")
	if view.observer != _observer:
		return reject("视图观察者不匹配")
	var player_ids: Array = []
	for player in view.players:
		if not player is Dictionary or not _keys(player, PLAYER) or not _types(player, PLAYER_TYPES):
			return reject("玩家视图含未知字段")
		if player.id < 0 or player_ids.has(player.id) or player.deck_count < 0 or player.hand_count < 0:
			return reject("玩家身份或牌数无效")
		player_ids.append(player.id)
		var own: bool = _observer >= 0 and (player.id == _observer or player.controller == _observer)
		if player.own != own:
			return reject("玩家控制关系不匹配")
		if player.has("servant_released") and not player.servant_released is bool:
			return reject("真名公开状态无效")
		for key in ["magic", "magic_limit", "score", "lives", "power", "order", "command_spell_count"]:
			if typeof(player.get(key)) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(player[key])):
				return reject("玩家数值无效")
		if player.has("total_power") and (typeof(player.total_power) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(player.total_power))):
			return reject("合计威力无效")
		if player.has("power_breakdown"):
			if not player.power_breakdown is Dictionary:
				return reject("威力明细无效")
			for key in ["power", "bonus", "board", "location_benefit", "preview", "total"]:
				if typeof(player.power_breakdown.get(key)) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(player.power_breakdown[key])):
					return reject("威力明细数值无效")
		for key in ["master", "servant"]:
			if not player.get(key) is Dictionary or not _keys(player[key], ["name", "image", "visible", "concealed", "zoom_kind", "description"]) or (not player[key].is_empty() and not _types(player[key], {"name": TYPE_STRING, "image": TYPE_STRING})):
				return reject("身份视图无效")
			if player[key].has("visible") or player[key].has("concealed") or player[key].has("zoom_kind") or player[key].has("description"):
				if not _types(player[key], {"visible": TYPE_BOOL, "concealed": TYPE_BOOL, "zoom_kind": TYPE_STRING, "description": TYPE_STRING}) or not player[key].visible or player[key].concealed:
					return reject("身份查看声明无效")
		for key in ["hand_cards", "discard", "played_cards", "master_skills", "servant_skills"]:
			if not _cards(player.get(key), own):
				return reject("牌区视图无效")
		if player.has("out_of_game_cards") and not _cards(player.out_of_game_cards, own):
			return reject("游戏外牌区视图无效")
		if player.has("buffs"):
			if not player.buffs is Array:
				return reject("Buff 视图无效")
			for buff in player.buffs:
				if not buff is Dictionary or not _keys(buff, ["card", "active"]):
					return reject("Buff 字段无效")
				if not buff.active is bool or not _identity(buff.card):
					return reject("Buff 内容无效")
		if not own and not player.get("servant_released", false):
			if not player.servant.is_empty() or not player.servant_skills.is_empty():
				return reject("视图泄露未公开从者")
		if player.has("held_cards"):
			if not _held_cards(player.held_cards) or (not own and not player.held_cards.is_empty()):
				return reject("持有展示视图无效或泄露")
			for entry in player.held_cards:
				var is_played: bool = player.played_cards.any(func(card): return card.get("id") == entry.card.id)
				if entry.played != is_played or (entry.played and entry.card.get("kind") != "skill"):
					return reject("持有展示出牌身份不匹配")
		if not own and not player.hand_cards.is_empty():
			return reject("视图泄露他人手牌")
		if player.has("command_spells"):
			if not _cards(player.command_spells, own) or (not own and not player.command_spells.is_empty()):
				return reject("令咒卡视图无效或泄露")
	var map_ids: Array = []
	for area in view.areas:
		if not area is Dictionary or not _keys(area, ["id", "name", "locations", "events"]) or not _types(area, {"id": TYPE_INT, "name": TYPE_STRING, "locations": TYPE_ARRAY}) or not _cards(area.get("events")):
			return reject("地图视图无效")
		if area.id <= 0 or map_ids.has(area.id):
			return reject("重复或无效战区 ID")
		map_ids.append(area.id)
		for location in area.locations:
			if not location is Dictionary or not _keys(location, ["id", "magic", "benefit", "capacity", "players"]) or not _types(location, {"id": TYPE_INT, "players": TYPE_ARRAY}):
				return reject("位置视图无效")
			if location.has("capacity") and not location.capacity is int:
				return reject("位置容量无效")
			if location.id <= 0 or map_ids.has(location.id):
				return reject("重复或无效位置 ID")
			map_ids.append(location.id)
			for key in ["magic", "benefit"]:
				if typeof(location.get(key)) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(location[key])):
					return reject("位置数值无效")
			for id in location.players:
				if not id is int or id < 0:
					return reject("位置占据者无效")
	if not _card(view.get("situation")):
		return reject("局势视图无效")
	if view.has("event_discard") and not _cards(view.event_discard):
		return reject("事件弃牌视图无效")
	if view.has("public_log"):
		if not view.public_log is Array:
			return reject("公共日志视图无效")
		for line in view.public_log:
			if not line is String:
				return reject("公共日志类型无效")
	_view = view.duplicate(true)
	return true

func read() -> Dictionary:
	return _view.duplicate(true)

func reject(reason: String) -> bool:
	error = reason
	return false

static func _keys(value: Dictionary, allowed: Array) -> bool:
	for key in value:
		if not allowed.has(key):
			return false
	return true

static func _held_cards(value) -> bool:
	if not value is Array:
		return false
	var seen: Array = []
	for entry in value:
		if not entry is Dictionary or not _keys(entry, ["card", "group", "label", "played", "unpublished"]) or not _types(entry, {"card": TYPE_DICTIONARY, "group": TYPE_STRING, "label": TYPE_STRING, "played": TYPE_BOOL, "unpublished": TYPE_BOOL}):
			return false
		if entry.group not in ["hand", "master", "servant"] or not _card(entry.card, true) or not entry.card.has_all(["id", "kind", "cost", "power", "back_image", "zoom_kind", "description"]) or not entry.card.get("visible", false):
			return false
		if seen.has(entry.card.id):
			return false
		seen.append(entry.card.id)
	return true

static func _cards(value, private_view: bool = false) -> bool:
	if not value is Array:
		return false
	for card in value:
		if not _card(card, private_view):
			return false
	return true

static func _identity(value) -> bool:
	if not value is Dictionary or not _keys(value, ["name", "image", "visible", "concealed", "zoom_kind", "description"]):
		return false
	return _types(value, {"name": TYPE_STRING, "image": TYPE_STRING, "visible": TYPE_BOOL, "concealed": TYPE_BOOL, "zoom_kind": TYPE_STRING, "description": TYPE_STRING}) and value.visible and not value.concealed

static func _card(value, private_view: bool = false) -> bool:
	if not value is Dictionary or not _keys(value, ["id", "concealed", "visible", "name", "image", "back_image", "kind", "cost", "power", "effects", "zoom_kind", "description"]):
		return false
	if value.is_empty():
		return true
	if not _types(value, {"id": TYPE_INT, "concealed": TYPE_BOOL, "visible": TYPE_BOOL}) or value.id <= 0:
		return false
	if value.has("back_image") and not value.back_image is String:
		return false
	if not private_view:
		if value.concealed and value.visible:
			return false
		if value.has("effects") and (not value.effects is Array or not value.effects.is_empty()):
			return false
	if not value.visible:
		if not private_view and value.get("back_image", "") != "":
			return false
		for field in ["name", "image", "kind", "cost", "power", "effects", "zoom_kind", "description"]:
			if value.has(field):
				return false
		return true
	if not _types(value, {"name": TYPE_STRING, "image": TYPE_STRING}):
		return false
	for field in ["zoom_kind", "description"]:
		if value.has(field) and not value[field] is String:
			return false
	if value.has("kind") and (not value.kind is String or value.kind not in ["card", "attack", "skill"]):
		return false
	for field in ["cost", "power"]:
		if value.has(field) and (typeof(value[field]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value[field]))):
			return false
	if value.has("effects"):
		if not value.effects is Array:
			return false
		for id in value.effects:
			if not id is int or id <= 0:
				return false
	return true

static func _types(value: Dictionary, required: Dictionary) -> bool:
	for key in required:
		if not value.has(key) or typeof(value[key]) != required[key]:
			return false
	return true

static func _primitive(value, depth: int = 0) -> bool:
	if depth > 32:
		return false
	if value is Array:
		for item in value:
			if not _primitive(item, depth + 1):
				return false
		return true
	if value is Dictionary:
		for key in value:
			if not key is String or not _primitive(value[key], depth + 1):
				return false
		return true
	return typeof(value) in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING]
