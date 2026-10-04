class_name BoardHasEffect
extends RefCounted

#全局面查询：激活的局势牌 + 各战区挂的事件牌与 buff 里，是否有指定名称的效果。
#「宝具禁止使用」这类禁令写在局势牌/事件牌效果上，规则位置（出牌入口）按效果名查询存在性，
#不关心也不需要知道是哪张牌声明的——新增一张禁令牌不必改出牌代码。
#效果名由调用方传入，本操作不写死任何具体规则名
func exec(effect_name:String) -> bool:

	if effect_name == "":
		return false
	var situation = MapData.active_situation
	if situation != null:
		for eff in situation._effects:
			if eff is BaseEffect and eff._name == effect_name:
				return true
	for area:BaseMapArea in MapData.areas:
		for event in area._events:
			for eff in event._effects:
				if eff is BaseEffect and eff._name == effect_name:
					return true
		for buff in area._buffs:
			if buff is BaseBuff and buff._is_active:
				for eff in buff._effects:
					if eff is BaseEffect and eff._name == effect_name:
						return true
	return false
