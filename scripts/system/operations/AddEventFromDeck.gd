class_name AddEventFromDeck
extends RefCounted

#从事件牌堆头取一张事件牌的克隆体挂到指定战区。局势牌「于某战场增加一张事件牌」
#（新都之战/深山町的杀人魔/转机/命运之夜等）都走这里，add_count 由调用方传入，不写死几张。
#挂克隆体而不是模板：效果登记时会写 _trigger_player_id，直接挂模板会让同一张牌
#下次进场不再被登记（与 EventResolver.place 同一条规则，这里补 add_count 循环）。
#concealed=false：正面事件牌明置进场
func exec(map_area:BaseMapArea, add_count:int = 1, concealed:bool = false):
	var state:Dictionary = start(map_area, add_count, concealed)
	if not state.get("ok", true): return state
	return state.placed


## 异步消费方保留状态，completed 为真后 placed 才是最终数量。
func start(map_area:BaseMapArea, add_count:int = 1, concealed:bool = false) -> Dictionary:
	var captured:Dictionary = EffectManager.execution_context()
	if not captured.ok: return captured
	var context:SessionContext = captured.context
	var state:Dictionary = {"area": map_area, "count": maxi(add_count, 0), "concealed": concealed, "placed": 0, "completed": false, "deck": MapData.event_deck, "events": map_area._events if map_area != null else [], "areas": MapData.areas}
	if map_area == null:
		state.completed = true
		return state
	state = EffectManager.record_loop_state(state, self)
	if state.is_empty() or not is_same(state.get("context"), context):
		return DrawCardFromPlDeckToHand.rejection(context, &"unbound_origin")
	var outcome = _resume_add(state)
	if outcome is Dictionary and not outcome.get("ok", true): return outcome
	var returned:Dictionary = _state_source_status(state)
	if not returned.ok: return returned
	return state


static func _resume_add(state:Dictionary):
	while true:
		var source:Dictionary = _state_source_status(state)
		if not source.ok: return source
		if state.placed >= state.count: break
		if not EffectManager.runtime_guard_checkpoint(state):
			var checkpoint_source:Dictionary = _state_source_status(state)
			if not checkpoint_source.ok: return checkpoint_source
			return
		if state.deck.is_empty():
			break
		var template = state.deck.pop_front()
		state.deck.append(template)
		var event = CloneObject.new().exec(template) as BaseEvent
		var cloned:Dictionary = _state_source_status(state)
		if not cloned.ok: return cloned
		# 克隆消费口不为未绑定对象补票；可信 runtime 克隆厂须另行接源。
		if not SetCardConcealed.source_is_current(event, state.context):
			return DrawCardFromPlDeckToHand.rejection(state.context, &"unbound_origin")
		preload("res://scripts/system/operation_router.gd").exec_registered("add_map_area_events", [state.area, event], state.context)
		var added:Dictionary = _state_source_status(state)
		if not added.ok: return added
		var concealed = preload("res://scripts/system/operation_router.gd").exec_registered("set_card_concealed", [event, state.concealed, -1, state.context], state.context)
		var flipped:Dictionary = _state_source_status(state)
		if not flipped.ok: return flipped
		if concealed != true: return DrawCardFromPlDeckToHand.rejection(state.context, &"unbound_origin")
		#暗置牌放置时不派发"本牌亮出时"：牌没亮出，提前执行等于泄露暗置信息（ActionPhase 翻开时才派）
		state.placed += 1
		if not state.concealed: EventResolver.new().register_entered(event)
		var entered:Dictionary = _state_source_status(state)
		if not entered.ok: return entered
		if EffectManager.defer_until_runtime_guard_complete(Callable(AddEventFromDeck, "_resume_add").bind(state)):
			return
	state.completed = true


static func _state_source_status(state:Dictionary) -> Dictionary:
	var source:Dictionary = DrawCardFromPlDeckToHand.source_status(state.get("context"))
	if not source.ok: return source
	if not state.has_all(["area", "placed", "count", "deck", "events", "areas"]) or state.area == null:
		return DrawCardFromPlDeckToHand.rejection(state.get("context"), &"unbound_origin")
	if not is_same(state.deck, MapData.event_deck) or not is_same(state.areas, MapData.areas) or not is_same(state.events, state.area._events):
		return DrawCardFromPlDeckToHand.rejection(state.context, &"unbound_origin")
	return source
