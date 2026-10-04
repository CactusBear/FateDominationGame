class_name HideTrueName
extends RefCounted

#规则：部分卡牌效果可以【隐藏】你的真名，将你的从者概览卡重新反面，
#表示你失去了【真名解放】状态，重新【真名隐藏】。
#与 ReleaseTrueName 成对，两者是两个独立动作（有效果只解放、有效果只隐藏），
#不合并成一个带开关的函数：合并后调用方每次都要传一个布尔，
#而"解放"和"隐藏"各自还有不同的展示范围与时点。
#要盖回去哪些区域由 hidden_areas 传入，默认与解放时展示的区域一致。
#返回是否真的发生了隐藏（本来就没解放时返回false）
func exec(player_id:int = -1, hidden_areas:Array = ["servant_skills", "master_skills", "master._specials.SKILLS", "side.skills"]) -> bool:

	var id = EffectManager.resolve_player_id(player_id)
	if !GameData.player_data_library.has(id):
		return false
	if !ReleaseTrueName.is_released(id):
		return false
	var player_data = GameDataManager.get_player_data(id) as Dictionary
	var hidden_count:int = 0
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
		if not card._is_concealed:
			SetCardConcealed.new().exec(card, true, id)
			hidden_count += 1
	GameLog.record("true_name_hidden", id, -1, "", null, [TimePoints.TRUE_NAME_HIDDEN],
		{"hidden_count": hidden_count})
	TimePointChecker.dynamic_time_point([TimePoints.TRUE_NAME_HIDDEN], id)
	return true
