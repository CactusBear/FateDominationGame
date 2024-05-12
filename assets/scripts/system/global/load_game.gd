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
	load_masters(masters_path)
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


func load_masters(load_path:String):
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
					load_masters(last_path)
			if load_dir.current_is_dir() and !_loaded_path.has(load_dir.get_current_dir() + "/" + load_file_name):
				load_masters(load_dir.get_current_dir() + "/" + load_file_name)
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
	var index = temp_stored_jsons_arr.size() - 1
	
	var data = JSON.parse_string(json)
	var master_name = data["master_name"]
	var shown_master_name = data["shown_master_name"]
	var header_img = path + "/" + data["header_img"]
	var master_card_img = path + "/" + data["master_card_img"]
	var command_spell_img = path + "/" + data["command_spell_img"]
	var effects = load_effects(data["effects"])
	var specials = data["specials"]
	var upgrade_skill = load_skills(data["upgrade_skill"], path)
	specials["SKILLS"] = load_skills(specials["SKILLS"], path)
	specials["ATTACKS"] = load_attacks(specials["ATTACKS"], path)
	
	
	var master = BaseMaster.new(master_name, shown_master_name, header_img, master_card_img, command_spell_img)
	master._effects = effects
	master._specials = specials
	master._upgrade_skill = upgrade_skill
	
	var tags = data["tags"] as Array
	for tag in tags:
		tag["from"] = index
	tag_list.append_array(tags)
	
	return master


func load_effects(effects:Array):
	var eff_arr:Array#[BaseEffect]
	for eff:Dictionary in effects:
		var nums = eff["effect_numbers"] as Array
		var effect = BaseEffect.new(eff["effect_name"], eff["time_points"])
		effect.set_numbers(nums)
		for _func:Dictionary in eff["funcs"]:
			if _func.has("func_name"):
				var key = _func["func_name"] as String
				if func_table[key] == null: 
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


func load_skills(skills:Array, pic_path:String):
	var ski_arr:Array
	for ski:Dictionary in skills:
		var skill_name = ski["skill_name"]
		var skill_card_img = pic_path + "/" + ski["skill_card_img"]
		var attributes = ski["attributes"]
		var cost = ski["cost"]
		var power = ski["power"]
		var ignore_limit = ski["ignore_limit"]
		var effects = load_effects(ski["effects"])
		var skill = BaseSkill.new(skill_name, skill_card_img, attributes, cost, power, ignore_limit, effects)
		ski_arr.append(skill)

	return ski_arr
	

func load_attacks(attacks:Array, pic_path:String):
	var att_arr:Array
	for att:Dictionary in attacks:
		var attack_name = att["attack_name"]
		var attack_crad_img = pic_path + "/" + att["attack_crad_img"]
		var attributes = att["attributes"]
		var cost = att["cost"]
		var power = att["power"]
		var effects = load_effects(att["effects"])
		var attack = BaseAttack.new(attack_name, attack_crad_img, attributes, cost, power, effects)
		att_arr.append(attack)

	return att_arr
