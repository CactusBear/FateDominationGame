extends Node


var masters_path = "data/masters"
var servants_path = "data/servants"
var tag_list_path = "data"
var tag_list:Array
var temp_stored_jsons_arr:Array#[String]
var _loaded_path = []
var load_masters_finished:bool = false
var _servants_loaded_path = []
var load_servants_finished:bool = false

func _ready():
	load_game()
	pass

func load_game():
	LoadAttack.load_all()
	LoadEvent.load_all()
	LoadSituation.load_all()
	load_masters_from_jsons(masters_path)
	load_servants_from_jsons(servants_path)
	write_tag_list()
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


func load_servants_from_jsons(load_path:String):
	var load_dir = DirAccess.open(load_path)
	if load_dir:
		load_dir.list_dir_begin()
		var load_file_name = load_dir.get_next()
		while !load_servants_finished:
			if load_file_name == "":
				var current_path = load_dir.get_current_dir()
				var rev_path = current_path.reverse()
				var index = rev_path.find("/")
				var last_path = current_path.left(current_path.length() - index - 1)
				var end_path_last = "/data"
				if last_path.right(end_path_last.length()) == end_path_last:
					_servants_loaded_path = []
					load_servants_finished = true
					return
				else:
					_servants_loaded_path.append(current_path)
					load_servants_from_jsons(last_path)
			if load_dir.current_is_dir() and !_servants_loaded_path.has(load_dir.get_current_dir() + "/" + load_file_name):
				load_servants_from_jsons(load_dir.get_current_dir() + "/" + load_file_name)
			elif !load_dir.current_is_dir():
				if load_file_name.right(5) != ".json":
					load_file_name = load_dir.get_next()
					continue
				GameData.loaded_servants.append(load_servant_file(load_dir.get_current_dir(), load_file_name))
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
	master._card_back_img = LoadHelper.resolve_card_back(data.get("card_back_img", ""), path, "master")
	var effects = load_effects(data["effects"], master)
	var specials = data["specials"] as Dictionary
	var upgrade_skill = load_skills(data.get("upgrade_skill", []), path, master, "upgrade_skill")
	var other_things = load_other_master_things(data.get("other_master_things", []), path, master)
	if specials.has("SKILLS") :
		specials["SKILLS"] = load_skills(specials["SKILLS"], path, master)
	if specials.has("ATTACKS") :
		specials["ATTACKS"] = load_attacks(specials["ATTACKS"], path, master)
	if specials.has("BUFFS") :
		specials["BUFFS"] = load_buffs(specials["BUFFS"], path, master)
	if specials.has("MAP_AREAS") :
		specials["MAP_AREAS"] = load_map_areas(specials["MAP_AREAS"], master)
	if specials.has("LOCATIONS") :
		specials["LOCATIONS"] = load_locations(specials["LOCATIONS"], master)
	if specials.has("EVENTS") :
		specials["EVENTS"] = load_events(specials["EVENTS"], path, master)
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
	master._other_things = other_things
	
	var tags = data["tags"] as Array
	#存名字而不是对象本身。master.tags里的字典再指回master会形成循环引用，对象永远不释放
	for tag in tags:
		tag["from"] = master._name
	tag_list.append_array(tags)
	
	return master


func load_servant_file(path:String, servant_file_name:String):
	var servant_file = FileAccess.open(path + "/" + servant_file_name, FileAccess.READ)
	var json = servant_file.get_as_text()
	servant_file.close()
	temp_stored_jsons_arr.append(json)

	var data = JSON.parse_string(json)
	var servant_name = data["servant_name"]
	var shown_servant_name = data["shown_servant_name"]
	var servant_class = data["servant_class"]
	var header_img = path + "/" + data["header_img"]
	var servant_card_img = path + "/" + data["servant_card_img"]

	var servant = BaseServant.new(servant_name, shown_servant_name, servant_class, header_img, servant_card_img)
	servant._card_back_img = LoadHelper.resolve_card_back(data.get("card_back_img", ""), path, "servant")
	var effects = load_effects(data["effects"], servant)
	var specials = data["specials"] as Dictionary
	if specials.has("SKILLS") :
		specials["SKILLS"] = load_skills(specials["SKILLS"], path, servant)
	if specials.has("ATTACKS") :
		specials["ATTACKS"] = load_attacks(specials["ATTACKS"], path, servant)
	if specials.has("BUFFS") :
		specials["BUFFS"] = load_buffs(specials["BUFFS"], path, servant)
	servant._effects = effects
	servant._specials = specials

	var tags = data["tags"] as Array
	#同上，存名字避免循环引用
	for tag in tags:
		tag["from"] = servant._name
	tag_list.append_array(tags)

	return servant


func load_effects(effects:Array, from):
	return LoadHelper.load_effects(effects, from)


func load_number(number:Dictionary):
	return LoadHelper.load_number(number)


func load_skills(skills:Array, pic_path:String, from, type_name:String = "skill"):
	var ski_arr:Array
	for ski:Dictionary in skills:
		var skill_name = ski["skill_name"]
		var skill_card_img = pic_path + "/" + ski["skill_card_img"]
		var attributes = ski["attributes"]
		var cost = load_number(ski["cost"])
		var power = load_number(ski["power"])
		var ignore_limit = ski["ignore_limit"]
		var skill = BaseSkill.new(skill_name, skill_card_img, attributes, cost, power, ignore_limit)
		skill._shown_name = ski.get("shown_skill_name", "")
		var effects = load_effects(ski["effects"], skill)
		skill._effects = effects
		skill.from = from
		skill._card_back_img = LoadHelper.resolve_card_back(ski.get("card_back_img", ""), pic_path, type_name)
		ski_arr.append(skill)

	return ski_arr
	

func load_attacks(attacks:Array, pic_path:String, from):
	var att_arr:Array
	for att in attacks:
		if att is String:
			#牌库构成引用："attribute:power"（如 strength:2）或 "special:name"（如 special:surveil）
			var card: BaseAttack = LoadAttack.resolve(att)
			if card != null:
				card.from = from
				att_arr.append(card)
			continue
		var attack_name = att["attack_name"]
		var attack_card_img = pic_path + "/" + att["attack_card_img"]
		var attributes = att["attributes"]
		var cost = load_number(att["cost"])
		var power = load_number(att["power"])
		var attack = BaseAttack.new(attack_name, attack_card_img, attributes, cost, power)
		attack._shown_name = att.get("shown_attack_name", "")
		var effects = load_effects(att["effects"], attack)
		attack._effects = effects
		attack.from = from
		#御主附带攻击牌默认用skill卡背，可用card_back_img覆盖
		attack._card_back_img = LoadHelper.resolve_card_back(att.get("card_back_img", ""), pic_path, "skill")
		att_arr.append(attack)

	return att_arr


func load_buffs(buffs:Array, pic_path:String, from):
	var buff_arr:Array
	for buf:Dictionary in buffs:
		var buff_name = buf["buff_name"]
		#buff一般没有卡图，有也是头像/token规格，buff_img为空就留空
		var buff_img = ""
		if buf.get("buff_img", "") != "":
			buff_img = pic_path + "/" + buf["buff_img"]
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


#不能归类为技能/攻击/buff的御主附带物件(如宝石卡)。用BaseCard承载卡面/卡背/效果，
#卡背默认走skill卡背，JSON可写card_back_img覆盖
func load_other_master_things(things:Array, pic_path:String, from):
	var thing_arr:Array
	for thing:Dictionary in things:
		var thing_name = thing["thing_name"]
		var card = BaseCard.new()
		card._name = thing_name
		card._shown_name = thing.get("shown_thing_name", "")
		card._card_img = pic_path + "/" + thing["card_img"]
		card._card_back_img = LoadHelper.resolve_card_back(thing.get("card_back_img", ""), pic_path, "skill")
		card._effects = load_effects(thing.get("effects", []), card)
		card._attributes = []
		card.from = from
		card.add_object()
		thing_arr.append(card)
	
	return thing_arr


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
		var upgrade_skill = load_skills(mas.get("upgrade_skill", []), pic_path, master)
		
		if specials.has("SKILLS") :
			specials["SKILLS"] = load_skills(specials["SKILLS"], pic_path, master)
		if specials.has("ATTACKS") :
			specials["ATTACKS"] = load_attacks(specials["ATTACKS"], pic_path, master)
		if specials.has("BUFFS") :
			specials["BUFFS"] = load_buffs(specials["BUFFS"], pic_path, master)
		if specials.has("MAP_AREAS") :
			specials["MAP_AREAS"] = load_map_areas(specials["MAP_AREAS"], master)
		if specials.has("LOCATIONS") :
			specials["LOCATIONS"] = load_locations(specials["LOCATIONS"], master)
		if specials.has("EVENTS") :
			specials["EVENTS"] = load_events(specials["EVENTS"], pic_path, master)
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
		#同上，存名字避免循环引用
		for tag in tags:
			tag["from"] = master._name
		tag_list.append_array(tags)
		
		master_arr.append(master)
	
	return master_arr
