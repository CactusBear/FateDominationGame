class_name BuildCard
extends RefCounted

#按一份完整的卡牌数据新建一张牌。数据格式与正式卡牌 JSON 相同，建牌走各种卡自己的加载函数，
#所以卡面字段、效果、词条、打出条件的含义与读文件时完全一致。只负责建牌：
#放进哪一区用 add_to_array，让它的效果生效用 register_object_effects。
#card_type：attack / skill / upgrade_skill / buff / thing / event / situation / command_spell。
#owner：新牌归属（from）。不传就归到发动这条效果的那张牌。
#image_dir：卡图所在目录。不传就用发动这条效果的那张牌的卡图所在目录（编辑器把图存在那里）。
#card_back_type：没写 card_back_img 时用哪一类通用卡背；不传就按各加载函数自己的默认。
func exec(card_data:Dictionary, card_type:String, owner = null, image_dir:String = "", card_back_type:String = ""):

	if card_data == null or card_data.is_empty():
		return null
	#每次建牌用一份独立的数据：加载函数会往里写东西，同一块积木重复执行也不能互相影响
	var data:Dictionary = card_data.duplicate(true)
	var source = _source_object()
	if owner == null:
		owner = source
	if image_dir == "":
		image_dir = _image_dir_of(source)
	var card = _build(data, card_type, owner, image_dir)
	if card == null:
		return null
	if owner != null:
		card.from = owner
	if card_back_type != "" and str(data.get("card_back_img", "")) == "" and "_card_back_img" in card:
		card._card_back_img = LoadHelper.resolve_card_back("", image_dir, card_back_type)
	return card


func _build(data:Dictionary, card_type:String, owner, dir:String):
	match card_type:
		"attack":
			return _first(LoadGame.load_attacks([data], dir, owner))
		"skill", "upgrade_skill":
			return _first(LoadGame.load_skills([data], dir, owner, card_type))
		"buff":
			return _first(LoadGame.load_buffs([data], dir, owner))
		"thing":
			return _first(LoadGame.load_other_master_things([data], dir, owner))
		"event":
			return LoadEvent.build_event(data, dir)
		"situation":
			return LoadSituation.build_situation(data, dir)
		"command_spell":
			return LoadCommandSpell.build_command_spell(data, dir)
	return null


func _first(arr:Array):
	return arr[0] if not arr.is_empty() else null


#发动这条效果的对象：效果的 from（牌、状态、御主、从者都可能）
func _source_object():
	var eff = EffectManager.activating_eff
	if eff == null:
		return null
	return eff.from


#各类对象存卡图的字段（加载时已拼成完整路径）。按顺序取第一个有值的，
#对象上没有就顺着 from 往上找——子牌的图与本体放在同一个文件夹
const IMAGE_FIELDS := ["_card_img", "_master_card_img", "_servant_card_img", "_header_img", "_buff_img"]

func _image_dir_of(source) -> String:
	var node = source
	while node is Object:
		for field in IMAGE_FIELDS:
			if field in node and str(node.get(field)) != "":
				return str(node.get(field)).get_base_dir()
		node = node.from if "from" in node else null
	return LoadHelper.get_data_dir()
