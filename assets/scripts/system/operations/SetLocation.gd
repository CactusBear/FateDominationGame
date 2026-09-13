class_name SetLocation
extends RefCounted

func exec(setted_location:BaseLocation, player_id:int = -1, is_move:bool = true):

	player_id = EffectManager.resolve_player_id(player_id)
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	if setted_location._pl_num_limit != -1 and setted_location._pl_num_limit <= setted_location._players.size():
		#show("目标位置已满")
		return
	var area:BaseMapArea
	for a:BaseMapArea in MapData.areas:
		if a._locations.has(setted_location):
			area = a
	if area._can_move_to == false and is_move:
		#show("无法移动至此区域")
		return
	#离开旧位置：把玩家从旧位置的_players里摘掉，否则旧位置的人数永远只增不减，
	#部署上限判定(_pl_num_limit)和"该位置有几人"的展示都会失真
	var old_location = player_data.get("location") as BaseLocation
	if old_location != null:
		old_location._players.erase(player_id)
	player_data["location"] = setted_location
	if !setted_location._players.has(player_id):
		setted_location._players.append(player_id)
