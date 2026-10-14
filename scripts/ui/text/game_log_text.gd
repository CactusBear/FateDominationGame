class_name GameLogText
extends RefCounted

## 日志展示文本；玩家显示名统一使用 EffectManager 的纯查询契约。
const CardDesc = preload("res://scripts/ui/text/card_desc_text.gd")

static func line(e: Dictionary) -> String:
	var round_num: int = int(e.get("round", 0))
	var phase_name: String = str(e.get("phase", ""))
	var phase_zh: String = ""
	match phase_name:
		"prepare": phase_zh = "准备"
		"outpost": phase_zh = "前哨"
		"action": phase_zh = "行动"
		"battle": phase_zh = "战斗"
		"end": phase_zh = "结束"
		_: phase_zh = phase_name
	var tag: String = "[第%d回合" % round_num + ("·%s]" % phase_zh if phase_zh != "" else "]")
	var actor_id: int = int(e.get("actor", -1))
	var actor_name: String = EffectManager.player_shown_name(actor_id) if actor_id >= 0 else ""
	var e_type: String = str(e.get("type", ""))
	var place: String = str(e.get("place", ""))
	match e_type:
		"deploy":
			return "%s %s 部署至【%s】" % [tag, actor_name, place]
		"move":
			return "%s %s 移动至【%s】" % [tag, actor_name, place]
		"command_spell_used":
			return "%s %s 使用令咒" % [tag, actor_name]
		"draw":
			# 抽到的具体牌属于隐藏信息；事实日志保留对象供规则查询，玩家战报只公布抽牌动作。
			return "%s %s 抽牌" % [tag, actor_name]
		"refill_hand":
			return "%s %s 补充手牌" % [tag, actor_name]
		"reshuffle_discard":
			return "%s %s 将弃牌洗入牌库" % [tag, actor_name]
		"magic_add", "magic_decrease", "score_add", "score_decrease":
			var resource_name: String = "魔力" if e_type.begins_with("magic") else "战果"
			var delta = e.get("data", {}).get("delta", 0)
			if e_type == "magic_decrease":
				var payment: bool = e.get("tags", []).has("magic_spend")
				var purpose: String = str(e.get("data", {}).get("purpose", ""))
				var uses: Dictionary = {"regular_play":"常规出牌", "effect_attack":"打出攻击", "effect_skill":"打出技能", "move":"移动", "effect_cost":"发动能力"}
				var use_text: String = " · " + str(uses.get(purpose, purpose)) if payment and purpose != "" else ""
				return "%s %s %s魔力%d%s" % [tag, actor_name, "支付" if payment else "失去", absi(int(delta)), use_text]
			return "%s %s %s %+d" % [tag, actor_name, resource_name, delta]
		"eliminated":
			return "%s %s 被淘汰" % [tag, actor_name]
		"true_name_release":
			return "%s %s 解放真名" % [tag, actor_name]
		"true_name_hidden":
			return "%s %s 隐藏真名" % [tag, actor_name]
		"score_add", "score_decrease":
			var score_data: Dictionary = e.get("data", {})
			var delta_score: int = int(score_data.get("delta", 0))
			var verb: String = "获得" if e_type == "score_add" else "失去"
			return "%s %s %s战果%s，当前%s" % [tag, actor_name, verb, abs(delta_score), int(score_data.get("now", 0))]
		"game_end":
			var winner_names: Array[String] = []
			for winner_id in e.get("data", {}).get("winners", []):
				winner_names.append(EffectManager.player_shown_name(int(winner_id)))
			return "%s 对局结束：圣杯溢出，全员判负" % tag if winner_names.is_empty() else "%s 对局结束，胜者：%s" % [tag, "、".join(winner_names)]
		"play":
			var played = e.get("object")
			var card_name: String = CardDesc.shown_name(played) if played != null else str(e.get("data", {}).get("card_name", ""))
			return "%s %s 打出%s%s" % [tag, actor_name, ("【%s】" % card_name) if card_name != "" else "牌", " · 暗置" if bool(e.get("data", {}).get("concealed", false)) else ""]
		"regular_play":
			return "%s %s 完成常规出牌，打出%s" % [tag, actor_name, str(e.get("data", {}).get("count", 0))]
		"effect":
			var data: Dictionary = e.get("data", {})
			var shown_effect: String = str(data.get("shown_effect", ""))
			if shown_effect == "" or not bool(data.get("applied", false)):
				return ""
			var source_name: String = str(data.get("source_name", ""))
			var points: Array = data.get("trigger_time_points", [])
			var shown_points: Array[String] = []
			for point in points:
				var shown_point: String = str(TimePoints.shown_time_points.get(str(point), ""))
				if shown_point != "" and not shown_points.has(shown_point):
					shown_points.append(shown_point)
			var when: String = " · " + "、".join(shown_points) if not shown_points.is_empty() else ""
			var source_text: String = "【%s】" % source_name if source_name != "" else ""
			return "%s %s%s发动%s：%s" % [tag, actor_name, when, source_text if source_text != "" else "效果", shown_effect]
		"option_used":
			#秘密选择只进规则日志，战报不公开选了哪一项（公开与否由发起选择的效果决定）
			if (e.get("tags", []) as Array).has("secret_choice"):
				return ""
			var option_text: String = str(e.get("data", {}).get("option_name", ""))
			return "%s %s 选择【%s】" % [tag, actor_name, option_text] if option_text != "" else ""
		"time_point":
			return ""
		"battle":
			return "%s 【%s】完成战斗结算" % [tag, place]
		_:
			return ""

