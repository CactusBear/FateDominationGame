class_name CreateCard
extends RefCounted

#按内部名从已加载的卡库新建一张独立的牌，只负责新建，不放进任何区域：
#放到哪、放几张由调用方用 add_to_array / for_func 等组合。
#card_name：卡的内部名；攻击牌也认牌库构成写法（如 strength:2、special:surveil）。
#card_type：attack / event / situation / command_spell；空字符串表示按这个顺序在各卡库里找。
#owner：新牌归属（from）。不传就归到发动这条效果的那张卡，要改可再用 set_property 改 from。
func exec(card_name:String, card_type:String = "", owner = null):

	if card_name == "":
		return null
	var card = null
	for type in ([card_type] if card_type != "" else ["attack", "event", "situation", "command_spell"]):
		card = _create(str(type), card_name)
		if card != null:
			break
	if card == null:
		return null
	if owner == null:
		owner = GetEffSourceCard.new().exec()
	if owner != null:
		card.from = owner
	return card


func _create(card_type:String, card_name:String):
	match card_type:
		"attack":
			if card_name.find(":") != -1:
				return LoadAttack.resolve(card_name)
			return LoadAttack.find_special(card_name)
		"event":
			return _clone_named(LoadEvent.events, card_name)
		"situation":
			var pool:Array = LoadSituation.situations.duplicate()
			pool.append_array(LoadSituation.climax_situations.values())
			return _clone_named(pool, card_name)
		"command_spell":
			var spell = LoadCommandSpell.get_command_spell(card_name)
			return CloneObject.new().exec(spell) if spell != null else null
	return null


#卡库里存的是模板，直接拿出去会让同一张模板在多处共用，所以复制一份
func _clone_named(pool:Array, card_name:String):
	for template in pool:
		if template is BaseObject and template._name == card_name:
			return CloneObject.new().exec(template)
	return null
