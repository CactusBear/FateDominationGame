class_name GetCardByIndexFrArr
extends RefCounted

func exec(card_index:BaseNumber, cards:Array):

	if cards.size() <= card_index.number:
		#show("超出数组范围")
		return
	return cards[card_index.number]
