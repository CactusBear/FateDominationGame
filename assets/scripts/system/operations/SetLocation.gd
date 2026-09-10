class_name SetLocation
extends RefCounted

func exec(setted_location:BaseLocation, player_id:int = -1, is_move:bool = true):

	player_id = EffectManager.resolve_player_id(player_id)
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	if setted_location._pl_num_limit <= setted_location._players.size():
		#show("目标位置已满")
		return
	var area:BaseMapArea
	for a:BaseMapArea in MapData.areas:
		if a._locations.has(setted_location):
			area = a
	if area._can_move_to == false and is_move:
		#show("无法移动至此区域")
		return
	player_data["location"] = setted_location
