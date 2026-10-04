class_name GetPlayerHandCards
extends RefCounted

#取出玩家手牌数组。牌库/弃牌/场上已有对应Get，手牌入口对齐它们，不另做筛选。
func exec(player_id:int = -1):

	player_id = EffectManager.resolve_player_id(player_id)
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["hand_cards"]
