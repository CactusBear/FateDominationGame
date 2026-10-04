class_name ModifyAttackPowerByAttribute
extends RefCounted

#按属性增减玩家的合计威力：场上每有一张匹配指定属性的攻击牌，合计威力就增减一份power_delta。
#不改动卡牌自身的_power，牌的印刷威力保持不变，改牌威力请用EditCardPower。
#required_attributes留空表示匹配所有攻击牌；
#传入attack时只判定这一张，不传则扫描该玩家场上所有攻击牌；
#exclude_attack在扫描时排除指定的一张牌，用于"其余攻击"这类自指效果；
#required_category限定只对某个类别生效(如卡面写"基础牌"就传"basic")，留空表示不限类别。
#min_power是"印刷威力至少达到多少才参与加成"的门槛，由调用方传入，
#留空(-1)表示不限——"基本威力≥4的攻击威力+1"这类规则用同一个开关表达，不写死数字。
#类别/门槛都由调用方声明，不在本操作里写死哪张卡该受限
func exec(required_attributes:Array, power_delta:BaseNumber = BaseNumber.new(0), player_id:int = -1, attack:BaseAttack = null, exclude_attack:BaseAttack = null, required_category:String = "", min_power:int = -1):

	var id = EffectManager.resolve_player_id(player_id)
	if power_delta.number == 0:
		return
	var counts_power = CardCountsPower.new()
	var total:int = 0
	if attack != null:
		#暗置等不计合计威力的牌不参与加成，是否计入统一由CardCountsPower判定
		if _match(attack, required_attributes, required_category, min_power) and counts_power.exec(attack, id):
			total = power_delta.number
	else:
		if !GameData.player_data_library.has(id):
			return
		var player_data:Dictionary = GameDataManager.get_player_data(id)
		for card in player_data["played_cards"]:
			if card is BaseAttack and _match(card, required_attributes, required_category, min_power) and counts_power.exec(card, id):
				if exclude_attack != null and card == exclude_attack:
					continue
				total += power_delta.number
	if total == 0:
		return
	#复用EditPower统一改写玩家的合计威力
	EditPower.new().exec(null, BaseNumber.new(total), id)


func _match(attack:BaseAttack, required_attributes:Array, required_category:String = "", min_power:int = -1) -> bool:
	if required_category != "" and str(attack.get("_category")) != required_category:
		return false
	if min_power >= 0 and (attack.numbers[1] as BaseNumber).number < min_power:
		return false
	if required_attributes.is_empty():
		return true
	for attr in required_attributes:
		if attack._attributes.has(attr):
			return true
	return false
