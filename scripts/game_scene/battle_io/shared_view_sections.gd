extends RefCounted

## 纯显示闭包：输入必须是当前 observer 的过滤 player 与已选定构成。
## 不读取 source/session/规则，不创建节点、动画或 zoom，也不扩大卡牌可见范围。
static func render_self_power(stats: Control, player: Dictionary, breakdown: Dictionary, tooltip_enabled: bool = true) -> void:
	var power: Label = stats.get_node("PowerRow/Power")
	var parts: Label = stats.get_node("PowerRow/BreakScroll/Break")
	var scroll: Control = stats.get_node("PowerRow/BreakScroll")
	if player.is_empty():
		power.text = ""
		power.tooltip_text = ""
		parts.text = ""
		scroll.hide()
		return
	power.text = BaseNumber.display_text(breakdown.get("total", player.get("total_power", 0)))
	var lines: Array[String] = []
	if breakdown.has("power"):
		lines.append("出牌 " + BaseNumber.display_text(breakdown.power + breakdown.get("preview", 0)))
	for pair in [["location_benefit", "地利"], ["board", "场上"], ["bonus", "加成"]]:
		if breakdown.get(pair[0], 0) != 0:
			lines.append(pair[1] + " " + BaseNumber.display_text(breakdown[pair[0]]))
	parts.text = " + ".join(lines)
	scroll.visible = not lines.is_empty()
	if tooltip_enabled:
		power.tooltip_text = "\n".join(power_lines({"power_breakdown": breakdown}))

## 兼容抽屉/本人 tooltip 的既有项目顺序与小数显示口径。
static func power_lines(player: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var breakdown: Dictionary = player.get("power_breakdown", {})
	for item in [["power", "出牌威力"], ["bonus", "合计威力加成"], ["board", "场上牌加成"], ["location_benefit", "地利"], ["preview", "待确认出牌"], ["total", "合计"]]:
		if not breakdown.has(item[0]):
			continue
		var value = breakdown[item[0]]
		if value == 0 and item[0] not in ["power", "total"]:
			continue
		result.append("%s %s%s" % [item[1], "+" if value > 0 and item[0] not in ["power", "total"] else "", BaseNumber.display_text(value)])
	return result

## 公共战斗摘要文字：仅消费调用者已授权的 summary/players 投影。
## 保留网络原文案、区域/赢家顺序与缺名字 fallback；不反查来源或规则对象。
static func public_battle_result_lines(summary: Dictionary, players: Array) -> Array[String]:
	var out: Array[String] = []
	for area_name in summary:
		var detail: Dictionary = summary[area_name]
		if not bool(detail.get("needs_win", true)):
			out.append("【%s】无需战斗，在场者共同获得战果" % area_name)
			continue
		var names := PackedStringArray()
		for winner_id in detail.get("winners", []):
			var winner: Dictionary = {}
			for player in players:
				if player.id == int(winner_id):
					winner = player
					break
			names.append(str(winner.get("master", {}).get("name", winner.get("player_name", ""))))
		out.append("【%s】%s，最高威力 %s" % [area_name, "无人可获胜，战区战果保留" if names.is_empty() else "胜者：" + "、".join(names), BaseNumber.display_text(detail.get("highest_power", 0))])
	return out