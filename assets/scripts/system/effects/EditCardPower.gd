class_name EditCardPower
extends RefCounted

#修改指定卡牌的威力。卡已打出时，玩家当前的力量总和也跟着变
func exec(card:BaseHandCard, vary_num:BaseNumber = BaseNumber.new(0), set_num:BaseNumber = null, player_id:int = -1):

	if card == null:
		return
	card.edit_power(vary_num, set_num)
	if !card._is_activating:
		return
	var id = EffectManager.resolve_player_id(player_id)
	var player_data:Dictionary = GameDataManager.get_player_data(id)
	if !(player_data["played_cards"] as Array).has(card):
		return
	var pl_power = player_data["power"] as BaseNumber
	pl_power.add(vary_num)
