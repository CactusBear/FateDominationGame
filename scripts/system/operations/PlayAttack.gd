class_name PlayAttack
extends RefCounted

#常规出牌：检查费用/魔力/出牌数量上限，扣费并把攻击牌计入合计威力。
#ignore_limit跳过play_limit常规出牌数量检查，供特殊效果(残留牌重新打出等)复用
func exec(attack:BaseAttack, player_id:int = -1, cost:BaseNumber = null, power:BaseNumber = null, ignore_limit:bool = false, allow_magic_overdraft:bool = false) -> bool:
	if attack == null:
		return false
	if cost == null:
		cost = attack._cost
	if power == null:
		power = attack._power
	# 资格判定统一由公开纯查询承载；这里在通过后才进入费用/入场副作用。
	var affordance:Dictionary = preload("res://scripts/system/play_affordance_query.gd").new().check(attack, player_id, ignore_limit)
	if !affordance.get("ok", false):
		return false
	var id:int = int(affordance.get("player_id", -1))
	# 动作在费用回调前捕获已验帧的原来源与两项身份，消费时不刷新。
	var source:Variant = RegisterObjectEffects.captured_context(null)
	if not RegisterObjectEffects.source_is_current(source):
		return false
	#带词条的牌入场后必须结算词条；来源不合格时在任何写入前拒绝，避免“已入场却报失败”的半状态。
	if not attack._keywords.is_empty() and not RegisterObjectEffects.source_is_current(source, attack):
		return false
	var player_data:Dictionary = GameDataManager.find_player_data(id)
	var magic:BaseNumber = player_data.get("magic") as BaseNumber
	if magic == null:
		return false

	#最终费用 = 印刷费用 - 玩家层折扣 - 卡牌自身折扣，折扣不会让费用变成负数
	var attack_cost_discount = player_data["attack_cost_discount"] as BaseNumber
	var card_cost_discount = attack._cost_discount as BaseNumber
	# 先派费用计算时点，费用修正才会作用于本次实际扣费。
	TimePointChecker.dynamic_time_point([TimePoints.CARD_COST_CALCULATED], id, attack, source)
	# 本同步入口不能把尚未完成的费用监听当作已完成报价。
	if EffectManager.runtime_guard_status().get("paused", false) or EffectManager.is_waiting_for_choice():
		return false
	var final_cost = cost.number - attack_cost_discount.number - card_cost_discount.number
	if final_cost < 0:
		final_cost = 0

	# 支付原语复核当时余额；保留本入口不派 MAGIC_DECREASE 的原有语义。
	if not PayMagic.new().exec(BaseNumber.new(final_cost), id, "effect_attack", attack, false, allow_magic_overdraft, source, player_data, magic):
		return false
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
		{"card_name": attack._name, "card_type": "attack", "extra": true, "concealed": attack._is_concealed})
	#词条带来的规则行为（如【真名解放】）在打出时点之前结算：
	#规则是"使用带此词条的牌后立即解放"，而有些牌监听 self_true_name_release，
	#顺序反了它们就接不上这次解放
	#词条结算显式带本次原来源并消费结果；被拒不能冒称打出成功。
	#无词条的牌没有规则动作，不经路由（路由在无来源时会拒绝，空操作不应因此失败）。
	if not attack._keywords.is_empty():
		var keyword_applied = preload("res://scripts/system/operation_router.gd").exec_registered("apply_card_keywords", [attack, id, source], source)
		if typeof(keyword_applied) != TYPE_BOOL or not keyword_applied:
			return false
	TimePointChecker.card_revealed(attack, source)
	TimePointChecker.dynamic_time_point([TimePoints.PLAYED_CARD], id, attack, source)
	return true
