class_name AddMapAreaEvents
extends RefCounted

func exec(map_area:BaseMapArea, add_event:BaseEvent):

	var event_arr:Array = map_area._events
	event_arr.append(add_event)
