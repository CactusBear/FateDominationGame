class_name MapAreaHasEffect
extends RefCounted

#单战区查询：该战区挂的事件牌与 buff 里，是否有指定名称的效果。
#「固有结界：所有玩家不能移动至此地点」「此战场的位置不提供地利」这类按战场生效的规则，
#用「目标/所在战区有没有声明该效果」判定，规则数字与例外都由数据声明，不写死战区名
func exec(map_area:BaseMapArea, effect_name:String) -> bool:

	if map_area == null or effect_name == "":
		return false
	for event in map_area._events:
		# 暗置事件尚未公开，其禁令/地利修正等声明也不能提前生效。
		if event is BaseCard and event._is_concealed:
			continue
		for eff in event._effects:
			if eff is BaseEffect and eff._name == effect_name:
				return true
	for buff in map_area._buffs:
		if buff is BaseBuff and buff._is_active:
			for eff in buff._effects:
				if eff is BaseEffect and eff._name == effect_name:
					return true
	return false
