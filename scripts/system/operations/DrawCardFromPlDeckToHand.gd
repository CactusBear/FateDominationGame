class_name DrawCardFromPlDeckToHand
extends RefCounted

#从牌库抽出下标指定的一张牌进手牌。
#from_index 兼容 int / float / BaseNumber：效果链里上一步算出来的多是 BaseNumber，
#要求调用方先拆包会在 rand/int 这类原生调用点直接抛错
func exec(from_index = 0, player_id:int = -1, context:SessionContext = null):
	var captured:Dictionary = capture_source(context)
	if not captured.ok: return captured
	context = captured.context

	player_id = EffectManager.resolve_player_id(player_id)
	var player_data:Dictionary = GameDataManager.find_player_data(player_id)
	if player_data.is_empty():
		return
	if !(player_data["can_draw_card"] as bool):
		return
	var index:int = int(from_index.number) if from_index is BaseNumber else int(from_index)
	var deck = player_data["deck"] as Array
	if index < 0 or deck.size() <= index:
		#show("超出数组范围")
		return
	var card = deck[index]
	var hand = player_data["hand_cards"] as Array
	var card_name = card.get_shown_name() if card.has_method("get_shown_name") else str(card)
	var before_move:Dictionary = source_status(context)
	if not before_move.ok: return before_move
	if not target_is_current(player_id, player_data, deck, hand):
		return rejection(context, &"unbound_origin")
	deck.pop_at(index)
	hand.append(card)
	#日志：抽牌事实（谁在第几回合哪个阶段抽了哪张），排查"手牌莫名多出来"时的第一手依据
	GameLog.record("draw", player_id, -1, "", card, ["draw"],
		{"card_name": card_name, "from_index": index})
	#抽牌时点带上这张牌作来源；牌区变化（离开牌库、进入手牌）与其它搬运入口同一套派发
	TimePointChecker.dynamic_time_point([TimePoints.CARD_DRAWN], player_id, card)
	var returned:Dictionary = source_status(context)
	if not returned.ok: return returned
	if not target_is_current(player_id, player_data, deck, hand):
		return rejection(context, &"unbound_origin")
	if not EffectManager.defer_until_runtime_guard_complete(Callable(DrawCardFromPlDeckToHand, "_notify_moved").bind(card, player_id, player_data, deck, hand, context)):
		return _notify_moved(card, player_id, player_data, deck, hand, context)


static func _notify_moved(card:BaseCard, player_id:int, player_data:Dictionary, deck:Array, hand:Array, context:SessionContext):
	var source:Dictionary = source_status(context)
	if not source.ok: return source
	if not target_is_current(player_id, player_data, deck, hand):
		return rejection(context, &"unbound_origin")
	CardZones.notify_moved(card, {"player_id": player_id, "zone": "deck"}, {"player_id": player_id, "zone": "hand_cards"})
	var returned:Dictionary = source_status(context)
	if not returned.ok: return returned
	if not target_is_current(player_id, player_data, deck, hand):
		return rejection(context, &"unbound_origin")


# 显式来源用于已捕获尾部；缺省只继承已验函数帧，绝不从 current/activating_eff 补票。
static func capture_source(context:SessionContext = null) -> Dictionary:
	if context == null:
		return EffectManager.execution_context()
	return source_status(context)


static func source_status(context:SessionContext) -> Dictionary:
	var status:Dictionary = SessionGeneration.validate_context(context)
	return {"ok":status.ok, "context":context, "reason":status.reason}


static func rejection(context:SessionContext, reason:StringName) -> Dictionary:
	return {"ok":false, "context":context, "reason":reason}


static func target_is_current(player_id:int, data:Dictionary, deck:Array, hand:Array) -> bool:
	var current:Dictionary = GameDataManager.find_player_data(player_id)
	return not current.is_empty() and is_same(current, data) and is_same(current.deck, deck) and is_same(current.hand_cards, hand)
