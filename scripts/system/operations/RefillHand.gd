class_name RefillHand
extends RefCounted

#规则：把自己的手牌补充到手牌上限（已经有上限张以上则不抽）。
#上限由调用方传入，不写在 operation 里——规则数字可能被效果改动。
#牌堆抽空时按规则先用弃牌堆洗混作为新牌堆；两边都空就停下，不报错。
#返回实际抽到的张数
func exec(player_id:int = -1, limit = 0):
	var captured:Dictionary = EffectManager.execution_context()
	if not captured.ok: return captured
	var context:SessionContext = captured.context

	player_id = EffectManager.resolve_player_id(player_id)
	var player_data:Dictionary = GameDataManager.find_player_data(player_id)
	if player_data.is_empty():
		return 0
	var hand = player_data["hand_cards"] as Array
	var target:int = limit.number if limit is BaseNumber else int(limit)
	var state:Dictionary = {"player": player_id, "data": player_data, "hand": hand, "target": target,
		"deck": player_data.deck, "discard": player_data.discard, "completed": false,
		"hand_before": hand.size(), "deck_before": player_data.deck.size(), "drawn": 0, "phase": "draw"}
	state = EffectManager.record_loop_state(state, self)
	if state.is_empty() or not is_same(state.get("context"), context):
		return DrawCardFromPlDeckToHand.rejection(context, &"unbound_origin")
	var outcome = _resume_refill(state)
	if outcome is Dictionary and not outcome.get("ok", true): return outcome
	#同步返回当前完成数量前复验；完成状态不是来源资格。
	var returned:Dictionary = DrawCardFromPlDeckToHand.source_status(context)
	if not returned.ok: return returned
	return state.drawn


static func continuation_is_current(state:Dictionary) -> bool:
	if not DrawCardFromPlDeckToHand.source_status(state.get("context")).ok or state.get("completed", false) or not state.has_all(["player", "data", "hand", "deck", "discard"]):
		return false
	var current:Dictionary = GameDataManager.find_player_data(int(state.player))
	return not current.is_empty() and is_same(current, state.data) and is_same(current.hand_cards, state.hand) \
		and is_same(current.deck, state.deck) and is_same(current.discard, state.discard)


static func _resume_refill(state:Dictionary):
	while true:
		var source:Dictionary = _state_source_status(state)
		if not source.ok: return source
		if state.phase == "after_draw":
			#抽牌效果完成后才判定是否抽动，避免用尚未结算的牌区状态推进。
			if state.hand.size() == state.before:
				break
			state.drawn += 1
			state.phase = "draw"
		if state.hand.size() >= state.target:
			break
		if not EffectManager.runtime_guard_checkpoint(state):
			var checkpoint_source:Dictionary = _state_source_status(state)
			if not checkpoint_source.ok: return checkpoint_source
			return
		if state.deck.is_empty():
			var shuffled = preload("res://scripts/system/operation_router.gd").exec_registered("reshuffle_discard", [state.player, state.context], state.context)
			var returned:Dictionary = _state_source_status(state)
			if not returned.ok: return returned
			if shuffled is Dictionary and not shuffled.get("ok", true): return shuffled
			if shuffled != true: break
		if not continuation_is_current(state):
			return _state_source_status(state)
		state["before"] = state.hand.size()
		state.phase = "after_draw"
		var drawn = preload("res://scripts/system/operation_router.gd").exec_registered("draw_card_from_pl_deck_to_hand", [0, state.player, state.context], state.context)
		var returned_draw:Dictionary = _state_source_status(state)
		if not returned_draw.ok: return returned_draw
		if drawn is Dictionary and not drawn.get("ok", true): return drawn
		if not continuation_is_current(state):
			return _state_source_status(state)
		if EffectManager.defer_until_runtime_guard_complete(Callable(RefillHand, "_resume_refill").bind(state)):
			return
	if not continuation_is_current(state):
		return _state_source_status(state)
	state.completed = true
	#日志：补牌事实（供"这次补了几张""为什么没补"这类历史查询与排查）
	GameLog.record("refill_hand", state.player, -1, "", null, ["refill_hand"],
		{"limit": state.target, "drawn": state.drawn, "hand_before": state.hand_before, "deck_before": state.deck_before})
	var logged:Dictionary = DrawCardFromPlDeckToHand.source_status(state.context)
	if not logged.ok: return logged


# 每次游标读取前以及同步回调后消费原句柄，不把空状态当成功数量。
static func _state_source_status(state:Dictionary) -> Dictionary:
	var source:Dictionary = DrawCardFromPlDeckToHand.source_status(state.get("context"))
	if not source.ok: return source
	if not continuation_is_current(state):
		return DrawCardFromPlDeckToHand.rejection(state.get("context"), &"unbound_origin")
	return source
