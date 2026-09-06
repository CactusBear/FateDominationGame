class_name GetCardsByNameFrArr
extends RefCounted

func exec(card_name:String, cards:Array):

	var got_cards:Array#[BaseCard]
	for card:BaseCard in cards:
		if card._name == card_name:
			got_cards.append(card)
	return got_cards
