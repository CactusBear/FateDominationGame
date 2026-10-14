class_name CloseCard
extends RefCounted

const operation_router = preload("res://scripts/system/operation_router.gd")

#关闭已打出手牌：技能返回技能区；攻击委托翻面唯一写点。
func exec(card:BaseHandCard, player_id:int = -1, context:SessionContext = null) -> bool:
	if context == null:
		var frame:Dictionary = EffectManager.execution_context()
		context = frame.get("context") if frame.get("ok", false) else null
	#先验原来源，再读卡状态/owner；旧卡不得以新局同ID获得资格。
	if not SetCardConcealed.source_is_current(card, context):
		return false
	if card._is_closed:
		return true

	var id = EffectManager.resolve_player_id(player_id)
	var player_data:Dictionary = GameDataManager.find_player_data(id)
	if player_data.is_empty():
		return false
	var players:Dictionary = GameData.player_data_library
	var pl_power = player_data.get("power") as BaseNumber
	var played_cards:Array = player_data.get("played_cards", [])
	if pl_power == null:
		return false
	#即将关闭：允许取消；同步监听回来后只能消费原context与原资源身份。
	var action:Dictionary = EffectManager.begin_pending_action(TimePoints.BEFORE_CARD_CLOSE, id, {"card":card}, card)
	if not SetCardConcealed.target_is_current(card, context, id, players, player_data, pl_power, played_cards):
		return false
	if action.get("cancelled", false):
		return false
	if EffectManager.runtime_guard_status().get("paused", false) or EffectManager.is_waiting_for_choice():
		return false

	card.set_closed(true)
	if not SetCardConcealed.target_is_current(card, context, id, players, player_data, pl_power, played_cards):
		return false
	if card is BaseSkill:
		card.set_if_activating(false)
		if not SetCardConcealed.target_is_current(card, context, id, players, player_data, pl_power, played_cards):
			return false
		#S-15非翻面例外：保留单次注册EditPower，不委托翻面再扣/再record。
		var counted:bool = CardCountsPower.new().exec(card, id)
		if not SetCardConcealed.target_is_current(card, context, id, players, player_data, pl_power, played_cards):
			return false
		if counted:
			operation_router.exec_registered("edit_power", [null, BaseNumber.new(-card._power.number), id, context], context)
		if not SetCardConcealed.target_is_current(card, context, id, players, player_data, pl_power, played_cards):
			return false
		played_cards.erase(card)
		#区迁移例外：离场后恢复明置，不另登记翻面来源。
		card.set_concealed(false)
		if not SetCardConcealed.target_is_current(card, context, id, players, player_data, pl_power, played_cards):
			return false
		operation_router.exec_registered("add_skill_to_skill_zone", [card, id], context)
	elif card is BaseAttack:
		#显式透传已捕获context；两层不各记一次差值。
		if not operation_router.exec_registered("set_card_concealed", [card, true, id, context], context):
			return false

	if not SetCardConcealed.target_is_current(card, context, id, players, player_data, pl_power, played_cards):
		return false
	# 带上被关闭的牌与原来源：source_bound 效果据此只响应“自己这张”被关闭
	TimePointChecker.dynamic_time_point([TimePoints.CARD_CLOSED], id, card, context)
	return SetCardConcealed.target_is_current(card, context, id, players, player_data, pl_power, played_cards)
