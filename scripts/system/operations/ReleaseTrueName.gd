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
#默认区域声明供显式来源调用复用，不复制一套展示规则。
const DEFAULT_SHOWN_AREAS:Array = ["servant_skills", "master_skills", "master._specials.SKILLS", "side.skills", "hand_cards", "played_cards", "deck", "discard"]

#保留原 bool：合法重复为 false，guard 待续为 true；不是异步最终完成回执。
func exec(player_id:int = -1, shown_areas:Array = DEFAULT_SHOWN_AREAS, context:Variant = null) -> bool:
	#缺省只继承已验证函数帧；整个翻牌尾部保存本次原来源。
	context = RegisterObjectEffects.captured_context(context)
	var resolved:Dictionary = RegisterObjectEffects.resolved_player_id(player_id, context)
	if not resolved.ok:
		return false
	var id:int = resolved.id
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
	#全部实际翻牌对象先验来源，避免旧对象在整批中途被拒绝。
	for card in seen:
		if card._is_concealed and not SetCardConcealed.source_is_current(card, context):
			return false
	var state:Dictionary = {"id": id, "cards": seen, "index": 0, "shown_count": 0,
		"context": context, "member": player_data, "phase": "show"}
	_resume_release(state)
	return state.phase != "rejected"

#只保存本次解放的翻牌尾部，不重新搜集区域或重派已经进入的亮出时点。
static func _resume_release(state:Dictionary) -> void:
	if state.phase != "show":
		return
	var id:int = state.id
	while state.index < state.cards.size():
		if not _source_member_is_current(state):
			state.phase = "rejected"
			return
		var card = state.cards[state.index]
		state.index += 1
		if card._is_concealed:
			var shown = preload("res://scripts/system/operation_router.gd").exec_registered("set_card_concealed", [card, false, id, state.context], state.context)
			#SetCardConcealed 的 bool 已明示成功/拒绝；拒绝不能记成功数量或续尾。
			if typeof(shown) != TYPE_BOOL or not shown:
				state.phase = "rejected"
				return
			state.shown_count += 1
			if EffectManager.defer_until_runtime_guard_complete(Callable(ReleaseTrueName, "_resume_release").bind(state), state.context):
				return
	if not _source_member_is_current(state):
		state.phase = "rejected"
		return
	state.phase = "done"
	#日志：谁解放了真名（"本局解放过真名吗"直接查这条事实）。
	#tags用客观时点名，与TimePointChecker记的时点日志口径一致
	GameLog.record("true_name_release", id, -1, "", null, [TimePoints.TRUE_NAME_RELEASE],
		{"shown_count": state.shown_count})
	TimePointChecker.dynamic_time_point([TimePoints.TRUE_NAME_RELEASE], id, null, state.context)


#只核验原 context 和同一成员对象，恢复口不新建或重新绑定来源。
static func _source_member_is_current(state:Dictionary) -> bool:
	return RegisterObjectEffects.source_is_current(state.context) \
		and is_same(state.member, GameDataManager.find_player_data(state.id))


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
