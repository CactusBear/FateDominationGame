class_name LoadEvent
extends RefCounted


#事件牌加载：从 data/events 递归加载所有事件牌 JSON，生成 BaseEvent 实例。
#事件牌不像攻击牌有牌库引用，直接生成实例池即可；进场逻辑从池里取牌挂到战场。

const EVENTS_PATH := "res://data/events"

#已加载的事件牌实例池
static var events:Array = []


static func load_all() -> void:
	events.clear()
	_load_dir(EVENTS_PATH)


static func _load_dir(dir_path:String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if dir.current_is_dir():
			_load_dir(dir_path + "/" + file_name)
		elif file_name.ends_with(".json"):
			var event:BaseEvent = load_event_file(dir_path, file_name)
			if event != null:
				events.append(event)
		file_name = dir.get_next()


static func load_event_file(dir_path:String, file_name:String) -> BaseEvent:
	var file := FileAccess.open(dir_path + "/" + file_name, FileAccess.READ)
	if file == null:
		return null
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if !(parsed is Dictionary):
		return null
	var data:Dictionary = parsed
	var event := BaseEvent.new(
		data["card_name"],
		dir_path + "/" + data["card_img"],
		LoadHelper.load_number(data["score"])
	)
	event._shown_name = data.get("shown_name", "")
	event._effects = LoadHelper.load_effects(data.get("effects", []), event)
	event._card_back_img = LoadHelper.resolve_card_back(data.get("card_back_img", ""), dir_path, "event")
	return event
