class_name LoadAttack
extends RefCounted


#攻击牌加载与查找。整合原 attack_pool.gd 的功能：
#1. 从 data/attacks 递归加载所有攻击牌 JSON，只存原始数据，不直接生成实例，
#   避免多个从者共享同一张卡实例。
#2. 牌库构成引用（"attribute:power" / "special:name"）在 resolve 时按数据新建独立实例，
#   与原 attack_pool 每次 new 的语义一致：每个从者的牌库各自持有独立卡实例。

const ATTACKS_PATH := "res://data/attacks"

#已加载的攻击牌原始数据。每项是 JSON 解析出的 Dictionary，额外带 _dir_path 用于拼图片路径。
static var _attack_datas:Array = []


#加载 data/attacks 下所有攻击牌 JSON。必须在加载从者牌库之前调用。
static func load_all() -> void:
	_attack_datas.clear()
	_load_dir(ATTACKS_PATH)


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
			var data:Dictionary = _load_json(dir_path + "/" + file_name)
			if !data.is_empty():
				data["_dir_path"] = dir_path
				_attack_datas.append(data)
		file_name = dir.get_next()


static func _load_json(full_path:String) -> Dictionary:
	var file := FileAccess.open(full_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		return parsed
	return {}


#按数据新建攻击牌实例。图片路径取 JSON 文件所在目录，与从者/御主卡牌的相对图片约定一致。
static func _create_attack(data:Dictionary) -> BaseAttack:
	var attack := BaseAttack.new(
		data["attack_name"],
		data["_dir_path"] + "/" + data["attack_card_img"],
		data["attributes"],
		LoadHelper.load_number(data["cost"]),
		LoadHelper.load_number(data["power"])
	)
	attack._shown_name = data.get("shown_attack_name", "")
	attack._category = data.get("category", BaseAttack.CATEGORY_NON_BASIC)
	attack._effects = LoadHelper.load_effects(data.get("effects", []), attack)
	attack._card_back_img = LoadHelper.resolve_card_back(data.get("card_back_img", ""), data["_dir_path"], "attack")
	return attack


#按属性+威力查找攻击卡（力量/敏捷/魔术）。基础牌优先于职阶牌，
#与牌库引用"attribute:power"的原语义一致（如 magic:4 匹配基础高位魔术而非月之癌）。
static func find_by_attribute_power(attribute:String, power:int) -> BaseAttack:
	for data:Dictionary in _attack_datas:
		if data.get("category", "") != BaseAttack.CATEGORY_BASIC:
			continue
		if attribute in data["attributes"] and int(data["power"]["number"]) == power:
			return _create_attack(data)
	for data:Dictionary in _attack_datas:
		if data.get("category", "") == BaseAttack.CATEGORY_BASIC:
			continue
		if attribute in data["attributes"] and int(data["power"]["number"]) == power:
			return _create_attack(data)
	return null


#按内部名查找特殊攻击卡（如 surveil / luck / preparation）。找不到返回 null。
static func find_special(attack_name:String) -> BaseAttack:
	for data:Dictionary in _attack_datas:
		if data["attack_name"] == attack_name:
			return _create_attack(data)
	return null


#解析牌库构成条目："attribute:power"（如 strength:2）或 "special:name"（如 special:surveil）。
static func resolve(entry:String) -> BaseAttack:
	var parts:Array = entry.split(":")
	if parts.size() != 2:
		return null
	if parts[0] == "special":
		return find_special(parts[1])
	return find_by_attribute_power(parts[0], int(parts[1]))
