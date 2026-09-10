class_name CardCountsPower
extends RefCounted

#判定一张牌当前是否计入玩家的合计威力。所有增减power的位置都应查询本函数，
#不要各自判断_is_concealed，否则每加一条例外规则都要改多处。
#默认规则：在场上且明置的牌计入合计威力。两个方向的例外都按效果名查询：
#  NeverCountsPowerEffect            明置也不计入(优先级最高)
#  CountsPowerWhileConcealedEffect   暗置也照常计入
func exec(card:BaseHandCard, player_id:int = -1) -> bool:

	if card == null:
		return false
	var id = EffectManager.resolve_player_id(player_id)
	if !GameData.player_data_library.has(id):
		return false
	var player_data:Dictionary = GameDataManager.get_player_data(id)
	#不在场上的牌(手牌、技能区、弃牌堆)一律不计威力
	if !(player_data["played_cards"] as Array).has(card):
		return false

	var has_effect = CardHasEffect.new()
	if has_effect.exec(NeverCountsPowerEffect.EFFECT_NAME, card):
		return false
	if !card._is_concealed:
		return true
	return has_effect.exec(CountsPowerWhileConcealedEffect.EFFECT_NAME, card)
