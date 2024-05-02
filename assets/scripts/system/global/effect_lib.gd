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

func edit_map_benefit():
	pass
func edit_map_magic():
	pass
func edit_map_score():
	pass
func edit_map_move_cost():
	pass
func edit_map_area_buff():
	pass
func edit_map_event_cards():
	pass
func edit_map_situatiuon_cards():
	pass

func move_location(move_location_num:int, player_id:int = GameData.player_id, ignore_limit:bool = false):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	var location:Dictionary = player_data["location"]
	var area:String
	for key in location.keys():
		area = key
	match area:
		MapData.MAGIC_WORKSHOP:
			match move_location_num:
				1:
					location = MapData.MIYAMA_2
				2:
					location = MapData.SHINTO_2
				3:
					var scout:Array = MapData.location_data["scout"]
					if !ignore_limit and get_num_of_pl_in_map_area("scout") >= 1:
						#show("目标地点上限已满")
						return
					for pos in scout:
						if pos == -1:
							location = MapData.SCOUT_0
							return
						if pos is Array:
							location = MapData.SCOUT_1
		MapData.MIYAMA:
			match move_location_num:
				1:
					location = MapData.SHINTO_2
				2:
					var scout:Array = MapData.location_data["scout"]
					if !ignore_limit and get_num_of_pl_in_map_area("scout") >= 1:
						#show("目标地点上限已满")
						return
					for pos in scout:
						if pos == -1:
							location = MapData.SCOUT_0
							return
						if pos is Array:
							location = MapData.SCOUT_1
				-1:
					var magic_workshop:Array = MapData.location_data["magic_workshop"]
					if !ignore_limit and get_num_of_pl_in_map_area("magic_workshop") >= 4:
						#show("目标地点上限已满")
						return
					for pos in magic_workshop:
						if pos == -1:
							location = {"magic_workshop" : magic_workshop.find(pos)}
							return
						if pos is Array:
							location = MapData.MAGIC_WORKSHOP_4
		MapData.SHINTO:
			match move_location_num:
				1:
					var scout:Array = MapData.location_data["scout"]
					if !ignore_limit and get_num_of_pl_in_map_area("scout") >= 1:
						#show("目标地点上限已满")
						return
					for pos in scout:
						if pos == -1:
							location = MapData.SCOUT_0
							return
						if pos is Array:
							location = MapData.SCOUT_1
				-1:
					location = MapData.MIYAMA_2
				-2:
					var magic_workshop:Array = MapData.location_data["magic_workshop"]
					if !ignore_limit and get_num_of_pl_in_map_area("magic_workshop") >= 4:
						#show("目标地点上限已满")
						return
					for pos in magic_workshop:
						if pos == -1:
							location = {"magic_workshop" : magic_workshop.find(pos)}
							return
						if pos is Array:
							location = MapData.MAGIC_WORKSHOP_4
		MapData.SCOUT:
			match move_location_num:
				-1:
					location = MapData.SHINTO_2
				-2:
					location = MapData.MIYAMA_2
				-3:
					var magic_workshop:Array = MapData.location_data["magic_workshop"]
					if !ignore_limit and get_num_of_pl_in_map_area("magic_workshop") >= 4:
						#show("目标地点上限已满")
						return
					for pos in magic_workshop:
						if pos == -1:
							location = {"magic_workshop" : magic_workshop.find(pos)}
							return
						if pos is Array:
							location = MapData.MAGIC_WORKSHOP_4
							
	pass

func set_location(setted_location:Dictionary, player_id:int = GameData.player_id, is_move:bool = true):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	var location:Dictionary = player_data["location"]
	var location_data:Dictionary = MapData.location_data 
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
func _if_func(_var1, _var2 = true):
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
	
func _has(parent_var, children_var, key = null):
	if parent_var is Array:
		if parent_var.find(children_var) != -1:
			return true
		else :
			return false
			
	if parent_var is Dictionary:
		if key == null:
			 #show("请输入字典的键")
			return
		if parent_var[key] is Array:
			var array:Array = parent_var[key]
			array.find(children_var)
		if parent_var[key] is Dictionary:
			var dic:Dictionary = parent_var[key]
			if dic.has(children_var):
				return true
			else :
				return false


#循环
func _for_func(_func:Callable, count:int):
	for i in range(count):
		_func.call()

func _while_func(_func:Callable, condition:bool):
	while condition:
		_func.call()
		
func _foreach_func(_func:Callable, _var):
	for i in _var:
		_func.call(i)

#获取数值
func create_buff(buff_name:String, buff_img:String, buff_id:int):
	var buff = BaseBuff.new(buff_name, buff_img)
	return buff

func _location(map_area:String, index:int):
	if MapData.location_data[map_area] == null:
		#show("不存在该地图区域，检查有无拼写错误")
		return
	var location:Dictionary
	match map_area:
		MapData.MAGIC_WORKSHOP:
			if index >= 5 or index < 0:
				#show("位置索引错误，不存在该位置")
				return
		MapData.MIYAMA:
			if index >= 3 or index < 0:
				#show("位置索引错误，不存在该位置")
				return
		MapData.SHINTO:
			if index >= 3 or index < 0:
				#show("位置索引错误，不存在该位置")
				return
		MapData.SCOUT:
			if index >= 2 or index < 0:
				#show("位置索引错误，不存在该位置")
				return
	location = {map_area : index}
	return location
	

func get_by_tag(tag:Dictionary):
	var objects:Array
	for object in GameData.objects:
		for t:Dictionary in object.tags:
			if t == tag:
				objects.append(object)
	return objects

func get_location(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["location"]

func get_num_of_pl_in_map_area(map_area:String):
	if MapData.location_data[map_area] == null:
		#show("不存在该地图区域，检查有无拼写错误")
		return
	var area_data = MapData.location_data[map_area]
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
	var location_data = MapData.location_data
	for key in location.keys():
		area = key
	var pl_or_pls = location_data[area][location[area]]	 
	return pl_or_pls
	

func get_data_num(key:String, player_id:int = GameData.player_id):
	var player_data = GameDataManager.get_player_data(player_id) as Dictionary
	if !player_data.has(key):
		#show("所提供的键不存在于player_data中")
		return
	if player_data[key] is Dictionary:
		var data:Dictionary = player_data[key]
		return data.size()
	if player_data[key] is Array:
		var data:Array = player_data[key]
		return data.size() 
	if player_data[key] is int:
		return player_data[key]
	
	
func get_player_name(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["player_name"]
	

func get_phase_order(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["phase_order"]
	

func get_player_time_points(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["current_time_points"]
	
	
func get_player_buffs(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["buffs"]


func get_player_master(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["master"] 


func get_player_servant(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["servant"] 


func get_location_magic(location:Dictionary):
	var area
	var val
	for key in location:
		area = key
		val = location[key]
	return MapData.location_magic[area][val]


func get_location_benefit(location:Dictionary):
	var area
	var val
	for key in location:
		area = key
		val = location[key]
	return MapData.location_benefit[area][val]


func get_area_score(map_area:String):
	return MapData.location_score[map_area]


func get_area_buffs(map_area:String):
	return MapData.area_buffs[map_area]


func get_move_cost(a_to_b:String):
	return MapData.move_cost[a_to_b]


func get_event_cards(map_area:String):
	return MapData.event_cards[map_area]


func get_situation_cards():
	return MapData.situation_cards


func get_area_score_need_win(map_area:String):
	return MapData.score_need_win[map_area]


func get_buff_by_name_fr_arr(buff_name:String, buffs:Array):
	var got_buffs:Array
	for buff:BaseBuff in buffs:
		if buff._buff_name == buff_name:
			got_buffs.append(buff)
	if got_buffs.size() > 1:
		#show_tag_check()
		pass
	else :
		for b in got_buffs:
			return b
	

func get_card_by_name_fr_arr(card_name:String, cards:Array):
	pass


#交互

