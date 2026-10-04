class_name SumLogData
extends RefCounted

#把日志里某个数值字段求和，例如"本回合我获得过多少战果"= score_add 的 delta 之和。
#查询条件与 actor=-1 的解析一并沿用 QueryLog，本操作只负责把命中的值加起来
func exec(filter:Dictionary = {}, round_offset = 0, key:String = "delta") -> BaseNumber:
	#不标注类型：:= 0 会被推断成 int，小数在累加时就被截断了
	var total:Variant = 0
	for entry in QueryLog.new().exec(filter, round_offset, -1):
		var data = entry.get("data", {})
		if !(data is Dictionary):
			continue
		var v = (data as Dictionary).get(key)
		if v is BaseNumber:
			total += (v as BaseNumber).number
		elif v is int or v is float:
			#不取整：字段本身是小数时求和结果也要是小数
			total += v
	return BaseNumber.new(total)
