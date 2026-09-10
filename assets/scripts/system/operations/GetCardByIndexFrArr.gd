class_name GetCardByIndexFrArr
extends RefCounted

func exec(card_index, cards:Array):

	if cards == null:
		return
	var i = card_index.number if card_index is BaseNumber else int(card_index)
	if i < 0 or cards.size() <= i:
		#show("超出数组范围")
		return
	return cards[i]
