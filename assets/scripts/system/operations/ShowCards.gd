class_name ShowCards
extends RefCounted

#把一组牌展示给指定玩家看（展示手牌、牌库顶、弃牌堆……）。只是"让人看到"：
#不改明置/暗置状态、不移动牌、不让效果生效——那些是 set_card_concealed、draw_card_by_card 的事。
#viewer_ids 为空表示展示给所有人；展示事实记进规则日志（type show_cards），供"本回合展示过"类查询。
#返回被展示的牌
func exec(cards:Array, viewer_ids:Array = [], shown_name:String = "") -> Array:
	var shown:Array = []
	var card_names:Array = []
	for card in cards:
		if card is BaseObject:
			shown.append(card)
			card_names.append(card.get_shown_name())
	var source:Dictionary = EffectManager.activating_source_info()
	GameLog.record("show_cards", int(source.get("by_player", -1)), -1, "", shown, ["show_cards"],
		{"card_names": card_names.duplicate(), "viewers": viewer_ids.duplicate(), "shown_name": shown_name})
	var text:String = "%s：%s" % [shown_name if shown_name != "" else "展示", "、".join(card_names) if !card_names.is_empty() else "没有牌"]
	if viewer_ids.is_empty():
		EffectManager.push_message(text, -1)
	else:
		for raw_id in viewer_ids:
			EffectManager.push_message(text, int(raw_id))
	return shown
