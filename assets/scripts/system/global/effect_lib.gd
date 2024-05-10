extends Node


var null_func = do_nothing
func do_nothing():
	pass
	
	



#编辑数值(记得写发信号)
func edit_num_and_return(num:int, add:int = 0, times:float = 1, is_round_up:bool = false):
	var result:int
	if add != 0:
		num += add
	if times != 1 and !is_round_up:
		num = num * times
	elif times != 1 and is_round_up:
		var val:float = num * times
		num = num * times
		if val != num:
			num += 1 
	result = num
	return result

func change_pl_order(set_order = null, vary_order:int = 0, player_id = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	if set_order != null and set_order is int:
		var current_order = player_data["order"] as int
		var pl_ids = get_all_players_id()
		if set_order < current_order:
			for order in range(set_order,current_order + 1):
				for id in pl_ids:
					var pl_data = GameDataManager.get_player_data(id)
					if pl_data["order"] == order:
						pl_data["order"] += 1
					if pl_data["order"] >= 8:
						pl_data["order"] -= 7
			player_data["order"] = set_order
		elif set_order > current_order:
			for order in range(current_order,set_order + 1):
				for id in pl_ids:
					var pl_data = GameDataManager.get_player_data(id)
					if pl_data["order"] == order:
						pl_data["order"] -= 1
					if pl_data["data"] <= 0:
						pl_data["order"] += 7
			player_data["order"] = set_order
			
	var pl_ids = get_all_players_id()
	for id in pl_ids:
		var pl_data = GameDataManager.get_player_data(id)
		pl_data["order"] += vary_order
		if pl_data["order"] >= 8:
			pl_data["order"] -= 7
		if pl_data["data"] <= 0:
			pl_data["order"] += 7



func set_player_data(key_name:String, value, player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	player_data[key_name] = value


func edit_magic(set_num = null, vary_num:int = 0, player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	if set_num != null:
		player_data["magic"] = set_num
	player_data["magic"] += vary_num

func edit_score(set_num = null, vary_num:int = 0, player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	if set_num != null:
		player_data["score"] = set_num
	player_data["score"] += vary_num
	
func edit_power(set_num = null, vary_num:int = 0, player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	if set_num != null:
		player_data["power"] = set_num
	player_data["power"] += vary_num

func edit_map_benefit(location:Dictionary, set_num = null, vary_num:int = 0):
	var area
	var pos
	for key in location:
		area = key
		pos = location[area]
	if set_num != null:
		MapData.location_benefit[area][pos] = set_num
	MapData.location_benefit[area][pos] += vary_num
	
	
func edit_map_magic(location:Dictionary, set_num = null, vary_num:int = 0):
	var area
	var pos
	for key in location:
		area = key
		pos = location[area]
	if set_num != null:
		MapData.location_magic[area][pos] = set_num
	MapData.location_magic[area][pos] += vary_num
	
func edit_map_score(map_area:String, set_num = null, vary_num:int = 0):
	if set_num != null:
		MapData.location_score[map_area] = set_num
	MapData.location_score[map_area] += vary_num

func edit_map_move_cost(a_to_b:String, set_num = null, vary_num:int = 0):
	if set_num != null:
		MapData.move_cost[a_to_b] = set_num
	MapData.move_cost[a_to_b] += vary_num
	
func add_map_area_buff(map_area:String, add_buff:BaseBuff):
	var buff_arr:Array = MapData.area_buffs[map_area]
	buff_arr.append(add_buff)
	
func add_map_event_cards(map_area:String, add_event:BaseEvent):
	var event_arr:Array = MapData.event_cards[map_area]
	event_arr.append(add_event)
	
func add_map_situatiuon_cards(add_situation:BaseSituation):
	var situation_arr = MapData.situation_cards as Array
	situation_arr.append(add_situation)

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


func random_int(range_start:int, range_end:int):
	return randi_range(range_start,range_end)

func random_float(range_start:float, range_end:float):
	return randf_range(range_start,range_end)


#功能函数(记得写发信号)
func deploy(deploy_location:Dictionary, player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	set_location(deploy_location, player_id, false)

func activate_effect(effect:BaseEffect):
	for f in effect._funcs:
		f._func.callv(f._parameters)
		
#func activate_effect_by_tp(effect:BaseEffect, time_points:Array):
	#for f in effect._funcs:
		#f._func.callv(f._parameters)

func play_attack(attack:BaseAttack, player_id:int = GameData.player_id, cost:int = attack._cost, power:int = attack._power):
	var player_data = GameDataManager.get_player_data(player_id)
	player_data["magic"] -= cost
	player_data["power"] += power
	for eff:BaseEffect in attack._effects:
		if eff._time_points.has(TimePoints.PLAYED_CRAD):
			activate_effect(eff)
	var playered_cards_arr = player_data["played_cards"] as Array
	var dic = {
		"card" : attack,
		"is_back" : false
	}
	playered_cards_arr.append(dic)

func play_skill(skill:BaseSkill, player_id:int = GameData.player_id, ignore_limit:bool = false, cost:int = skill._cost, power:int = skill._power):
	var player_data = GameDataManager.get_player_data(player_id)
	if player_data["magic"] < 8 :
		if !ignore_limit and !skill._ignore_limit:
			#show_lack_of_magic()
			return
	player_data["magic"] -= cost
	player_data["power"] += power
	for eff:BaseEffect in skill._effects:
		if eff._time_points.has(TimePoints.PLAYED_CRAD):
			activate_effect(eff)
	var playered_cards_arr = player_data["played_cards"] as Array
	var dic = {
		"card" : skill,
		"is_back" : false
	}
	playered_cards_arr.append(dic)

func add_attack(attack:BaseAttack, player_id:int = GameData.player_id, power:int = attack._power):
	var player_data = GameDataManager.get_player_data(player_id)
	player_data["power"] += power
	for eff:BaseEffect in attack._effects:
		if eff._time_points.has(TimePoints.PLAYED_CRAD):
			activate_effect(eff)
	var playered_cards_arr = player_data["played_cards"] as Array
	var dic = {
		"card" : attack,
		"is_back" : false
	}
	playered_cards_arr.append(dic)

func add_skill(skill:BaseSkill, player_id:int = GameData.player_id, ignore_limit:bool = false,  power:int = skill._power):
	var player_data = GameDataManager.get_player_data(player_id)
	if player_data["magic"] < 8 :
		if !ignore_limit and !skill._ignore_limit:
			#show_lack_of_magic()
			return
	player_data["power"] += power
	for eff:BaseEffect in skill._effects:
		if eff._time_points.has(TimePoints.PLAYED_CRAD):
			activate_effect(eff)
	var playered_cards_arr = player_data["played_cards"] as Array
	var dic = {
		"card" : skill,
		"is_back" : false
	}
	playered_cards_arr.append(dic)
	
func draw_card_by_card(card:BaseCard, from:Array, to:Array, to_index:int = -1):
	var i = from.find(card)
	if i == -1:
		return
	from.pop_at(i)
	if to_index == -1:
		to.append(card)
	to.insert(to_index, card)
	
func draw_card_by_index(from:Array, to:Array, from_index:int = 0, to_index:int = -1):
	var card = from[0]
	if card is BaseCard:
		from.pop_at(0)
		if to_index == -1:
			to.append(card)
		to.insert(to_index, card)

func draw_card_from_pl_deck_to_hand(from_index:int = 0, player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	var deck = player_data["deck"] as Array
	var card = deck[from_index]
	deck.pop_at(from_index)
	var hand = player_data["hand_cards"] as Array
	hand.append(card)


func defeat(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	player_data["is_battle_lose"] = true
	player_data["is_battle_win"] = false


#禁止系效果
func prevent(time_points:Array, player_id:int = GameData.player_id, _func:BaseFunc = null):
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
func _for_func(_func:BaseFunc, count:int):
	for i in range(count):
		_func._func.callv(_func._parameters)

func _while_func(_func:BaseFunc, condition:bool):
	while condition:
		_func._func.callv(_func._parameters)
		
func _foreach_func(_func:BaseFunc, _var, parameter_index:int = 0):
	for i in _var:
		_func._parameters[parameter_index] = i
		_func._func.callv(_func._parameters)

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
	
func _tag(tag_name:String, from_player_id:int):
	var tag = {
		"tag_name" : tag_name,
		"from" : from_player_id
	}
	return tag
	
func get_all_players_id():
	return GameData.player_data_library.keys()


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

func get_player_commmand_spell(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["command_spell"]

func get_player_deck(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["deck"]
	
func get_player_discard(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["discard"]
	
func get_player_played_cards(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["played_cards"]

func get_player_master_skills(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["master_skills"]

func get_player_servant_skills(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["servant_skills"]

func get_pl_master_side(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["side"]["master"]

func get_pl_servant_side(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["side"]["servant"]

func get_pl_command_spell_side(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["side"]["command_spell"]

func get_pl_deck_side(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["side"]["deck"]
	
func get_pl_discard_side(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["side"]["discard"]

func get_pl_skills_side(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["side"]["skills"]

func get_pl_buffs_side(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["side"]["buffs"]
	
func get_pl_others_side(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["side"]["others"]

func get_pl_master_out_game(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["out_of_game"]["master"]

func get_pl_servant_out_game(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["out_of_game"]["servant"]

func get_pl_command_spell_out_game(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["out_of_game"]["command_spell"]

func get_pl_attacks_out_game(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["out_of_game"]["attacks"]

func get_pl_skills_out_game(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["out_of_game"]["skills"]

func get_pl_buffs_out_game(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["out_of_game"]["buffs"]
	
func get_pl_others_out_game(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["out_of_game"]["others"]



func get_location_magic(location:Dictionary):
	var area
	var pos
	for key in location:
		area = key
		pos = location[area]
	return MapData.location_magic[area][pos]


func get_location_benefit(location:Dictionary):
	var area
	var pos
	for key in location:
		area = key
		pos = location[area]
	return MapData.location_benefit[area][pos]


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
	var got_buffs:Array[BaseBuff]
	for buff:BaseBuff in buffs:
		if buff._buff_name == buff_name:
			got_buffs.append(buff)
	if got_buffs.size() > 1:
		#show_check()
		pass
	else :
		for b in got_buffs:
			return b
	

func get_cards_by_name_fr_arr(card_name:String, cards:Array):
	var got_cards:Array[BaseCard]
	for card:BaseCard in cards:
		if card._card_name == card_name:
			got_cards.append(card)
	return got_cards
	

func get_card_by_index_fr_arr(card_index:int, cards:Array):
	return cards[card_index]

func get_nums(object:BaseObject):
	return object.numbers

func get_num(index:int, object:BaseObject):
	return object.numbers[index]



#交互



#效果处理
func start_effect():
	pass
	
	
func end_effect():
	pass
