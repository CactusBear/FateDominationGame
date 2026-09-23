extends Node

#时点显示名回归：每个声明的时点常量、以及数据里每个被声明使用的时点，都必须有中文显示名。
#背景：时点显示名只维护在 TimePoints.shown_time_points 一处，缺失时不报错——
#界面的「发动 · 时机」会整段消失（查不到就当空串）、卡牌制作器的时点下拉会回退显示英文 id。
#card_revealed 与 non_climax 家庭就是这么漏了很久才被发现的。
#另外守住显示名的文案口径：不带括号补充、不带量词，且互不重名（战报按名字去重，重名会把两次发动并成一条）。

var failures:Array=[]
var checks:=0

func check(ok:bool,label:String):
	checks+=1
	if not ok: failures.append(label)
	print("CHECK ",label," ",ok)

func _ready(): call_deferred("run")

func run():
	# —— 第一段：常量覆盖。判据取自脚本常量表，新增时点必须同步补显示名 ——
	var consts:Dictionary = load("res://assets/scripts/system/time_points.gd").get_script_constant_map()
	var values:Array[String]=[]
	var point_names:Dictionary={}
	for key in consts:
		var value = consts[key]
		if not value is String:
			continue
		#前缀常量（self_/others_）只用于拼时点名，本身不是时点，不需要翻译
		if str(key).ends_with("_PREFIX"):
			continue
		point_names[str(key)] = str(value)
		values.append(str(value))
	#常量表读空会让后面的断言全部空跑通过，先把规模钉住
	check(values.size() > 100, "the source declares a full time point table (%d entries)" % values.size())

	var missing:Array=[]
	for key in point_names.keys():
		if str(TimePoints.shown_time_points.get(point_names[key], "")).strip_edges() == "":
			missing.append("%s(%s)" % [str(key), point_names[key]])
	check(missing.is_empty(), "every declared time point has a shown name: %s" % str(missing))

	#反向：字典里不许留下已经删掉的时点（幽灵键）或拼错的值
	var orphan_keys:Array=[]
	for value in TimePoints.shown_time_points.keys():
		if not values.has(str(value)):
			orphan_keys.append(str(value))
	check(orphan_keys.is_empty(), "no shown name points at a removed time point: %s" % str(orphan_keys))

	#显示名互不重名：战报按显示名去重，两条时点取到同一个名字会把两次发动合并成一条
	var seen:Dictionary={}
	var duplicates:Array=[]
	for value in TimePoints.shown_time_points.keys():
		var shown:String = str(TimePoints.shown_time_points[value])
		if seen.has(shown):
			duplicates.append(shown)
		seen[shown] = true
	check(duplicates.is_empty(), "shown names stay unique: %s" % str(duplicates))

	#文案口径：不带括号补充说明、不带量词（点/层/画/枚/个）
	var off_style:Array=[]
	for value in TimePoints.shown_time_points.keys():
		var shown:String = str(TimePoints.shown_time_points[value])
		for banned in ["（", "）", "(", ")", "【", "】", "点", "层", "画", "枚", "个"]:
			if shown.contains(banned):
				off_style.append("%s=%s" % [str(value), shown])
	check(off_style.is_empty(), "shown names carry no brackets or counters: %s" % str(off_style))

	# —— 第二段：数据面。JSON 里声明的每个时点都要查得到显示名 ——
	#这条正对玩家的症状：界面战报少一行「发动 · 时机」、制作器下拉显示英文 id
	var data_points:Array=[]
	for path in _json_files("res://data"):
		_collect_time_points(JSON.parse_string(FileAccess.get_file_as_string(path)), data_points, path)
	check(data_points.size() > 0, "the data actually declares time points (%d declarations)" % data_points.size())

	var unknown:Array=[]
	for entry in data_points:
		var point:String = entry.split(" -> ")[0]
		if str(TimePoints.shown_time_points.get(point, "")).strip_edges() == "":
			unknown.append(entry)
	check(unknown.is_empty(), "every time point used in data resolves to a shown name: %s" % str(unknown))

	print("RESULT checks=",checks," failures=",failures)
	var f=FileAccess.open("res://time_point_label_result.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"failures":failures})); f.close()
	get_tree().quit(0 if failures.is_empty() else 1)


#递归收集所有名为 time_points 的数组元素，带上来源路径便于定位（不按卡牌类型分支）
func _collect_time_points(value, out:Array, path:String) -> void:
	if value is Array:
		for item in value:
			_collect_time_points(item, out, path)
		return
	if value is Dictionary:
		for key in value.keys():
			if str(key) == "time_points" and value[key] is Array:
				for point in value[key]:
					out.append("%s -> %s" % [str(point), path])
			_collect_time_points(value[key], out, path)


func _json_files(path:String) -> Array:
	var files:Array=[]
	var dir:=DirAccess.open(path)
	if dir == null:
		return files
	dir.list_dir_begin()
	var entry:=dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			if !entry.begins_with("."):
				files.append_array(_json_files(path + "/" + entry))
		elif entry.ends_with(".json"):
			files.append(path + "/" + entry)
		entry=dir.get_next()
	dir.list_dir_end()
	return files
