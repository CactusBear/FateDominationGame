class_name PlayAttack
extends RefCounted

#常规出牌：检查费用/魔力/出牌数量上限，扣费并把攻击牌计入合计威力。
#ignore_limit跳过play_limit常规出牌数量检查，供特殊效果(残留牌重新打出等)复用
func exec(attack:BaseAttack, player_id:int = -1, cost:BaseNumber = attack._cost, power:BaseNumber = attack._power, ignore_limit:bool = false) -> bool:
	if attack == null:
		return false

	var id = EffectManager.resolve_player_id(player_id)
	if !GameData.player_data_library.has(id):
		return false
	var player_data = GameDataManager.get_player_data(id) as Dictionary
	if player_data["is_out"]:
		return false
	#带有"无法打出卡牌"效果的buff(如【败北】)会阻止出牌，
	#但不影响已激活的牌和能力的其他使用。按效果名通用查询，不关心具体buff类型
	if PlayerBuffsHaveEffect.new().exec(CannotPlayCardsEffect.EFFECT_NAME, id):
		return false
	if GameProgress.get_current_phase().get("name", "") != "action":
		return false
	if GameProgress.current_player_id != id:
		return false
	if attack._is_activating:
		return false

	var play_limit = player_data["play_limit"] as BaseNumber
	var played_this_turn = player_data["played_attacks_this_turn"] as Array
	if !ignore_limit and played_this_turn.size() >= play_limit.number:
		return false

	#最终费用 = 印刷费用 - 玩家层折扣 - 卡牌自身折扣，折扣不会让费用变成负数
	var attack_cost_discount = player_data["attack_cost_discount"] as BaseNumber
	var card_cost_discount = attack._cost_discount as BaseNumber
	var final_cost = cost.number - attack_cost_discount.number - card_cost_discount.number
	if final_cost < 0:
		final_cost = 0
	TimePointChecker.dynamic_time_point([TimePoints.CARD_COST_CALCULATED], id)

	var pl_magic = player_data["magic"] as BaseNumber
	var is_magic_immune = player_data["is_magic_immune"] as bool
	if !is_magic_immune and pl_magic.number < final_cost:
		return false

	if !is_magic_immune:
		pl_magic.minus(BaseNumber.new(final_cost))
	attack._is_activating = true

	var playered_cards_arr = player_data["played_cards"] as Array
	playered_cards_arr.append(attack)
	played_this_turn.append(attack)
	#出牌即离手：从手牌移进打出区，手牌区不再显示
	(player_data["hand_cards"] as Array).erase(attack)

	#是否计入合计威力交给CardCountsPower判定(默认暗置牌不计，例外由卡上的效果声明)。
	#必须在入场后再判定，因为判定包含"是否在场上"这一条
	if CardCountsPower.new().exec(attack, id):
		var pl_power = player_data["power"] as BaseNumber
		pl_power.add(power)

	TimePointChecker.dynamic_time_point([TimePoints.PLAYED_CARD], id)
	return true

