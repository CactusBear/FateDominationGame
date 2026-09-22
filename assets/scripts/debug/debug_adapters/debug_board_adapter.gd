class_name DebugBoardAdapter
extends RefCounted

var maps:DebugMapAdapter


func _init(map_adapter:DebugMapAdapter = null):
	maps = map_adapter if map_adapter != null else DebugMapAdapter.new()


func place_event(area_name:String, concealed:bool = false, count:int = 1) -> Dictionary:
	var area = maps.find_area(area_name)
	if area == null:
		return _fail("战区不存在")
	var before:int = area._events.size()
	var added:int = AddEventFromDeck.new().exec(area, count, concealed)
	return {"ok":added > 0, "changed":added > 0, "object_id":area.get_instance_id(),
		"before":before, "value":area._events.size(), "added":added,
		"error":"事件牌堆不足或放置失败" if added <= 0 else ""}


func clear_events() -> Dictionary:
	var before:int = 0
	for area in MapData.areas:
		before += area._events.size()
	EventResolver.new().clear_all()
	return {"ok":true, "changed":before > 0, "before":before, "value":MapData.event_discard.size()}


func reveal_planned() -> Dictionary:
	var count:int = EventResolver.new().reveal_planned(GameProgress.event_placements)
	return {"ok":true, "changed":count > 0, "value":count}


func activate_situation() -> Dictionary:
	if MapData.active_situation != null:
		return _fail("已有激活局势，先执行 situation.clear")
	SituationResolver.new().activate()
	return {"ok":MapData.active_situation != null, "changed":MapData.active_situation != null,
		"object_id":MapData.active_situation.get_instance_id() if MapData.active_situation != null else null,
		"value":_summary(MapData.active_situation)}


func clear_situation() -> Dictionary:
	var old = MapData.active_situation
	SituationResolver.new().clear_all()
	return {"ok":true, "changed":old != null, "object_id":old.get_instance_id() if old != null else null, "value":null}


func replace_situation(template_name:String, grant_printed_magic:bool = false) -> Dictionary:
	var template = _find_situation_template(template_name)
	if template == null:
		return _fail("局势模板不存在")
	if MapData.active_situation != null:
		SituationResolver.new().clear_all()
	var situation = CloneObject.new().exec(template) as BaseSituation
	if situation == null:
		return _fail("局势模板克隆失败")
	MapData.active_situation = situation
	if grant_printed_magic:
		for id in GameDataManager.get_active_player_ids():
			EditMagic.new().exec(null, situation._magic, int(id))
	var ids:Array = GameDataManager.get_active_player_ids()
	if !ids.is_empty():
		RegisterObjectEffects.new().exec(situation, int(ids[0]))
	TimePointChecker.global_time_point([TimePoints.CARD_ENTERED], situation)
	return {"ok":true, "changed":true, "object_id":situation.get_instance_id(), "value":_summary(situation)}


func _find_situation_template(template_name:String):
	var templates:Array = LoadSituation.situations.duplicate()
	templates.append_array(LoadSituation.climax_situations.values())
	for template in templates:
		if template is BaseSituation and (template._name == template_name or str(template.get_instance_id()) == template_name):
			return template
	return null


func _summary(object):
	if object == null:
		return null
	return {"id":object.get_instance_id(), "name":object._name, "shown_name":object.get_shown_name()}


func _fail(reason:String) -> Dictionary:
	return {"ok":false, "changed":false, "error":reason}
