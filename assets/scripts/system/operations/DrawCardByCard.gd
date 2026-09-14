class_name DrawCardByCard
extends RefCounted

#把指定的卡从 from 数组搬到 to 数组（to_index 为 -1 时追加到末尾）。
#下标校验一律在搬运之前做完：先 pop 再发现下标非法，卡会同时不在来源区也不在目标区，
#等于静默把卡弄丢（不报错，只是那张牌从牌堆/手牌里凭空消失）。
func exec(card:BaseCard, from:Array, to:Array, to_index = -1):

	var i = from.find(card)
	if i == -1:
		return
	#index 兼容 int / float / BaseNumber：只有整数值才当"插入位置"，-1 表示追加到末尾
	var index:int = _index_of(to_index)
	if index != -1:
		if index < 0 or index > to.size():
			#show("超出数组范围")
			return
	from.pop_at(i)
	if index == -1:
		to.append(card)
		return
	to.insert(index, card)


func _index_of(value) -> int:
	#JSON 里的整数经解析后是 float，所以"整数值的 float"也要当整数用，否则调用方写 0 会被当成非法下标
	var n = value.number if value is BaseNumber else value
	if n is int:
		return n
	if n is float and n == floor(n):
		return int(n)
	return -1
