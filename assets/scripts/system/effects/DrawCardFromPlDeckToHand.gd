class_name DrawCardFromPlDeckToHand
extends RefCounted

func exec(from_index:BaseNumber = BaseNumber.new(0), player_id:int = GameData.player_id):

	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	var deck = player_data["deck"] as Array
	if deck.size() <= from_index.number:
		#show("超出数组范围")
		return
	var card = deck[from_index.number]
	deck.pop_at(from_index.number)
	var hand = player_data["hand_cards"] as Array
	hand.append(card)
