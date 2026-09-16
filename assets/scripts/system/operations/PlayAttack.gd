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
	#卡面声明的打出条件(如"魔力需达到8点")与"需追加打出"：条件写在卡的数据里，不在入口写死
	if !PlayRules.can_play(attack, player_data):
		return false
	#局面级禁令（如安哥拉·曼纽系列局势牌的"宝具禁止使用"）按效果名查询全局面，
	#禁令声明在哪张牌上、禁什么属性由数据决定，出牌入口只认效果名
	if attack._attributes.has(Attributes.NOBLE_PHANTASM) and BoardHasEffect.new().exec(ForbidNoblePhantasmEffect.EFFECT_NAME):
		return false
	if attack._attributes.has(Attributes.SPECIAL) and BoardHasEffect.new().exec(ForbidSpecialAttackEffect.EFFECT_NAME):
		return false

	var play_limit = player_data["play_limit"] as BaseNumber
	#本回合已打出的攻击数直接数日志，不再维护一份 played_attacks_this_turn。
	#口径与界面提示共用 PlayRules.played_count，不在这里另写一份 filter
	var played_count:int = PlayRules.played_count(id, "attack")
	if !ignore_limit and played_count >= play_limit.number:
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
		var magic_before = pl_magic.number
		pl_magic.minus(BaseNumber.new(final_cost))
		#扣费与 EditMagic 同一套记录口径（本操作不派 MAGIC_DECREASE 时点，保持原有行为）
		GameLog.record_resource_change("magic", id, magic_before, pl_magic.number)
	attack._is_activating = true

	var playered_cards_arr = player_data["played_cards"] as Array
	playered_cards_arr.append(attack)
	#出牌即离手：从手牌移进打出区，手牌区不再显示
	(player_data["hand_cards"] as Array).erase(attack)

	#是否计入合计威力交给CardCountsPower判定(默认暗置牌不计，例外由卡上的效果声明)。
	#必须在入场后再判定，因为判定包含"是否在场上"这一条
	if CardCountsPower.new().exec(attack, id):
		var pl_power = player_data["power"] as BaseNumber
		pl_power.add(power)

	#日志：谁打出了哪张牌（供"本回合我打出了什么"这类历史查询）
	GameLog.record("play", id, -1, "", attack, ["play"],
		{"card_name": attack._name, "card_type": "attack", "extra": false})
	TimePointChecker.dynamic_time_point([TimePoints.PLAYED_CARD], id)
	return true

