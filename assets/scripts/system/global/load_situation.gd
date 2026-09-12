class_name LoadSituation
extends RefCounted


#局势牌加载：从 data/situations 递归加载所有局势牌 JSON，生成 BaseSituation 实例。
#局势牌是全局共用的一副牌堆(A1)，不属于任何从者/御主，进场逻辑从池里抽牌放激活区(A2)。

const SITUATIONS_PATH := "res://data/situations"

#已加载的非高潮局势牌实例池(模板)
static var situations:Array = []
#已加载的高潮局势牌，按展示回合存 {回合号 : BaseSituation}
static var climax_situations:Dictionary = {}


static func load_all() -> void:
	situations.clear()
	climax_situations.clear()
	_load_dir(SITUATIONS_PATH)


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
	var situation := BaseSituation.new(
		data["card_name"],
		dir_path + "/" + data["card_img"],
		LoadHelper.load_number(data["magic"])
	)
	situation._shown_name = data.get("shown_name", "")
	situation._effects = LoadHelper.load_effects(data.get("effects", []), situation)
	#高潮牌按展示回合索引，非高潮牌进牌堆
	if data.get("is_climax", false):
		situation._card_back_img = LoadHelper.resolve_card_back(data.get("card_back_img", ""), dir_path, "climax_situation")
		climax_situations[int(data.get("climax_round", 0))] = situation
	else:
		situation._card_back_img = LoadHelper.resolve_card_back(data.get("card_back_img", ""), dir_path, "situation")
		situations.append(situation)
