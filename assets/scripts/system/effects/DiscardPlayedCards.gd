class_name DiscardPlayedCards
extends RefCounted

func exec(player_id:int = -1):

	var id = EffectManager.resolve_player_id(player_id)
	var player_data:Dictionary = GameDataManager.get_player_data(id)
	var cards_arr = player_data["played_cards"] as Array
	var discard = player_data["discard"] as Array
	for card:BaseHandCard in cards_arr:
		var card_is_residue:bool = false
		for eff:BaseEffect in card._effects:
			if eff._is_residue:
				card_is_residue = true
				break
		if card_is_residue: continue
		card._is_activating = false
		DrawCardByCard.new().exec(card, cards_arr, discard, BaseNumber.new(0))


#禁止系效果
