class_name LogFieldValues
extends RefCounted

#把日志条目里某个字段的值收集成数组。field 先按条目顶层键取(object/actor/place…),
#顶层没有就取 data 里的同名键(effect_name/delta/winners…)。
#用于"本回合我打出的攻击牌有哪些"（field="object"）、
#"本局触发过哪些效果"（field="effect_name"）、"本场战斗的胜者"（field="winners"）
func exec(filter:Dictionary = {}, round_offset = 0, field:String = "object", limit:int = -1) -> Array:
	var got:Array = []
	for entry in QueryLog.new().exec(filter, round_offset, limit):
		if entry.has(field):
			got.append(entry[field])
			continue
		var data = entry.get("data", {})
		if data is Dictionary and (data as Dictionary).has(field):
			got.append((data as Dictionary)[field])
	return got
