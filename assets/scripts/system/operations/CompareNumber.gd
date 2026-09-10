class_name CompareNumber
extends RefCounted

#通用数值比较，兼容BaseNumber和裸数字。返回-1(a<b)/0(a==b)/1(a>b)，
#供条件判断类func组合使用(如判断"数量是否达到上限")
func exec(a, b) -> int:

	var av = a.number if a is BaseNumber else a
	var bv = b.number if b is BaseNumber else b
	if av < bv:
		return -1
	elif av > bv:
		return 1
	return 0
