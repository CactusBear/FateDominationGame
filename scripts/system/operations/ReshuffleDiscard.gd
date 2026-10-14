class_name ReshuffleDiscard
extends RefCounted

#规则：需要从耗尽的牌堆中抽牌时，把相应的弃牌堆洗混作为新的牌堆。
#只做这一件事——搬运与洗牌；抽牌由调用方自己调 draw_card_from_pl_deck_to_hand，
#这样"洗回牌堆"也能被其它效果单独使用。
#牌堆还有牌、或两边都空时返回 false（没有发生洗牌）
func exec(player_id:int = -1, context:SessionContext = null):
	var captured:Dictionary = DrawCardFromPlDeckToHand.capture_source(context)
	if not captured.ok: return captured
	context = captured.context

	player_id = EffectManager.resolve_player_id(player_id)
	var player_data:Dictionary = GameDataManager.find_player_data(player_id)
	if player_data.is_empty():
		return false
	var deck = player_data["deck"] as Array
	if !deck.is_empty():
		return false
	var discard = player_data["discard"] as Array
	if discard.is_empty():
		return false
	var shuffle := ShuffleArray.new()
	if not shuffle.can_shuffle():
		return DrawCardFromPlDeckToHand.rejection(context, &"unknown_random_stream")
	var shuffled:Array = discard.duplicate()
	if shuffle.exec(shuffled) == null:
		return DrawCardFromPlDeckToHand.rejection(context, &"unknown_random_stream")
	var count:int = shuffled.size()
	# 成功后才发布到原容器；拒绝不搬牌、不清弃牌、不派事实或时点。
	deck.append_array(shuffled)
	discard.clear()
	#日志：牌堆抽空后把弃牌堆洗回（供"这局洗过几次"这类历史查询）
	GameLog.record("reshuffle_discard", player_id, -1, "", null, ["reshuffle_discard"],
		{"count": count})
	#提示当事玩家：牌堆抽干了、弃牌堆已洗回。只给他看，别人不需要知道
	var logged:Dictionary = DrawCardFromPlDeckToHand.source_status(context)
	if not logged.ok: return logged
	EffectManager.push_message("牌库已抽空，弃牌堆 %d 张洗混作为新牌库" % count, player_id)
	var messaged:Dictionary = DrawCardFromPlDeckToHand.source_status(context)
	if not messaged.ok: return messaged
	TimePointChecker.dynamic_time_point([TimePoints.DECK_RESHUFFLED], player_id)
	var returned:Dictionary = DrawCardFromPlDeckToHand.source_status(context)
	if not returned.ok: return returned
	var current:Dictionary = GameDataManager.find_player_data(player_id)
	if not is_same(current, player_data) or not is_same(current.get("deck"), deck) or not is_same(current.get("discard"), discard):
		return DrawCardFromPlDeckToHand.rejection(context, &"unbound_origin")
	return true
