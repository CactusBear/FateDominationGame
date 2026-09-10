class_name FindPlayerArrayContaining
extends RefCounted

#在玩家各区域里找出包含该对象的那一个数组。只查询，不移动。
#找到后由DrawCardByCard/RemoveFromArray处理去向，这样移除游戏和换区可以共用。
func exec(item, player_id:int = -1):

	var id = EffectManager.resolve_player_id(player_id)
	var player_data:Dictionary = GameDataManager.get_player_data(id)
	var zones:Array = [
		player_data["deck"],
		player_data["hand_cards"],
		player_data["played_cards"],
		player_data["discard"],
		player_data["master_skills"],
		player_data["servant_skills"],
		player_data["buffs"],
		player_data["command_spell"],
		player_data["side"]["deck"],
		player_data["side"]["discard"],
		player_data["side"]["hand_cards"],
		player_data["side"]["skills"],
		player_data["side"]["buffs"],
		player_data["side"]["others"],
		player_data["side"]["command_spell"],
		player_data["out_of_game"]["attacks"],
		player_data["out_of_game"]["skills"],
		player_data["out_of_game"]["buffs"],
		player_data["out_of_game"]["others"],
		player_data["out_of_game"]["command_spell"]
	]
	for zone in zones:
		if zone is Array and zone.has(item):
			return zone
	return null
