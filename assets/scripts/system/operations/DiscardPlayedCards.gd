class_name DiscardPlayedCards
extends RefCounted

func exec(player_id:int = -1):

	var id = EffectManager.resolve_player_id(player_id)
	var player_data:Dictionary = GameDataManager.get_player_data(id)
	var cards_arr = player_data["played_cards"] as Array
	var discard = player_data["discard"] as Array
	for card:BaseHandCard in cards_arr.duplicate():
		var card_is_residue:bool = false
		for eff:BaseEffect in card._effects:
			if eff._is_residue:
				card_is_residue = true
				break
		#残留牌回合结束不自动关闭，留在场上继续提供威力；
		#但已被自身或其他效果关闭的残留牌此时已是暗置，仍要走"弃置暗置攻击"这一步
		if card_is_residue and !card._is_closed and !card._is_concealed: continue
		card._is_activating = false
		if card is BaseSkill:
			#技能牌回合结束保持明置并放回技能区，不进入弃牌堆
			SetCardConcealed.new().exec(card, false, id)
			cards_arr.erase(card)
			AddSkillToSkillZone.new().exec(card, id)
			continue
		#普通攻击牌弃置前暗置，再进入弃牌堆
		if card is BaseAttack:
			SetCardConcealed.new().exec(card, true, id)
		DrawCardByCard.new().exec(card, cards_arr, discard, BaseNumber.new(0))


#禁止系效果
