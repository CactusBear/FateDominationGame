class_name DebugValidate
extends RefCounted

## 写命令后的只读一致性检查。只报告问题，绝不自动修正。

const ROOT_ZONE_KEYS:Array = [
	"deck", "hand_cards", "played_cards", "discard", "master_skills",
	"servant_skills", "buffs", "command_spell"
]
const NESTED_ZONE_KEYS:Array = [
	"side.deck", "side.discard", "side.hand_cards", "side.skills", "side.buffs",
	"side.others", "side.command_spell", "out_of_game.attacks", "out_of_game.skills",
	"out_of_game.buffs", "out_of_game.others", "out_of_game.command_spell"
]


static func validate_all(template_baseline:Dictionary = {}) -> Dictionary:
	var issues:Array = []
	_validate_unique_card_ownership(issues)
	_validate_locations(issues)
	_validate_effect_ownership(issues)
	_validate_templates_not_in_zones(issues)
	_validate_power_breakdowns(issues)
	_validate_command_spells(issues)
	_validate_template_integrity(issues, template_baseline)
	return {"ok":issues.is_empty(), "checks":7, "issues":issues}


static func template_fingerprints() -> Dictionary:
	var result:Dictionary = {}
	for object in _template_objects():
		if object != null:
			result[object.get_instance_id()] = _template_fingerprint(object)
	return result


static func player_zones(player_id:int) -> Dictionary:
	if !GameData.player_data_library.has(player_id):
		return {}
	var data:Dictionary = GameData.player_data_library[player_id]
	var result:Dictionary = {}
	for key in ROOT_ZONE_KEYS:
		var value = data.get(key)
		if value is Array:
			result[key] = value
	for path in NESTED_ZONE_KEYS:
		var parts:Array = path.split(".")
		var parent = data.get(parts[0])
		if parent is Dictionary:
			var value = parent.get(parts[1])
			if value is Array:
				result[path] = value
	return result


static func _validate_unique_card_ownership(issues:Array) -> void:
	var owners:Dictionary = {}
	for raw_id in GameData.player_data_library.keys():
		var player_id:int = int(raw_id)
		for path in player_zones(player_id):
			for object in player_zones(player_id)[path]:
				if !(object is BaseCard):
					continue
				var instance_id:int = object.get_instance_id()
				var labels:Array = owners.get(instance_id, [])
				labels.append("%s:%s" % [player_id, path])
				owners[instance_id] = labels
	for instance_id in owners:
		if owners[instance_id].size() > 1:
			issues.append({"check":"card_unique_zone", "object_id":instance_id, "owners":owners[instance_id]})


static func _validate_locations(issues:Array) -> void:
	var map_members:Dictionary = {}
	for area in MapData.areas:
		if !(area is BaseMapArea):
			continue
		for location in area._locations:
			if !(location is BaseLocation):
				continue
			for raw_id in location._players:
				var player_id:int = int(raw_id)
				if map_members.has(player_id) and map_members[player_id] != location:
					issues.append({"check":"location_duplicate_seat", "player_id":player_id})
				map_members[player_id] = location
				if !GameData.player_data_library.has(player_id) or GameData.player_data_library[player_id].get("location") != location:
					issues.append({"check":"location_reverse", "player_id":player_id, "location_id":location.get_instance_id()})
	for raw_id in GameData.player_data_library.keys():
		var player_id:int = int(raw_id)
		var data:Dictionary = GameData.player_data_library[player_id]
		var location = data.get("location")
		if bool(data.get("is_out", false)) and (location != null or map_members.has(player_id)):
			issues.append({"check":"out_player_on_board", "player_id":player_id})
		elif location != null and (!map_members.has(player_id) or map_members[player_id] != location):
			issues.append({"check":"location_forward", "player_id":player_id, "location_id":location.get_instance_id()})


static func _validate_effect_ownership(issues:Array) -> void:
	for raw_id in GameData.player_data_library.keys():
		var player_id:int = int(raw_id)
		var data:Dictionary = GameData.player_data_library[player_id]
		var actual:Array = data.get("self_effects", [])
		var expected_objects:Array = [data.get("master"), data.get("servant")]
		expected_objects.append_array(data.get("buffs", []))
		expected_objects.append_array(data.get("played_cards", []))
		expected_objects.append_array(data.get("servant_skills", []))
		expected_objects.append_array(data.get("master_skills", []))
		var side:Dictionary = data.get("side", {})
		expected_objects.append_array(side.get("skills", []))
		var out:Dictionary = data.get("out_of_game", {})
		expected_objects.append_array(out.get("command_spell", []))
		for object in expected_objects:
			if object == null or !("_effects" in object):
				continue
			for effect in object._effects:
				if effect is BaseEffect and effect._trigger_player_id == player_id and !actual.has(effect):
					issues.append({"check":"missing_self_effect", "player_id":player_id, "object_id":object.get_instance_id(), "effect":effect._name})
		for effect in actual:
			if effect is BaseEffect and effect._trigger_player_id != player_id:
				issues.append({"check":"effect_wrong_owner", "player_id":player_id, "effect":effect._name, "trigger":effect._trigger_player_id})


static func _validate_templates_not_in_zones(issues:Array) -> void:
	var templates:Array = _template_objects()
	for raw_id in GameData.player_data_library.keys():
		var player_id:int = int(raw_id)
		for path in player_zones(player_id):
			for object in player_zones(player_id)[path]:
				if templates.has(object):
					issues.append({"check":"template_in_player_zone", "player_id":player_id, "zone":path, "object_id":object.get_instance_id()})


static func _validate_power_breakdowns(issues:Array) -> void:
	for raw_id in GameData.player_data_library.keys():
		var player_id:int = int(raw_id)
		var b:Dictionary = GetPlayerTotalPower.breakdown(player_id)
		var summed:float = float(b.get("power", 0)) + float(b.get("bonus", 0)) + float(b.get("board", 0)) + float(b.get("location_benefit", 0))
		if !is_equal_approx(summed, float(b.get("total", 0))):
			issues.append({"check":"power_breakdown", "player_id":player_id, "sum":summed, "total":b.get("total")})


static func _validate_command_spells(issues:Array) -> void:
	for raw_id in GameData.player_data_library.keys():
		var player_id:int = int(raw_id)
		var data:Dictionary = GameData.player_data_library[player_id]
		var cards:Array = data.get("out_of_game", {}).get("command_spell", [])
		if cards.size() > 1:
			issues.append({"check":"command_spell_clone_count", "player_id":player_id, "count":cards.size()})
		for card in cards:
			if !(card is BaseCard):
				issues.append({"check":"command_spell_type", "player_id":player_id})
				continue
			if LoadCommandSpell.command_spells.values().has(card) if LoadCommandSpell.command_spells is Dictionary else LoadCommandSpell.command_spells.has(card):
				issues.append({"check":"command_spell_is_template", "player_id":player_id, "object_id":card.get_instance_id()})


static func _validate_template_integrity(issues:Array, baseline:Dictionary) -> void:
	if baseline.is_empty():
		return
	var current:Dictionary = template_fingerprints()
	for instance_id in baseline:
		if !current.has(instance_id):
			issues.append({"check":"template_missing", "object_id":instance_id})
		elif current[instance_id] != baseline[instance_id]:
			issues.append({"check":"template_modified", "object_id":instance_id})


static func _template_objects() -> Array:
	var templates:Array = []
	templates.append_array(GameData.loaded_masters)
	templates.append_array(GameData.loaded_servants)
	templates.append_array(LoadEvent.events)
	templates.append_array(LoadSituation.situations)
	templates.append_array(LoadSituation.climax_situations.values())
	templates.append_array(LoadCommandSpell.command_spells.values() if LoadCommandSpell.command_spells is Dictionary else LoadCommandSpell.command_spells)
	return templates


static func _template_fingerprint(object) -> String:
	var data:Dictionary = {
		"class":object.get_class(),
		"name":str(object.get("_name")),
		"shown_name":str(object.get_shown_name()) if object.has_method("get_shown_name") else "",
		"effects":_instance_ids(object.get("_effects")) if "_effects" in object else [],
	}
	for key in ["_attributes", "_keywords", "_shown_notes"]:
		if key in object:
			data[key] = (object.get(key) as Array).duplicate(true)
	for key in ["_cost", "_power", "_magic", "_score"]:
		if key in object:
			var value = object.get(key)
			data[key] = value.number if value is BaseNumber else value
	if "_specials" in object:
		var specials:Dictionary = {}
		for key in object._specials:
			var value = object._specials[key]
			specials[str(key)] = _instance_ids(value) if value is Array else str(value)
		data["specials"] = specials
	return JSON.stringify(data)


static func _instance_ids(values) -> Array:
	var result:Array = []
	if !(values is Array):
		return result
	for value in values:
		result.append(value.get_instance_id() if value is Object else value)
	return result
