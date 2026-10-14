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
	var state := AddEventFromDeck.new().start(area, count, concealed)
	var result := {"ok":true, "changed":state.placed > 0, "object_id":area.get_instance_id(), "before":before, "pending":not state.completed}
	if not EffectManager.defer_until_runtime_guard_complete(Callable(DebugBoardAdapter, "_finish_place_event").bind(result, state)):
		_finish_place_event(result, state)
	return result


static func _finish_place_event(result:Dictionary, state:Dictionary) -> void:
	result.pending = not state.completed
	if result.pending:
		return
	result.ok = state.placed > 0
	result.changed = state.placed > 0
	result["value"] = state.area._events.size()
	result["added"] = state.placed
	result["error"] = "事件牌堆不足或放置失败" if state.placed <= 0 else ""


func clear_events(context:SessionContext = null) -> Dictionary:
	var before:int = 0
	for area in MapData.areas:
		before += area._events.size()
	var state:Dictionary = EventResolver.new().clear_all(context)
	return {"ok":state.ok, "changed":state.ok and before > 0, "before":before,
		"value":MapData.event_discard.size(), "error":str(state.get("reason", ""))}


func reveal_planned(context:SessionContext = null) -> Dictionary:
	var state := EventResolver.new().start_reveal(GameProgress.event_placements, context)
	# 保留原 resolver 回执；普通选择和 guard 都等同一 completed ABI。
	var result := {"ok":state.ok, "changed":false, "pending":true, "state":state}
	_finish_reveal(result, state, context)
	return result


static func _finish_reveal(result:Dictionary, state:Dictionary, context:SessionContext) -> void:
	var outcome:Dictionary = await GameProgress.wait_progress_state(state, context)
	result.pending = false
	result.ok = outcome.ok
	result.changed = outcome.ok and state.count > 0
	result["value"] = state.count
	result["error"] = str(outcome.get("reason", ""))


func activate_situation(context:SessionContext = null) -> Dictionary:
	if MapData.active_situation != null:
		return _fail("已有激活局势，先执行 situation.clear")
	var state:Dictionary = SituationResolver.new().activate(context)
	var result := {"ok":state.ok, "changed":false, "pending":true, "state":state}
	_finish_activation(result, state, context)
	return result


static func _finish_activation(result:Dictionary, state:Dictionary, context:SessionContext) -> void:
	var outcome:Dictionary = await GameProgress.wait_progress_state(state, context)
	result.pending = false
	result.ok = outcome.ok and MapData.active_situation != null
	result.changed = result.ok
	var situation = MapData.active_situation if result.ok else null
	result["object_id"] = situation.get_instance_id() if situation != null else null
	result["value"] = _summary(situation)
	result["error"] = str(outcome.get("reason", ""))


func clear_situation(context:SessionContext = null) -> Dictionary:
	var old = MapData.active_situation
	var state:Dictionary = SituationResolver.new().clear_all(context)
	return {"ok":state.ok, "changed":state.ok and old != null,
		"object_id":old.get_instance_id() if old != null else null, "value":null,
		"error":str(state.get("reason", ""))}


func replace_situation(template_name:String, grant_printed_magic:bool = false, source_context:SessionContext = null) -> Dictionary:
	# 消费创建层保存的原来源；可信模板 identity 仍由加载池查询确认。
	var source:Dictionary = SessionGeneration.validate_context(source_context)
	if not source.ok:
		return _fail(str(source.reason))
	var template = _find_situation_template(template_name)
	if template == null:
		return _fail("局势模板不存在")
	var factory := CloneContext.new()
	if not factory.configure_template(source_context, [template]):
		return _fail("局势模板来源拒绝：" + str(factory.failure_reason()))
	var copied:Dictionary = factory.copy_result(template, source_context)
	if not copied.ok or not (copied.object is BaseSituation):
		return _fail("局势模板克隆失败：" + str(copied.reason))
	var situation:BaseSituation = copied.object
	# C0 可以返回不同 context identity，必须仍是同一原 token + origin。
	var origin:Dictionary = SessionGeneration.origin_of(situation)
	if not origin.ok or not is_same(origin.context.token(), source_context.token()) or origin.context.origin() != source_context.origin():
		return _fail("局势模板来源拒绝：unbound_origin")
	# 先完成统一工厂前验/复制；失败不能清掉原局势或修改弃牌区。
	if MapData.active_situation != null:
		var cleared:Dictionary = SituationResolver.new().clear_all(source_context)
		if not cleared.ok:
			return _fail(str(cleared.get("reason", "")))
	MapData.active_situation = situation
	if grant_printed_magic:
		for id in GameDataManager.get_active_player_ids():
			EditMagic.new().exec(null, situation._magic, int(id))
	var ids:Array = GameDataManager.get_active_player_ids()
	if !ids.is_empty():
		RegisterObjectEffects.new().exec(situation, int(ids[0]), source_context)
	#与真实对局同一条路径：亮出这张局势牌并派发三种亮出时点
	TimePointChecker.card_revealed(situation, source_context)
	return {"ok":true, "changed":true, "object_id":situation.get_instance_id(), "value":_summary(situation)}


func _find_situation_template(template_name:String):
	var templates:Array = LoadSituation.situations.duplicate()
	templates.append_array(LoadSituation.climax_situations.values())
	for template in templates:
		if template is BaseSituation and (template._name == template_name or str(template.get_instance_id()) == template_name):
			return template
	return null


static func _summary(object):
	if object == null:
		return null
	return {"id":object.get_instance_id(), "name":object._name, "shown_name":object.get_shown_name()}


func _fail(reason:String) -> Dictionary:
	return {"ok":false, "changed":false, "error":reason}
