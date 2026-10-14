class_name EventResolver
extends RefCounted

const ROUTER = preload("res://scripts/system/operation_router.gd")

# 数量、完成、拒绝分开；只消费原来源，不给卡补票。
func place(plan:Array, context:SessionContext = null) -> Dictionary:
	var state:Dictionary = {"ok":true, "context":context, "plan":plan.duplicate(true), "index":0,
		"placed":[], "completed":false, "areas":MapData.areas, "deck":MapData.event_deck}
	_resume_place(state)
	return state

static func _source(state:Dictionary) -> bool:
	var valid:Dictionary = SessionGeneration.validate_context(state.get("context"))
	if not valid.ok:
		_refuse(state, valid.reason)
		return false
	if not is_same(state.get("areas"), MapData.areas):
		_refuse(state, &"unbound_origin")
		return false
	return state.get("ok", false)

static func _refuse(state:Dictionary, reason:StringName) -> void:
	state["ok"] = false
	state["reason"] = reason
	state["completed"] = true

static func _resume_place(state:Dictionary) -> void:
	if not _source(state): return
	if not state.has_all(["plan", "index", "placed", "deck"]) or not is_same(state.deck, MapData.event_deck):
		_refuse(state, &"unbound_origin")
		return
	while state.index < state.plan.size():
		if not _source(state): return
		var p = state.plan[state.index]
		var area = GetMapAreaByName.new().exec(p["area_name"])
		if area == null:
			state.index += 1
			continue
		var operation:Dictionary = GameProgress.start_progress_operation("add_event_from_deck", [area, 1, p.get("concealed", false)], state.context)
		var outcome:Dictionary = await GameProgress.wait_progress_operation(operation)
		if not _source(state): return
		if not outcome.ok:
			_refuse(state, outcome.reason)
			return
		var count = outcome.value
		if not count is int:
			_refuse(state, &"invalid_operation_result")
			return
		if count > 0: state.placed.append(true)
		state.index += 1
	state.completed = true

func reveal_planned(plan:Array, context:SessionContext = null) -> Dictionary:
	return start_reveal(plan, context)

func start_reveal(plan:Array, context:SessionContext = null) -> Dictionary:
	var planned:Array = []
	for p in plan:
		if p.get("concealed", false): planned.append(str(p.get("area_name", "")))
	var state:Dictionary = {"ok":true, "context":context, "areas":MapData.areas, "planned":planned,
		"area_index":0, "event_index":0, "count":0, "completed":false}
	_resume_reveal(state)
	return state

static func _resume_reveal(state:Dictionary) -> void:
	if not _source(state): return
	while state.area_index < state.areas.size():
		if not _source(state): return
		var area:BaseMapArea = state.areas[state.area_index]
		if not state.planned.has(area._area_name) or state.event_index >= area._events.size():
			state.area_index += 1
			state.event_index = 0
			continue
		var event = area._events[state.event_index]
		state.event_index += 1
		if event is BaseEvent and event._is_concealed:
			var flipped = ROUTER.exec_registered("set_card_concealed", [event, false, -1, state.context], state.context)
			if not _source(state): return
			if flipped != true:
				_refuse(state, &"operation_rejected")
				return
			state.count += 1
			if not EventResolver.new().register_entered(event, state.context):
				_refuse(state, &"unbound_origin")
				return
			while SessionGeneration.validate_context(state.context).ok and (EffectManager.is_running or EffectManager.is_waiting_for_choice()):
				await GameProgress.get_tree().process_frame
			if not _source(state): return
	state.completed = true

# 缺省仅供 AddEventFromDeck 继承已验帧，无帧调用必须显式原来源。
func register_entered(event:BaseEvent, context:SessionContext = null) -> bool:
	if context == null:
		var frame:Dictionary = EffectManager.execution_context()
		if not frame.ok: return false
		context = frame.context
	if not SetCardConcealed.source_is_current(event, context): return false
	var ids:Array = GameDataManager.get_active_player_ids()
	if ids.is_empty(): return true
	for effect in event._effects:
		if not SessionGeneration.validate_context(context).ok: return false
		if effect._trigger_player_id == -1 and not EffectManager.register_effect(effect, int(ids[0])): return false
	TimePointChecker.card_revealed(event, context)
	return SessionGeneration.validate_context(context).ok

func clear_all(context:SessionContext = null) -> Dictionary:
	var state:Dictionary = {"ok":true, "context":context, "areas":MapData.areas}
	if not _source(state): return state
	for area:BaseMapArea in state.areas:
		for i in range(area._events.size() - 1, -1, -1):
			if not _source(state): return state
			var event = area._events[i]
			if not SetCardConcealed.source_is_current(event, context):
				_refuse(state, &"unbound_origin")
				return state
			ROUTER.exec_registered("unregister_object_effects", [event], context)
			if not _source(state): return state
			area._events.remove_at(i)
			event.set_concealed(false)
			MapData.event_discard.append(event)
	state["completed"] = true
	return state
