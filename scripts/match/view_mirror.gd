class_name MatchViewMirror
extends RefCounted

## 镜像只存基础类型副本；调用者必须只接收主机来源消息。
var error: String = ""
var _view: Dictionary = {}
var _observer: int = -1
const ROOT := ["v", "seq", "observer", "round", "phase", "current_player", "game_over", "players", "areas", "situation", "public_log", "event_discard", "event_discard_by_source", "situation_discard", "battle_result", "state", "notifications", "battle_broadcast"]
const PLAYER := ["id", "controller", "player_name", "avatar", "own", "magic", "magic_limit", "score", "lives", "power", "power_breakdown", "total_power", "order", "command_spell_count", "command_spells", "special_command_spells", "is_out", "is_battle", "is_victory", "master", "servant", "servant_present", "servant_class", "servant_released", "deck_count", "hand_count", "hand_cards", "discard", "buffs", "out_of_game_cards", "zone_hand_entries", "played_cards", "residue_cards", "master_skills", "servant_skills", "held_cards", "location"]
const ROOT_TYPES := {"v": TYPE_INT, "seq": TYPE_INT, "observer": TYPE_INT, "round": TYPE_INT, "phase": TYPE_STRING, "current_player": TYPE_INT, "game_over": TYPE_BOOL, "players": TYPE_ARRAY, "areas": TYPE_ARRAY, "situation": TYPE_DICTIONARY}
const PLAYER_TYPES := {"id": TYPE_INT, "controller": TYPE_INT, "player_name": TYPE_STRING, "avatar": TYPE_STRING, "own": TYPE_BOOL, "is_out": TYPE_BOOL, "is_battle": TYPE_BOOL, "is_victory": TYPE_BOOL, "servant_class": TYPE_STRING, "deck_count": TYPE_INT, "hand_count": TYPE_INT, "location": TYPE_INT}

## 切换房间/观察者只能由本地会话管理调用，不从收到的视图猜身份。
func reset(observer: int = -1) -> void:
	_observer = observer
	_view.clear()
	error = ""


func accepts_pending(prompt: Dictionary) -> bool:
	if prompt.is_empty(): return true
	if _observer < 0 or not _primitive(prompt) or not _types(prompt,{"kind":TYPE_STRING,"effect":TYPE_INT,"label":TYPE_STRING,"allow_cancel":TYPE_BOOL}) or prompt.effect <= 0: return false
	var common: Array = ["kind","effect","label","allow_cancel"]
	match prompt.kind:
		"active_choice":
			if not _keys(prompt,common+["options","multi","cost_text"]) or not _types(prompt,{"options":TYPE_ARRAY,"multi":TYPE_BOOL,"cost_text":TYPE_STRING}): return false
			for i in prompt.options.size():
				var option = prompt.options[i]
				if not option is Dictionary or not _keys(option,["index","label","available","quantity_range","max_uses"]) or not _types(option,{"index":TYPE_INT,"label":TYPE_STRING,"available":TYPE_BOOL,"max_uses":TYPE_INT}) or option.index != i: return false
				if option.has("quantity_range") and (not option.quantity_range is Array or option.quantity_range.size()!=2 or not option.quantity_range[0] is int or not option.quantity_range[1] is int or option.quantity_range[0]>option.quantity_range[1]): return false
		"card_choice", "player_choice":
			var key: String = "cards" if prompt.kind == "card_choice" else "players"
			var fields: Array = common+[key,"min","max"]
			if key == "cards": fields += ["required","card_views","verb","secret","confirm_text"]
			if not _keys(prompt,fields) or not _types(prompt,{key:TYPE_ARRAY,"min":TYPE_INT,"max":TYPE_INT}) or prompt.min < 0 or prompt.max < -1: return false
			if not _choice_ids(prompt[key]): return false
			if key == "cards":
				if not _types(prompt,{"required":TYPE_ARRAY,"card_views":TYPE_ARRAY,"verb":TYPE_STRING,"secret":TYPE_BOOL,"confirm_text":TYPE_STRING}) or not _choice_ids(prompt.required) or not _cards(prompt.card_views,true): return false
				var ids: Array = []
				for card in prompt.card_views: ids.append(card.id)
				if ids != prompt.cards: return false
				for id in prompt.required:
					if not prompt.cards.has(id): return false
		"location_choice":
			if not _keys(prompt,common+["areas"]) or not _types(prompt,{"areas":TYPE_ARRAY}) or not _choice_ids(prompt.areas): return false
		_: return false
	return true

static func _choice_ids(ids: Array) -> bool:
	var seen: Array = []
	for id in ids:
		if not id is int or id < 0 or seen.has(id): return false
		seen.append(id)
	return true

func accept(view: Dictionary) -> bool:
	error = ""
	if not _keys(view, ROOT) or not _primitive(view) or not _types(view, ROOT_TYPES) or view.v != 1:
		return reject("视图格式无效")
	if int(view.seq) <= int(_view.get("seq", 0)):
		return reject("视图序号重复或回退")
	if view.observer != _observer:
		return reject("视图观察者不匹配")
	if not _timeline_state(view.get("state"), view.phase):
		return reject("阶段时间轴声明无效")
	if view.has("notifications"):
		if not view.notifications is Array: return reject("提示视图无效")
		var notice_ids: Array = []
		for notice in view.notifications:
			if not notice is Dictionary or not _keys(notice,["id","recipient","text"]) or not _types(notice,{"id":TYPE_STRING,"recipient":TYPE_INT,"text":TYPE_STRING}): return reject("提示字段无效")
			if notice.id.is_empty() or notice_ids.has(notice.id) or (notice.recipient != -1 and notice.recipient != _observer): return reject("提示重复或泄露")
			notice_ids.append(notice.id)
	var player_ids: Array = []
	for player in view.players:
		if not player is Dictionary or not _keys(player, PLAYER) or not _types(player, PLAYER_TYPES):
			return reject("玩家视图含未知字段")
		if player.id < 0 or player_ids.has(player.id) or player.deck_count < 0 or player.hand_count < 0:
			return reject("玩家身份或牌数无效")
		player_ids.append(player.id)
		var own: bool = _observer >= 0 and (player.id == _observer or player.controller == _observer)
		# controller 可授权旧牌面，但历史仅限本地绑定的当前所属席位。
		var history_private: bool = own and player.id == _observer
		if player.own != own:
			return reject("玩家控制关系不匹配")
		if player.has("servant_present") and not player.servant_present is bool:
			return reject("从者存在声明无效")
		if player.has("servant_released") and not player.servant_released is bool:
			return reject("真名公开状态无效")
		if not player.get("servant") is Dictionary:
			return reject("从者视图无效")
		if player.get("servant_present", false) and not _servant_view(player.servant, player.get("servant_released", false), own):
			return reject("从者占位视图无效")
		if not _cards(player.get("special_command_spells", [])):
			return reject("特殊令咒视图无效")
		if not _zone_entries(player.get("zone_hand_entries", []), own, history_private):
			return reject("技能附带物视图无效")
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
			if key == "servant" and not own and not player.get("servant_released", false) and not player.servant.is_empty():
				if not _servant_view(player.servant, false, false): return reject("从者占位视图无效")
				continue
			if not player.get(key) is Dictionary or not _keys(player[key], ["name", "image", "visible", "concealed", "zoom_kind", "description"]) or (not player[key].is_empty() and not _types(player[key], {"name": TYPE_STRING, "image": TYPE_STRING})):
				return reject("身份视图无效")
			if player[key].has("visible") or player[key].has("concealed") or player[key].has("zoom_kind") or player[key].has("description"):
				if not _identity(player[key]):
					return reject("身份查看声明无效")
		for key in ["hand_cards", "discard", "played_cards", "master_skills", "servant_skills"]:
			if not _cards(player.get(key), own, history_private):
				return reject("牌区视图无效")
		if not _cards(player.get("residue_cards"), own, history_private):
			return reject("残留牌区视图无效")
		var residue_ids: Array = []
		for card in player.residue_cards:
			if not card.visible or card.concealed or residue_ids.has(card.id) or not player.played_cards.has(card):
				return reject("残留牌公开状态或出牌身份无效")
			residue_ids.append(card.id)
		if player.has("out_of_game_cards") and not _cards(player.out_of_game_cards, own, history_private):
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
			if (not player.servant.is_empty() and not (player.servant.has("present") and not player.servant.visible)) or not player.servant_skills.is_empty():
				return reject("视图泄露未公开从者")
		if player.has("held_cards"):
			if not _held_cards(player.held_cards, history_private) or (not own and not player.held_cards.is_empty()):
				return reject("持有展示视图无效或泄露")
			for entry in player.held_cards:
				var is_played: bool = player.played_cards.any(func(card): return card.get("id") == entry.card.id)
				if entry.played != is_played or (entry.played and entry.card.get("kind") != "skill"):
					return reject("持有展示出牌身份不匹配")
		if not own and not player.hand_cards.is_empty():
			return reject("视图泄露他人手牌")
		if player.has("command_spells"):
			if not _cards(player.command_spells, own, history_private) or (not own and not player.command_spells.is_empty()):
				return reject("令咒卡视图无效或泄露")
	if not _broadcast(view.get("battle_broadcast"), player_ids):
		return reject("播报确认投影无效")
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
	if view.has("event_discard_by_source") and (not view.event_discard_by_source is Dictionary or not _source_discard(view.event_discard_by_source)):
		return reject("事件弃牌来源无效")
	if view.has("battle_result") and (not view.battle_result is Dictionary or not _battle_result(view.battle_result)):
		return reject("战斗结算摘要无效")
	if view.has("event_discard") and not _cards(view.event_discard):
		return reject("事件弃牌视图无效")
	if view.has("situation_discard") and not _cards(view.situation_discard):
		return reject("局势弃牌视图无效")
	if view.has("public_log"):
		if not view.public_log is Array:
			return reject("公共日志视图无效")
		for line in view.public_log:
			if not line is String:
				return reject("公共日志类型无效")
	if not _card_references_consistent(view):
		return reject("同一牌身份的投影声明冲突")
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

static func _broadcast(value, player_ids: Array) -> bool:
	if not value is Dictionary or not _keys(value, ["pending", "batch_id", "confirmers", "confirmed"]) or not _types(value, {"pending": TYPE_BOOL, "batch_id": TYPE_INT, "confirmers": TYPE_ARRAY, "confirmed": TYPE_ARRAY}):
		return false
	if (value.pending and value.batch_id <= 0) or (not value.pending and (value.batch_id != 0 or not value.confirmed.is_empty())):
		return false
	if not _choice_ids(value.confirmers) or not _choice_ids(value.confirmed): return false
	for seat in value.confirmers:
		if not player_ids.has(seat): return false
	for seat in value.confirmed:
		if not value.confirmers.has(seat): return false
	return true

static func _timeline_state(value, phase: String) -> bool:
	if not value is Dictionary or not _keys(value, ["phases", "total_rounds", "climax_rounds"]) or not value.has_all(["phases", "total_rounds", "climax_rounds"]):
		return false
	if not value.phases is Array or not value.total_rounds is int or value.total_rounds < 0 or not value.climax_rounds is Array:
		return false
	var seen: Array = []
	for name in value.phases:
		if not name is String or name.is_empty() or seen.has(name):
			return false
		seen.append(name)
	if not phase.is_empty() and not seen.has(phase):
		return false
	seen.clear()
	for night in value.climax_rounds:
		if not night is int or night < 1 or seen.has(night):
			return false
		seen.append(night)
	return true

static func _servant_view(value: Dictionary, released: bool, own: bool) -> bool:
	if own or released:
		return _identity(value)
	return _keys(value, ["present", "visible", "concealed", "placeholder_kind"]) and _types(value, {"present":TYPE_BOOL, "visible":TYPE_BOOL, "concealed":TYPE_BOOL, "placeholder_kind":TYPE_STRING}) and value.present and not value.visible and value.concealed and value.placeholder_kind == "servant"

static func _source_discard(value: Dictionary) -> bool:
	if not _keys(value, ["shinto", "miyama", "other"]): return false
	for key in ["shinto", "miyama", "other"]:
		if not value.has(key) or not _cards(value[key]):
			return false
	return true

static func _battle_result(value: Dictionary) -> bool:
	for area in value:
		var detail = value[area]
		if not detail is Dictionary or not _keys(detail, ["winners", "needs_win", "highest_power"]) or not _types(detail, {"winners":TYPE_ARRAY, "needs_win":TYPE_BOOL}) or not detail.has("highest_power"):
			return false
		if not detail.needs_win is bool or typeof(detail.highest_power) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(detail.highest_power)):
			return false
		for winner in detail.winners:
			if not winner is int or winner < 0:
				return false
	return true

static func _zone_entries(value, private_view: bool, history_private: bool = false) -> bool:
	if not value is Array:
		return false
	var seen: Dictionary = {}
	for entry in value:
		if not entry is Dictionary or not _keys(entry, ["card", "group", "label"]) or not _types(entry, {"card":TYPE_DICTIONARY, "group":TYPE_STRING, "label":TYPE_STRING}):
			return false
		if entry.group not in ["servant", "master", "other", "upgrade"] or not _card(entry.card, private_view, history_private) or entry.card.is_empty():
			return false
		if seen.has(entry.card.id): return false
		seen[entry.card.id] = true
	return true

static func _held_cards(value, history_private: bool = false) -> bool:
	if not value is Array:
		return false
	var seen: Array = []
	for entry in value:
		if not entry is Dictionary or not _keys(entry, ["card", "group", "label", "played", "unpublished"]) or not _types(entry, {"card": TYPE_DICTIONARY, "group": TYPE_STRING, "label": TYPE_STRING, "played": TYPE_BOOL, "unpublished": TYPE_BOOL}):
			return false
		if entry.group not in ["hand", "master", "servant"] or not _card(entry.card, true, history_private) or not entry.card.has_all(["id", "kind", "cost", "power", "back_image", "description"]) or not entry.card.get("visible", false):
			return false
		if seen.has(entry.card.id):
			return false
		seen.append(entry.card.id)
	return true

static func _cards(value, private_view: bool = false, history_private: bool = false) -> bool:
	if not value is Array:
		return false
	var seen: Dictionary = {}
	for card in value:
		if not _card(card, private_view, history_private) or card.is_empty():
			return false
		if seen.has(card.id): return false
		seen[card.id] = true
	return true

## ID 指向对象，不指向展示位；同一容器不可重复，跨容器引用可以重复。
## 比较共同已声明的身份/卡面事实；私有效果、说明与卡背经过隐私投影，不可要求相等。
## 本函数只在全部容器通过类型/隐私校验后执行，不读取或反查客户端规则对象。
static func _card_references_consistent(view: Dictionary) -> bool:
	var cards: Array = []
	for player in view.players:
		for key in ["hand_cards", "discard", "played_cards", "residue_cards", "master_skills", "servant_skills", "out_of_game_cards", "command_spells", "special_command_spells"]:
			cards.append_array(player.get(key, []))
		for key in ["zone_hand_entries", "held_cards"]:
			for entry in player.get(key, []): cards.append(entry.card)
	for area in view.areas: cards.append_array(area.events)
	if not view.situation.is_empty(): cards.append(view.situation)
	for key in ["event_discard", "situation_discard"]: cards.append_array(view.get(key, []))
	for entries in view.get("event_discard_by_source", {}).values(): cards.append_array(entries)
	var seen: Dictionary = {}
	for card in cards:
		if not seen.has(card.id): seen[card.id] = {}
		var facts: Dictionary = seen[card.id]
		# 可见性可因 own/public 不同；暗置状态来自同一规则对象，不随容器改变。
		for key in ["concealed", "name", "image", "kind", "cost", "power", "zoom_kind"]:
			if not card.has(key): continue
			if facts.has(key) and facts[key] != card[key]: return false
			facts[key] = card[key]
	return true

static func _identity(value) -> bool:
	if not value is Dictionary or not _keys(value, ["name", "image", "visible", "concealed", "zoom_kind", "description"]):
		return false
	return _types(value, {"name": TYPE_STRING, "image": TYPE_STRING, "visible": TYPE_BOOL, "concealed": TYPE_BOOL, "description": TYPE_STRING}) and (not value.has("zoom_kind") or value.zoom_kind is String) and value.visible and not value.concealed

static func _card(value, private_view: bool = false, history_private: bool = false) -> bool:
	if not value is Dictionary or not _keys(value, ["id", "concealed", "visible", "name", "image", "back_image", "kind", "cost", "power", "effects", "zoom_kind", "description", "modification_history"]):
		return false
	if value.is_empty():
		return true
	if not _types(value, {"id": TYPE_INT, "concealed": TYPE_BOOL, "visible": TYPE_BOOL}) or value.id <= 0:
		return false
	if value.has("back_image") and not value.back_image is String:
		return false
	# 缺字段兼容旧快照；任何越权字段（包括空数组）拒绝整份投影。
	# 候选提示是混合牌源，private_view=true 不代表每张牌属于观察者。
	if value.has("modification_history"):
		if not private_view or not history_private or not value.visible or value.concealed:
			return false
		if not value.modification_history is Array:
			return false
		for record in value.modification_history:
			if not record is Dictionary or not _keys(record, ["type", "detail"]) or not _types(record, {"type": TYPE_STRING, "detail": TYPE_STRING}):
				return false
	if not private_view:
		if value.concealed and value.visible:
			return false
		if value.has("effects") and (not value.effects is Array or not value.effects.is_empty()):
			return false
	if not value.visible:
		# 所有隐藏牌允许自身声明的卡背字符串；协议不按图片地址推断身份。
		# back_image 的 String 类型已在上方校验，未授权正面字段仍全部拒绝。
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
