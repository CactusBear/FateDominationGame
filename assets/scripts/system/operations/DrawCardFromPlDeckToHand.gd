class_name DrawCardFromPlDeckToHand
extends RefCounted

#从牌库抽出下标指定的一张牌进手牌。
#from_index 兼容 int / float / BaseNumber：效果链里上一步算出来的多是 BaseNumber，
#要求调用方先拆包会在 rand/int 这类原生调用点直接抛错
func exec(from_index = 0, player_id:int = -1):

	player_id = EffectManager.resolve_player_id(player_id)
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	if !(player_data["can_draw_card"] as bool):
		return
	var index:int = int(from_index.number) if from_index is BaseNumber else int(from_index)
	var deck = player_data["deck"] as Array
	if index < 0 or deck.size() <= index:
		#show("超出数组范围")
		return
	var card = deck[index]
	deck.pop_at(index)
	var hand = player_data["hand_cards"] as Array
	hand.append(card)
	#日志：抽牌事实（谁在第几回合哪个阶段抽了哪张），排查"手牌莫名多出来"时的第一手依据
	GameLog.record("draw", player_id, -1, "", card, ["draw"],
		{"card_name": card.get_shown_name() if card.has_method("get_shown_name") else str(card), "from_index": index})
