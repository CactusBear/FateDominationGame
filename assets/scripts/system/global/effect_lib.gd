extends Node
class_name EffectLib

var null_func = do_nothing
static func do_nothing():
	pass
	
	



#编辑数值(记得写发信号)
static func edit_num_and_return(num:BaseNumber, add:BaseNumber = BaseNumber.new(0), times:BaseNumber = BaseNumber.new(1), is_round_up:bool = false):
	var result:BaseNumber
	if add.number != 0:
		num.add(add)
	if times.number != 1 and !is_round_up:
		num.multiply(times)
	elif times.number != 1 and is_round_up:
		var val:float = num.number * times.number
		var numi = int(num.number * times.number)
		if val != numi:
			numi += 1 
	result.number = num
	return result

static func change_pl_order(set_order:BaseNumber = null, vary_order:BaseNumber = BaseNumber.new(0), player_id = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	if set_order != null and set_order.number is int:
		var current_order = player_data["order"] as BaseNumber
		var pl_ids = get_all_players_id()
		if set_order.number < current_order.number:
			for order in range(set_order.number,current_order.number + 1):
				for id in pl_ids:
					var pl_data = GameDataManager.get_player_data(id)
					var pl_order = pl_data["order"] as BaseNumber
					if pl_order.number == order:
						pl_order.add(BaseNumber.new(1))
					if pl_order.number >= GameData.player_num:
						pl_order.minus(BaseNumber.new(GameData.player_num))
			player_data["order"] = set_order
		elif set_order.number > current_order.number:
			for order in range(current_order.number,set_order.number + 1):
				for id in pl_ids:
					var pl_data = GameDataManager.get_player_data(id)
					var pl_order = pl_data["order"] as BaseNumber
					if pl_order.number == order:
						pl_order.minus(BaseNumber.new(1))
					if pl_order.number <= -1:
						pl_order.add(BaseNumber.new(GameData.player_num))
			player_data["order"] = set_order
			
	var pl_ids = get_all_players_id()
	for id in pl_ids:
		var pl_data = GameDataManager.get_player_data(id)
		var pl_order = pl_data["order"] as BaseNumber
		pl_order.add(vary_order)
		if pl_order.number >= GameData.player_num:
			pl_order.minus(BaseNumber.new(GameData.player_num))
		if pl_order.number <= -1:
			pl_order.add(BaseNumber.new(GameData.player_num))



static func set_player_data(key_name:String, value, player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	player_data[key_name] = value


static func edit_magic(set_num:BaseNumber = null, vary_num:BaseNumber = BaseNumber.new(0), player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	if set_num != null:
		player_data["magic"] = set_num
	var magic = player_data["magic"] as BaseNumber
	magic.add(vary_num)

static func edit_score(set_num:BaseNumber = null, vary_num:BaseNumber = BaseNumber.new(0), player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	if set_num != null:
		player_data["score"] = set_num
	var score = player_data["score"] as BaseNumber
	score.add(vary_num)
	
static func edit_power(set_num:BaseNumber = null, vary_num:BaseNumber = BaseNumber.new(0), player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	if set_num != null:
		player_data["power"] = set_num
	var power = player_data["power"] as BaseNumber
	power.add(vary_num)
#waiting
static func edit_location_benefit(location:BaseLocation, set_num:BaseNumber = null, vary_num:BaseNumber = BaseNumber.new(0)):
	if set_num != null:
		location._benefit = set_num
	location._benefit.add(vary_num)
	
	
static func edit_location_magic(location:BaseLocation, set_num:BaseNumber = null, vary_num:BaseNumber = BaseNumber.new(0)):
	if set_num != null:
		location._magic = set_num
	location._magic.add(vary_num)
	
static func edit_map_area_score(map_area:BaseMapArea, set_num:BaseNumber = null, vary_num:BaseNumber = BaseNumber.new(0)):
	if set_num != null:
		map_area._score = set_num
	map_area._score.add(vary_num)

static func edit_map_area_move_cost(map_area:BaseMapArea, set_num:BaseNumber = null, vary_num:BaseNumber = BaseNumber.new(0)):
	if set_num != null:
		map_area._move_cost = set_num
	map_area._move_cost.add(vary_num)
	
static func add_map_area_buff(map_area:BaseMapArea, add_buff:BaseBuff):
	var buff_arr:Array = map_area._buffs
	buff_arr.append(add_buff)
	
static func add_map_area_events(map_area:BaseMapArea, add_event:BaseEvent):
	var event_arr:Array = map_area._events
	event_arr.append(add_event)
	
static func add_situatiuons(add_situation:BaseSituation):
	var situation_arr = MapData.situations as Array
	situation_arr.append(add_situation)

static func move_location(move_num:BaseNumber, player_id:int = GameData.player_id, ignore_limit:bool = false) -> BaseNumber:
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	var location:BaseLocation = player_data["location"]
	var area:BaseMapArea
	for a:BaseMapArea in MapData.areas:
		var arr = area._locations as Array
		if !arr.has(location): 
			#show("玩家所处位置不位于地图上")
			return BaseNumber.new(0)
		area = a
	
	var total_cost:BaseNumber = BaseNumber.new(0)
	if move_num.number > 0:
		for n in move_num.number:
			if area._linked_map_area != null:
				total_cost.add(area._move_cost)
				area = area._linked_map_area
	elif move_num.number < 0:
		move_num.set_num(BaseNumber.new(0 - move_num.number))
		for n in move_num.number:
			var area_arr:Array
			for a:BaseMapArea in MapData.areas:
				if a._linked_map_area == area:
					area_arr.append(a)
			if area_arr.size() > 1:
				#area = choose_where_to_go()
				continue
			if area_arr.size() == 1:
				area = area_arr[0]
	else:
		return BaseNumber.new(0)
	
	if area._can_move_to == false:
		#show("无法移动至此区域")
		return BaseNumber.new(0)
	if ignore_limit:
		for loc:BaseLocation in area._locations:
			if loc._pl_num_limit == -1:
				var arr = loc._players as Array
				arr.append(player_id)
				player_data["location"] = loc
				return total_cost
	else :
		for loc:BaseLocation in area._locations:
			if loc._pl_num_limit <= loc._players.size():
				#show("目标位置已满")
				return BaseNumber.new(0)
			if loc._pl_num_limit > loc._players.size() and loc._will_move_to:
				var arr = loc._players as Array
				arr.append(player_id)
				player_data["location"] = loc
				return total_cost
				
	return BaseNumber.new(0)

static func set_location(setted_location:BaseLocation, player_id:int = GameData.player_id, is_move:bool = true):
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
	
	
static func manage_buff(buff, player_id:int = GameData.player_id, add_or_del:bool = true):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	if add_or_del:
		var buffs:Array = player_data["buffs"]
		buffs.append(buff)
	else:
		var buffs:Array = player_data["buffs"]
		buffs.erase(buff)


static func random_int(range_start:int, range_end:int):
	return randi_range(range_start,range_end)

static func random_float(range_start:float, range_end:float):
	return randf_range(range_start,range_end)


#功能函数(记得写发信号)
static func deploy(deploy_location:BaseLocation, player_id:int = GameData.player_id, ignore_limit:bool = false):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	set_location(deploy_location, player_id, ignore_limit)
	
static func move(move_num:BaseNumber, player_id:int = GameData.player_id, ignore_limit:bool = false, ignore_battle:bool = false):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	if !ignore_battle and player_data["is_battle"] == true:
		#show("处于交战状态，无法移动")
		return
	var cost = move_location(move_num,player_id,ignore_limit)
	edit_magic(null, 0 - cost, player_id)

static func activate_effect(effect:BaseEffect):
	start_effect()
	for f in effect._funcs:
		var paras = f._parameters as Array
		for para in paras:
			if para is Dictionary:
				if para.has("number_index"):
					if para["number_index"] == -1: return
					para = effect._using_numbers[para["number_index"]]
				if para.has("self_var"):
					if para["self_var"] == -1: return
					para = effect._self_vars[para["self_var"]]
		if f._var_index == -1:
			f._func.callv(paras)
		else :
			if effect._self_vars.size() <= f._var_index:
				for i in f._var_index + 1:
					if effect._self_vars.size() <= i:
						effect._self_vars.append(null)
			effect._self_vars[f._var_index] = f._func.callv(paras)
	end_effect()
	
#func activate_effect_by_tp(effect:BaseEffect, time_points:Array):
	#for f in effect._funcs:
		#f._func.callv(f._parameters)

static func play_attack(attack:BaseAttack, player_id:int = GameData.player_id, cost:BaseNumber = attack._cost, power:BaseNumber = attack._power):
	var player_data = GameDataManager.get_player_data(player_id)
	var pl_magic = player_data["magic"] as BaseNumber
	pl_magic.minus(cost)
	var pl_power = player_data["power"] as BaseNumber
	pl_power.add(power)
	
	attack._is_activating = true
	
	var playered_cards_arr = player_data["played_cards"] as Array
	playered_cards_arr.append(attack)

static func play_skill(skill:BaseSkill, player_id:int = GameData.player_id, ignore_limit:bool = false, cost:BaseNumber = skill._cost, power:BaseNumber = skill._power):
	var player_data = GameDataManager.get_player_data(player_id)
	if player_data["magic"] < 8 :
		if !ignore_limit and !skill._ignore_limit:
			#show_lack_of_magic()
			return
	var pl_magic = player_data["magic"] as BaseNumber
	pl_magic.minus(cost)
	var pl_power = player_data["power"] as BaseNumber
	pl_power.add(power)
	
	skill._is_activating = true
	
	var playered_cards_arr = player_data["played_cards"] as Array
	playered_cards_arr.append(skill)

static func add_attack(attack:BaseAttack, player_id:int = GameData.player_id, power:BaseNumber = attack._power):
	var player_data = GameDataManager.get_player_data(player_id)
	var pl_power = player_data["power"] as BaseNumber
	pl_power.add(power)
	
	attack._is_activating = true
	
	var playered_cards_arr = player_data["played_cards"] as Array
	playered_cards_arr.append(attack)

static func add_skill(skill:BaseSkill, player_id:int = GameData.player_id, ignore_limit:bool = false,  power:BaseNumber = skill._power):
	var player_data = GameDataManager.get_player_data(player_id)
	if player_data["magic"] < 8 :
		if !ignore_limit and !skill._ignore_limit:
			#show_lack_of_magic()
			return
	var pl_power = player_data["power"] as BaseNumber
	pl_power.add(power)
	
	skill._is_activating = true
	
	var playered_cards_arr = player_data["played_cards"] as Array
	playered_cards_arr.append(skill)
	
static func played_cards(player_id:int = GameData.player_id):
	TimePointChecker.dynamic_time_point([TimePoints.PLAYED_CRAD], player_id)
	
static func draw_card_by_card(card:BaseCard, from:Array, to:Array, to_index:BaseNumber = BaseNumber.new(-1)):
	var i = from.find(card)
	if i == -1:
		return
	from.pop_at(i)
	if to_index.number == -1:
		to.append(card)
	if !(to_index.number is int):
		#show("index只能为整数")
		return
	if to.size() < to_index.number:
		#show("超出数组范围")
		return
	to.insert(to_index.number, card)
	
static func draw_card_by_index(from:Array, to:Array, from_index:BaseNumber = BaseNumber.new(0), to_index:BaseNumber = BaseNumber.new(-1)):
	if from.size() <= from_index.number:
		#show("超出数组范围")
		return
	var card = from[from_index.number]
	if card is BaseCard:
		from.pop_at(0)
		if to_index.number == -1:
			to.append(card)
		if !(to_index.number is int):
			#show("index只能为整数")
			return
		if to.size() < to_index.number:
			#show("超出数组范围")
			return
		to.insert(to_index.number, card)

static func draw_card_from_pl_deck_to_hand(from_index:BaseNumber = BaseNumber.new(0), player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	var deck = player_data["deck"] as Array
	if deck.size() <= from_index.number:
		#show("超出数组范围")
		return
	var card = deck[from_index.number]
	deck.pop_at(from_index.number)
	var hand = player_data["hand_cards"] as Array
	hand.append(card)


static func defeat(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	player_data["is_battle_lose"] = true
	player_data["is_battle_win"] = false


static func discard_played_cards(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	var cards_arr = player_data["played_cards"] as Array
	var discard = player_data["discard"] as Array
	for card:BaseHandCard in cards_arr:
		var card_is_residue:bool = false
		for eff:BaseEffect in card._effects:
			if eff._is_residue:
				card_is_residue = true
				break
		if card_is_residue: continue
		card._is_activating = false
		draw_card_by_card(card, cards_arr, discard, BaseNumber.new(0))


#禁止系效果
static func counter(effect:BaseEffect, countered_func:BaseFunc = null):
	for i in range(GameProgress.effect_progress.size()-1, -1, -1):
		var arr = GameProgress.effect_progress[i] as Array
		var index = arr.find(effect)
		if index == -1:continue
		if countered_func == null:
			arr.remove_at(index)
		else:
			var eff = effect.duplicate() as BaseEffect
			eff.del_func(countered_func)
			arr[index] = eff




#判断
static func _if_func(_var1, _var2 = true):
	if _var1 == _var2:
		return true
	elif _var1 != _var2:
		return false

static func _match_func(_var, cases:Array):
	if cases.has(_var):
		return true
	else:
		return false
		
static func _not_func(_bool:bool):
	if _bool:
		return false
		
static func _when(time_points:Array):
	if TimePointChecker.current_time_points.has(time_points):
		return true
	
static func _has(parent_var, children_var, key = null):
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
static func _for_func(_func:BaseFunc, count:int):
	for i in range(count):
		_func._func.callv(_func._parameters)

static func _while_func(_func:BaseFunc, condition:bool):
	while condition:
		_func._func.callv(_func._parameters)
		
static func _foreach_func(_func:BaseFunc, _var, parameter_index:int = 0):
	for i in _var:
		_func._parameters[parameter_index] = i
		_func._func.callv(_func._parameters)

#获取数值
static func create_base_number(number, can_change:bool = false):
	var n
	var num
	if number is int:
		n = number
		num = BaseNumber.new(n, can_change)
		num.is_float = false
	elif number is float:
		n = number
		num = BaseNumber.new(n, can_change)
		num.is_float = true
	return num
	

static func create_func(callable:Callable, parameters:Array):
	var _func = BaseFunc.new(callable, parameters)
	return _func

static func create_buff(buff_name:String, buff_img:String, buff_id:int):
	var buff = BaseBuff.new(buff_name, buff_img)
	return buff

static func _location(magic:BaseNumber = BaseNumber.new(0), benefit:BaseNumber = BaseNumber.new(0), pl_num_limit:int = 1, will_move_to:bool = false):
	var location = BaseLocation.new(magic,benefit,pl_num_limit,will_move_to)
	return location
	
static func _tag(tag_name:String, from_pl_id:int):
	var tag = {
		"tag_name" : tag_name,
		"from" : from_pl_id
	}
	return tag
	
static func get_all_players_id():
	return GameData.player_data_library.keys()


static func get_by_tag(tag:Dictionary):
	var objects:Array
	for object in GameData.objects:
		for t:Dictionary in object.tags:
			if t == tag:
				objects.append(object)
	return objects

static func get_location(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["location"]

static func get_num_of_pl_in_map_area(map_area:BaseMapArea):
	var count:int = 0
	for loc:BaseLocation in map_area._locations:
		for pl in loc._players:
			count += 1
	return count

static func get_pls_in_location(location:BaseLocation):
	return location._players
	

static func get_data_number(key:String, player_id:int = GameData.player_id):
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
	
	
static func get_player_name(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["player_name"]
	

static func get_phase_order(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["phase_order"]
	

static func get_player_time_points(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["current_time_points"]
	
	
static func get_player_buffs(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["buffs"]


static func get_player_master(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["master"] 


static func get_player_servant(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["servant"] 

static func get_player_commmand_spell(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["command_spell"]

static func get_player_deck(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["deck"]
	
static func get_player_discard(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["discard"]
	
static func get_player_played_cards(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["played_cards"]

static func get_player_master_skills(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["master_skills"]

static func get_player_servant_skills(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["servant_skills"]

static func get_pl_master_side(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["side"]["master"]

static func get_pl_servant_side(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["side"]["servant"]

static func get_pl_command_spell_side(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["side"]["command_spell"]

static func get_pl_deck_side(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["side"]["deck"]
	
static func get_pl_discard_side(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["side"]["discard"]

static func get_pl_skills_side(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["side"]["skills"]

static func get_pl_buffs_side(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["side"]["buffs"]
	
static func get_pl_others_side(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["side"]["others"]

static func get_pl_master_out_game(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["out_of_game"]["master"]

static func get_pl_servant_out_game(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["out_of_game"]["servant"]

static func get_pl_command_spell_out_game(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["out_of_game"]["command_spell"]

static func get_pl_attacks_out_game(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["out_of_game"]["attacks"]

static func get_pl_skills_out_game(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["out_of_game"]["skills"]

static func get_pl_buffs_out_game(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["out_of_game"]["buffs"]
	
static func get_pl_others_out_game(player_id:int = GameData.player_id):
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	return player_data["out_of_game"]["others"]



static func get_location_magic(location:BaseLocation):
	return location._magic


static func get_location_benefit(location:BaseLocation):
	return location._benefit


static func get_map_area_score(map_area:BaseMapArea):
	return map_area._score


static func get_map_area_score_need_win(map_area:BaseMapArea):
	return map_area._score_need_win


static func get_map_area_buffs(map_area:BaseMapArea):
	return map_area._buffs


static func get_move_cost(map_area:BaseMapArea):
	return map_area._move_cost


static func get_events(map_area:BaseMapArea):
	return map_area._events


static func get_situations():
	return MapData.situations



static func get_buff_by_name_fr_arr(buff_name:String, buffs:Array):
	var got_buffs:Array#[BaseBuff]
	for buff:BaseBuff in buffs:
		if buff._buff_name == buff_name:
			got_buffs.append(buff)
	if got_buffs.size() > 1:
		#show_check()
		pass
	else :
		for b in got_buffs:
			return b
	

static func get_cards_by_name_fr_arr(card_name:String, cards:Array):
	var got_cards:Array#[BaseCard]
	for card:BaseCard in cards:
		if card._card_name == card_name:
			got_cards.append(card)
	return got_cards
	

static func get_card_by_index_fr_arr(card_index:BaseNumber, cards:Array):
	if cards.size() <= card_index.number:
		#show("超出数组范围")
		return
	return cards[card_index.number]

static func get_printed_nums(object:BaseObject):
	return object.numbers

static func get_effect_using_nums(effect:BaseEffect):
	return effect._using_numbers

static func get_printed_num(index:BaseNumber, object:BaseObject):
	if object.numbers.size() <= index.number:
		#show("超出数组范围")
		return
	return object.numbers[index.number]

static func get_attack_printed_cost(attack:BaseAttack):
	return attack.numbers[0]

static func get_attack_printed_power(attack:BaseAttack):
	return attack.numbers[1]

static func get_skill_printed_cost(skill:BaseSkill):
	return skill.numbers[0]
	
static func get_skill_printed_power(skill:BaseSkill):
	return skill.numbers[1]

static func get_event_printed_score(event:BaseEvent):
	return event.numbers[0]
	
static func get_situation_printed_magic(situation:BaseSituation):
	return situation.numbers[0]

static func get_pl_id_using_eff():
	var pl_ids = EffectLib.get_all_players_id() as Array
	for id in pl_ids:
		var pl_data = GameDataManager.get_player_data(id) as Dictionary
		var arr = pl_data["self_effects"] as Array
		if arr.has(GameProgress.activating_eff):
			return id


static func get_activating_eff():
	return GameProgress.activating_eff


#交互



#效果处理
static func start_effect():
	var pl_ids = get_all_players_id() as Array
	for id in pl_ids:
		var pl_data = GameDataManager.get_player_data(id) as Dictionary
		pl_data["dynamic_time_points"] = []
	TimePointChecker.time_point_update()
	
	if GameProgress.eff_progress_index >= -1:
		GameProgress.eff_progress_index += 1
	
	
static func end_effect():
	TimePointChecker.time_point_check()
