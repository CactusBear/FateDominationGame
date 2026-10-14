class_name AddAttack
extends RefCounted

func exec(attack:BaseAttack, player_id:int = -1, power:BaseNumber = null):
	if attack == null:
		return false
	if power == null:
		power = attack._power

	#只继承已验证函数帧，入场后的词条与时点沿用同一来源。
	var source:Variant = RegisterObjectEffects.captured_context(null)
	#带词条的牌入场后必须结算词条；来源不合格时在任何写入前拒绝，避免“已入场却报失败”的半状态。
	if not attack._keywords.is_empty() and not RegisterObjectEffects.source_is_current(source, attack):
		return false
	var id = EffectManager.resolve_player_id(player_id)
	var player_data = GameDataManager.get_player_data(id)

	attack._is_activating = true

	var playered_cards_arr = player_data["played_cards"] as Array
	playered_cards_arr.append(attack)

	#是否计入合计威力交给CardCountsPower判定，必须在入场后再判定
	if CardCountsPower.new().exec(attack, id):
		var pl_power = player_data["power"] as BaseNumber
		pl_power.add(power)

	GameLog.record("play", id, -1, "", attack, ["play", "extra"],
		{"card_name": attack._name, "card_type": "attack", "extra": true, "concealed": attack._is_concealed})
	#词条规则在打出时点之前结算，理由同 PlayAttack。
	#追加打出也算"使用了这张牌"，所以同样适用
	#词条结算显式带本次原来源并消费结果；被拒不能冒称打出成功。
	#无词条的牌没有规则动作，不经路由（路由在无来源时会拒绝，空操作不应因此失败）。
	if not attack._keywords.is_empty():
		var keyword_applied = preload("res://scripts/system/operation_router.gd").exec_registered("apply_card_keywords", [attack, id, source], source)
		if typeof(keyword_applied) != TYPE_BOOL or not keyword_applied:
			return false
	TimePointChecker.card_revealed(attack, source)
	TimePointChecker.dynamic_time_point([TimePoints.PLAYED_CARD], id, attack, source)
	return true
