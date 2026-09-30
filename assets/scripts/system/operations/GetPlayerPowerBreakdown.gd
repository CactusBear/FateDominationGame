class_name GetPlayerPowerBreakdown
extends RefCounted

#按来源筛选后的合计威力（"排除局势与事件影响后的合计威力""令咒获得的合计威力"）。
#以 get_player_total_power 的当前合计威力为起点：
#  exclude_sources 不为空时，减去带这些来源标签、且此刻仍在生效的改动；
#  include_sources 不为空时，改为只统计带这些来源标签的改动之和（不含起点）。
#两者都空时就是当前合计威力。来源标签：
#  situation event master servant buff skill attack command_spell other rule（改动来自哪类对象）
#  self others（改动是这名玩家自己还是其他玩家发动的）
#  board（场上局势/事件牌持续声明的威力加成，只算在排除/统计 situation 或 event 时）
#  location_benefit（地利）
#多个标签是"命中任一"。改动的来源由 PowerSources 在改威力时自动记下，不需要写卡的人声明
func exec(player_id:int = -1, include_sources:Array = [], exclude_sources:Array = []) -> BaseNumber:

	var id:int = EffectManager.resolve_player_id(player_id)
	var b:Dictionary = GetPlayerTotalPower.breakdown(id)
	if include_sources.is_empty():
		var total:int = int(b.get("total", 0))
		if !exclude_sources.is_empty():
			total -= _sum(id, b, exclude_sources)
		return BaseNumber.new(total)
	return BaseNumber.new(_sum(id, b, include_sources))


#带任一标签的改动之和，加上按标签对应的固定分量（场上牌加成、地利）
func _sum(id:int, b:Dictionary, labels:Array) -> int:
	var total:int = 0
	for entry in PowerSources.active_entries(id):
		var tags:Array = entry.get("tags", [])
		for label in labels:
			if tags.has(str(label)):
				total += int(entry.get("data", {}).get("delta", 0))
				break
	if labels.has("board") or labels.has("situation") or labels.has("event"):
		total += int(b.get("board", 0))
	if labels.has("location_benefit"):
		total += int(b.get("location_benefit", 0))
	return total
