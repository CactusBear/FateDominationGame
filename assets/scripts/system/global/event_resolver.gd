class_name EventResolver
extends RefCounted


#事件牌流程：每回合按放置计划抽牌放置，回合结束时清掉场上的事件牌。
#抽几张、放哪个战场、明置还是暗置全部由plan决定，规则数字不写死


#按plan把事件牌放到各战场。plan里每一项是 {"area_name" : String, "concealed" : bool}。
#从牌库头取模板再把模板移回末尾，牌库不会耗尽，一回合内也不会重复抽到同一张。
#挂到战场上的是克隆体：效果登记时会写_trigger_player_id，
#直接挂模板会让同一张牌下次进场时不再被登记
func place(plan:Array) -> Array:
	var placed:Array = []
	for p in plan:
		if MapData.event_deck.is_empty():
			break
		var area = GetMapAreaByName.new().exec(p["area_name"])
		if area == null:
			continue
		var template = MapData.event_deck.pop_front()
		MapData.event_deck.append(template)
		var event = CloneObject.new().exec(template) as BaseEvent
		AddMapAreaEvents.new().exec(area, event)
		SetCardConcealed.new().exec(event, p.get("concealed", false))
		placed.append(event)
	return placed


#清掉场上所有事件牌：注销效果、从区域摘下、从对象表删除。
#事件牌每回合重新抽，用完直接丢弃，不回牌库
func clear_all():
	for area:BaseMapArea in MapData.areas:
		var events:Array = area._events
		for i in range(events.size() - 1, -1, -1):
			var event = events[i]
			UnregisterObjectEffects.new().exec(event)
			events.remove_at(i)
			if event is BaseEvent:
				event.del()
