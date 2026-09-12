class_name AddMapAreaEvents
extends RefCounted

func exec(map_area:BaseMapArea, add_event:BaseEvent):

	#事件牌挂到区域时，把from指向所属区域，供效果内部用get_property(event, "from")反查战场
	add_event.from = map_area
	var event_arr:Array = map_area._events
	event_arr.append(add_event)
