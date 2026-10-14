class_name SetCardConcealed
extends RefCounted

#改变卡牌的明置/暗置状态，并实时同步玩家的合计威力。
#比较变更前后CardCountsPower：暗置仍计威力/永不计威力的声明例外不另扣。
#翻面差值的数值与来源只在此写一次；非手牌只翻面，不参与合计威力。
func exec(card:BaseCard, concealed:bool, player_id:int = -1, context:SessionContext = null) -> bool:
	#只继承已经验证的函数帧；裸直调必须带原context，不向当前会话领票。
	if context == null:
		var frame:Dictionary = EffectManager.execution_context()
		context = frame.get("context") if frame.get("ok", false) else null
	if not source_is_current(card, context):
		return false
	if card._is_concealed == concealed:
		return true

	if not (card is BaseHandCard):
		card.set_concealed(concealed)
		return source_is_current(card, context)

	var handcard = card as BaseHandCard
	var id = EffectManager.resolve_player_id(player_id)
	var player_data:Dictionary = GameDataManager.find_player_data(id)
	if player_data.is_empty():
		return false
	#保存原资源和容器；同ID新对象不能承接旧翻面尾部。
	var players:Dictionary = GameData.player_data_library
	var pl_power = player_data.get("power") as BaseNumber
	var played_cards:Array = player_data.get("played_cards", [])
	if pl_power == null:
		return false
	var counts_power = CardCountsPower.new()
	var counted_before:bool = counts_power.exec(handcard, id)
	if not target_is_current(card, context, id, players, player_data, pl_power, played_cards):
		return false
	handcard.set_concealed(concealed)
	if not target_is_current(card, context, id, players, player_data, pl_power, played_cards):
		return false
	var counted_after:bool = counts_power.exec(handcard, id)
	if not target_is_current(card, context, id, players, player_data, pl_power, played_cards):
		return false
	if counted_before == counted_after:
		return true

	var before = pl_power.number
	if counted_after:
		pl_power.add(handcard._power)
	else:
		pl_power.minus(handcard._power)
	if not target_is_current(card, context, id, players, player_data, pl_power, played_cards):
		return false
	#S-15唯一翻面差值来源写点，保留实际整卡delta；不新增分类/去重字段。
	PowerSources.record(id, "power", pl_power.number - before, null, context)
	if not target_is_current(card, context, id, players, player_data, pl_power, played_cards):
		return false
	#事件由EventResolver登记效果后统一派发；保持原亮出时点顺序。
	#亮出时点沿用本次原来源，否则无执行帧的显式调用里监听不会被派发。
	if not concealed and not (card is BaseEvent):
		TimePointChecker.card_revealed(card, context)
	return target_is_current(card, context, id, players, player_data, pl_power, played_cards)


#CloseCard复用同一只读源门；未绑定对象失败关闭，消费口绝不bind_origin。
static func source_is_current(card:BaseCard, context:SessionContext) -> bool:
	if not SessionGeneration.validate_context(context).ok:
		return false
	var source:Dictionary = SessionGeneration.origin_of(card)
	return source.ok and is_same(source.context.token(), context.token())


#来源与同局对象identity是两层资格，不以玩家ID或当前容器补原来源。
static func target_is_current(card:BaseCard, context:SessionContext, id:int, players:Dictionary, player_data:Dictionary, power:BaseNumber, played_cards:Array) -> bool:
	if not source_is_current(card, context):
		return false
	var current:Dictionary = GameDataManager.find_player_data(id)
	return is_same(players, GameData.player_data_library) and not current.is_empty() \
		and is_same(player_data, current) and is_same(power, current.get("power")) \
		and is_same(played_cards, current.get("played_cards"))
