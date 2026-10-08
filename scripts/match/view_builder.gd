class_name MatchViewBuilder
extends RefCounted

const CardText := preload("res://scripts/game_scene/tactical_board_ui.gd")

## 传输视图只按白名单生成，绝不反射规则对象。-1 为公共观战。
const Ids = preload("res://scripts/match/net_ids.gd")
var ids = Ids.new()
var sequence: int = 0
var _held_origins: Dictionary = {}

func build(observer: int = -1) -> Dictionary:
	sequence += 1
	var players: Array = []
	for pid in EffectManager.get_player_order_ids():
		var data: Dictionary = GameData.player_data_library.get(pid, {})
		var own: bool = observer >= 0 and (pid == observer or int(data.get("controller", -1)) == observer)
		var released: bool = ReleaseTrueName.is_released(pid)
		var player := {"id": pid, "controller": int(data.get("controller", -1)), "player_name": str(data.get("player_name", "")), "own": own}
		for key in ["magic", "score", "lives", "power", "order", "command_spell_count"]:
			player[key] = number(data.get(key))
		player["magic_limit"] = number(GameData.player_magic_limit(pid))
		player["servant_released"] = released
		for key in ["is_out", "is_battle", "is_victory"]:
			player[key] = bool(data.get(key, false))
		var master = data.get("master")
		player["avatar"] = str(master.get("_header_img")) if master != null else ""
		var breakdown: Dictionary = GetPlayerTotalPower.breakdown(pid)
		# 只传显式数值分量，不传来源对象、效果名或预览的隐藏牌。
		player["power_breakdown"] = {}
		for key in ["power", "bonus", "board", "location_benefit", "preview", "total"]:
			player["power_breakdown"][key] = breakdown.get(key, 0)
		player["total_power"] = player["power_breakdown"]["total"]
		player["master"] = identity(master, "_master_card_img", own)
		var servant = data.get("servant")
		player["servant"] = identity(servant, "_servant_card_img", own) if own or released else {}
		player["servant_class"] = str(servant._servant_class) if servant != null and (own or GameDataManager.can_see_servant_class(observer, pid)) else ""
		player["deck_count"] = data.get("deck", []).size()
		player["hand_count"] = data.get("hand_cards", []).size()
		player["hand_cards"] = cards(data.get("hand_cards", []), true) if own else []
		player["command_spells"] = cards(data.get("out_of_game", {}).get("command_spell", []), true) if own else []
		player["discard"] = cards(data.get("discard", []), own)
		player["buffs"] = buff_views(data.get("buffs", []), own)
		# 与现有游戏外浏览契约一致：仅攻击、技能、其他，不混入令咒。
		var removed: Array = []
		for key in ["attacks", "skills", "others"]:
			for card in data.get("out_of_game", {}).get(key, []):
				if card is BaseCard and not removed.has(card):
					removed.append(card)
		player["out_of_game_cards"] = cards(removed, own)
		player["played_cards"] = cards(data.get("played_cards", []), own)
		player["held_cards"] = held_cards(data, pid) if own else []
		player["master_skills"] = cards(data.get("master_skills", []), own)
		player["servant_skills"] = cards(data.get("servant_skills", []), own) if own or released else []
		var loc = data.get("location")
		player["location"] = ids.id_for(loc) if loc != null else 0
		players.append(player)
	var areas: Array = []
	for area in MapData.areas:
		var locations: Array = []
		for loc in area._locations:
			locations.append({"id": ids.id_for(loc), "magic": number(loc._magic), "benefit": GetEffectiveLocationBenefit.current_benefit(loc), "capacity": loc._pl_num_limit, "players": loc._players.duplicate()})
		areas.append({"id": ids.id_for(area), "name": str(area._area_name), "locations": locations, "events": cards(area._events, false)})
	return {"v": 1, "seq": sequence, "observer": observer, "round": GameProgress.current_round, "phase": str(GameProgress.get_current_phase().get("name", "")), "current_player": GameProgress.current_player_id, "game_over": GameProgress.is_game_over, "players": players, "areas": areas, "situation": card_view(MapData.active_situation, false), "public_log": public_log(), "event_discard": cards(MapData.event_discard, false)}

## 持有展示来源由权威显式声明；不将升华技混入普通出牌卡位。
func held_cards(data: Dictionary, pid: int) -> Array:
	var result: Array = []
	var seen: Array = []
	var master = data.get("master")
	var upgrades: Array = master._upgrade_skill if master != null else []
	var played: Array = data.get("played_cards", [])
	var play_zone: Array = RegularPlay.play_zone_cards(data)
	var push := func(source: Array, group: String, label: String):
		for card in source:
			if not card is BaseHandCard or seen.has(card) or upgrades.has(card):
				continue
			if (data.get("deck", []).has(card) or data.get("discard", []).has(card)) and not play_zone.has(card):
				continue
			if played.has(card) and not card is BaseSkill:
				continue
			var view: Dictionary = card_view(card, true)
			if not view.get("visible", false):
				continue
			seen.append(card)
			if not _held_origins.has(view.id):
				_held_origins[view.id] = {"group": group, "label": label, "order": _held_origins.size()}
			var origin: Dictionary = _held_origins[view.id]
			result.append({"card": view, "group": origin.group if played.has(card) else group, "label": origin.label if played.has(card) else label, "played": played.has(card), "unpublished": bool(card._is_concealed) or (card is BaseSkill and not ReleaseTrueName.is_released(pid))})
	push.call(data.get("servant_skills", []), "servant", "从者技能")
	push.call(data.get("master_skills", []), "master", "御主牌")
	for card in data.get("side", {}).get("skills", []):
		var source = card.get_from() if card is BaseCard else null
		push.call([card], "servant" if source != null and source == data.get("servant") else "master", "从者技能" if source != null and source == data.get("servant") else ("御主牌" if source != null and source == master else "技能牌"))
	if master != null:
		for key in ["SKILLS", "ATTACKS"]:
			push.call(master._specials.get(key, []), "master", "御主牌")
	push.call(data.get("hand_cards", []), "hand", "手牌")
	push.call(play_zone, "hand", "手牌")
	# 出牌会从来源数组移除技能，但原规则对象与来源身份仍有效。
	for card in played:
		if card is BaseSkill:
			var source = card.get_from()
			push.call([card], "servant" if source != null and source == data.get("servant") else "master", "从者技能" if source != null and source == data.get("servant") else ("御主牌" if source != null and source == master else "技能牌"))
	result.sort_custom(func(a, b): return _held_origins[a.card.id].order < _held_origins[b.card.id].order)
	return result

## 只输出公开事实的格式化文本；效果/选项/来源参数不进入公共快照。
func public_log() -> Array:
	var result: Array = []
	var allowed := ["deploy", "move", "command_spell_used", "draw", "refill_hand", "reshuffle_discard", "magic_add", "magic_decrease", "score_add", "score_decrease", "eliminated", "true_name_release", "true_name_hidden", "game_end", "play", "regular_play", "battle"]
	for entry in GameLog.query({}, null, -1):
		if not entry is Dictionary or entry.get("type", "") not in allowed or entry.get("tags", []).has("secret_choice"):
			continue
		var public_entry := {"type": entry.type, "round": int(entry.get("round", 0)), "phase": public_phase(str(entry.get("phase", ""))), "actor": int(entry.get("actor", -1)), "place": public_place(str(entry.get("place", ""))), "tags": [], "object": null, "data": {}}
		var facts = entry.get("data", {})
		if facts is Dictionary:
			if entry.get("tags", []).has("magic_spend"):
				public_entry.tags.append("magic_spend")
			if facts.get("purpose") in ["regular_play", "effect_attack", "effect_skill", "move", "effect_cost"]:
				public_entry.data["purpose"] = facts.purpose
			for field in ["delta", "count"]:
				if typeof(facts.get(field)) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(facts[field])):
					public_entry.data[field] = facts[field]
			if entry.type == "game_end" and facts.get("winners") is Array:
				public_entry.data["winners"] = []
				for winner in facts.winners:
					if winner is int and GameData.player_data_library.has(winner): public_entry.data.winners.append(winner)
		if entry.get("type") == "play":
			public_entry["object"] = null
			public_entry["data"] = {"concealed": bool(entry.get("data", {}).get("concealed", false))}
		var line: String = CardText._format_game_log_line(public_entry)
		if not line.is_empty():
			result.append(line)
	return result

## 日志元数据仅接受当前规则声明的阶段、地图区域；不向 formatter 传诊断自由文本。
static func public_phase(value: String) -> String:
	for phase in GameProgress.phases:
		if str(phase.get("name", "")) == value:
			return value
	return ""

static func public_place(value: String) -> String:
	for area in MapData.areas:
		if str(area._area_name) == value:
			return value
	return ""

## BUFF 只展示获准公开的来源；未解放从者的状态不暴露名称或图片。
func buff_views(source: Array, own: bool) -> Array:
	var result: Array = []
	for buff in source:
		if not buff is BaseBuff or (not own and not publicly_identifiable(buff)):
			continue
		result.append({"card": identity(buff, "_buff_img", own), "active": bool(buff._is_active)})
	return result

func cards(source: Array, own: bool) -> Array:
	var result: Array = []
	for card in source:
		if card is BaseCard:
			result.append(card_view(card, own))
	return result

func card_view(card, own: bool) -> Dictionary:
	if card == null:
		return {}
	var concealed: bool = card._is_concealed
	var visible: bool = own or (not concealed and publicly_identifiable(card))
	if card is BaseSkill and not card._is_awakened:
		visible = false
	# 隐藏牌不携带专属卡背路径（其中可能包含从者名/职阶/来源目录）。
	var result := {"id": ids.id_for(card), "concealed": concealed, "visible": visible, "back_image": str(card._card_back_img) if visible or own else ""}
	if visible:
		result["name"] = card.get_shown_name()
		result["zoom_kind"] = card.get_zoom_kind()
		result["description"] = CardText._build_card_desc(card) if own else public_description(card)
		result["image"] = str(card._card_img)
		result["kind"] = "skill" if card is BaseSkill else ("attack" if card is BaseAttack else "card")
		result["cost"] = number(card.get("_cost"))
		result["power"] = number(card.get("_power"))
		result["effects"] = []
		var holders: Array = [card]
		var related = card.get("_relate_buff")
		if related != null:
			holders.append(related)
		for holder in holders:
			for effect in holder._effects:
				if own and effect is BaseEffect:
					result.effects.append(ids.id_for(effect))
	return result

func identity(object, image_field: String, own: bool = false) -> Dictionary:
	if object == null:
		return {}
	return {"name": object.get_shown_name(), "image": str(object.get(image_field)), "visible": true, "concealed": false, "zoom_kind": object.get_zoom_kind(image_field), "description": CardText._build_card_desc(object) if own else public_description(object)}

## 按原规则对象来源判定，不依赖当前位置；转到出牌/弃牌区不能公开真名。
func publicly_identifiable(card) -> bool:
	var source = card
	var seen: Array = []
	var master_source: bool = false
	while source is BaseObject and not seen.has(source):
		seen.append(source)
		for pid in GameData.player_data_library:
			var data: Dictionary = GameData.player_data_library[pid]
			if source == data.get("servant") or (card is BaseSkill and data.get("servant_skills", []).has(card)):
				return ReleaseTrueName.is_released(pid)
			if source == data.get("master") or (card is BaseSkill and data.get("master_skills", []).has(card)):
				master_source = true
		source = source.get_from()
	# 未登记的从者来源不能按“查不到”视为公开。
	for object in seen:
		if object is BaseServant:
			return false
	return not card is BaseSkill or master_source

## 公共说明只读取声明的卡面字段，绝不回退到内部效果名/诊断数据。
static func public_description(object) -> String:
	var lines: Array[String] = []
	for field in ["_cost", "_power"]:
		var value = object.get(field)
		if value is BaseNumber:
			lines.append("%s：%s" % ["费用" if field == "_cost" else "威力", BaseNumber.display_text(value.number)])
	var attributes = object.get("_attributes")
	if attributes is Array:
		var labels: Array[String] = []
		for attribute in attributes:
			# 自定义属性只要显式登记展示名仍可公开，未知内部键不回退。
			if attribute is String and Attributes.is_known_attribute(attribute):
				labels.append(Attributes.get_shown_attribute(attribute))
		if not labels.is_empty():
			lines.append("属性：" + "、".join(labels))
	var category = object.get("_category")
	if category is String and CardText.ATTACK_CATEGORY_LABELS.has(category):
		lines.append("类别：" + str(CardText.ATTACK_CATEGORY_LABELS[category]))
	var notes = object.get("_shown_notes")
	if notes is Array:
		for note in notes:
			if note is String and not note.is_empty(): lines.append(note)
	var requirements = object.get("_play_requirements")
	if requirements is Array:
		for requirement in requirements:
			if requirement is Dictionary and requirement.get("shown_note") is String and not requirement.shown_note.is_empty(): lines.append(requirement.shown_note)
	var effects = object.get("_effects")
	if effects is Array:
		for effect in effects:
			if not effect is BaseEffect: continue
			if not effect._shown_name.is_empty(): lines.append(effect._shown_name)
			for option in effect._options:
				if option is Dictionary and option.get("shown_option_name") is String and not option.shown_option_name.is_empty(): lines.append(option.shown_option_name)
	return "\n".join(lines)

static func number(value) -> float:
	return float(value.number) if value is BaseNumber else 0.0
