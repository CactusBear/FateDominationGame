class_name DebugMapAdapter
extends RefCounted

var cards:DebugCardAdapter
var host


func _init(card_adapter:DebugCardAdapter = null, p_host = null):
	cards = card_adapter if card_adapter != null else DebugCardAdapter.new()
	host = p_host


func inspect_board() -> Dictionary:
	var areas:Array = []
	for area in MapData.areas:
		var locations:Array = []
		for location in area._locations:
			locations.append({
				"id":location.get_instance_id(),
				"players":location._players.duplicate(),
				"benefit":GetEffectiveLocationBenefit.current_benefit(location),
				"limit":location._pl_num_limit
			})
		var events:Array = []
		for event in area._events:
			events.append(_object_summary(event))
		areas.append({"name":area._area_name, "id":area.get_instance_id(), "locations":locations, "events":events})
	return {"ok":true, "changed":false, "value":{
		"areas":areas,
		"active_situation":_object_summary(MapData.active_situation),
		"event_discard":_summaries(MapData.event_discard),
		"situation_discard":_summaries(MapData.situation_discard)
	}}


func deploy(player_id:int, area_name:String) -> Dictionary:
	var readiness := _rule_action_ready(player_id, "outpost")
	if !readiness.ok:
		return readiness
	var area = find_area(area_name)
	if area == null:
		return _fail("战区不存在")
	var location = DeployRules.deploy_to_area(area, player_id)
	return {"ok":location != null, "changed":location != null, "player_id":player_id,
		"object_id":location.get_instance_id() if location != null else null,
		"value":_object_summary(location), "error":"部署被规则拒绝" if location == null else ""}


func move(player_id:int, steps:int, ignore_limit:bool = false, ignore_battle:bool = false) -> Dictionary:
	var readiness := _rule_action_ready(player_id, "action")
	if !readiness.ok:
		return readiness
	if steps <= 0:
		return _fail("常规移动只接受正向步数")
	var data:Dictionary = GameData.player_data_library[player_id]
	if host != null and host.has_method("_estimate_move_cost") and host.has_method("_is_magic_enough_for_move"):
		var cost:int = int(host.call("_estimate_move_cost", data, steps))
		if !bool(host.call("_is_magic_enough_for_move", data, cost)):
			return _fail("魔力不足，不能执行常规移动")
	var before = GameData.player_data_library[player_id].get("location")
	Move.new().exec(BaseNumber.new(steps), player_id, ignore_limit, ignore_battle)
	var after = GameData.player_data_library[player_id].get("location")
	return {"ok":after != before, "changed":after != before, "player_id":player_id,
		"before":_object_summary(before), "value":_object_summary(after),
		"error":"移动被规则拒绝" if after == before else ""}


func teleport(player_id:int, location_id:int) -> Dictionary:
	if !GameData.player_data_library.has(player_id):
		return _fail("玩家不存在")
	var location = find_location(location_id)
	if location == null:
		return _fail("位置实例不存在")
	var before = GameData.player_data_library.get(player_id, {}).get("location")
	var ok:bool = SetLocation.new().exec(location, player_id, false)
	var after = GameData.player_data_library.get(player_id, {}).get("location")
	return {"ok":ok and after == location, "changed":after != before, "player_id":player_id,
		"object_id":location_id, "value":_object_summary(after), "error":"瞬移失败" if after != location else ""}


func leave(player_id:int) -> Dictionary:
	if !GameData.player_data_library.has(player_id):
		return _fail("玩家不存在")
	var before = GameData.player_data_library[player_id].get("location")
	RemoveFromBoard.new().exec(player_id)
	var after = GameData.player_data_library[player_id].get("location")
	return {"ok":after == null, "changed":before != null, "player_id":player_id, "value":null,
		"error":"" if after == null else "未能离板"}


func regular_play(player_id:int, card_ids:Array, hidden:Array) -> Dictionary:
	var readiness := _rule_action_ready(player_id, "action")
	if !readiness.ok:
		return readiness
	if card_ids.size() != hidden.size():
		return _fail("cards 与 hidden 数量不一致")
	var selected:Array = []
	for raw_id in card_ids:
		var card = cards.find_card(int(raw_id))
		if !(card is BaseHandCard):
			return _fail("常规出牌包含无效卡牌实例")
		selected.append(card)
	if !RegularPlay.can_submit_group(player_id, selected, hidden):
		return _fail("RegularPlay.can_submit_group 拒绝该整组")
	var ok:bool = RegularPlay.submit_group(player_id, selected, hidden)
	return {"ok":ok, "changed":ok, "player_id":player_id, "value":ok}


func extra_play(player_id:int, card_id:int, kind:String) -> Dictionary:
	var card = cards.find_card(card_id)
	var ok:bool = false
	if kind == "attack" and card is BaseAttack:
		ok = bool(PlayAttack.new().exec(card, player_id, null, null, true))
	elif kind == "skill" and card is BaseSkill:
		var owner:Dictionary = cards.find_card_owner(card)
		ok = bool(PlaySkill.new().exec(card, player_id, true))
		if ok and !owner.is_empty() and str(owner.get("path", "")) != "played_cards":
			RemoveFromArray.new().exec(card, owner.array)
	else:
		return _fail("牌型与命令不匹配")
	return {"ok":ok, "changed":ok, "player_id":player_id, "object_id":card_id, "value":ok,
		"error":"" if ok else "出牌原语拒绝了这次追加打出（阶段、行动者或卡面条件不满足）"}


func release_name(player_id:int) -> Dictionary:
	var ok:bool = ReleaseTrueName.new().exec(player_id)
	return {"ok":ok, "changed":ok, "player_id":player_id, "value":ReleaseTrueName.is_released(player_id),
		"error":"" if ok else "原语未执行（已处于真名解放状态或缺卡）"}


func hide_name(player_id:int) -> Dictionary:
	var ok:bool = HideTrueName.new().exec(player_id)
	return {"ok":ok, "changed":ok, "player_id":player_id, "value":ReleaseTrueName.is_released(player_id),
		"error":"" if ok else "原语未执行（当前不处于可隐藏的状态）"}


func _rule_action_ready(player_id:int, phase_name:String) -> Dictionary:
	if !GameData.player_data_library.has(player_id):
		return _fail("玩家不存在")
	if bool(GameData.player_data_library[player_id].get("is_out", false)):
		return _fail("淘汰玩家不能执行规则动作")
	if GameProgress.current_player_id != player_id:
		return _fail("当前未轮到该玩家行动")
	if str(GameProgress.get_current_phase().get("name", "")) != phase_name:
		return _fail("当前阶段不允许该规则动作")
	return {"ok":true, "changed":false}


func find_area(area_name:String):
	for area in MapData.areas:
		if area is BaseMapArea and (area._area_name == area_name or str(area.get_instance_id()) == area_name):
			return area
	return null


func find_location(instance_id:int):
	for area in MapData.areas:
		for location in area._locations:
			if location is BaseLocation and location.get_instance_id() == instance_id:
				return location
	return null


func _summaries(objects:Array) -> Array:
	var result:Array = []
	for object in objects:
		result.append(_object_summary(object))
	return result


func _object_summary(object):
	if object == null:
		return null
	var result := {"id":object.get_instance_id(), "class":object.get_class()}
	if "_name" in object:
		result["name"] = object._name
	if "_area_name" in object:
		result["area_name"] = object._area_name
	return result


func _fail(reason:String) -> Dictionary:
	return {"ok":false, "changed":false, "error":reason}
