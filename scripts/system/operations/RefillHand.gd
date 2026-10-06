class_name RefillHand
extends RefCounted

#规则：把自己的手牌补充到手牌上限（已经有上限张以上则不抽）。
#上限由调用方传入，不写在 operation 里——规则数字可能被效果改动。
#牌堆抽空时按规则先用弃牌堆洗混作为新牌堆；两边都空就停下，不报错。
#返回实际抽到的张数
func exec(player_id:int = -1, limit = 0) -> int:

	player_id = EffectManager.resolve_player_id(player_id)
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	var hand = player_data["hand_cards"] as Array
	var target:int = limit.number if limit is BaseNumber else int(limit)
	var state:Dictionary = {"player": player_id, "data": player_data, "hand": hand, "target": target,
		"hand_before": hand.size(), "deck_before": player_data.deck.size(), "drawn": 0, "phase": "draw"}
	state = EffectManager.record_loop_state(state, self)
	_resume_refill(state)
	#同步返回当前完成数量；正式回合以补牌完成尾部为推进边界。
	return state.drawn


static func _resume_refill(state:Dictionary) -> void:
	while true:
		if state.phase == "after_draw":
			#抽牌效果完成后才判定是否抽动，避免用尚未结算的牌区状态推进。
			if state.hand.size() == state.before:
				break
			state.drawn += 1
			state.phase = "draw"
		if state.hand.size() >= state.target:
			break
		if not EffectManager.runtime_guard_checkpoint(state):
			return
		if state.data.deck.is_empty() and not ReshuffleDiscard.new().exec(state.player):
			break
		state["before"] = state.hand.size()
		state.phase = "after_draw"
		DrawCardFromPlDeckToHand.new().exec(0, state.player)
		if EffectManager.defer_until_runtime_guard_complete(Callable(RefillHand, "_resume_refill").bind(state)):
			return
	#日志：补牌事实（供"这次补了几张""为什么没补"这类历史查询与排查）
	GameLog.record("refill_hand", state.player, -1, "", null, ["refill_hand"],
		{"limit": state.target, "drawn": state.drawn, "hand_before": state.hand_before, "deck_before": state.deck_before})
