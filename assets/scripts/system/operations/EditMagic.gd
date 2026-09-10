class_name EditMagic
extends RefCounted

func exec(set_num:BaseNumber = null, vary_num:BaseNumber = BaseNumber.new(0), player_id:int = -1):

	var id = EffectManager.resolve_player_id(player_id)
	var player_data:Dictionary = GameDataManager.get_player_data(id)
	#is_magic_immune是规则例外开关，由效果打开；本操作只负责尊重它，不解释谁赋予的
	if player_data.get("is_magic_immune", false):
		return
	var magic = player_data["magic"] as BaseNumber
	var before = magic.number
	#就地改写玩家自己的数字，不能把效果自带的数字对象直接挂到玩家身上，否则后续变化会污染卡面数值
	if set_num != null:
		magic.set_num(set_num)
	magic.add(vary_num)

	if magic.number > before:
		TimePointChecker.dynamic_time_point([TimePoints.MAGIC_ADD], id)
	elif magic.number < before:
		TimePointChecker.dynamic_time_point([TimePoints.MAGIC_DECREASE], id)
