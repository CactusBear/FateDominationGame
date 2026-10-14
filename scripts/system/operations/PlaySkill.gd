class_name PlaySkill
extends RefCounted

func exec(skill:BaseSkill, player_id:int = -1, ignore_limit:bool = false, cost:BaseNumber = null, power:BaseNumber = null, allow_magic_overdraft:bool = false):
	# 消费口只继承已验函数帧；旧卡、无帧或未绑定对象不得首读默认数值。
	var source:Variant = RegisterObjectEffects.captured_context(null)
	if skill == null or not RegisterObjectEffects.source_is_current(source, skill):
		return false
	if cost == null:
		cost = skill._cost
	if power == null:
		power = skill._power

	if not ignore_limit and EffectManager.activating_eff == null:
		return false
	var id = EffectManager.resolve_player_id(player_id)
	var player_data:Dictionary = GameDataManager.find_player_data(id)
	if not GameData.player_data_library.has(id):
		return false
	# 保留本次对象身份；同 ID 的新字典不能承接旧出牌链。
	var context:Dictionary = {"source":source, "skill":skill, "players":GameData.player_data_library,
		"player":player_data, "magic":player_data.get("magic"), "game_over":GameProgress.is_game_over}
	#带有"无法打出卡牌"效果的buff(如【败北】)会阻止出牌，
	#但不影响已激活的牌和能力的其他使用。按效果名通用查询，不关心具体buff类型
	if PlayerBuffsHaveEffect.new().exec(CannotPlayCardsEffect.EFFECT_NAME, id):
		return false
	#卡面声明的打出条件与"需追加打出"，与攻击牌共用同一套判断
	if !PlayRules.can_play(skill, player_data):
		return false
	#局面禁令已由 PlayRules.can_play 统一校验，不因 ignore_limit 绕过。
	var pl_magic = player_data["magic"] as BaseNumber
	var is_magic_immune = player_data["is_magic_immune"] as bool
	var ignore_zone_limit = player_data["ignore_skill_zone_magic_limit"] as bool
	#技能区的卡需要足够魔力才能打出，门槛取自规则数字而非写死
	if !is_magic_immune and pl_magic.number < GameData.skill_zone_magic_limit.number:
		if !ignore_limit and !skill._ignore_limit and !ignore_zone_limit:
			#show_lack_of_magic()
			return false
	# 费用计算时点必须先于最终费用与可支付性判断；卡面减费才影响本次出牌。
	if not _context_is_current(id, context):
		return false
	TimePointChecker.dynamic_time_point([TimePoints.CARD_COST_CALCULATED], id, skill, source)
	if not _context_is_current(id, context):
		return false
	# 本同步入口没有费用续行状态；结算未完成时不得提前支付或入场。
	if EffectManager.runtime_guard_status().get("paused", false) or EffectManager.is_waiting_for_choice():
		return false
	#费用下限为 0：动态费用公式（如阵地建造的"16 - 回合数×2"）在后期会算成负数，
	#不取下限会让扣费反向加魔力。口径与 PlayAttack、RegularPlay.cost 完全一致
	var final_cost = cost.number
	if final_cost < 0:
		final_cost = 0
	# 支付原语复核当时余额；本次透支许可不绕过前置资格，且不派 MAGIC_DECREASE。
	if not _context_is_current(id, context):
		return false
	if not PayMagic.new().exec(BaseNumber.new(final_cost), id, "effect_skill", skill, false, allow_magic_overdraft, source, context.player, context.magic):
		return false
	if not _context_is_current(id, context):
		return false

	skill._is_activating = true

	var playered_cards_arr = player_data["played_cards"] as Array
	playered_cards_arr.append(skill)

	#是否计入合计威力交给CardCountsPower判定，必须在入场后再判定
	if CardCountsPower.new().exec(skill, id):
		var pl_power = player_data["power"] as BaseNumber
		pl_power.add(power)

	GameLog.record("play", id, -1, "", skill, ["play"],
		{"card_name": skill._name, "card_type": "skill", "extra": true, "concealed": skill._is_concealed})
	#词条规则在打出时点之前结算，理由同 PlayAttack
	if not _context_is_current(id, context):
		return false
	preload("res://scripts/system/operation_router.gd").exec_registered("apply_card_keywords", [skill, id], source)
	if not _context_is_current(id, context):
		return false
	TimePointChecker.card_revealed(skill, source)
	if not _context_is_current(id, context):
		return false
	TimePointChecker.dynamic_time_point([TimePoints.PLAYED_CARD], id, skill, source)
	return _context_is_current(id, context)


# 只读引用校验，不借创建式 getter 重新认证主体，也不刷新为新局字典。
func _context_is_current(id:int, context:Dictionary) -> bool:
	return RegisterObjectEffects.source_is_current(context.source, context.skill) \
		and is_same(GameData.player_data_library, context.players) \
		and GameData.player_data_library.has(id) \
		and is_same(GameDataManager.find_player_data(id), context.player) \
		and is_same(context.player.get("magic"), context.magic) \
		and GameProgress.is_game_over == context.game_over
