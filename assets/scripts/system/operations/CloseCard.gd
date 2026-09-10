class_name CloseCard
extends RefCounted

#关闭一张已打出的手牌：技能牌返回技能区(从played_cards移除、停止激活)，
#攻击牌转为暗置(不再计入合计威力)。规则用语"关闭"对两类卡效果不同，故按类型分支
func exec(card:BaseHandCard, player_id:int = -1):
	if card == null or card._is_closed:
		return

	var id = EffectManager.resolve_player_id(player_id)
	var player_data:Dictionary = GameDataManager.get_player_data(id)
	var played_cards = player_data["played_cards"] as Array

	card.set_closed(true)
	if card is BaseSkill:
		card.set_if_activating(false)
		#技能牌离场后不再计入合计威力，先按判定入口扣掉它此前贡献的威力再移出场
		if CardCountsPower.new().exec(card, id):
			EditPower.new().exec(null, BaseNumber.new(-card._power.number), id)
		played_cards.erase(card)
		#技能牌关闭后立刻明置返回技能区，复用AddSkillToSkillZone一并重新登记其效果
		card.set_concealed(false)
		AddSkillToSkillZone.new().exec(card, id)
	elif card is BaseAttack:
		#转暗置后不再计入合计威力，由SetCardConcealed同步扣减
		SetCardConcealed.new().exec(card, true, id)

	TimePointChecker.dynamic_time_point([TimePoints.CARD_CLOSED], id)
