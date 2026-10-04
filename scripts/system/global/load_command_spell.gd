class_name LoadCommandSpell
extends RefCounted


#令咒加载：从 data/command_spells 递归加载令咒 JSON，生成 BaseCard 实例。
#令咒不占手牌/牌堆，是各御主共用的通用卡；界面说明与规则都从这里取，避免写死在 UI 里。

#已加载的令咒池，{card_name : BaseCard}
static var command_spells:Dictionary = {}


static func load_all() -> void:
	command_spells.clear()
	_load_dir(LoadHelper.get_data_dir().path_join("command_spells"))


static func get_command_spell(card_name:String) -> BaseCard:
	return command_spells.get(card_name, null)


#常规令咒：各御主默认持有的通用令咒
static func get_normal() -> BaseCard:
	return get_command_spell("normal_command_spell")


#解析某名玩家的全部令咒：按声明顺序去重，第一个是主令咒、其余是特殊令咒；
#谁都没声明时回退通用常规令咒。界面用整个列表，效果挂载仍取第一个。
static func resolve_player_command_spells(master, servant) -> Array:
	var resolved:Array = []
	for holder in [master, servant]:
		for card_name in _declared_command_spell_names(holder):
			var card := get_command_spell(card_name)
			if card != null and !resolved.has(card):
				resolved.append(card)
	if resolved.is_empty():
		var normal := get_normal()
		if normal != null:
			resolved.append(normal)
	return resolved


#解析某名玩家的主令咒：列表里的第一个
static func resolve_player_command_spell(master, servant) -> BaseCard:
	var resolved:Array = resolve_player_command_spells(master, servant)
	return resolved[0] if resolved.size() > 0 else null


#声明里写的是令咒 card_name：单个字符串或数组（数组顺序即优先顺序，去重保序）
static func _declared_command_spell_names(holder) -> Array:
	if holder == null:
		return []
	var specials = holder.get("_specials")
	if !(specials is Dictionary):
		return []
	var declared = specials.get("COMMAND_SPELLS", null)
	if declared is String:
		return [declared] if declared != "" else []
	if declared is Array:
		var names:Array = []
		for item in declared:
			var card_name := str(item)
			if card_name != "" and !names.has(card_name):
				names.append(card_name)
		return names
	return []


static func _load_dir(dir_path:String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if dir.current_is_dir():
			_load_dir(dir_path + "/" + file_name)
		elif file_name.ends_with(".json"):
			_load_file(dir_path, file_name)
		file_name = dir.get_next()


static func _load_file(dir_path:String, file_name:String) -> void:
	var file := FileAccess.open(dir_path + "/" + file_name, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if !(parsed is Dictionary):
		return
	var card := build_command_spell(parsed, dir_path)
	command_spells[card._name] = card


#按一份令咒数据建牌，图片相对 dir_path，不放进令咒池。读文件与效果里自定义生成的牌共用这一份
static func build_command_spell(data:Dictionary, dir_path:String) -> BaseCard:
	var card := BaseCard.new()
	card._name = data["card_name"]
	card._shown_name = data.get("shown_name", "")
	card._zoom_kind = LoadHelper.resolve_zoom_kind(data, "card_img")
	#card_img 支持两种写法：同目录文件名，或 res:// 开头的完整路径
	#(通用令咒没有自己的图，可以直接借用某个御主目录下的令咒图当默认图)
	if data.has("card_img"):
		var raw_img: String = str(data["card_img"])
		var img_path: String = raw_img if raw_img.begins_with("res://") else dir_path + "/" + raw_img
		if LoadHelper.texture_exists(img_path):
			card._card_img = img_path
	card._card_back_img = LoadHelper.resolve_card_back(data.get("card_back_img", ""), dir_path, "command_spell")
	card._effects = LoadHelper.load_effects(data.get("effects", []), card)
	LoadHelper.load_object_extras(card, data)
	return card
