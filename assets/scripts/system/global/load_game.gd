extends Node


var masters_path = "data/masters"
var _loaded_path = []

func load_game():
	load_masters(masters_path)
	


func load_masters(load_path:String):
	var load_dir = DirAccess.open(load_path)
	if load_dir:
		load_dir.list_dir_begin()
		var load_file_name = load_dir.get_next()
		while true:
			if load_dir.current_is_dir() and !_loaded_path.has(load_dir.get_current_dir()):
				load_masters(load_dir.get_current_dir())
			elif !load_dir.current_is_dir():
				GameData.master_datas.append(load_master_file(load_dir.get_current_dir(), load_file_name)) 
			load_file_name = load_dir.get_next()
			if load_file_name == "":
				var current_path = load_dir.get_current_dir()
				var rev_path = current_path.reverse()
				var index = rev_path.find("/")
				var last_path = current_path.erase(current_path.length() - index)
				var end_path_last = "/data"
				if last_path.right(end_path_last.length()) == end_path_last:
					_loaded_path = []
					break
				else: 
					_loaded_path.append(current_path)
					load_masters(last_path)
	else:
		print("尝试访问路径时出错。")


func load_master_file(path:String, master_file_name:String):
	var master_file = FileAccess.open(path + "/" + master_file_name, FileAccess.READ)
	var json = master_file.get_as_text()
	master_file.close()
	var data = JSON.parse_string(json)
	var abilities:Dictionary = data["effects"]
	for effect:Dictionary in abilities:
		var _funcs = effect.keys()
		if !_funcs.find("time_points"):
			#show("没有检测到效果时点！")
			return
	return data
	pass



#func add_tag():
	#var datas = GameData.master_datas.append_array(GameData.servant_datas)
	#var master_tags:Array[String]
	#var servant_tags:Array[String]
	#var skill_tags:Array[String]
	#var attack_tags:Array[String]
	#var situation_tags:Array[String]
	#var event_tags:Array[String]
	#var buff_tags:Array[String]
	#var others_tags:Array[String]
	#
	#for data:Dictionary in datas:
		#master_tags = data[]
