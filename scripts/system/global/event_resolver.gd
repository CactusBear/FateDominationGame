class_name EventResolver
extends RefCounted


#事件牌流程：每回合按放置计划抽牌放置，回合结束时清掉场上的事件牌。
#抽几张、放哪个战场、明置还是暗置全部由plan决定，规则数字不写死


#按plan把事件牌放到各战场。plan里每一项是 {"area_name" : String, "concealed" : bool}。
#从牌库头取模板再把模板移回末尾，牌库不会耗尽，一回合内也不会重复抽到同一张。
#挂到战场上的是克隆体：效果登记时会写_trigger_player_id，
#直接挂模板会让同一张牌下次进场时不再被登记
func place(plan:Array) -> Array:
	var state:Dictionary = {"plan": plan, "index": 0, "placed": []}
	_resume_place(state)
	return state.placed


static func _resume_place(state:Dictionary) -> void:
	while state.index < state.plan.size():
		var p = state.plan[state.index]
		state.index += 1
		var area = GetMapAreaByName.new().exec(p["area_name"])
		if area == null:
			continue
		#取牌堆头模板克隆挂载的完整链路在 AddEventFromDeck 里，这里只按计划传参
		var count:int = AddEventFromDeck.new().exec(area, 1, p.get("concealed", false))
		if count > 0:
			state.placed.append(true)
		if EffectManager.defer_until_runtime_guard_complete(Callable(EventResolver, "_resume_place").bind(state)):
			return


#规则：行动阶段开始时展示暗置放置的事件牌（基础规则是"展示位于新都的暗置事件牌"）。
#"该翻哪个战区"沿用本回合的放置计划里 concealed=true 的那几项：
#不写死战区名，也不会误翻别处碰巧暗置的牌。返回翻开的张数
func reveal_planned(plan:Array) -> int:
	return start_reveal(plan).count


## 完成状态与数量共用原游标；暂停消费方不读取部分数量作为最终结果。
func start_reveal(plan:Array) -> Dictionary:
	var concealed_areas:Array = []
	for p in plan:
		if p.get("concealed", false):
			concealed_areas.append(str(p.get("area_name", "")))
	var state:Dictionary = {"areas": MapData.areas, "planned": concealed_areas, "area_index": 0, "event_index": 0, "count": 0, "completed": false}
	_resume_reveal(state)
	#翻开即亮出：循环里每张翻开的牌各自派发三种卡牌亮出时点（见 TimePoints.CARD_REVEALED），
	#让布置类效果立刻执行；一张都没翻开就不派发，避免空时点白跑一轮效果检查
	#同步调用返回已完成数量；暂停时，剩余流程由显式尾部完成。
	return state


static func _resume_reveal(state:Dictionary) -> void:
	while state.area_index < state.areas.size():
		var area:BaseMapArea = state.areas[state.area_index]
		if not state.planned.has(area._area_name) or state.event_index >= area._events.size():
			state.area_index += 1
			state.event_index = 0
			continue
		var event = area._events[state.event_index]
		state.event_index += 1
		if event is BaseEvent and event._is_concealed:
			SetCardConcealed.new().exec(event, false)
			state.count += 1
			EventResolver.new().register_entered(event)
			if EffectManager.defer_until_runtime_guard_complete(Callable(EventResolver, "_resume_reveal").bind(state)):
				return
	state.completed = true


#明置放置（AddEventFromDeck）与暗置翻开（reveal_planned）共用这一条：
#登记本牌效果，再带 source 派发"本牌亮出时"——只唤醒本牌的效果，不广播给别处监听
func register_entered(event:BaseEvent):
	var ids:Array = GameDataManager.get_active_player_ids()
	if ids.is_empty(): return
	for effect in event._effects:
		if effect._trigger_player_id == -1: EffectManager.register_effect(effect, int(ids[0]))
	TimePointChecker.card_revealed(event)


#清掉场上所有事件牌：注销效果、从区域摘下、从对象表删除。
#事件牌每回合重新抽，用完直接丢弃，不回牌库
func clear_all():
	for area:BaseMapArea in MapData.areas:
		var events:Array = area._events
		for i in range(events.size() - 1, -1, -1):
			var event = events[i]
			#先注销效果：离场的牌不能继续生效
			UnregisterObjectEffects.new().exec(event)
			events.remove_at(i)
			if event is BaseEvent:
				#移入事件牌弃牌区而不是销毁：玩家要能回看本局出过哪些事件牌。
				#弃牌区在每局开始时统一销毁并清空，不会跨局累积
				event.set_concealed(false)
				MapData.event_discard.append(event)
