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

	#先把这次的差值固定下来并记完日志，再派发时点（理由同 EditScore）
	var delta = magic.number - before
	GameLog.record_resource_change("magic", id, before, magic.number)

	if delta > 0:
		TimePointChecker.dynamic_time_point([TimePoints.MAGIC_ADD], id)
	elif delta < 0:
		TimePointChecker.dynamic_time_point([TimePoints.MAGIC_DECREASE], id)
