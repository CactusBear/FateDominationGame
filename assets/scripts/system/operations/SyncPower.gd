class_name SyncPower
extends RefCounted

#把玩家的合计威力重算为场上明置牌的威力之和，丢弃回合内累积的非卡牌来源加成。
#power平时由出牌/改威力/翻面等操作实时增减，这个操作用于回合结束等需要重建基线的时点：
#规则上残留牌跨回合留在场上并继续提供威力，所以基线不是0而是留场牌的威力之和
func exec(player_id:int = -1):

	var id = EffectManager.resolve_player_id(player_id)
	if !GameData.player_data_library.has(id):
		return
	var player_data:Dictionary = GameDataManager.get_player_data(id)
	var total:int = 0
	var counts_power = CardCountsPower.new()
	for card in player_data["played_cards"]:
		if card is BaseHandCard and counts_power.exec(card, id):
			total += (card._power as BaseNumber).number
	(player_data["power"] as BaseNumber).set_num(BaseNumber.new(total))
