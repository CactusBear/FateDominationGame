class_name BuildEffect
extends RefCounted

#按卡牌 JSON 里 effects 的单条格式新建一个效果对象（"授予文字"类：给对手一项能力、让一张牌获得某效果）。
#只建对象，不挂到牌上也不登记：挂到哪张牌用 add_to_array 放进它的 _effects，
#让它生效用 register_object_effects，与建牌/入区/登记分开组合的做法一致。
#owner：效果归属（from），不传就归到发动这条效果的那张牌
func exec(effect_data:Dictionary, owner = null):

	if effect_data == null or effect_data.is_empty():
		return null
	if owner == null:
		owner = GetEffSourceCard.new().exec()
	#每次建一份独立数据：同一块积木重复执行不能共用加载器写过的字典
	var effects:Array = LoadHelper.load_effects([effect_data.duplicate(true)], owner)
	return effects[0] if !effects.is_empty() else null
