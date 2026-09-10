class_name SetCardConcealed
extends RefCounted

#改变卡牌的明置/暗置状态，并实时同步玩家的合计威力。
#不直接按暗置与否加减威力，而是比较变更前后CardCountsPower的结果：
#带"暗置也计威力"这类例外效果的牌翻面时前后都计威力，差值为0，不会被误扣。
#所有需要翻面的效果都应走这个入口，避免各自手动增减power时漏掉配对操作
func exec(card:BaseHandCard, concealed:bool, player_id:int = -1):
	if card == null or card._is_concealed == concealed:
		return

	var id = EffectManager.resolve_player_id(player_id)
	var counts_power = CardCountsPower.new()
	var counted_before:bool = counts_power.exec(card, id)
	card.set_concealed(concealed)
	var counted_after:bool = counts_power.exec(card, id)
	if counted_before == counted_after:
		return

	var player_data:Dictionary = GameDataManager.get_player_data(id)
	var pl_power = player_data["power"] as BaseNumber
	if counted_after:
		pl_power.add(card._power)
	else:
		pl_power.minus(card._power)
