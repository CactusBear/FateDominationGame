class_name GetCardsByAttributesFrArr
extends RefCounted

#从给定数组里筛出带有指定属性的卡。默认命中任意一个属性，require_all为true时必须全部具备。
#不扫描全局对象，只处理调用方传入的数组，和GetCardsByNameFrArr同一用法。
func exec(attributes:Array, cards:Array, require_all:bool = false) -> Array:

	var got_cards:Array = []
	if cards == null:
		return got_cards
	var has_attribute = HasAttribute.new()
	for card in cards:
		if !(card is BaseCard):
			continue
		if require_all:
			var matched:bool = true
			for attribute in attributes:
				if !card.has_attribute(attribute):
					matched = false
					break
			if matched:
				got_cards.append(card)
		elif has_attribute.exec(attributes, card):
			got_cards.append(card)
	return got_cards
