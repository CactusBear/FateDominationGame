class_name SetBattleResult
extends RefCounted

#改写本回合某个战场的胜负（直接指定胜者、追加胜者、只在败北者中计胜者）。
#只把改写声明记在战区上（_battle_override），真正的结算仍由 BattleResolver 做：
#它读到声明后按 mode 算出胜者，战果照常按胜者人数分配，之后清掉声明，不留到下一回合。
#mode：
#  "replace"      胜者直接定为 winner_ids（不比威力）
#  "add"          比威力得出的胜者之外再加上 winner_ids（共享胜利）
#  "losers_only"  只在带有"排除出胜负判定"效果（如【败北】）的玩家里比威力定胜者
#winner_ids 里不在该战场参战的玩家不计入。同一回合对同一战场再写一次会覆盖上一次。
#返回写入的声明；map_area 为空或 mode 不认识时返回 null
const MODES := ["replace", "add", "losers_only"]

func exec(map_area:BaseMapArea, winner_ids:Array = [], mode:String = "replace"):

	if map_area == null or !MODES.has(mode):
		return null
	var ids:Array = []
	for raw in winner_ids:
		if raw != null and !ids.has(int(raw)):
			ids.append(int(raw))
	map_area._battle_override = {"mode": mode, "winners": ids}
	return map_area._battle_override
