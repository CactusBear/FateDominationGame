class_name DealPlayerCards
extends RefCounted

#按 GameProgress.card_deal_rules 给一名玩家(重新)发放从者的牌到牌库与技能区。
#换从者时用：从者换了，手里的牌也要跟着换成新从者的。
#发放规则(发哪些区、是否洗牌、是否暗置)全部在 card_deal_rules 数据里，这里只做触发
func exec(player_id:int = -1):

	GameProgress.deal_player_cards(player_id)
