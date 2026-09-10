class_name EditCardPower
extends RefCounted

#修改指定卡牌的威力。卡已打出时，玩家当前的力量总和也跟着变
func exec(card:BaseHandCard, vary_num:BaseNumber = BaseNumber.new(0), set_num:BaseNumber = null, player_id:int = -1):

	if card == null:
		return
	var id = EffectManager.resolve_player_id(player_id)
	#改威力前先记下这张牌原本贡献了多少，改完按同一判定入口重新贡献一次，
	#这样set_num整体改写和暗置牌不计威力两种情况都能算对
	var counts_power = CardCountsPower.new()
	var counted:bool = counts_power.exec(card, id)
	var old_power:int = (card._power as BaseNumber).number
	card.edit_power(vary_num, set_num)
	if !counted:
		return
	var player_data:Dictionary = GameDataManager.get_player_data(id)
	var pl_power = player_data["power"] as BaseNumber
	pl_power.add(BaseNumber.new((card._power as BaseNumber).number - old_power))
