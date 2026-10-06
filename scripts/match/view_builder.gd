class_name MatchViewBuilder
extends RefCounted

const CardText := preload("res://scripts/game_scene/tactical_board_ui.gd")

## 传输视图只按白名单生成，绝不反射规则对象。-1 为公共观战。
const Ids = preload("res://scripts/match/net_ids.gd")
var ids = Ids.new()
var sequence: int = 0

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
		player["total_power"] = int(GetPlayerTotalPower.breakdown(pid).get("total", 0))
		player["master"] = identity(master, "_master_card_img")
		var servant = data.get("servant")
		player["servant"] = identity(servant, "_servant_card_img") if own or released else {}
		player["servant_class"] = str(servant._servant_class) if servant != null and (own or GameDataManager.can_see_servant_class(observer, pid)) else ""
		player["deck_count"] = data.get("deck", []).size()
		player["hand_count"] = data.get("hand_cards", []).size()
		player["hand_cards"] = cards(data.get("hand_cards", []), true) if own else []
		player["command_spells"] = cards(data.get("out_of_game", {}).get("command_spell", []), true) if own else []
		player["discard"] = cards(data.get("discard", []), own)
		player["played_cards"] = cards(data.get("played_cards", []), own)
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
	return {"v": 1, "seq": sequence, "observer": observer, "round": GameProgress.current_round, "phase": str(GameProgress.get_current_phase().get("name", "")), "current_player": GameProgress.current_player_id, "game_over": GameProgress.is_game_over, "players": players, "areas": areas, "situation": card_view(MapData.active_situation, false)}

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
	var visible: bool = own or not concealed
	if card is BaseSkill and not card._is_awakened:
		visible = false
	var result := {"id": ids.id_for(card), "concealed": concealed, "visible": visible, "back_image": str(card._card_back_img)}
	if visible:
		result["name"] = card.get_shown_name()
		result["zoom_kind"] = card.get_zoom_kind()
		result["description"] = CardText._build_card_desc(card)
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
				if effect is BaseEffect:
					result.effects.append(ids.id_for(effect))
	return result

func identity(object, image_field: String) -> Dictionary:
	if object == null:
		return {}
	return {"name": object.get_shown_name(), "image": str(object.get(image_field)), "visible": true, "concealed": false, "zoom_kind": object.get_zoom_kind(image_field), "description": CardText._build_card_desc(object)}

static func number(value) -> float:
	return float(value.number) if value is BaseNumber else 0.0
