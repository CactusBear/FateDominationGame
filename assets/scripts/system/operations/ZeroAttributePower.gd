class_name ZeroAttributePower
extends RefCounted

#将目标玩家指定属性的攻击威力按0计：扫描其场上这些属性的攻击牌，
#把它们的威力贡献从合计威力里一次性扣掉。
#在战斗结算前的时点(所有人出完牌后)调用；回合结束 SyncPower 重建基线时恢复，不永久改牌。
#属性由调用方传入，不写死迅捷/魔术/力量；player_id 默认当前效果归属玩家。
func exec(player_id:int = -1, attributes:Array = []):

	var id = EffectManager.resolve_player_id(player_id)
	if !GameData.player_data_library.has(id):
		return 0
	var player_data:Dictionary = GameDataManager.get_player_data(id)
	var total:int = 0
	var counts_power = CardCountsPower.new()
	for card in player_data["played_cards"]:
		if !(card is BaseAttack):
			continue
		if !counts_power.exec(card, id):
			continue
		for attribute in attributes:
			if card.has_attribute(attribute):
				total += (card._power as BaseNumber).number
				break
	if total > 0:
		EditPower.new().exec(null, BaseNumber.new(-total), id)
	return total
