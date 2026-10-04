class_name EditLocationBenefit
extends RefCounted

#改某席位当前的地利数。印刷值留在 _printed_benefit 作基线（回合结束由
#RestoreLocationBenefits 还原），本操作只动当前值 _benefit。
#不替换 _benefit 这个对象、只写它的数值：别处可能持有同一个 BaseNumber 的引用，
#而且构造时 _benefit 与 _printed_benefit 可能就是同一个实例，
#直接替换/就地加会把印刷基线也一起改掉，之后再也还原不回去
func exec(location:BaseLocation, set_num:BaseNumber = null, vary_num:BaseNumber = BaseNumber.new(0)):

	if location == null:
		return
	var printed = location._printed_benefit
	#印刷基线与当前值共用一个实例时先拆开，否则改当前值会连带改掉基线
	if location._benefit == printed and printed is BaseNumber:
		location._benefit = BaseNumber.new(printed.number)
	var current = location._benefit
	if !(current is BaseNumber):
		return
	if set_num != null:
		current.set_num(BaseNumber.new(set_num.number))
	if vary_num != null:
		current.add(vary_num)
	return current
