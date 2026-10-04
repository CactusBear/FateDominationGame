class_name PowerSources
extends RefCounted

#合计威力的来源记账。改合计威力的入口（EditPower、EditDataNumber 改 total_power_bonus、EditCardPower）
#在改完之后调 record，把"变了多少、因为哪类对象、谁发动的"记进规则日志；
#get_player_power_breakdown 读这些记录，回答"排除局势/事件/他人能力之后是多少"这类问题。
#来源类型取正在结算的效果所属对象的真实类型（EffectManager.object_source_kind），不需要调用方传参，
#也不按名字猜。没有正在结算的效果（常规出牌、规则流程）时来源记为 rule


#来源标签：一条记录同时带类型标签与"是谁的能力"标签，查询按标签交集筛。
#  类型：situation event master servant buff skill attack command_spell other rule
#  归属：self（这名玩家自己发动的）others（其他玩家发动的）；场上牌与规则没有归属标签
static func record(player_id:int, field:String, delta, card = null) -> void:
	if delta == null or delta == 0:
		return
	var info:Dictionary = EffectManager.activating_source_info()
	var by:int = int(info.get("by_player", -1))
	var tags:Array = [str(info.get("source_kind", "rule")), field]
	if by >= 0:
		tags.append("self" if by == player_id else "others")
	GameLog.record("power_source", player_id, by, "", card, tags,
		{"delta": delta, "field": field, "source_name": str(info.get("source_name", ""))})


#本回合仍在生效的来源记录。出牌威力与合计威力加成只在本回合有效（回合结束重建/归零）；
#改卡牌威力的记录只要那张牌此刻仍计入合计威力就一直有效（残留牌跨回合也算）
static func active_entries(player_id:int) -> Array:
	var result:Array = []
	for entry in GameLog.query({"type": "power_source", "actor": player_id}, null):
		var field:String = str(entry.get("data", {}).get("field", ""))
		if field == "card_power":
			var card = entry.get("object")
			if card is BaseHandCard and CardCountsPower.new().exec(card, player_id):
				result.append(entry)
		elif int(entry.get("round", -1)) == GameLog.current_round:
			result.append(entry)
	return result
