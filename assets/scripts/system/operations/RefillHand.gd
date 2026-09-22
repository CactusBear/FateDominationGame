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
	var hand_before:int = hand.size()
	var deck_before:int = (player_data["deck"] as Array).size()
	var drawn:int = 0
	while hand.size() < target:
		if (player_data["deck"] as Array).is_empty() and !ReshuffleDiscard.new().exec(player_id):
			break
		var before:int = hand.size()
		DrawCardFromPlDeckToHand.new().exec(0, player_id)
		#抽牌入口可能因"不能抽牌"这类状态而拒发，抽不动就停，避免死循环
		if hand.size() == before:
			break
		drawn += 1
	#日志：补牌事实（供"这次补了几张""为什么没补"这类历史查询与排查）
	GameLog.record("refill_hand", player_id, -1, "", null, ["refill_hand"],
		{"limit": target, "drawn": drawn, "hand_before": hand_before, "deck_before": deck_before})
	return drawn
