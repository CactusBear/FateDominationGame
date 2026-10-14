class_name DealPlayerCards
extends RefCounted

#按 GameProgress.card_deal_rules 给一名玩家(重新)发放从者的牌到牌库与技能区。
#换从者时用：从者换了，手里的牌也要跟着换成新从者的。
#发放规则(发哪些区、是否洗牌、是否暗置)全部在 card_deal_rules 数据里，这里只做触发
func exec(player_id:int = -1) -> Dictionary:
	# 只继承可信执行器已验的原帧；无帧直接交回拒绝，不在消费者重签来源。
	var captured:Dictionary = EffectManager.execution_context()
	if not captured.ok:
		return captured
	# 发牌的成员/角色来源检查由原入口承担，Dictionary.ok 原样交回执行器。
	return GameProgress.deal_player_cards(player_id, captured.context)
