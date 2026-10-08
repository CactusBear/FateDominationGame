extends Node


var masters_path := ""
var servants_path := ""
var tag_list_path := ""
var tag_list:Array
var temp_stored_jsons_arr:Array#[String]
var load_masters_finished:bool = false
var load_servants_finished:bool = false
var roster_catalog = preload("res://scripts/selection/roster_catalog.gd").new()

static func is_server_worker_process(arguments:PackedStringArray = OS.get_cmdline_user_args()) -> bool:
	for role in ["--server-console", "--room-data-validation-worker", "--server-room-worker", "--server-gateway", "--server-signaling"]:
		if arguments.has(role):
			return true
	return false

func _ready():
	# 正式客户端也会复用自身可执行文件启动后台职责，路由复用统一入口。
	if not OS.has_feature("editor") and not OS.has_feature("fate_server") and is_server_worker_process():
		get_tree().change_scene_to_file.call_deferred("res://assets/scenes/main_menu/server_bootstrap.tscn")
		return
	if OS.has_feature("fate_server") or OS.get_cmdline_user_args().has("--server-console") or OS.get_cmdline_user_args().has("--room-data-validation-worker") or OS.get_cmdline_user_args().has("--server-room-worker") or OS.get_cmdline_user_args().has("--server-gateway"):
		return
	load_game()
	pass

func load_game():
	var data_dir := LoadHelper.get_data_dir()
	masters_path = data_dir.path_join("masters")
	servants_path = data_dir.path_join("servants")
	tag_list_path = data_dir
	LoadAttack.load_all()
	LoadEvent.load_all()
	LoadSituation.load_all()
	LoadCommandSpell.load_all()
	load_masters_from_jsons(masters_path)
	load_servants_from_jsons(servants_path)
	write_tag_list()
	load_stored_jsons()
	store_jsons()
	roster_catalog.seed(GameData.loaded_masters, GameData.loaded_servants)
	


#中途结束对局后重新加载全部模板。load_game 依赖的递归扫描标志与标签/缓存累加器
#都是启动时一次性的状态，不复位就会跳过扫描或把标签重复追加，所以先清再加载
func reload_game():
	load_masters_finished = false
	load_servants_finished = false
	tag_list.clear()
	temp_stored_jsons_arr.clear()
	load_game()


## 仅在未开局时同步角色模板，不重跑全局加载与游戏初始化。
func refresh_roster() -> bool:
	if GameStart._started:
		return false
	return roster_catalog.refresh(self)


func write_tag_list():
	var tag_list_file = FileAccess.open(tag_list_path + "/" + "tag_list.json", FileAccess.WRITE)
	#data 目录在导出后是外部目录，可能因安装位置无写权限而打不开。
	#写不了只是少一份缓存清单，不该让整个加载流程崩掉
	if tag_list_file == null:
		push_warning("tag_list.json 写入失败，跳过：" + tag_list_path)
		return
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
	var files: Dictionary = {}
	roster_catalog.error = ""
	roster_catalog._scan(load_path, files)
	if not roster_catalog.error.is_empty():
		push_error(roster_catalog.error)
		return
	for path in files:
		GameData.loaded_masters.append(load_master_file(path.get_base_dir(), path.get_file()))
	load_masters_finished = true


func load_servants_from_jsons(load_path:String):
	var files: Dictionary = {}
	roster_catalog.error = ""
	roster_catalog._scan(load_path, files)
	if not roster_catalog.error.is_empty():
		push_error(roster_catalog.error)
		return
	for path in files:
		GameData.loaded_servants.append(load_servant_file(path.get_base_dir(), path.get_file()))
	load_servants_finished = true


#JSON 内容快照的存放路径。必须是 user://：res:// 导出后是只读的 pck，写不进去。
#这只是一份"卡数据有没有变过"的缓存，放用户数据目录即可
const STORED_JSONS_PATH := "user://game_data/stored_jsons.dat"
var stored_jsons_path: String = STORED_JSONS_PATH
var max_snapshot_cache_bytes: int = 64 * 1024 * 1024


func store_jsons():
	if DirAccess.make_dir_recursive_absolute(stored_jsons_path.get_base_dir()) != OK:
		push_warning("stored_jsons.dat 写入失败，跳过缓存")
		return
	var bytes := JSON.stringify(temp_stored_jsons_arr).to_utf8_buffer()
	if bytes.size() > max_snapshot_cache_bytes:
		push_warning("JSON 快照超过缓存预算，跳过缓存")
		return
	var temporary := stored_jsons_path + ".%s.tmp" % OS.get_process_id()
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		push_warning("stored_jsons.dat 写入失败，跳过缓存")
		return
	file.store_buffer(bytes)
	file.flush()
	var result := file.get_error()
	file.close()
	if result != OK or read_json_snapshot(temporary) != temp_stored_jsons_arr:
		DirAccess.remove_absolute(temporary)
		push_warning("JSON 快照写入不完整，保留原缓存")
		return
	if DirAccess.rename_absolute(temporary, stored_jsons_path) != OK:
		DirAccess.remove_absolute(temporary)
		push_warning("JSON 快照替换失败，保留原缓存")


func read_json_snapshot(path: String):
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() <= 0 or file.get_length() > max_snapshot_cache_bytes:
		return null
	# 旧二进制是可重建缓存，不调用 get_var 解码损坏或过时的文件。
	if file.get_8() != 91:
		file.close()
		return null
	file.seek(0)
	var parser := JSON.new()
	var result := parser.parse(file.get_as_text())
	file.close()
	if result != OK or not parser.data is Array:
		return null
	var snapshot: Array = parser.data
	for entry in snapshot:
		if not entry is String:
			return null
	return snapshot

func same_json_snapshot(previous: Array, current: Array) -> bool:
	var old := previous.duplicate()
	var fresh := current.duplicate()
	old.sort()
	fresh.sort()
	return old == fresh

func load_stored_jsons():
	var previous = read_json_snapshot(stored_jsons_path)
	load_tags(previous == null or not same_json_snapshot(previous, temp_stored_jsons_arr))

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
	#御主同时有头像/御主卡/令咒卡三张图，用途不同，各自按JSON声明记一档
	master._zoom_kinds = {
		"_header_img" : LoadHelper.resolve_zoom_kind(data, "header_img"),
		"_master_card_img" : LoadHelper.resolve_zoom_kind(data, "master_card_img"),
		"_command_spell_img" : LoadHelper.resolve_zoom_kind(data, "command_spell_img")
	}
	master._zoom_kind = str(master._zoom_kinds["_master_card_img"])
	LoadHelper.load_object_extras(master, data)
	var effects = load_effects(data["effects"], master)
	var specials = data["specials"] as Dictionary
	var upgrade_skill = load_skills(data.get("upgrade_skill", []), path, master, "upgrade_skill")
	var other_things = load_other_master_things(data.get("other_master_things", []), path, master)
	if specials.has("SKILLS") :
		specials["SKILLS"] = load_skills(specials["SKILLS"], path, master)
	if specials.has("ATTACKS") :
		#御主附带攻击牌的卡背要按"这张卡最终去哪"分类，搬进牌库的声明写在御主效果里，
		#所以把御主效果原始数据传进去一起判定
		specials["ATTACKS"] = load_attacks(specials["ATTACKS"], path, master, data.get("effects", []))
	if specials.has("BUFFS") :
		specials["BUFFS"] = load_buffs(specials["BUFFS"], path, master)
		#御主物品卡(黑泥、宝石等)是某个buff的卡面形态：接上buff实例，
		#渲染时才能按它此刻的激活状态给卡面加深红遮罩。对应关系写在数据的relate_buff里
		LoadHelper.bind_things_to_buffs(data.get("other_master_things", []), other_things, specials["BUFFS"])
	if specials.has("MAP_AREAS") :
		specials["MAP_AREAS"] = load_map_areas(specials["MAP_AREAS"], master)
	if specials.has("LOCATIONS") :
		specials["LOCATIONS"] = load_locations(specials["LOCATIONS"], master)
	if specials.has("EVENTS") :
		specials["EVENTS"] = load_events(specials["EVENTS"], path, master)
	if specials.has("NPCS") :
		specials["NPCS"]
	#令咒：声明本角色专属令咒(card_name，或数组按顺序取)，界面按名从 LoadCommandSpell 池取用，
	#未声明时回退通用常规令咒，这里无需额外处理
	if specials.has("COMMAND_SPELLS") :
		pass
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
	var header_file = data.get("header_img", "")
	var header_img:String = path + "/" + str(header_file) if header_file is String and header_file != "" else ""
	var servant_card_img = path + "/" + data["servant_card_img"]

	var servant = BaseServant.new(servant_name, shown_servant_name, servant_class, header_img, servant_card_img)
	servant._card_back_img = LoadHelper.resolve_card_back(data.get("card_back_img", ""), path, "servant")
	#从者有头像与概览卡两张图，各自按JSON声明记一档
	servant._zoom_kinds = {
		"_header_img" : LoadHelper.resolve_zoom_kind(data, "header_img"),
		"_servant_card_img" : LoadHelper.resolve_zoom_kind(data, "servant_card_img")
	}
	servant._zoom_kind = str(servant._zoom_kinds["_servant_card_img"])
	LoadHelper.load_object_extras(servant, data)
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
		skill._zoom_kind = LoadHelper.resolve_zoom_kind(ski, "skill_card_img")
		#升华技默认未觉醒(要靠特定从者激活)，其它技能牌默认已获得
		skill._is_awakened = bool(ski.get("is_awakened", type_name != "upgrade_skill"))
		#打出规则与卡面提示都是卡自己的数据；没声明就什么都不加
		skill._play_requirements = ski.get("play_requirements", [])
		skill._shown_notes = ski.get("shown_notes", [])
		skill._need_extra_play = bool(ski.get("need_extra_play", false))
		#词条(如真名解放)：卡自己显式声明，引擎按词条名执行对应规则。没声明就没有
		skill._keywords = ski.get("keywords", [])
		LoadHelper.load_object_extras(skill, ski)
		ski_arr.append(skill)

	return ski_arr
	

#owner_effects_data 是持有者(御主)的效果原始 JSON：御主附带攻击牌的卡背要按"这张卡最终去哪"分类，
#而"加入牌库"的声明写在持有者效果里而不是这张卡上，所以要一并传进来判定。从者牌库不传，走默认
func load_attacks(attacks:Array, pic_path:String, from, owner_effects_data:Array = []):
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
		#写了类别就按写的，没写保持构造时的默认
		attack._category = att.get("category", attack._category)
		var effects = load_effects(att["effects"], attack)
		attack._effects = effects
		attack.from = from
		#会被持有者效果搬进牌库的（如葛木的蛇）印攻击牌卡背，留在持有者身上随时打出的
		#（如凛的阴炁弹）印技能牌卡背；JSON 写了 card_back_img 的走同目录特殊卡背
		var back_type := "skill"
		if LoadHelper.is_card_inserted_to_deck(str(attack_name), owner_effects_data):
			back_type = "attack"
		attack._card_back_img = LoadHelper.resolve_card_back(att.get("card_back_img", ""), pic_path, back_type)
		attack._zoom_kind = LoadHelper.resolve_zoom_kind(att, "attack_card_img")
		attack._play_requirements = att.get("play_requirements", [])
		attack._shown_notes = att.get("shown_notes", [])
		attack._need_extra_play = bool(att.get("need_extra_play", false))
		attack._initial_zone = str(att.get("initial_zone", ""))
		attack._initial_count = maxi(0, int(att.get("initial_count", 1)))
		#词条同技能牌：攻击牌也能带词条(如御主附加牌带真名解放)，声明在卡自己身上
		attack._keywords = att.get("keywords", [])
		LoadHelper.load_object_extras(attack, att)
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
		buff._shown_name = buf.get("shown_buff_name", "")
		buff._related_effect_names = (buf.get("related_effect_names", []) as Array).duplicate()
		buff._zoom_kind = LoadHelper.resolve_zoom_kind(buf, "buff_img")
		var effects = load_effects(buf["effects"], buff)
		buff._effects = effects
		buff._is_active = is_active
		buff._buff_level = buff_level
		buff.from = from
		LoadHelper.load_object_extras(buff, buf)
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
		card._zoom_kind = LoadHelper.resolve_zoom_kind(thing, "card_img")
		card._effects = load_effects(thing.get("effects", []), card)
		card._attributes = []
		card.from = from
		LoadHelper.load_object_extras(card, thing)
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
		#是否接受前哨阶段部署由地图数据声明，不在代码里按战区名/下标写死
		map_area._can_deploy = bool(area.get("can_deploy", false))
		var locations = load_locations(area["locations"], map_area)
		#读出来的席位要挂回战区，否则新战区没有任何席位（之前 MAP_AREAS 没有使用方，这一步一直缺着）
		map_area.set_map_area_locations(locations)
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
		var upgrade_skill = load_skills(mas.get("upgrade_skill", []), pic_path, master, "upgrade_skill")
		
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
		#令咒：specials.COMMAND_SPELLS 里声明本角色专属令咒(card_name，或数组按顺序取)，
		#界面按名从 LoadCommandSpell 池取用，未声明时回退通用常规令咒，这里无需额外处理
		if specials.has("COMMAND_SPELLS") :
			pass
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
