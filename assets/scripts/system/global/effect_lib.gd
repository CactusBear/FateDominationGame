extends Node


var null_func = do_nothing
func do_nothing():
	pass
	
	

#编辑数值(记得写发信号)
func set_player_data(key_name:String, value, player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	player_data[key_name] = value


func edit_magic(set_num:int = -1, vary_num:int = 0, player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	if set_num != -1:
		player_data["magic"] = set_num
	player_data["magic"] += vary_num
	pass

func edit_score(set_num:int = -1, vary_num:int = 0, player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	if set_num != -1:
		player_data["score"] = set_num
	player_data["score"] += vary_num
	pass
	
func edit_power(set_num:int = -1, vary_num:int = 0, player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	if set_num != -1:
		player_data["power"] = set_num
	player_data["power"] += vary_num
	pass

func move_location(move_location_num:int, player_id:int = GameData.player_id, ignore_limit:bool = false):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	var location:Dictionary = player_data["location"]
	var area:String
	for key in location.keys():
		area = key
	match area:
		GameData.MAGIC_WORKSHOP:
			match move_location_num:
				1:
					location = GameData.MIYAMA_2
				2:
					location = GameData.SHINTO_2
				3:
					var scout:Array = GameData.location_data["scout"]
					if !ignore_limit and get_num_of_pl_in_map_area("scout") >= 1:
						#show("目标地点上限已满")
						return
					for pos in scout:
						if pos == -1:
							location = GameData.SCOUT_0
							return
						if pos is Array:
							location = GameData.SCOUT_1
		GameData.MIYAMA:
			match move_location_num:
				1:
					location = GameData.SHINTO_2
				2:
					var scout:Array = GameData.location_data["scout"]
					if !ignore_limit and get_num_of_pl_in_map_area("scout") >= 1:
						#show("目标地点上限已满")
						return
					for pos in scout:
						if pos == -1:
							location = GameData.SCOUT_0
							return
						if pos is Array:
							location = GameData.SCOUT_1
				-1:
					var magic_workshop:Array = GameData.location_data["magic_workshop"]
					if !ignore_limit and get_num_of_pl_in_map_area("magic_workshop") >= 4:
						#show("目标地点上限已满")
						return
					for pos in magic_workshop:
						if pos == -1:
							location = {"magic_workshop" : magic_workshop.find(pos)}
							return
						if pos is Array:
							location = GameData.MAGIC_WORKSHOP_4
		GameData.SHINTO:
			match move_location_num:
				1:
					var scout:Array = GameData.location_data["scout"]
					if !ignore_limit and get_num_of_pl_in_map_area("scout") >= 1:
						#show("目标地点上限已满")
						return
					for pos in scout:
						if pos == -1:
							location = GameData.SCOUT_0
							return
						if pos is Array:
							location = GameData.SCOUT_1
				-1:
					location = GameData.MIYAMA_2
				-2:
					var magic_workshop:Array = GameData.location_data["magic_workshop"]
					if !ignore_limit and get_num_of_pl_in_map_area("magic_workshop") >= 4:
						#show("目标地点上限已满")
						return
					for pos in magic_workshop:
						if pos == -1:
							location = {"magic_workshop" : magic_workshop.find(pos)}
							return
						if pos is Array:
							location = GameData.MAGIC_WORKSHOP_4
		GameData.SCOUT:
			match move_location_num:
				-1:
					location = GameData.SHINTO_2
				-2:
					location = GameData.MIYAMA_2
				-3:
					var magic_workshop:Array = GameData.location_data["magic_workshop"]
					if !ignore_limit and get_num_of_pl_in_map_area("magic_workshop") >= 4:
						#show("目标地点上限已满")
						return
					for pos in magic_workshop:
						if pos == -1:
							location = {"magic_workshop" : magic_workshop.find(pos)}
							return
						if pos is Array:
							location = GameData.MAGIC_WORKSHOP_4
							
	pass

func set_location(setted_location:Dictionary, player_id:int = GameData.player_id, is_move:bool = true):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	var location:Dictionary = player_data["location"]
	var location_data:Dictionary = GameData.location_data 
	var area
	for key in setted_location.keys():
		area = key
	if get_pl_or_pls_in_location(setted_location) != -1 and !(get_pl_or_pls_in_location(setted_location) is Array):
		#show("目标位置已满")
		return
	location = setted_location
	
	
func manage_buff(buff, player_id:int = GameData.player_id, add_or_del:bool = true):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	if add_or_del:
		var buffs:Array = player_data["buffs"]
		buffs.append(buff)
	else:
		var buffs:Array = player_data["buffs"]
		buffs.erase(buff)
	pass


#功能函数(记得写发信号)
func deploy(deploy_location:Dictionary, player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	set_location(deploy_location, player_id, false)
	pass




#判断
func _if_func(_var1, _var2):
	if _var1 == _var2:
		return true
	elif _var1 != _var2:
		return false

func _match_func(_var, cases:Array):
	if cases.has(_var):
		return true
	else:
		return false
		
func _not_func(_bool:bool):
	if _bool:
		return false
		
func _when(time_points:Array):
	if TimePointChecker.current_time_points.has(time_points):
		return true
	

#循环
func _for_func(_func:Callable, count:int):
	for i in range(count):
		_func.call()

func _while_func(_func:Callable, condition:bool):
	while condition:
		_func.call()

#获取数值
func create_buff(buff_name:String, buff_img:String):
	var buff = {
		"buff_name" = buff_name,
		"buff_img" = buff_img
	}
	return buff

func _location(map_area:String, index:int):
	if GameData.location_data[map_area] == null:
		#show("不存在该地图区域，检查有无拼写错误")
		return
	var location:Dictionary
	match map_area:
		GameData.MAGIC_WORKSHOP:
			if index >= 5 or index < 0:
				#show("位置索引错误，不存在该位置")
				return
		GameData.MIYAMA:
			if index >= 3 or index < 0:
				#show("位置索引错误，不存在该位置")
				return
		GameData.SHINTO:
			if index >= 3 or index < 0:
				#show("位置索引错误，不存在该位置")
				return
		GameData.SCOUT:
			if index >= 2 or index < 0:
				#show("位置索引错误，不存在该位置")
				return
	location = {map_area : index}
	return location
	
	
func get_location(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["location"]

func get_num_of_pl_in_map_area(map_area:String):
	if GameData.location_data[map_area] == null:
		#show("不存在该地图区域，检查有无拼写错误")
		return
	var area_data = GameData.location_data[map_area]
	var count = 0
	for location in area_data:
		if !(location is Array) and location != -1:
			count += 1
		elif location is Array:
			for i in location:
				count += 1
	return count

func get_pl_or_pls_in_location(location:Dictionary):
	var area
	var location_data = GameData.location_data
	for key in location.keys():
		area = key
	var pl_or_pls = location_data[area][location[area]]	 
	return pl_or_pls
