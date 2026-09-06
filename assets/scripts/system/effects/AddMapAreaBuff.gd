class_name AddMapAreaBuff
extends RefCounted

func exec(map_area:BaseMapArea, add_buff:BaseBuff):

	var buff_arr:Array = map_area._buffs
	buff_arr.append(add_buff)
