class_name LoadCommandSpell
extends RefCounted


#令咒加载：从 data/command_spells 递归加载令咒 JSON，生成 BaseCard 实例。
#令咒不占手牌/牌堆，是各御主共用的通用卡；界面说明与规则都从这里取，避免写死在 UI 里。

const COMMAND_SPELLS_PATH := LoadHelper.DATA_DIR + "/command_spells"

#已加载的令咒池，{card_name : BaseCard}
static var command_spells:Dictionary = {}


static func load_all() -> void:
	command_spells.clear()
	_load_dir(COMMAND_SPELLS_PATH)


static func get_command_spell(card_name:String) -> BaseCard:
	return command_spells.get(card_name, null)


#常规令咒：各御主默认持有的通用令咒
static func get_normal() -> BaseCard:
	return get_command_spell("normal_command_spell")


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
	var data:Dictionary = parsed
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
	command_spells[card._name] = card
