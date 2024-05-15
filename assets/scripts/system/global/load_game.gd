extends Node


var masters_path = "data/masters"
var tag_list_path = "data"
var tag_list:Array
var temp_stored_jsons_arr:Array#[String]
var _loaded_path = []
var func_table:Dictionary = FuncTable.new().funcs
var load_masters_finished:bool = false

func _ready():
	load_game()
	pass

func load_game():
	load_masters_from_jsons(masters_path)
	load_stored_jsons()
	store_jsons()
	

func write_tag_list():
	var tag_list_file = FileAccess.open(tag_list_path + "/" + "tag_list.json", FileAccess.WRITE)
	var tags = tag_list.duplicate(true)
	for tag:Dictionary in tags:
		tag.erase("from")
	
	var tag_list_json = JSON.stringify(tags)
	tag_list_file.store_string(tag_list_json)
	tag_list_file.close()

func load_tags(need_check:bool = false):
	for object in GameData.objects:
		if object is BaseAttack:
			for t in tag_list:
				if t["type"] != "attack_tag": continue
				for n in t["name_list"]:
					var o = object as BaseAttack
					if o._name == n:
						var tags = o.tags as Array
						tags.append({
							"tag_name" : t["tag"],
							"from" : t["from"]
						})
		elif object is BaseBuff:
			for t in tag_list:
				if t["type"] != "buff_tag": continue
				for n in t["name_list"]:
					var o = object as BaseBuff
					if o._name == n:
						var tags = o.tags as Array
						tags.append({
							"tag_name" : t["tag"],
							"from" : t["from"]
						})
		elif object is BaseEffect:
			for t in tag_list:
				if t["type"] != "effect_tag": continue
				for n in t["name_list"]:
					var o = object as BaseEffect
					if o._name == n:
						var tags = o.tags as Array
						tags.append({
							"tag_name" : t["tag"],
							"from" : t["from"]
						})
		elif object is BaseEvent:
			for t in tag_list:
				if t["type"] != "event_tag": continue
				for n in t["name_list"]:
					var o = object as BaseEvent
					if o._name == n:
						var tags = o.tags as Array
						tags.append({
							"tag_name" : t["tag"],
							"from" : t["from"]
						})
		elif object is BaseMaster:
			for t in tag_list:
				if t["type"] != "master_tag": continue
				for n in t["name_list"]:
					var o = object as BaseMaster
					if o._name == n:
						var tags = o.tags as Array
						tags.append({
							"tag_name" : t["tag"],
							"from" : t["from"]
						})
		elif object is BaseSituation:
			for t in tag_list:
				if t["type"] != "situation_tag": continue
				for n in t["name_list"]:
					var o = object as BaseSituation
					if o._name == n:
						var tags = o.tags as Array
						tags.append({
							"tag_name" : t["tag"],
							"from" : t["from"]
						})
		elif object is BaseSkill:
			for t in tag_list:
				if t["type"] != "skill_tag": continue
				for n in t["name_list"]:
					var o = object as BaseSkill
					if o._name == n:
						var tags = o.tags as Array
						tags.append({
							"tag_name" : t["tag"],
							"from" : t["from"]
						})
		elif object is BaseServant:
			for t in tag_list:
				if t["type"] != "servant_tag": continue
				for n in t["name_list"]:
					var o = object as BaseServant
					if o._name == n:
						var tags = o.tags as Array
						tags.append({
							"tag_name" : t["tag"],
							"from" : t["from"]
						})
		else :
			for t in tag_list:
				if t["type"] != "others_tag": continue
				for n in t["name_list"]:
					var o = object as BaseObject
					if o._name == n:
						var tags = o.tags as Array
						tags.append({
							"tag_name" : t["tag"],
							"from" : t["from"]
						})
	#check_tag(need_check)


func load_masters_from_jsons(load_path:String):
	var load_dir = DirAccess.open(load_path)
	if load_dir:
		load_dir.list_dir_begin()
		var load_file_name = load_dir.get_next()
		while !load_masters_finished:
			if load_file_name == "":
				var current_path = load_dir.get_current_dir()
				var rev_path = current_path.reverse()
				var index = rev_path.find("/")
				var last_path = current_path.left(current_path.length() - index - 1)
				var end_path_last = "/data"
				if last_path.right(end_path_last.length()) == end_path_last:
					_loaded_path = []
					load_masters_finished = true
					write_tag_list()
					return
				else: 
					_loaded_path.append(current_path)
					load_masters_from_jsons(last_path)
			if load_dir.current_is_dir() and !_loaded_path.has(load_dir.get_current_dir() + "/" + load_file_name):
				load_masters_from_jsons(load_dir.get_current_dir() + "/" + load_file_name)
			elif !load_dir.current_is_dir():
				if load_file_name.right(5) != ".json": 
					load_file_name = load_dir.get_next()
					continue
				GameData.loaded_masters.append(load_master_file(load_dir.get_current_dir(), load_file_name))
			load_file_name = load_dir.get_next()
			
	else:
		print("尝试访问路径时出错。")


func store_jsons():
	var stored_jsons = FileAccess.open("res://game_data/stored_jsons.dat", FileAccess.WRITE_READ)
	stored_jsons.store_var(temp_stored_jsons_arr)


func load_stored_jsons():
	var stored_jsons = FileAccess.open("res://game_data/stored_jsons.dat", FileAccess.READ)
	if stored_jsons == null: 
		load_tags(true)
		return
	var stored_jsons_arr = stored_jsons.get_var() as Array
	
	var equal:bool
	if stored_jsons_arr.size() != temp_stored_jsons_arr.size():
		equal = false
	else :
		for str in stored_jsons_arr:
			for t_str in temp_stored_jsons_arr:
				if str == t_str:
					equal = true
				else :
					equal = false
			
	if !equal:
		load_tags(true)
	else :
		load_tags(false)
	

func load_master_file(path:String, master_file_name:String):
	var master_file = FileAccess.open(path + "/" + master_file_name, FileAccess.READ)
	var json = master_file.get_as_text()
	master_file.close()
	temp_stored_jsons_arr.append(json)
	
	var data = JSON.parse_string(json)
	var master_name = data["master_name"]
	var shown_master_name = data["shown_master_name"]
	var header_img = path + "/" + data["header_img"]
	var master_card_img = path + "/" + data["master_card_img"]
	var command_spell_img = path + "/" + data["command_spell_img"]
	
	
	var master = BaseMaster.new(master_name, shown_master_name, header_img, master_card_img, command_spell_img)
	var effects = load_effects(data["effects"], master)
	var specials = data["specials"] as Dictionary
	var upgrade_skill = load_skills(data["upgrade_skill"], path, master)
	if specials.has("SKILLS") :
		specials["SKILLS"] = load_skills(specials["SKILLS"], path, master)
	if specials.has("ATTACKS") :
		specials["ATTACKS"] = load_attacks(specials["ATTACKS"], path, master)
	if specials.has("BUFFS") :
		specials["BUFFS"] = load_buffs(specials["BUFFS"], path, master)
	if specials.has("COUNTERS") :
		specials["COUNTERS"] = load_counters(specials["COUNTERS"], master)
	if specials.has("MAP_AREAS") :
		specials["MAP_AREAS"] = load_map_areas(specials["MAP_AREAS"], master)
	if specials.has("LOCATIONS") :
		specials["LOCATIONS"] = load_locations(specials["LOCATIONS"], master)
	if specials.has("EVENTS") :
		specials["EVENTS"] = load_events(specials["EVENTS"], path, master)
	if specials.has("SITUATIONS") :
		specials["SITUATIONS"] = load_situations(specials["SITUATIONS"], path, master)
	if specials.has("NPCS") :
		specials["NPCS"]
	if specials.has("COMMAND_SPELLS") :
		specials["COMMAND_SPELLS"]
	if specials.has("MASTERS") :
		specials["MASTERS"]
	if specials.has("SERVANTS") :
		specials["SERVANTS"]
	master._effects = effects
	master._specials = specials
	master._upgrade_skill = upgrade_skill
	
	var tags = data["tags"] as Array
	for tag in tags:
		tag["from"] = master
	tag_list.append_array(tags)
	
	return master


func load_effects(effects:Array, from):
	var eff_arr:Array#[BaseEffect]
	for eff:Dictionary in effects:
		var priority = eff["priority"] as int
		var is_pure_passive = eff["is_pure_passive"] as bool
		var is_residue = eff["is_residue"] as bool
		var numbers = eff["effect_numbers"] as Array
		var nums:Array
		for number:Dictionary in numbers:
			var num = load_number(number)
			nums.append(num)
		
		var effect = BaseEffect.new(eff["effect_name"], eff["time_points"], priority, is_pure_passive, is_residue)
		effect.from = from
		effect.set_numbers(nums)
		effect._using_numbers = nums
		for _func:Dictionary in eff["funcs"]:
			if _func.has("func_name"):
				var key = _func["func_name"] as String
				if !func_table.has(key): 
					print("没有函数:" + "'" + key + "'")
					return
				var main_callable = func_table[key] as Callable
				var paras = _func["parameters"] as Array
				var var_index = _func["var_index"]
				var eff_func = BaseFunc.new(main_callable, paras, var_index)
				effect.add_func(eff_func)
			
			elif _func.has("self_var"):
				if _func["self_var"] == -1: continue
				if !(effect._self_vars[_func["self_var"]]) is Node: continue
				var v = effect._self_vars[_func["self_var"]] as Node
				for f in v.get_method_list():
					if f["name"] == _func["sub_func"]:
						var sub_callable = Callable(v, _func["sub_func"])
						var paras = _func["parameters"] as Array
						var var_index = _func["var_index"]
						var eff_func = BaseFunc.new(sub_callable, paras, var_index)
						effect.add_func(eff_func)
		
		eff_arr.append(effect)
	
	return eff_arr


func load_number(number:Dictionary):
	var num = BaseNumber.new(number["number"], number["can_change"], number["is_pure_number"])
	return num


func load_skills(skills:Array, pic_path:String, from):
	var ski_arr:Array
	for ski:Dictionary in skills:
		var skill_name = ski["skill_name"]
		var skill_card_img = pic_path + "/" + ski["skill_card_img"]
		var attributes = ski["attributes"]
		var cost = load_number(ski["cost"])
		var power = load_number(ski["power"])
		var ignore_limit = ski["ignore_limit"]
		var skill = BaseSkill.new(skill_name, skill_card_img, attributes, cost, power, ignore_limit)
		var effects = load_effects(ski["effects"], skill)
		skill._effects = effects
		skill.from = from
		ski_arr.append(skill)

	return ski_arr
	

func load_attacks(attacks:Array, pic_path:String, from):
	var att_arr:Array
	for att:Dictionary in attacks:
		var attack_name = att["attack_name"]
		var attack_crad_img = pic_path + "/" + att["attack_crad_img"]
		var attributes = att["attributes"]
		var cost = load_number(att["cost"])
		var power = load_number(att["power"])
		var attack = BaseAttack.new(attack_name, attack_crad_img, attributes, cost, power)
		var effects = load_effects(att["effects"], attack)
		attack._effects = effects
		attack.from = from
		att_arr.append(attack)

	return att_arr


func load_buffs(buffs:Array, pic_path:String, from):
	var buff_arr:Array
	for buf:Dictionary in buffs:
		var buff_name = buf["buff_name"]
		var buff_img = pic_path + "/" + buf["buff_img"]
		var is_active = buf["is_active"]
		var buff_level = load_number(buf["buff_level"])
		var buff = BaseBuff.new(buff_name, buff_img)
		var effects = load_effects(buf["effects"], buff)
		buff._effects = effects
		buff._is_active = is_active
		buff._buff_level = buff_level
		buff.from = from
		buff_arr.append(buff)
	
	return buff_arr


func load_counters(counters:Array, from):
	var counter_arr:Array
	for coun:Dictionary in counters:
		var counter_name = coun["counter_name"]
		var is_active = coun["is_active"]
		var num = load_number(coun["num"])
		var counter = BaseCounter.new(counter_name, is_active, num)
		counter.from = from
		counter_arr.append(counter)
		
	return counter_arr


func load_map_areas(map_areas:Array, from):
	var map_area_arr:Array
	var map_links:Array
	for area:Dictionary in map_areas:
		var area_name = area["area_name"]
		var score = load_number(area["score"])
		var move_cost = load_number(area["move_cost"])
		var map_area = BaseMapArea.new(area_name, score, move_cost)
		var locations = load_locations(area["locations"], map_area)
		var linked_map_area_name = area["linked_map_area_name"]
		var link_dic:Dictionary = {
			map_area : linked_map_area_name
		}
		map_links.append(link_dic)
		map_area.from = from
		map_area_arr.append(map_area)
	
	for link_dic:Dictionary in map_links:
		var area:BaseMapArea
		for key in link_dic.keys():
			area = key
			for a:BaseMapArea in map_area_arr:
				if a._area_name == link_dic[key]:
					area._linked_map_area = a
	
	return map_area_arr

func load_locations(locations:Array, from):
	var location_arr:Array
	for loc:Dictionary in locations:
		var magic = load_number(loc["magic"])
		var benefit = load_number(loc["benefit"])
		var pl_num_limit = loc["player_num_limit"]
		var will_move_to = loc["will_move_to"]
		var location = BaseLocation.new(magic, benefit, pl_num_limit, will_move_to)
		location_arr.append(location)
		location.from = from
		
	return location_arr


func load_events(events:Array, pic_path:String, from):
	var event_arr:Array
	for even:Dictionary in events:
		var card_name = even["card_name"]
		var card_img = pic_path + "/" + even["card_img"]
		var score = load_number(even["score"])
		var event = BaseEvent.new(card_name, card_img, score)
		event._effects = load_effects(even["effects"], event)
		event.from = from
		event_arr.append(event)
	
	return event_arr
	


func load_situations(situations:Array, pic_path:String, from):
	var situation_arr:Array
	for situa:Dictionary in situations:
		var card_name = situa["card_name"]
		var card_img = situa["card_img"]
		var magic = load_number(situa["magic"])
		var situation = BaseSituation.new(card_name, card_img, magic)
		situation._effects = load_effects(situa["effects"], situation)
		situation.from = from
		situation_arr.append(situation)
	
	return situation_arr


func load_masters(masters:Array, pic_path:String, from):
	var master_arr:Array
	for mas:Dictionary in masters:
		var master_name = mas["master_name"]
		var shown_master_name = mas["shown_master_name"]
		var header_img = pic_path + "/" + mas["header_img"]
		var master_card_img = pic_path + "/" + mas["master_card_img"]
		var command_spell_img = pic_path + "/" + mas["command_spell_img"]
		
		var master = BaseMaster.new(master_name, shown_master_name, header_img, master_card_img, command_spell_img)
		var effects = load_effects(mas["effects"], master)
		var specials = mas["specials"] as Dictionary
		var upgrade_skill = load_skills(mas["upgrade_skill"], pic_path, master)
		
		if specials.has("SKILLS") :
			specials["SKILLS"] = load_skills(specials["SKILLS"], pic_path, master)
		if specials.has("ATTACKS") :
			specials["ATTACKS"] = load_attacks(specials["ATTACKS"], pic_path, master)
		if specials.has("BUFFS") :
			specials["BUFFS"] = load_buffs(specials["BUFFS"], pic_path, master)
		if specials.has("COUNTERS") :
			specials["COUNTERS"] = load_counters(specials["COUNTERS"], master)
		if specials.has("MAP_AREAS") :
			specials["MAP_AREAS"] = load_map_areas(specials["MAP_AREAS"], master)
		if specials.has("LOCATIONS") :
			specials["LOCATIONS"] = load_locations(specials["LOCATIONS"], master)
		if specials.has("EVENTS") :
			specials["EVENTS"] = load_events(specials["EVENTS"], pic_path, master)
		if specials.has("SITUATIONS") :
			specials["SITUATIONS"] = load_situations(specials["SITUATIONS"], pic_path, master)
		if specials.has("NPCS") :
			specials["NPCS"]
		if specials.has("COMMAND_SPELLS") :
			specials["COMMAND_SPELLS"]
		if specials.has("MASTERS") :
			specials["MASTERS"] = load_masters(specials["MASTERS"], pic_path, master)
		if specials.has("SERVANTS") :
			specials["SERVANTS"]
		master._effects = effects
		master._specials = specials
		master._upgrade_skill = upgrade_skill
		
		var tags = mas["tags"] as Array
		for tag in tags:
			tag["from"] = master
		tag_list.append_array(tags)
		
		master_arr.append(master)
	
	return master_arr
