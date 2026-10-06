class_name AddEventFromDeck
extends RefCounted

#从事件牌堆头取一张事件牌的克隆体挂到指定战区。局势牌「于某战场增加一张事件牌」
#（新都之战/深山町的杀人魔/转机/命运之夜等）都走这里，add_count 由调用方传入，不写死几张。
#挂克隆体而不是模板：效果登记时会写 _trigger_player_id，直接挂模板会让同一张牌
#下次进场不再被登记（与 EventResolver.place 同一条规则，这里补 add_count 循环）。
#concealed=false：正面事件牌明置进场
func exec(map_area:BaseMapArea, add_count:int = 1, concealed:bool = false) -> int:
	return start(map_area, add_count, concealed).placed


## 异步消费方保留状态，completed 为真后 placed 才是最终数量。
func start(map_area:BaseMapArea, add_count:int = 1, concealed:bool = false) -> Dictionary:
	var state:Dictionary = {"area": map_area, "count": maxi(add_count, 0), "concealed": concealed, "placed": 0, "completed": false}
	if map_area == null:
		state.completed = true
		return state
	state = EffectManager.record_loop_state(state, self)
	_resume_add(state)
	return state


static func _resume_add(state:Dictionary) -> void:
	while state.placed < state.count:
		if not EffectManager.runtime_guard_checkpoint(state):
			return
		if MapData.event_deck.is_empty():
			break
		var template = MapData.event_deck.pop_front()
		MapData.event_deck.append(template)
		var event = CloneObject.new().exec(template) as BaseEvent
		AddMapAreaEvents.new().exec(state.area, event)
		SetCardConcealed.new().exec(event, state.concealed)
		#暗置牌放置时不派发"本牌亮出时"：牌没亮出，提前执行等于泄露暗置信息（ActionPhase 翻开时才派）
		state.placed += 1
		if not state.concealed: EventResolver.new().register_entered(event)
		if EffectManager.defer_until_runtime_guard_complete(Callable(AddEventFromDeck, "_resume_add").bind(state)):
			return
	state.completed = true
