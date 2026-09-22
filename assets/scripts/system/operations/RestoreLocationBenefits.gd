class_name RestoreLocationBenefits
extends RefCounted

#把所有席位的地利数恢复到印刷基线。回合结束时调用——
#地利修正类效果（远隔操作"地利效果翻倍"、占领高地、卫宫"地利变为3倍"）
#只在本回合有效，回合结束必须还原，否则同一个席位的地利会跨回合越乘越大，
#而且改动的是共享的地图数据，会连带影响之后占据该席位的其他玩家。
#与 RestoreMapAreaMoveFlags / RestoreLocationPlNumLimits 同一套做法：
#印刷值是数据声明的事实（_printed_benefit），当前值（_benefit）才允许被效果改写。
#返回被还原的席位数
func exec() -> int:

	var restored:int = 0
	for area:BaseMapArea in MapData.areas:
		for loc:BaseLocation in area._locations:
			var printed = loc._printed_benefit
			var current = loc._benefit
			if !(printed is BaseNumber) or !(current is BaseNumber):
				continue
			if current.number == printed.number:
				continue
			#写回数值而不是替换对象：别处可能持有 _benefit 这个 BaseNumber 的引用
			current.set_num(BaseNumber.new(printed.number))
			restored += 1
	return restored
