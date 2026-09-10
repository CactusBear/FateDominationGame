class_name CanGainMagic
extends RefCounted

#通用查询：玩家能否从指定来源获得魔力。source由JSON调用方自定义(如"workshop"、
#"skill_zone"、"event"等)，不写死任何具体来源，效果名按约定拼成
#"cannot_gain_magic_from_<source>"；同时存在总闸"cannot_gain_magic"可一次性
#屏蔽所有来源。任何buff把对应名字的效果挂进_effects即可获得限制，
#新增限制来源不需要改动引擎代码，只需要JSON侧填写对应effect_name
func exec(source:String = "", player_id:int = -1) -> bool:

	var id = EffectManager.resolve_player_id(player_id)
	var checker = PlayerBuffsHaveEffect.new()
	if checker.exec("cannot_gain_magic", id):
		return false
	if source != "" and checker.exec("cannot_gain_magic_from_" + source, id):
		return false
	return true
