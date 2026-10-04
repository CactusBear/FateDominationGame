class_name GetMapDataValue
extends RefCounted

#读取 MapData 上的字段（事件牌堆 event_deck、事件弃牌区 event_discard、局势牌堆 situations、
#局势弃牌区 situation_discard、当前局势 active_situation、全部战区 areas……）。
#与 get_game_data_value 对称：字段名由调用方传入，不为每个牌堆各写一个 Get。
#返回的是字段本身（数组是同一个引用），搬运用 draw_card_by_card 直接作用在它上面
func exec(key:String):

	if key == "":
		return null
	return MapData.get(key)
