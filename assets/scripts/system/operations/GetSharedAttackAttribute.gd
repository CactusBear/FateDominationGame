class_name GetSharedAttackAttribute
extends RefCounted

#查「玩家场上所有攻击是否至少有一种共同属性」，有则返回该属性名，没有则返回 null。
#「若至少一种属性相同则…」这类条件（协同、对未来的憧憬）都用它做门槛；
#哪几张牌参与、参与判定的玩家是谁由调用方（通常是事件牌效果遍历战场玩家）决定。
#不计入合计威力的牌（暗置等）不参与——与威力加成的口径一致。
#返回 null 而不是空串：配合 is_null 原语判断，与「查询失败返回 null」的项目约定一致
func exec(player_id:int = -1):

	var id:int = EffectManager.resolve_player_id(player_id)
	var player_data:Dictionary = GameDataManager.get_player_data(id)
	if player_data == null or player_data.is_empty():
		return null
	var counts_power := CardCountsPower.new()
	var attacks:Array = []
	for card in player_data["played_cards"]:
		if !(card is BaseAttack) or !counts_power.exec(card, id):
			continue
		attacks.append(card)
	return from_cards(attacks)

#Only intersect the supplied attacks; callers decide membership and power eligibility.
#Both committed and preview queries reuse this pure algorithm.
static func from_cards(cards:Array):
	var shared:Array = []
	for card in cards:
		var attrs:Array = (card as BaseAttack)._attributes
		if shared.is_empty():
			shared = attrs.duplicate()
		else:
			shared = shared.filter(func(a): return attrs.has(a))
		if shared.is_empty():
			return null
	if shared.is_empty():
		return null
	return str(shared[0])
