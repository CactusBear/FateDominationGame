class_name GetCardsByNameFrArr
extends RefCounted

func exec(card_name:String, cards:Array):

	var got_cards:Array#[BaseCard]
	for card:BaseCard in cards:
		#别名（"同时名为/视为"）与本名同等看待，比对口径统一在 BaseObject.has_name
		if card.has_name(card_name):
			got_cards.append(card)
	return got_cards
