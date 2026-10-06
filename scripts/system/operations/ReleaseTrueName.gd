class_name ReleaseTrueName
extends RefCounted

#规则：有些卡牌拥有【真名解放】词条，使用这些卡牌后，立即展示你的从者概览卡
#与所有技能牌，并处于【真名解放】状态。
#本operation只做"解放"这一件事：把该展示的牌翻到明置、派发时点、记下事实。
#不判断"哪张牌带真名解放词条"——那由卡牌数据在自己的效果里调用本函数决定；
#也不负责隐藏（重新盖回去是另一条独立动作，见 HideTrueName），
#更不改威力/战果（那些是各张卡自己的效果）。
#默认展示实际持有的技能牌（包括已离开技能区的牌），不翻开普通暗置攻击。
#自定义区域仍由调用方声明；side.skills 是技能回收后的实际区域。
#返回是否真的发生了解放（已经是解放状态时返回false，不重复派时点）
func exec(player_id:int = -1, shown_areas:Array = ["servant_skills", "master_skills", "master._specials.SKILLS", "side.skills", "hand_cards", "played_cards", "deck", "discard"]) -> bool:

	var id = EffectManager.resolve_player_id(player_id)
	if !GameData.player_data_library.has(id):
		return false
	#已经解放过就不再解放：是否解放过查日志，不给玩家加状态字段
	if is_released(id):
		return false
	var player_data = GameDataManager.get_player_data(id) as Dictionary
	#展示从者概览卡与所有技能牌：翻面统一走SetCardConcealed，
	#它会按CardCountsPower同步合计威力，不在这里手动加减
	var seen:Array = []
	for area_key in shown_areas:
		var cards = player_data
		for key in str(area_key).split("."):
			if cards == null: break
			cards = cards.get(key)
		if !(cards is Array):
			continue
		for card in cards:
			if card is BaseSkill and not seen.has(card):
				seen.append(card)
	_resume_release({"id": id, "cards": seen, "index": 0, "shown_count": 0})
	return true

#只保存本次解放的翻牌尾部，不重新搜集区域或重派已经进入的亮出时点。
static func _resume_release(state:Dictionary) -> void:
	var id:int = state.id
	while state.index < state.cards.size():
		var card = state.cards[state.index]
		state.index += 1
		if card._is_concealed:
			state.shown_count += 1
			SetCardConcealed.new().exec(card, false, id)
			if EffectManager.defer_until_runtime_guard_complete(Callable(ReleaseTrueName, "_resume_release").bind(state)):
				return
	#日志：谁解放了真名（"本局解放过真名吗"直接查这条事实）。
	#tags用客观时点名，与TimePointChecker记的时点日志口径一致
	GameLog.record("true_name_release", id, -1, "", null, [TimePoints.TRUE_NAME_RELEASE],
		{"shown_count": state.shown_count})
	TimePointChecker.dynamic_time_point([TimePoints.TRUE_NAME_RELEASE], id)


#该玩家本局是否已处于真名解放状态：解放记一条、隐藏记一条，取最后一条判断。
#查询与写入放在同一处，避免调用方各自拼日志条件
static func is_released(player_id:int) -> bool:
	var entries:Array = GameLog.query({"actor": player_id}, null)
	var released:bool = false
	for entry in entries:
		var t:String = str(entry.get("type", ""))
		if t == "true_name_release":
			released = true
		elif t == "true_name_hidden":
			released = false
	return released
