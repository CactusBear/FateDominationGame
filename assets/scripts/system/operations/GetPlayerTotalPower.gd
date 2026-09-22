class_name GetPlayerTotalPower
extends RefCounted

#查一名玩家此刻的合计威力（比较胜负用的那个值）及其构成。
#公式：出牌威力 power + 合计威力加成 total_power_bonus + 场上牌加成 + 当前实际享有的地利。
#
#为什么要独立成一个查询：这个公式原先在战斗结算里写一份、界面里另写五份，
#任何一处口径变了就会出现"界面显示 12、结算却按 10 判"这类对不上的问题
#（本项目已因此出过误报）。结算与界面共用这里唯一一份实现。
#
#"马上算出来"靠的就是它：四个分量都是随时可读的当前值——
#total_power_bonus 由效果实时写入，场上牌加成由 BoardPowerQuery 纯查询即时求值，
#地利由 GetEffectiveLocationBenefit 即时判定。任何时候调用都是当前真值，
#不必等到战斗阶段才知道自己多少威力。本查询只读不写，随时可调用。

#返回合计威力数值
#preview_power：尚未入场的预估增量（出牌区在确认前用，见 breakdown）
func exec(player_id:int = -1, preview_power:int = 0, preview_cards:Array = [], preview_hidden:Array = []) -> int:
	return int(breakdown(player_id, preview_power, preview_cards, preview_hidden).get("total", 0))


#返回威力构成明细，供战报与界面悬浮提示逐项展示：
#{power:出牌威力, bonus:合计威力加成, board:场上牌加成, location_benefit:地利,
# preview:尚未入场的预估增量, total:比较用总威力}
#preview_power 由调用方计算并传入（出牌区用 CardCountsPower.counts_when_played 逐张累加），
#preview_cards / preview_hidden 仅供场上牌查询建立只读预览，不重复计算 preview_power。
#不传预览参数时结果与原先完全一致，
#结算路径（battle_resolver）因此不会把尚未确认的选择算进胜负。
#找不到该玩家时各项为 0——查询不该因为玩家不存在就报错，调用方按 0 处理即可
static func breakdown(player_id:int = -1, preview_power:int = 0, preview_cards:Array = [], preview_hidden:Array = []) -> Dictionary:
	var id:int = EffectManager.resolve_player_id(player_id)
	var empty := {"power": 0, "bonus": 0, "board": 0, "location_benefit": 0, "preview": 0, "total": 0}
	if !GameData.player_data_library.has(id):
		return empty
	var pl_data = GameDataManager.get_player_data(id) as Dictionary
	if pl_data == null:
		return empty
	var base_power:int = (pl_data["power"] as BaseNumber).number
	#合计威力加成只在比较胜负时叠加、不写回 power 本身，避免 power 被重复累加
	var bonus:int = (pl_data["total_power_bonus"] as BaseNumber).number
	#场上明置的事件牌与局势牌声明的威力加成（协同、占领高地、对未来的憧憬等）。
	#单独一项而不并进 power：并进去的话战报只会显示一个变大的"出牌威力"，
	#玩家看不出这几点是哪张场上牌给的，也无法核对
	var board:int = BoardPowerQuery.total(id, preview_cards, preview_hidden)
	#地利的两条例外（战区声明不提供地利、只有部署到该位置才算）都在这个查询里处理
	var benefit:int = GetEffectiveLocationBenefit.new().exec(id)
	return {
		"power": base_power,
		"bonus": bonus,
		"board": board,
		"location_benefit": benefit,
		"preview": preview_power,
		"total": base_power + bonus + board + benefit + preview_power,
	}


#把构成明细排成给人看的文本行，供战报与界面悬浮提示共用。
#只列非零项（除出牌威力始终列出），零项列出来只是噪音
static func breakdown_lines(player_id:int = -1, preview_power:int = 0, preview_cards:Array = [], preview_hidden:Array = []) -> Array:
	var b:Dictionary = breakdown(player_id, preview_power, preview_cards, preview_hidden)
	var lines:Array = ["出牌威力 %d" % int(b["power"])]
	for item in [
		{"key": "bonus", "label": "合计威力加成"},
		{"key": "board", "label": "场上牌加成"},
		{"key": "location_benefit", "label": "地利"},
		{"key": "preview", "label": "待确认出牌"},
	]:
		var v:int = int(b[item["key"]])
		if v != 0:
			lines.append("%s %+d" % [item["label"], v])
	lines.append("合计 %d" % int(b["total"]))
	return lines
