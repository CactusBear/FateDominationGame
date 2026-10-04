extends RefCounted

## 开局前角色目录同步。文件内容快照识别新增、删除和同秒修改。
var error: String = ""
var _files: Dictionary = {}
var _templates: Dictionary = {}

func _scan(directory: String, result: Dictionary) -> void:
	var dir := DirAccess.open(directory)
	if dir == null:
		error = "无法读取角色目录：" + directory
		return
	for file in dir.get_files():
		if file.ends_with(".json"):
			var path := directory.path_join(file)
			var handle := FileAccess.open(path, FileAccess.READ)
			if handle == null:
				error = "无法读取角色文件：" + path
				return
			result[path] = handle.get_as_text()
	for child in dir.get_directories():
		_scan(directory.path_join(child), result)

func _snapshot() -> Dictionary:
	error = ""
	var result: Dictionary = {}
	var data_dir := LoadHelper.get_data_dir()
	_scan(data_dir.path_join("masters"), result)
	_scan(data_dir.path_join("servants"), result)
	return result

func _is_master(path: String) -> bool:
	return path.begins_with(LoadHelper.get_data_dir().path_join("masters") + "/")

func seed(masters: Array, servants: Array) -> void:
	_files = _snapshot()
	_templates.clear()
	for path in _files:
		var data = JSON.parse_string(_files[path])
		if not data is Dictionary:
			continue
		var master := _is_master(path)
		var name: String = str(data.get("master_name" if master else "servant_name", ""))
		for template in masters if master else servants:
			if template != null and template._name == name:
				_templates[path] = template
				break

func _valid(data, master: bool) -> bool:
	if not data is Dictionary:
		return false
	var strings: Array = ["master_name", "shown_master_name", "header_img", "master_card_img", "command_spell_img"] if master else ["servant_name", "shown_servant_name", "servant_class", "servant_card_img"]
	for key in strings:
		if not data.get(key) is String:
			return false
	return data.get("effects") is Array and data.get("specials") is Dictionary and data.get("tags") is Array

func _owned_objects(root) -> Array:
	var result: Array = [root]
	# from 是既有弱归属链；固定点查询覆盖效果、技能及其下级对象。
	var grew := true
	while grew:
		grew = false
		for object in GameData.objects:
			if object is BaseObject and not result.has(object) and result.has(object.from):
				result.append(object)
				grew = true
	return result

func refresh(loader) -> bool:
	var current := _snapshot()
	if not error.is_empty() or current == _files:
		return false
	var names: Dictionary = {}
	for path in current:
		var parser := JSON.new()
		if parser.parse(current[path]) != OK or not _valid(parser.data, _is_master(path)):
			error = "角色文件无效，暂时保留原名单：" + path
			return false
		var data: Dictionary = parser.data
		var key := ("master:" if _is_master(path) else "servant:") + str(data.get("master_name" if _is_master(path) else "servant_name"))
		if names.has(key):
			error = "角色内部名称重复：" + key
			return false
		names[key] = true
	var retired: Array = []
	var retired_names: Array = []
	for path in _templates:
		if not current.has(path) or current[path] != _files.get(path):
			retired.append_array(_owned_objects(_templates[path]))
			retired_names.append(_templates[path]._name)
	# 只清除被替换角色贡献的标签，避免每次重载追加重复标签。
	loader.tag_list = loader.tag_list.filter(func(tag): return not retired_names.has(tag.get("from")))
	var new_templates: Dictionary = {}
	# 角色加载器还收集缓存 JSON；热更新不能向该启动缓存反复追加。
	var stored: Array = loader.temp_stored_jsons_arr.duplicate()
	for path in current:
		if _templates.has(path) and current[path] == _files.get(path):
			new_templates[path] = _templates[path]
		else:
			new_templates[path] = loader.load_master_file(path.get_base_dir(), path.get_file()) if _is_master(path) else loader.load_servant_file(path.get_base_dir(), path.get_file())
	loader.temp_stored_jsons_arr = stored
	for object in retired:
		GameData.objects.erase(object)
	# 只更新模板库，不重置对局、不绑定角色效果、不发牌。
	GameData.loaded_masters.clear()
	GameData.loaded_servants.clear()
	for path in new_templates:
		if _is_master(path):
			GameData.loaded_masters.append(new_templates[path])
		else:
			GameData.loaded_servants.append(new_templates[path])
	_files = current
	_templates = new_templates
	return true
