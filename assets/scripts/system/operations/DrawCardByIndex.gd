class_name DrawCardByIndex
extends RefCounted

#把 from 数组里指定下标的卡搬到 to 数组（to_index 为 -1 时追加到末尾）。
#与 DrawCardByCard 同理：两个下标都先校验完再动手，避免摘除成功后插入失败把卡弄丢。
func exec(from:Array, to:Array, from_index = 0, to_index = -1):

	#两个下标都兼容 int / float / BaseNumber，与 DrawCardByCard 同款宽松
	var src:int = _index_of(from_index, -1)
	if src < 0 or from.size() <= src:
		#show("超出数组范围")
		return
	var card = from[src]
	if !(card is BaseCard):
		return
	var index:int = _index_of(to_index, -1)
	if index != -1:
		if index < 0 or index > to.size():
			#show("超出数组范围")
			return
	from.pop_at(src)
	if index == -1:
		to.append(card)
		return
	to.insert(index, card)


func _index_of(value, fallback:int) -> int:
	#JSON 里的整数经解析后是 float，所以"整数值的 float"也要当整数用
	var n = value.number if value is BaseNumber else value
	if n is int:
		return n
	if n is float and n == floor(n):
		return int(n)
	return fallback
