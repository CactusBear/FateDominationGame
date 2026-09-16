class_name EventJournal
extends RefCounted

#事实日志：按"回合 + 阶段"顺序记下发生过的、可查询的事实。
#只负责"存 + 按条件筛 + 返回隔离副本"，不认识玩家/效果/数值对象——
#记录方（GameLog 适配层）在调用前就把数值转成普通数字、把容器整理好。
#entries 不对外暴露：历史只能通过 query 拿隔离副本，防止调用方改写历史

var entries:Array = []


func reset() -> void:
	entries = []


#记一条事实，返回它的隔离副本。容器会再复制一层，调用方之后改自己的数据不影响历史；
#object 保留引用（效果链要靠它取卡），只把 tags/data 复制一层
func record(entry:Dictionary) -> Dictionary:
	var stored:Dictionary = entry.duplicate()
	stored["tags"] = _deep_copy(entry.get("tags", []))
	stored["data"] = _deep_copy(entry.get("data", {}))
	entries.append(stored)
	return _isolate(stored)


#按条件查。filter 每个键都要求命中：type/actor/target/place 直接比，
#tags 有交集即中，data 给定键值全等。
#current_round 由调用方传入（journal 不自己维护回合）
func query(filter:Dictionary, current_round:int, round_offset, limit:int = -1) -> Array:
	var got:Array = []
	if round_offset == null:
		for entry in entries:
			if _matches(entry, filter):
				got.append(entry)
	else:
		var want_round:int = current_round + int(round_offset)
		#倒序扫但绝不提前 break：日志允许补记/导入不同回合的事实，
		#追加顺序不等于回合顺序，只有「条目回合 == 目标回合才收集」是安全的
		for i in range(entries.size() - 1, -1, -1):
			var entry:Dictionary = entries[i]
			if int(entry.get("round", 0)) != want_round:
				continue
			if _matches(entry, filter):
				got.append(entry)
		got.reverse()
	#先按 limit 截取再复制：只要最近几条时不必把命中的每一条都拷一遍
	if limit > 0 and got.size() > limit:
		got = got.slice(got.size() - limit)
	var isolated:Array = []
	for entry in got:
		isolated.append(_isolate(entry))
	return isolated


#裁掉比 oldest 更旧的条目
func trim_rounds(oldest:int) -> void:
	var kept:Array = []
	for entry in entries:
		if int(entry.get("round", 0)) >= oldest:
			kept.append(entry)
	entries = kept


func _matches(entry:Dictionary, filter:Dictionary) -> bool:
	for key in filter.keys():
		var want = filter[key]
		match str(key):
			"tags":
				if !_shares_tag(entry.get("tags", []), want):
					return false
			"data":
				if !_data_matches(entry.get("data", {}), want):
					return false
			_:
				#与 data 同一个语义：字段不存在不算"显式为 null"，不能命中
				if !entry.has(key) or entry[key] != want:
					return false
	return true


func _shares_tag(has, want) -> bool:
	var has_arr:Array = has if has is Array else []
	var want_arr:Array = want if want is Array else [want]
	for t in want_arr:
		if has_arr.has(t):
			return true
	return false


func _data_matches(data, want) -> bool:
	#条件写错（如 data 给成字符串）不能当成"没有这个条件"放行，否则不匹配的也会算命中
	if !(want is Dictionary):
		push_warning("GameLog: data 条件必须是字典，收到 " + str(typeof(want)))
		return false
	if !(data is Dictionary):
		return false
	for k in want.keys():
		if !(data as Dictionary).has(k) or data[k] != want[k]:
			return false
	return true


func _isolate(entry:Dictionary) -> Dictionary:
	var copied:Dictionary = entry.duplicate()
	copied["tags"] = _deep_copy(entry.get("tags", []))
	copied["data"] = _deep_copy(entry.get("data", {}))
	return copied


func _deep_copy(value):
	if value is Array:
		var copied:Array = []
		for item in value:
			copied.append(_deep_copy(item))
		return copied
	if value is Dictionary:
		var copied:Dictionary = {}
		for key in value:
			copied[key] = _deep_copy(value[key])
		return copied
	return value
