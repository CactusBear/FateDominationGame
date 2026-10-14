class_name HideTrueName
extends RefCounted

#规则：部分卡牌效果可以【隐藏】你的真名，将你的从者概览卡重新反面，
#表示你失去了【真名解放】状态，重新【真名隐藏】。
#与 ReleaseTrueName 成对，两者是两个独立动作（有效果只解放、有效果只隐藏），
#不合并成一个带开关的函数：合并后调用方每次都要传一个布尔，
#而"解放"和"隐藏"各自还有不同的展示范围与时点。
#要盖回去哪些区域由 hidden_areas 传入，默认与解放时展示的区域一致。
#返回是否真的发生了隐藏（本来就没解放时返回false）
const DEFAULT_HIDDEN_AREAS:Array = ["servant_skills", "master_skills", "master._specials.SKILLS", "side.skills"]

func exec(player_id:int = -1, hidden_areas:Array = DEFAULT_HIDDEN_AREAS, context:Variant = null) -> bool:
	#缺省只继承已验证函数帧；隐藏与解放各自保存原来源，不合并业务。
	context = RegisterObjectEffects.captured_context(context)
	var resolved:Dictionary = RegisterObjectEffects.resolved_player_id(player_id, context)
	if not resolved.ok:
		return false
	var id:int = resolved.id
	if !GameData.player_data_library.has(id):
		return false
	if !ReleaseTrueName.is_released(id):
		return false
	var player_data = GameDataManager.get_player_data(id) as Dictionary
	var seen:Array = []
	for area_key in hidden_areas:
		var cards = player_data
		for key in str(area_key).split("."):
			if cards == null:
				break
			cards = cards.get(key)
		if !(cards is Array):
			continue
		for card in cards:
			if card is BaseSkill and not seen.has(card):
				seen.append(card)
	for card in seen:
		if not card._is_concealed and not SetCardConcealed.source_is_current(card, context):
			return false
	var state:Dictionary = {"id": id, "cards": seen, "index": 0, "hidden_count": 0,
		"context": context, "member": player_data, "phase": "hide"}
	_resume_hide(state)
	#与解放一致，待续不冒称最终完成；同步拒绝仍沿原 bool 返回 false。
	return state.phase != "rejected"


#不重新搜区域；重复/迟到续行不能再翻牌或发成功事实。
static func _resume_hide(state:Dictionary) -> void:
	if state.phase != "hide":
		return
	var id:int = state.id
	while state.index < state.cards.size():
		if not ReleaseTrueName._source_member_is_current(state):
			state.phase = "rejected"
			return
		var card = state.cards[state.index]
		state.index += 1
		if not card._is_concealed:
			var hidden = preload("res://scripts/system/operation_router.gd").exec_registered("set_card_concealed", [card, true, id, state.context], state.context)
			if typeof(hidden) != TYPE_BOOL or not hidden:
				state.phase = "rejected"
				return
			state.hidden_count += 1
			if EffectManager.defer_until_runtime_guard_complete(Callable(HideTrueName, "_resume_hide").bind(state), state.context):
				return
	if not ReleaseTrueName._source_member_is_current(state):
		state.phase = "rejected"
		return
	state.phase = "done"
	GameLog.record("true_name_hidden", id, -1, "", null, [TimePoints.TRUE_NAME_HIDDEN],
		{"hidden_count": state.hidden_count})
	TimePointChecker.dynamic_time_point([TimePoints.TRUE_NAME_HIDDEN], id, null, state.context)
