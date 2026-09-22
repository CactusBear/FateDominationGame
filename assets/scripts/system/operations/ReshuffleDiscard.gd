class_name ReshuffleDiscard
extends RefCounted

#规则：需要从耗尽的牌堆中抽牌时，把相应的弃牌堆洗混作为新的牌堆。
#只做这一件事——搬运与洗牌；抽牌由调用方自己调 draw_card_from_pl_deck_to_hand，
#这样"洗回牌堆"也能被其它效果单独使用。
#牌堆还有牌、或两边都空时返回 false（没有发生洗牌）
func exec(player_id:int = -1) -> bool:

	player_id = EffectManager.resolve_player_id(player_id)
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	var deck = player_data["deck"] as Array
	if !deck.is_empty():
		return false
	var discard = player_data["discard"] as Array
	if discard.is_empty():
		return false
	var count:int = discard.size()
	deck.append_array(discard)
	discard.clear()
	ShuffleArray.new().exec(deck)
	#日志：牌堆抽空后把弃牌堆洗回（供"这局洗过几次"这类历史查询）
	GameLog.record("reshuffle_discard", player_id, -1, "", null, ["reshuffle_discard"],
		{"count": count})
	#提示当事玩家：牌堆抽干了、弃牌堆已洗回。只给他看，别人不需要知道
	EffectManager.push_message("牌库已抽空，弃牌堆 %d 张洗混作为新牌库" % count, player_id)
	return true
