class_name JsonMaker
extends RefCounted

# 独立 JSON 生成器的数据层。
# 只读加载器真正使用的键（json_maker/types.json）和 AllOperations 摘要。
# 不调用任何既有编辑器的场景、脚本或保存入口。

const TYPES_PATH := "res://json_maker/types.json"
const OPS_DIR := "res://assets/scripts/system/operations/"
const IMAGE_EXTS := ["png", "jpg", "jpeg", "webp"]

var types:Dictionary = {}
var operations:Array = []
var time_points:Array = []
var attributes:Array = []
var player_keys:Array = []
var player_key_types:Dictionary = {}   # 玩家数据键 -> 默认值的类型名，按用途筛键时用
var issues:Array = []
# 用户自己的导出设置（存在 user://，不动源码与 types.json）：{种类或子牌类型: {root, folder_name, serial_digits, pattern_defaults, sub_image_prefix, images:{字段: 命名}, zip_layout}, "_global": {zip_dir, last_image_dir:{dir, card}}}
# _global 放跟具体卡无关的编辑器记忆：zip 存到哪，「选图」面板上次去的位置（连当时编辑哪张卡一起记）。
# 没设的项沿用 types.json 的声明。
const EXPORT_CFG := "user://json_maker_export.cfg"
const EXPORT_KEYS := ["root", "folder_name", "serial_digits", "pattern_defaults", "sub_image_prefix", "zip_layout"]
const ZIP_LAYOUTS := ["project", "root", "folder", "flat"]
var export_overrides:Dictionary = {}


func load_catalog() -> void:
	types = JSON.parse_string(FileAccess.get_file_as_string(TYPES_PATH))
	_load_operations()
	_load_time_points()
	_load_attributes()
	_load_player_keys()


func kind_spec(kind_id:String) -> Dictionary:
	var spec:Dictionary = types.get("kinds", {}).get(kind_id, {})
	if spec.has("extends"):
		var base := kind_spec(str(spec.extends))
		var merged := base.duplicate(true)
		for key in spec:
			if key == "fields_extra":
				var fields:Array = merged.get("fields", []).duplicate()
				fields.append_array(spec.fields_extra)
				merged.fields = fields
			elif key != "extends":
				merged[key] = spec[key]
		merged.erase("nested_only")
		return merged
	return spec


func item_spec(item_id:String) -> Dictionary:
	if types.get("kinds", {}).has(item_id):
		return kind_spec(item_id)
	return types.get("items", {}).get(item_id, {})


func file_kinds() -> Array:
	var out:Array = []
	for kind_id in types.get("kinds", {}):
		var spec := export_spec(str(kind_id))
		if str(spec.get("root", "")) != "":
			out.append({"id": str(kind_id), "shown": str(spec.get("shown", kind_id)), "spec": spec})
	return out


func list_files(kind_id:String) -> Array:
	var spec := export_spec(kind_id)
	var root := str(spec.get("root", ""))
	if root == "":
		return []
	root = _res(root)
	var out:Array = []
	if str(spec.get("file", "")) == "named":
		var path := root.path_join(str(spec.get("file_name", "")))
		if FileAccess.file_exists(path):
			out.append({"path": path, "shown": str(spec.get("shown", kind_id))})
		return out
	_scan_json(root, str(spec.get("file", "folder")), out)
	out.sort_custom(func(a, b): return str(a.path) < str(b.path))
	return out


# 内部名索引只读 data，按类型声明的 identity 字段分组；保留对象路径以精确排除自身。
var _identity_index = null

func identity_conflicts(key:String, value:String, source_path:String, object_path:Array) -> Array:
	if value == "":
		return []
	if not _identity_index is Dictionary:
		_identity_index = {}
		var keys:Dictionary = {}
		for kind in types.get("kinds", {}):
			var identity := str(kind_spec(str(kind)).get("identity", ""))
			if identity != "":
				keys[identity] = true
		var files:Array = []
		_scan_json("res://data", "file", files)
		for file in files:
			_index_identities(read_json(str(file.path)), keys, str(file.path), [])
	var source := ProjectSettings.localize_path(source_path).simplify_path() if source_path != "" else ""
	var out:Array = []
	for identity_key in _identity_index:
		for entry in _identity_index[identity_key].get(value, []):
			if identity_key == key and entry.file == source and entry.path == object_path:
				continue
			if not out.has(entry):
				out.append(entry)
	return out


func _index_identities(value, keys:Dictionary, file:String, at:Array) -> void:
	if value is Dictionary:
		for key in keys:
			if value.get(key) is String and value[key] != "":
				if not _identity_index.has(key):
					_identity_index[key] = {}
				if not _identity_index[key].has(value[key]):
					_identity_index[key][value[key]] = []
				_identity_index[key][value[key]].append({"file": file, "path": at})
		for key in value:
			_index_identities(value[key], keys, file, at + [key])
	elif value is Array:
		for i in value.size():
			_index_identities(value[i], keys, file, at + [i])


func read_json(path:String):
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var text := file.get_as_text()
	file.close()
	return JSON.parse_string(text)


func blank(kind_id:String) -> Dictionary:
	var spec := kind_spec(kind_id)
	if str(spec.get("shape", "")) == "array":
		return {"items": []}
	var data := {}
	_fill_object(data, spec)
	return data


# 只写加载器必读的键。可选键不预先写进去：写了默认值会改变语义（例如 need_activate 的默认值跟随纯被动）。
func blank_required(item_id:String) -> Dictionary:
	var spec := item_spec(item_id)
	var data := {}
	for field in spec.get("fields", []):
		if bool(field.get("required", false)):
			data[field.key] = _default_of(field)
	for item in spec.get("lists", []):
		if bool(item.get("required", false)):
			data[item.key] = []
	for group in spec.get("groups", []):
		if bool(group.get("required", false)):
			var inner := {}
			for item in group.get("lists", []):
				inner[item.key] = []
			data[group.key] = inner
	for block in spec.get("blocks", []):
		if str(block.key) == "funcs":
			data["funcs"] = []
	return data


func validate(data, kind_id:String) -> Array:
	issues = []
	var spec := kind_spec(kind_id)
	if str(spec.get("shape", "")) == "array":
		if not data is Array:
			issues.append("这一份应该是列表")
			return issues
		_check_list(data, str(spec.get("item", "")), "第", "")
		return issues
	if not data is Dictionary:
		issues.append("这一份应该是对象")
		return issues
	_check_object(data, spec, "")
	return issues


func export_text(data, style:Dictionary = {}) -> String:
	var indent := str(style.get("indent", "	"))
	var text := JSON.stringify(_whole_numbers(data), indent, false, true) + "\n"
	if bool(style.get("crlf", false)):
		text = text.replace("\n", "\r\n")
	return text


# 记下原文件的缩进与换行，保存时照原样写回，避免整文件变成改动。
func text_style(path:String) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(path)
	var text := bytes.get_string_from_utf8()
	var indent := "	"
	# 按第一行缩进判断：仓库里有空格缩进、也有空格与 Tab 混着的旧文件
	var at := text.find("\n")
	while at != -1 and at + 1 < text.length():
		var ch := text[at + 1]
		if ch == "	":
			break
		if ch == " ":
			var n := 0
			while at + 1 + n < text.length() and text[at + 1 + n] == " ":
				n += 1
			indent = " ".repeat(n)
			break
		at = text.find("\n", at + 1)
	return {"indent": indent, "crlf": text.find("\r\n") != -1}


func save_file(target:String, payload, kind:String, style:Dictionary = {}) -> Dictionary:
	var found := validate(payload, kind)
	if not found.is_empty():
		return {"ok": false, "error": str(found[0]), "count": found.size()}
	var folder := target.get_base_dir()
	_ensure_dir(folder)
	var abs := ProjectSettings.globalize_path(target) if target.begins_with("res://") else target
	var file := FileAccess.open(abs, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "写不进去"}
	file.store_string(export_text(payload, style))
	file.close()
	_identity_index = null
	return {"ok": true, "path": target}


func _whole_numbers(value):
	if value is float and value == floor(value) and is_finite(value):
		return int(value)
	if value is Dictionary:
		var out := {}
		for key in value:
			out[key] = _whole_numbers(value[key])
		return out
	if value is Array:
		var out:Array = []
		for item in value:
			out.append(_whole_numbers(item))
		return out
	return value


func suggest_path(kind_id:String, data:Dictionary) -> String:
	var spec := export_spec(kind_id)
	var root := str(spec.get("root", ""))
	if root == "":
		return ""
	root = _res(root)
	if str(spec.get("file", "")) == "named":
		return root.path_join(str(spec.get("file_name", "")))
	if str(spec.get("file", "")) == "file":
		var name := str(data.get(spec.get("identity", ""), "")).strip_edges()
		return root.path_join(name + ".json") if name != "" else ""
	var folder := folder_for(kind_id, data)
	if folder == "":
		return ""
	# 现有数据：json 与所在文件夹同名（00002_tohsaka_rin/00002_tohsaka_rin.json、luck/luck.json）
	return root.path_join(folder).path_join(folder.get_file() + ".json")


# 这张卡放在 root 下的哪个文件夹：按 types.json 的 folder_name 声明拼，没有声明就是内部名。
# 占位符取卡里的同名字段；{identity} 是内部名，{serial} 是编号（同名文件夹已存在就沿用它的编号）。
# 缺值时先看 pattern_defaults，仍缺就返回空，由调用方提示补填。
func folder_for(kind_id:String, data:Dictionary) -> String:
	var spec := export_spec(kind_id)
	var identity := str(data.get(spec.get("identity", ""), "")).strip_edges()
	if identity == "":
		return ""
	var pattern := str(spec.get("folder_name", "{identity}"))
	var values:Dictionary = spec.get("pattern_defaults", {}).duplicate()
	for key in data:
		if data[key] is String and str(data[key]).strip_edges() != "":
			values[str(key)] = str(data[key]).strip_edges()
	values["identity"] = identity
	if pattern.find("{serial}") != -1:
		values["serial"] = serial_for(str(spec.get("root", "")), identity, int(spec.get("serial_digits", 5)))
	return fill_pattern(pattern, values)


# 把 {名字} 换成 values 里的值；任何一个占位符没有值就返回空字符串。
func fill_pattern(pattern:String, values:Dictionary) -> String:
	var out := pattern
	var at := out.find("{")
	while at != -1:
		var end := out.find("}", at)
		if end == -1:
			break
		var key := out.substr(at + 1, end - at - 1)
		if str(values.get(key, "")) == "":
			return ""
		out = out.substr(0, at) + str(values[key]) + out.substr(end + 1)
		at = out.find("{", at + str(values[key]).length())
	return out


# root 下「编号_内部名」文件夹的编号：已有同内部名的就沿用，否则取现有最大编号 + 1。
func serial_for(root:String, identity:String, digits:int) -> String:
	var biggest := 0
	var dir := DirAccess.open(_res(root))
	if dir != null:
		for name in dir.get_directories():
			var cut := name.find("_")
			if cut <= 0 or not name.substr(0, cut).is_valid_int():
				continue
			if name.substr(cut + 1) == identity:
				return name.substr(0, cut)
			biggest = maxi(biggest, name.substr(0, cut).to_int())
	return str(biggest + 1).pad_zeros(digits)


# 把卡里（含各子牌）引用的图片都放进 folder（json 所在的文件夹），并改写引用：
# - 只写了文件名、且就在 folder 里的：不动；
# - 只写了文件名、在 from_folder（另存为时原来的文件夹）里的：原名复制过来；
# - 写的是完整路径的（刚选的图）：按字段的 file_name 声明起名，子牌再加本体的 sub_image_prefix；
# 找不到的记进 missing，不写文件。返回 {placed:[新名字], missing:[原名字], errors:[]}。
func place_images(data, kind_id:String, folder:String, from_folder:String) -> Dictionary:
	var result := {"placed": [], "missing": [], "errors": []}
	var spec := export_spec(kind_id)
	var new_folder := folder.get_file()
	var prefix := fill_pattern(str(spec.get("sub_image_prefix", "")), {"folder": new_folder})
	var plan:Array = []
	for hit in images_of(data, kind_id):
		var obj:Dictionary = hit.obj
		var field:Dictionary = hit.field
		var name := str(obj[field.key])
		var bare := name.get_file() == name
		if bare and FileAccess.file_exists(folder.path_join(name)):
			continue
		var source := ""
		var target_base := ""
		if not bare and FileAccess.file_exists(name):
			source = name
			var values := {"folder": new_folder, "identity": str(obj.get(hit.spec.get("identity", ""), ""))}
			target_base = fill_pattern(str(field.get("file_name", "{identity}")), values)
			if target_base == "":
				target_base = name.get_file().get_basename()
			if not bool(hit.is_root):
				target_base = prefix + target_base
		elif bare and from_folder != "" and FileAccess.file_exists(from_folder.path_join(name)):
			# 原文件夹里的图原名带过去：别的卡、别的子牌可能也按这个名字引用它
			source = from_folder.path_join(name)
			target_base = name.get_basename()
		else:
			result.missing.append(name)
			continue
		plan.append({"obj": obj, "key": field.key, "source": source, "base": target_base})
	# 有找不到的图就一张都不复制，免得留下半套文件
	if not result.missing.is_empty():
		return result
	for step in plan:
		_ensure_dir(folder)
		var target := _free_name(folder, str(step.base), str(step.source))
		if not FileAccess.file_exists(folder.path_join(target)) and DirAccess.copy_absolute(_abs(str(step.source)), _abs(folder.path_join(target))) != OK:
			result.errors.append(str(step.obj[step.key]))
			continue
		step.obj[step.key] = target
		result.placed.append(target)
	return result


# 卡里（含各子牌）所有填了图片的字段：[{obj, field, spec, is_root}]。哪些字段是图片、子牌在哪，全按 types.json 声明。
func images_of(data, kind_id:String) -> Array:
	var out:Array = []
	_images_walk(data, export_spec(kind_id), true, out)
	# 自定义牌的图同子牌：和本卡放同一个文件夹，名字前加子牌前缀
	for hit in custom_cards(data):
		_images_walk(hit.card, export_spec(str(hit.kind)), false, out)
	return out


func _images_walk(obj, spec:Dictionary, is_root:bool, out:Array) -> void:
	if not obj is Dictionary:
		return
	for field in spec.get("fields", []):
		if str(field.get("control", "")) == "image" and str(obj.get(field.key, "")) != "":
			out.append({"obj": obj, "field": field, "spec": spec, "is_root": is_root})
	var lists:Array = []
	for item in spec.get("lists", []):
		lists.append([obj, item])
	for group in spec.get("groups", []):
		if obj.get(group.key) is Dictionary:
			for item in group.get("lists", []):
				lists.append([obj[group.key], item])
	for pair in lists:
		var owner:Dictionary = pair[0]
		var item:Dictionary = pair[1]
		var child_spec := export_spec(str(item.get("item", "")))
		if not owner.get(item.key) is Array or child_spec.is_empty():
			continue
		for child in owner[item.key]:
			_images_walk(child, child_spec, false, out)


# 这张卡要带走的文件：json 本身 + 它引用的、就在 json 旁边的图片（去重）。
func card_files(data, kind_id:String, json_path:String) -> Array:
	var out:Array = [json_path]
	var folder := json_path.get_base_dir()
	for hit in images_of(data, kind_id):
		var p := folder.path_join(str(hit.obj[hit.field.key]))
		if FileAccess.file_exists(p) and not out.has(p):
			out.append(p)
	return out


# 同名文件不存在、或内容相同就用这个名字；内容不同就加 _2、_3……，不覆盖别的图。
func _free_name(folder:String, base:String, source:String) -> String:
	var ext := "." + source.get_extension().to_lower()
	var bytes := FileAccess.get_file_as_bytes(source)
	var n := 1
	while true:
		var name := base + ext if n == 1 else base + "_" + str(n) + ext
		var p := folder.path_join(name)
		if not FileAccess.file_exists(p) or FileAccess.get_file_as_bytes(p) == bytes:
			return name
		n += 1
	return base + ext


# 把一组文件打成 zip。条目路径相对 base（传项目根 res:// 就是 data/... 的结构，解压到项目根即可）。
func zip_files(files:Array, zip_path:String, base:String) -> Dictionary:
	if files.is_empty():
		return {"ok": false, "error": "没有要打包的文件"}
	_ensure_dir(zip_path.get_base_dir())
	var zip := ZIPPacker.new()
	if zip.open(_abs(zip_path)) != OK:
		return {"ok": false, "error": "zip 写不进去"}
	var base_abs := _abs(base).trim_suffix("/")
	for f in files:
		var entry := _abs(str(f)).trim_prefix(base_abs).trim_prefix("/")
		if entry == _abs(str(f)):
			entry = str(f).get_file()   # 不在 base 里的文件放在 zip 根
		zip.start_file(entry)
		zip.write_file(FileAccess.get_file_as_bytes(str(f)))
		zip.close_file()
	zip.close()
	return {"ok": true, "path": zip_path, "count": files.size()}


# =============== 导出设置 ===============

# 种类（或子牌类型）的声明，叠上用户的导出设置。只影响放在哪、叫什么、怎么打包，不影响卡的内容。
func export_spec(item_id:String) -> Dictionary:
	var spec := item_spec(item_id)
	var own:Dictionary = export_overrides.get(item_id, {})
	if own.is_empty():
		return spec
	var merged := spec.duplicate(true)
	for key in EXPORT_KEYS:
		if own.has(key):
			merged[key] = own[key]
	var images:Dictionary = own.get("images", {})
	for field in merged.get("fields", []):
		if images.has(str(field.key)):
			field["file_name"] = images[str(field.key)]
	return merged


# 某种卡有哪些可以设的导出项（界面据此画表单）：图片字段来自声明，不写死。
func export_fields(item_id:String) -> Dictionary:
	var spec := item_spec(item_id)
	var images:Array = []
	for field in spec.get("fields", []):
		if str(field.get("control", "")) == "image":
			images.append({"key": str(field.key), "shown": str(field.get("shown", field.key)), "default": str(field.get("file_name", "{identity}"))})
	return {"root": str(spec.get("root", "")), "file": str(spec.get("file", "")), "images": images}


# 设了导出项的种类，加上带图片字段的子牌类型（技能牌、状态、附带物……它们的图片名也能改）。
func export_kinds() -> Array:
	var out:Array = []
	for kind_id in types.get("kinds", {}):
		var fields := export_fields(str(kind_id))
		if fields.root != "" or not fields.images.is_empty():
			out.append({"id": str(kind_id), "shown": str(kind_spec(str(kind_id)).get("shown", kind_id))})
	return out


func set_export(item_id:String, key:String, value) -> void:
	if not export_overrides.has(item_id):
		export_overrides[item_id] = {}
	if value == null:
		export_overrides[item_id].erase(key)
	else:
		export_overrides[item_id][key] = value
	if export_overrides[item_id].is_empty():
		export_overrides.erase(item_id)


func set_export_image(item_id:String, field_key:String, pattern) -> void:
	var images:Dictionary = export_overrides.get(item_id, {}).get("images", {}).duplicate()
	if pattern == null:
		images.erase(field_key)
	else:
		images[field_key] = pattern
	set_export(item_id, "images", null if images.is_empty() else images)


func reset_export(item_id:String) -> void:
	export_overrides.erase(item_id)


func global_export(key:String, fallback):
	return export_overrides.get("_global", {}).get(key, fallback)


func load_export_settings(cfg_path := EXPORT_CFG) -> void:
	export_overrides = {}
	var cfg := ConfigFile.new()
	if cfg.load(cfg_path) != OK:
		return
	for key in cfg.get_section_keys("export") if cfg.has_section("export") else []:
		var value = cfg.get_value("export", key)
		if value is Dictionary:
			export_overrides[key] = value


func save_export_settings(cfg_path := EXPORT_CFG) -> bool:
	var cfg := ConfigFile.new()
	for key in export_overrides:
		cfg.set_value("export", key, export_overrides[key])
	return cfg.save(cfg_path) == OK


# zip 里的路径从哪一层开始算：
# project 相对项目根（data/masters/…，解压到项目根即可）；root 相对这种卡的根目录（00002_x/…）；
# folder 相对卡文件夹的上一层（只剩卡文件夹本身）；flat 所有文件直接放在 zip 根。
func zip_base(kind_id:String, json_path:String) -> String:
	var layout := str(export_spec(kind_id).get("zip_layout", "project"))
	var folder := json_path.get_base_dir()
	var root := _res(str(export_spec(kind_id).get("root", "")))
	match layout:
		"flat":
			return folder
		"folder":
			return folder.get_base_dir()
		"root":
			if str(export_spec(kind_id).get("root", "")) != "" and folder.begins_with(root):
				return root
			return folder.get_base_dir()
	if json_path.begins_with(LoadHelper.get_base_dir()):
		return LoadHelper.get_base_dir()
	# 项目外：从根目录的上一层算，保留「masters/…」这一层
	if str(export_spec(kind_id).get("root", "")) != "" and folder.begins_with(root):
		return root.get_base_dir()
	return folder.get_base_dir()


func _res(p:String) -> String:
	return LoadHelper.resolve_path(p)


func _abs(p:String) -> String:
	return ProjectSettings.globalize_path(p) if p.begins_with("res://") or p.begins_with("user://") else p


func images_near(path:String) -> Array:
	var folder := path.get_base_dir() if path.ends_with(".json") else path
	return _images_in(folder)


func copy_image(source:String, folder:String) -> Dictionary:
	if not FileAccess.file_exists(source):
		return {"ok": false, "error": "找不到这张图"}
	var ext := source.get_extension().to_lower()
	if not IMAGE_EXTS.has(ext):
		return {"ok": false, "error": "只接受图片文件"}
	_ensure_dir(folder)
	var file_name := source.get_file()
	var target := folder.path_join(file_name)
	if FileAccess.file_exists(target):
		if FileAccess.get_file_as_bytes(source) != FileAccess.get_file_as_bytes(target):
			return {"ok": false, "error": "同名图片内容不同，没有覆盖"}
		return {"ok": true, "file_name": file_name, "path": target}
	var err := DirAccess.copy_absolute(_abs(source), _abs(target))
	if err != OK:
		return {"ok": false, "error": "复制图片失败"}
	return {"ok": true, "file_name": file_name, "path": target}


func param_shown(name:String) -> String:
	var table:Dictionary = types.get("param_names", {})
	if table.has(name):
		return str(table[name])
	return name


# 积木句式与说明（types.json 的 blocks）。缺声明时退回摘要 + 按形参顺序排空位。
func block_spec(func_name:String) -> Dictionary:
	return types.get("blocks", {}).get(func_name, {})


# 声明里的分类 + 操作里出现了但声明里没有的分类（新登记的分类、未登记的新操作），后者灰色排在最后。
func categories() -> Array:
	var out:Array = types.get("categories", []).duplicate()
	var known := {}
	for item in out:
		known[str(item.id)] = true
	for op in operations:
		var cat := str(op.category)
		if known.has(cat):
			continue
		known[cat] = true
		out.append({"id": cat, "shown": "新操作" if cat == UNREGISTERED else cat, "color": "#8C8C8C", "reporter": false})
	return out


func category_of(category_shown:String) -> Dictionary:
	for item in categories():
		if str(item.id) == category_shown:
			return item
	return {}


# 哪些操作的哪几个参数是「一串操作」（C 形积木的嘴）。只认声明，不按参数名猜。
func container_params() -> Dictionary:
	var out := {}
	for item in operations:
		var names:Array = block_spec(item.func_name).get("script", [])
		if names.is_empty():
			continue
		var positions:Array = []
		for i in item.params.size():
			if names.has(item.params[i].name):
				positions.append(i)
		out[item.func_name] = positions
	return out


# 哪些操作的哪几个参数是选项列表（每项带自己的一串操作）。只认 blocks[x].kinds 里声明为 options 的。
func option_params() -> Dictionary:
	var out := {}
	for item in operations:
		var kinds:Dictionary = block_spec(item.func_name).get("kinds", {})
		var positions:Array = []
		for i in item.params.size():
			if str(kinds.get(item.params[i].name, "")) == "options":
				positions.append(i)
		if not positions.is_empty():
			out[item.func_name] = positions
	return out


# 空位用什么控件：先看这个操作的逐个声明，再看按形参名的总表，都没有就是普通输入框。
func param_kind(func_name:String, param_name:String) -> String:
	var own:Dictionary = block_spec(func_name).get("kinds", {})
	if own.has(param_name):
		return str(own[param_name])
	return str(types.get("param_kinds", {}).get(param_name, ""))


func kind_choices(kind:String) -> Array:
	return types.get("kind_choices", {}).get(kind, [])


# kind_choices 声明的可选值做成下拉分组；值原样带着（-1、null 都可以）。
func kind_choice_groups(kind:String) -> Array:
	var items:Array = []
	for c in kind_choices(kind):
		var v = _whole_numbers(c.get("v"))
		items.append({"id": "" if v == null else str(v), "shown": str(c.get("shown", "")), "value": v})
	return [] if items.is_empty() else [{"shown": "可选值", "items": items}]


# 卡背种类：直接读加载器用的 LoadHelper.CARD_BACK_FILES；中文名借 custom_card_type 和卡牌种类的名字，没有就显示原名。
func card_back_groups() -> Array:
	var names := {}
	for c in kind_choices("custom_card_type"):
		names[str(c.v)] = str(c.shown)
	var items:Array = []
	for key in LoadHelper.CARD_BACK_FILES:
		var id := str(key)
		items.append({"id": id, "shown": str(names.get(id, kind_spec(id).get("shown", "")))})
	return [{"shown": "卡背种类", "items": items}]


# 某个操作的某个参数在卡库里实际写过的字面值，按出现次数排，给空位当下拉候选。
# 只收字面值：文字、数字、开关，以及不含变量、效果数字、嵌套操作和整条效果的列表与字典。读一次存起来，重新扫描时清掉。
var _used_values = null


func used_value_groups(func_name:String, param_name:String) -> Array:
	if not _used_values is Dictionary:
		_used_values = {}
		var param_names := {}
		for kind in file_kinds():
			for file in list_files(str(kind.id)):
				_collect_used(read_json(str(file.path)), param_names)
	var found:Dictionary = _used_values.get(func_name + ":" + param_name, {})
	if found.is_empty():
		return []
	var rows:Array = found.values()
	rows.sort_custom(func(a, b): return a.id < b.id if a.count == b.count else a.count > b.count)
	var items:Array = []
	for row in rows:
		items.append({"id": row.id, "shown": "", "value": row.value})
	return [{"shown": "卡库里用过的", "items": items}]


func _collect_used(value, param_names:Dictionary) -> void:
	if value is Dictionary:
		if value.get("func_name") is String and value.get("parameters") is Array:
			var fn := str(value.func_name)
			if not param_names.has(fn):
				var list:Array = []
				for p in operation_of(fn).get("params", []):
					list.append(str(p.name))
				param_names[fn] = list
			var names:Array = param_names[fn]
			var params:Array = value.parameters
			for i in mini(params.size(), names.size()):
				if params[i] != null and not _has_ref(params[i]):
					_add_used(fn + ":" + str(names[i]), _whole_numbers(params[i]))
		for key in value:
			_collect_used(value[key], param_names)
	elif value is Array:
		for item in value:
			_collect_used(item, param_names)


func _has_ref(value) -> bool:
	if value is Dictionary:
		for key in ["self_var", "number_index", "func_name", "effect_name"]:
			if value.has(key):
				return true
		for key in value:
			if _has_ref(value[key]):
				return true
	elif value is Array:
		for item in value:
			if _has_ref(item):
				return true
	return false


func _add_used(where:String, value) -> void:
	var table:Dictionary = _used_values.get(where, {})
	var key := JSON.stringify(value)
	if not table.has(key):
		table[key] = {"id": value if value is String else key, "value": value, "count": 0}
	table[key].count += 1
	_used_values[where] = table


# 下拉搜索面板用的分组候选：[{shown, items:[{id, shown}]}]。
# 内部名：先列 data 里（正在编辑的这张卡）所有声明在 name_rules.fields 的内部名，再列 name_library 声明的卡库牌名。
# 传了 source 时，internal_name_sources 里给这个形参声明的字段和卡库种类排在前面，其余内部名归到「其他」组放在后面，不删。
func internal_name_groups(data, source:String = "") -> Array:
	var rules:Dictionary = types.get("name_rules", {})
	var fields:Dictionary = rules.get("fields", {})
	var shown_keys:Dictionary = rules.get("shown", {})
	var sources:Dictionary = types.get("internal_name_sources", {}).get(source, {})
	var allowed_fields:Array = sources.get("fields", [])
	var allowed_kinds:Array = sources.get("kinds", [])
	var found := {}
	_collect_names(data, fields, shown_keys, found)
	var first:Array = []
	var rest:Array = []
	for field in fields:
		if found.has(field):
			var group := {"shown": "这张卡里的" + str(fields[field]), "items": found[field]}
			(first if sources.is_empty() or allowed_fields.has(field) else rest).append(group)
	for group in library_name_groups():
		var fit := sources.is_empty()
		for kind in allowed_kinds:
			if str(group.shown) == "卡库里的" + str(kind_spec(str(kind)).get("shown", kind)):
				fit = true
		(first if fit else rest).append(group)
	for group in rest:
		first.append({"shown": "其他 · " + str(group.shown), "items": group.items})
	return first


# 卡库牌名要读全部卡文件，读一次存起来；重新扫描积木时清掉
var _library_names = null


func library_name_groups() -> Array:
	if _library_names is Array:
		return _library_names
	_library_names = []
	for kind in types.get("name_library", {}).get("kinds", []):
		var spec := kind_spec(str(kind))
		var items:Array = []
		for file in list_files(str(kind)):
			var card = read_json(str(file.path))
			var cards:Array = card if card is Array else [card]
			for one in cards:
				if one is Dictionary and str(one.get(spec.get("identity", ""), "")) != "":
					items.append({"id": str(one[spec.identity]), "shown": str(one.get(spec.get("shown_key", ""), ""))})
		if not items.is_empty():
			_library_names.append({"shown": "卡库里的" + str(spec.get("shown", kind)), "items": items})
	return _library_names


func _collect_names(value, fields:Dictionary, shown_keys:Dictionary, found:Dictionary) -> void:
	if value is Dictionary:
		for field in fields:
			if value.get(field) is String and str(value[field]) != "":
				var list:Array = found.get(field, [])
				var id := str(value[field])
				if not list.any(func(x): return x.id == id):
					list.append({"id": id, "shown": str(value.get(shown_keys.get(field, ""), ""))})
				found[field] = list
		for key in value:
			_collect_names(value[key], fields, shown_keys, found)
	elif value is Array:
		for item in value:
			_collect_names(item, fields, shown_keys, found)


# 对象属性名：按 object_classes 反射脚本自己声明的属性（不含父类的，父类另成一组），中文名查 property_names。
# 传了控件名时按 object_property_filters 声明的值类型筛。
func object_property_groups(kind:String = "") -> Array:
	var rule = types.get("object_property_filters", {}).get(kind)
	return script_property_groups(types.get("object_classes", {}).get("scripts", {}), rule.get("types", []) if rule is Dictionary else [])


# 其余按脚本属性列候选的空位（游戏数据键、战场数据键……）：types.json 的 property_sources 声明 {控件名: {分组名: 脚本路径}}。
func property_source_groups(kind:String) -> Array:
	var scripts = types.get("property_sources", {}).get(kind)
	return script_property_groups(scripts) if scripts is Dictionary else []


# {分组名: 脚本路径} → 每个脚本自己声明的属性一组。want_types 不空时只留这些类型的属性（类取 class_name）。
func script_property_groups(scripts:Dictionary, want_types:Array = []) -> Array:
	var names:Dictionary = types.get("property_names", {})
	var out:Array = []
	for group in scripts:
		var script = load(str(scripts[group])) if ResourceLoader.exists(str(scripts[group])) else null
		if not script is Script:
			continue
		var items:Array = []
		for prop in script.get_script_property_list():
			var pname := str(prop.name)
			if int(prop.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0 or pname.ends_with(".gd"):
				continue
			if not want_types.is_empty():
				var ptype := str(prop.class_name) if str(prop.get("class_name", "")) != "" else type_string(int(prop.type))
				if not want_types.has(ptype):
					continue
			items.append({"id": pname, "shown": str(names.get(pname, ""))})
		if not items.is_empty():
			out.append({"shown": str(group), "items": items})
	return out


# 玩家数据键：与原来的下拉同一份来源（GameData.new_player_data 的键），中文名查 player_key_names。
# 传了控件名时按 player_key_filters 的声明筛（值类型、要不要「区.子项」路径、另列的路径）；没声明就全列。
func player_key_groups(kind:String = "") -> Array:
	var names:Dictionary = types.get("player_key_names", {})
	var rule = types.get("player_key_filters", {}).get(kind)
	var items:Array = []
	var keys:Array = player_keys.duplicate()
	if rule is Dictionary:
		for extra in rule.get("extra", []):
			if not keys.has(str(extra)):
				keys.append(str(extra))
	for key in keys:
		if rule is Dictionary:
			var dotted := str(key).find(".") != -1
			if dotted and not bool(rule.get("dotted", false)):
				continue
			var want:Array = rule.get("values", [])
			if player_key_types.has(key) and not want.is_empty() and not want.has(player_key_types[key]):
				continue
		var base := str(key).split(".")[0]
		var shown := str(names.get(key, "")) if names.has(key) else (str(names.get(base, base)) + " · " + str(key).get_slice(".", 1) if str(key).find(".") != -1 else "")
		items.append({"id": str(key), "shown": shown})
	return [{"shown": "玩家数据", "items": items}]


# ---------- 空位能放什么结果 ----------
# 空位接受的类型：blocks[x].accepts → param_accepts（按形参名）→ 形参自己的类型。
func param_accept(func_name:String, param_name:String, type_name:String) -> String:
	var own:Dictionary = block_spec(func_name).get("accepts", {})
	if own.has(param_name):
		return str(own[param_name])
	var table:Dictionary = types.get("param_accepts", {})
	if table.has(param_name) and param_name != "note":
		return str(table[param_name])
	return type_name


# 积木给出的结果类型：blocks[x].result 的声明优先，否则用反射到的 exec 返回类型，都没有是空（不知道）。
func result_of(func_name:String) -> String:
	var spec := block_spec(func_name)
	if spec.has("result"):
		return str(spec.result)
	return str(operation_of(func_name).get("returns", ""))


# 结果能不能放进空位。不知道的一边（空、Variant、Nil）一律算能放，不猜；
# 「没有结果」哪里都不放。多种可接受用 | 分开，数组比较元素类型，类按 class_name 的继承关系比较。
func type_fits(accept:String, result:String) -> bool:
	if result == "none":
		return false
	if _unknown_type(accept) or _unknown_type(result):
		return true
	for want in accept.split("|"):
		for got in result.split("|"):
			if _one_type_fits(want.strip_edges(), got.strip_edges()):
				return true
	return false


func _unknown_type(type_name:String) -> bool:
	return type_name in ["", "Variant", "Nil"]


func _one_type_fits(want:String, got:String) -> bool:
	if _unknown_type(want) or _unknown_type(got) or want == got:
		return true
	var want_elem = _array_elem(want)
	var got_elem = _array_elem(got)
	if want_elem != null or got_elem != null:
		# 数组对数组才比元素；一边写的是不带元素的 Array 就算相符
		if want_elem == null:
			return want == "Array"
		if got_elem == null:
			return got == "Array"
		return _one_type_fits(want_elem, got_elem)
	var families:Dictionary = types.get("type_families", {})
	for family in families:
		if family == "note":
			continue
		var members:Array = families[family]
		var want_in:bool = want == family or members.has(want)
		var got_in:bool = got == family or members.has(got)
		if want_in and got_in:
			return true
	# 玩家编号本身就是整数：整数格也能放
	if got == "player":
		return want == "int" or want == "number"
	return _is_subclass(got, want)


# "Array[X]" 返回 "X"，不是数组类型返回 null。
func _array_elem(type_name:String):
	if type_name.begins_with("Array[") and type_name.ends_with("]"):
		return type_name.substr(6, type_name.length() - 7)
	return null


var _class_parents = null   # class_name -> 父类名，读 ProjectSettings 的全局类表


func _is_subclass(child:String, parent:String) -> bool:
	if not _class_parents is Dictionary:
		_class_parents = {}
		for info in ProjectSettings.get_global_class_list():
			_class_parents[str(info["class"])] = str(info["base"])
	var at := child
	var guard := 0
	while _class_parents.has(at) and guard < 32:
		at = str(_class_parents[at])
		if at == parent:
			return true
		guard += 1
	return false


# value_sources 声明的卡库文字值：读 kinds 里各卡种的全部文件，收集任意层级 field 键的文字值。
var _value_source_cache := {}


func value_source_groups(kind:String) -> Array:
	var rule = types.get("value_sources", {}).get(kind)
	if not rule is Dictionary:
		return []
	if not _value_source_cache.has(kind):
		var found := {}
		for card_kind in rule.get("kinds", []):
			for file in list_files(str(card_kind)):
				_collect_field(read_json(str(file.path)), str(rule.get("field", "")), found)
		var items:Array = []
		var ids := found.keys()
		ids.sort()
		for id in ids:
			items.append({"id": str(id), "shown": ""})
		_value_source_cache[kind] = [] if items.is_empty() else [{"shown": "卡库里的", "items": items}]
	return _value_source_cache[kind]


func _collect_field(value, field:String, found:Dictionary) -> void:
	if value is Dictionary:
		if value.get(field) is String and str(value[field]) != "":
			found[str(value[field])] = true
		for key in value:
			_collect_field(value[key], field, found)
	elif value is Array:
		for item in value:
			_collect_field(item, field, found)


# 操作执行后给不给出结果：只有 no_result 显式列出的操作算没有结果。
func has_result(func_name:String) -> bool:
	return not (types.get("no_result", {}).get("funcs", []) as Array).has(func_name)


func time_point_shown(point_id:String) -> String:
	var shown := _time_point_known(point_id)
	return shown if shown != "" else point_id


func operation_of(func_name:String) -> Dictionary:
	for item in operations:
		if item.func_name == func_name:
			return item
	for item in _power_blocks():
		if item.func_name == func_name:
			return item
	return {}


func _power_blocks() -> Array:
	# 这三个只在威力计算里由 BoardPowerQuery 解释，不是 operations 目录里的文件。
	return [
		{"func_name": "power_contribution", "shown": "给这名玩家加上合计威力", "category": "威力计算", "params": [
			{"name": "unused", "type": "Variant", "required": false, "default": null},
			{"name": "amount", "type": "BaseNumber", "required": true, "default": null},
			{"name": "player_id", "type": "int", "required": true, "default": null}
		]},
		{"func_name": "attack_power_contribution", "shown": "按攻击牌条件加上合计威力", "category": "威力计算", "params": [
			{"name": "attributes", "type": "Array", "required": false, "default": []},
			{"name": "amount", "type": "BaseNumber", "required": true, "default": null},
			{"name": "player_id", "type": "int", "required": true, "default": null},
			{"name": "only_card", "type": "Variant", "required": false, "default": null},
			{"name": "except_card", "type": "Variant", "required": false, "default": null},
			{"name": "category", "type": "String", "required": false, "default": ""},
			{"name": "min_power", "type": "int", "required": false, "default": -1}
		]},
		{"func_name": "card_power_contribution", "shown": "改这张攻击牌的当前威力", "category": "威力计算", "params": [
			{"name": "card", "type": "BaseAttack", "required": true, "default": null},
			{"name": "vary", "type": "BaseNumber", "required": false, "default": null},
			{"name": "set_to", "type": "BaseNumber", "required": false, "default": null},
			{"name": "player_id", "type": "int", "required": true, "default": null}
		]}
	]


func _fill_object(data:Dictionary, spec:Dictionary) -> void:
	for field in spec.get("fields", []):
		if data.has(field.key):
			continue
		data[field.key] = _default_of(field)
	for item in spec.get("lists", []):
		if not data.has(item.key):
			data[item.key] = []
	for group in spec.get("groups", []):
		if not data.has(group.key) or not data[group.key] is Dictionary:
			data[group.key] = {}
		for item in group.get("lists", []):
			if not data[group.key].has(item.key):
				data[group.key][item.key] = []


func _default_of(field:Dictionary):
	match str(field.get("control", "text")):
		"bool":
			return false
		"int":
			return 0
		"float":
			return 0
		"number":
			return {"number": 0, "can_change": true, "is_pure_number": true}
		"attributes", "lines", "time_points", "requirements":
			return []
		"cost":
			return {}
		_:
			return ""


func _check_object(data:Dictionary, spec:Dictionary, where:String) -> void:
	for field in spec.get("fields", []):
		var key := str(field.key)
		if bool(field.get("required", false)) and not data.has(key):
			issues.append(_where(where) + str(field.get("shown", key)) + " 还没填")
			continue
		if data.has(key):
			_check_value(data[key], field, _where(where) + str(field.get("shown", key)))
			_check_name(data[key], key, _where(where) + str(field.get("shown", key)))
	for item in spec.get("lists", []):
		if bool(item.get("required", false)) and not data.has(item.key):
			issues.append(_where(where) + str(item.get("shown", item.key)) + " 缺失")
			continue
		if data.has(item.key):
			_check_list(data[item.key], str(item.get("item", "")), str(item.get("shown", item.key)), where)
	for group in spec.get("groups", []):
		if bool(group.get("required", false)) and not data.get(group.key) is Dictionary:
			issues.append(_where(where) + str(group.get("shown", group.key)) + " 缺失")
			continue
		if data.get(group.key) is Dictionary:
			for item in group.get("lists", []):
				if data[group.key].has(item.key):
					_check_list(data[group.key][item.key], str(item.get("item", "")), str(item.get("shown", item.key)), where)
	if spec.has("blocks"):
		_check_effect_shape(data, spec, where)


func _check_list(value, item_id:String, label:String, where:String) -> void:
	if not value is Array:
		issues.append(_where(where) + label + " 应该是列表")
		return
	if item_id == "text" or item_id == "deck_ref":
		return
	var child := item_spec(item_id)
	if child.is_empty():
		return
	for i in value.size():
		var prefix := _where(where) + label + " " + str(i + 1) + " / "
		if not value[i] is Dictionary:
			issues.append(prefix + "不是对象")
			continue
		_check_object(value[i], child, prefix)
	_check_unique_names(value, _where(where) + label)


# 内部名格式：规则写在 types.json 的 name_rules，只检查其中列出的字段。
func _check_name(value, key:String, label:String) -> void:
	var rules:Dictionary = types.get("name_rules", {})
	if not rules.get("fields", {}).has(key) or str(value) == "":
		return
	var regex := RegEx.new()
	if regex.compile(str(rules.get("pattern", ""))) != OK:
		return
	if regex.search(str(value)) == null:
		issues.append(label + " 「" + str(value) + "」格式不对：" + str(rules.get("pattern_shown", "")))


# 同一列表里不能重名的内部名（name_rules.unique_in_list 声明）。
func _check_unique_names(list:Array, label:String) -> void:
	for key in types.get("name_rules", {}).get("unique_in_list", []):
		var seen := {}
		for item in list:
			if not item is Dictionary or str(item.get(key, "")) == "":
				continue
			var name := str(item[key])
			if seen.has(name):
				issues.append(label + " 里有重名的「" + name + "」")
			seen[name] = true


func _check_value(value, field:Dictionary, label:String) -> void:
	match str(field.get("control", "")):
		"number":
			if not value is Dictionary or not value.has("number") or not value.has("can_change") or not value.has("is_pure_number"):
				issues.append(label + " 的数字不完整")
		"image":
			if str(value) == "":
				if bool(field.get("required", false)):
					issues.append(label + " 还没选图")
		"choice":
			var choices:Array = field.get("choices", [])
			if not choices.is_empty() and value != null and str(value) != "" and not choices.has(value):
				issues.append(label + " 不在可选项里")
		"time_points":
			if not value is Array:
				issues.append(label + " 应该是时机列表")
			else:
				for item in value:
					if _time_point_known(str(item)) == "":
						issues.append(label + " 有未登记时机 " + str(item))
		"cost":
			if value is Dictionary and not value.is_empty():
				if value.has("number"):
					_check_value(value, {"control": "number"}, label)
				elif not value.has("type"):
					issues.append(label + " 既不是魔力数字也不是资源类型")


func _check_effect_shape(data:Dictionary, spec:Dictionary, where:String) -> void:
	var has_options:bool = data.has("options") and data.options is Array and not data.options.is_empty()
	for block in spec.get("blocks", []):
		var key := str(block.key)
		if key == "funcs" and str(block.get("unless", "")) == "options" and has_options:
			continue
		if not data.has(key):
			if str(block.get("unless", "")) == "" and key == "funcs" and not has_options:
				issues.append(_where(where) + str(block.get("shown", key)) + " 还没写")
			return
		if not data[key] is Array:
			issues.append(_where(where) + str(block.get("shown", key)) + " 应该是操作列表")
			return
		for i in data[key].size():
			_check_block(data[key][i], _where(where) + str(block.get("shown", key)) + " " + str(i + 1))
	if data.has("effect_numbers") and data.effect_numbers is Array:
		_check_number_refs(data, where)


func _check_block(block, label:String) -> void:
	if not block is Dictionary:
		issues.append(label + " 不是操作")
		return
	if block.has("func_name"):
		var op := operation_of(str(block.func_name))
		if op.is_empty():
			issues.append(label + " 没有这个操作：" + str(block.func_name))
		if not block.get("parameters", []) is Array:
			issues.append(label + " 的参数不是列表")
		else:
			var given:int = block.parameters.size()
			var required_count:int = 0
			for param in op.get("params", []):
				if bool(param.get("required", false)):
					required_count += 1
			if not op.is_empty() and given < required_count:
				issues.append(label + " 至少要 " + str(required_count) + " 个参数，现在是 " + str(given) + " 个")
			for param in block.parameters:
				_check_param(param, label)
			for hit in _custom_cards_of_block(block):
				_check_object(hit.card, kind_spec(hit.kind), label + " 生成的「" + str(hit.card.get(kind_spec(hit.kind).get("identity", ""), "")) + "」 / ")
	elif block.has("self_var"):
		if str(block.get("sub_func", "")) == "":
			issues.append(label + " 没写要调用的方法")
	else:
		issues.append(label + " 既不是操作也不是对象方法")


func _check_param(param, label:String) -> void:
	if param is Dictionary and param.has("func_name"):
		_check_block(param, label + " 里嵌的操作")
	elif param is Array:
		for item in param:
			if item is Dictionary and (item.has("func_name") or item.has("self_var")):
				_check_block(item, label + " 里嵌的操作")


func _check_number_refs(effect:Dictionary, where:String) -> void:
	var count:int = effect.effect_numbers.size()
	_walk_refs(effect.get("funcs", []), count, where)
	_walk_refs(effect.get("power_query", []), count, where)
	for option in effect.get("options", []):
		if option is Dictionary:
			_walk_refs(option.get("funcs", []), count, where)


func _walk_refs(node, count:int, where:String) -> void:
	# 嵌着的整条效果引用的是它自己的效果数字，由检查那张牌时单独查
	if node is Dictionary and node.has("effect_name"):
		return
	if node is Dictionary:
		if node.has("number_index") and int(node.number_index) >= count:
			issues.append(_where(where) + "引用了不存在的效果数字")
		for key in node:
			_walk_refs(node[key], count, where)
	elif node is Array:
		for item in node:
			_walk_refs(item, count, where)


# 一块操作里写着的自定义牌：参数声明为 card_data 的那一格是整张牌，
# 同一块里声明为 custom_card_type 的那一格决定它按哪种卡解释（custom_card_types 表）。只认声明，不按内容猜。
func _custom_cards_of_block(block:Dictionary) -> Array:
	var out:Array = []
	var func_name := str(block.get("func_name", ""))
	var op := operation_of(func_name)
	var params:Array = block.get("parameters", []) if block.get("parameters") is Array else []
	var data_at := -1
	var type_at := -1
	for i in op.get("params", []).size():
		match param_kind(func_name, str(op.params[i].name)):
			"card_data":
				data_at = i
			"custom_card_type":
				type_at = i
	if data_at < 0 or data_at >= params.size() or not params[data_at] is Dictionary:
		return out
	var type_id := str(params[type_at]) if type_at >= 0 and type_at < params.size() else ""
	var kind := custom_card_kind(type_id)
	if kind != "":
		out.append({"card": params[data_at], "kind": kind})
	return out


# 自定义牌的种类 → types.json 的卡种（决定表单、校验与图片命名）。
func custom_card_kind(type_id:String) -> String:
	for item in types.get("custom_card_types", []):
		if str(item.type) == type_id:
			return str(item.kind)
	return ""


# 整张卡里所有写在操作里的自定义牌（含自定义牌自己效果里再生成的），[{card, kind}]。
func custom_cards(value, out:Array = []) -> Array:
	if value is Dictionary:
		if value.has("func_name"):
			out.append_array(_custom_cards_of_block(value))
		for key in value:
			custom_cards(value[key], out)
	elif value is Array:
		for item in value:
			custom_cards(item, out)
	return out


func _where(prefix:String) -> String:
	return prefix if prefix != "" else ""


func _scan_json(folder:String, mode:String, out:Array) -> void:
	var dir := DirAccess.open(folder)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var path := folder.path_join(name)
		if dir.current_is_dir():
			if mode == "folder":
				var json_path := path.path_join(name + ".json")
				if FileAccess.file_exists(json_path):
					var data = read_json(json_path)
					var shown := name
					if data is Dictionary:
						for key in ["shown_master_name", "shown_servant_name", "shown_attack_name", "shown_name", "shown_skill_name"]:
							if str(data.get(key, "")) != "":
								shown = str(data[key])
								break
					out.append({"path": json_path, "shown": shown})
				else:
					_scan_json(path, mode, out)
			else:
				_scan_json(path, mode, out)
		elif mode == "file" and name.ends_with(".json"):
			out.append({"path": path, "shown": name.get_basename()})
		name = dir.get_next()


func _images_in(folder:String) -> Array:
	var out:Array = []
	var dir := DirAccess.open(folder)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and IMAGE_EXTS.has(name.get_extension().to_lower()):
			out.append(folder.path_join(name))
		name = dir.get_next()
	out.sort()
	return out


func _ensure_dir(folder:String) -> void:
	DirAccess.make_dir_recursive_absolute(_abs(folder))


const ALL_OPS_PATH := "res://assets/scripts/system/global/all_operations.gd"
const UNREGISTERED := "未登记"

var _op_mtimes := {}   # 脚本路径 -> 上次读到的修改时间，变了就绕过缓存重新读


# 按 operations 目录里实际存在的脚本列出积木，不只看登记表：新加的脚本不登记也能马上用。
# 登记表只提供分类与摘要；没登记的归到「新操作」，说明取脚本开头的注释。
func _load_operations() -> void:
	operations.clear()
	var table:Dictionary = AllOperations.TABLE
	var category_shown:Dictionary = AllOperations.CATEGORY_SHOWN
	# 运行中改了登记表时读一份新的（不替换全局缓存）
	if FileAccess.get_modified_time(ALL_OPS_PATH) != int(_op_mtimes.get(ALL_OPS_PATH, FileAccess.get_modified_time(ALL_OPS_PATH))):
		var fresh = ResourceLoader.load(ALL_OPS_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
		if fresh is Script:
			var consts:Dictionary = fresh.get_script_constant_map()
			table = consts.get("TABLE", table)
			category_shown = consts.get("CATEGORY_SHOWN", category_shown)
	_op_mtimes[ALL_OPS_PATH] = FileAccess.get_modified_time(ALL_OPS_PATH)
	var by_class := {}
	for func_name in table:
		by_class[str(table[func_name].get("class", ""))] = str(func_name)
	for file_name in _op_files():
		var class_text:String = str(file_name).get_basename()
		var func_name := str(by_class.get(class_text, _snake(class_text)))
		# JSON 靠 func_name 反推类名来找脚本；推不回同一个文件的，JSON 调不到，不列
		if LoadHelper.func_name_to_class_name(func_name) != class_text:
			continue
		var path:String = OPS_DIR + str(file_name)
		var params = _reflect_params(class_text)
		if params == null:
			continue
		var row:Dictionary = table.get(func_name, {})
		var registered := not row.is_empty()
		var summary := str(row.get("summary", "")) if registered else _script_comment(path)
		var item := {
			"func_name": func_name,
			"shown": str(block_spec(func_name).get("say", summary if summary != "" else func_name)),
			"category": str(category_shown.get(row.get("category", ""), row.get("category", ""))) if registered else UNREGISTERED,
			"params": params,
			"returns": _reflect_return(class_text),
			"registered": registered,
			"help": str(block_spec(func_name).get("help", summary))
		}
		operations.append(item)
	for item in _power_blocks():
		item.shown = str(block_spec(item.func_name).get("say", item.shown))
		item["help"] = str(block_spec(item.func_name).get("help", ""))
		operations.append(item)
	for item in operations:
		item["say"] = _say_of(item)
	operations.sort_custom(func(a, b): return str(a.category) + a.shown < str(b.category) + b.shown)


# 没写句式的积木：名字后面按形参顺序排出空位，保证每个参数都有地方填。
func _say_of(item:Dictionary) -> String:
	var spec := block_spec(str(item.func_name))
	if spec.has("say"):
		return str(spec.say)
	var parts:Array = [str(item.shown)]
	for p in item.get("params", []):
		parts.append("{" + str(p.name) + "}")
	return " ".join(PackedStringArray(parts))


func say_of(func_name:String) -> String:
	var op := operation_of(func_name)
	return str(op.get("say", block_spec(func_name).get("say", func_name)))


func help_of(func_name:String) -> String:
	return str(operation_of(func_name).get("help", block_spec(func_name).get("help", "")))


func _op_files() -> Array:
	var out:Array = []
	var dir := DirAccess.open(OPS_DIR)
	if dir == null:
		return out
	for file_name in dir.get_files():
		# 导出后的工程里脚本可能是 .gd.remap
		var name := file_name.trim_suffix(".remap")
		if name.ends_with(".gd"):
			out.append(name)
	out.sort()
	return out


# 目录里的脚本名单 + 各自修改时间 + 登记表与声明文件的修改时间。任何一项变了就该重新扫描。
func catalog_signature() -> String:
	var parts:Array = []
	for file_name in _op_files():
		parts.append(file_name + ":" + str(FileAccess.get_modified_time(OPS_DIR + file_name)))
	parts.append(str(FileAccess.get_modified_time(ALL_OPS_PATH)))
	parts.append(str(FileAccess.get_modified_time(TYPES_PATH)))
	return "|".join(PackedStringArray(parts))


func reload_catalog() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(TYPES_PATH))
	if parsed is Dictionary:
		types = parsed
	_library_names = null
	_identity_index = null
	_used_values = null
	_value_source_cache.clear()
	_load_operations()


func _snake(class_text:String) -> String:
	var out := ""
	for i in class_text.length():
		var ch := class_text[i]
		if ch != ch.to_lower() and i > 0:
			out += "_"
		out += ch.to_lower()
	return out


func _script_comment(path:String) -> String:
	var lines:Array = []
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var text := line.strip_edges()
		if text.begins_with("func "):
			break
		if text.begins_with("#"):
			lines.append(text.trim_prefix("#").strip_edges())
	return " ".join(PackedStringArray(lines)).left(120)


func _reflect_params(class_name_text:String):
	var path := OPS_DIR + class_name_text + ".gd"
	if not ResourceLoader.exists(path):
		return null
	var script = _load_op_script(path)
	if not script is GDScript or not script.can_instantiate():
		return null
	var inst = script.new()
	for method in inst.get_method_list():
		if method.name != "exec":
			continue
		var args:Array = method.args
		var defaults:Array = method.default_args
		var required := args.size() - defaults.size()
		var params:Array = []
		# 反射拿不到非常量默认值（如 BaseNumber.new(0) 会报成 null），按源码里的签名补上
		var source := FileAccess.get_file_as_string(path)
		for i in args.size():
			var arg:Dictionary = args[i]
			var type_name := str(arg.class_name) if arg.class_name != &"" else type_string(arg.type)
			var default_value = null if i < required else defaults[i - required]
			var number_default := RegEx.create_from_string(str(arg.name) + "\\s*:\\s*BaseNumber\\s*=\\s*BaseNumber\\.new\\(\\s*(-?[0-9.]+)\\s*\\)").search(source)
			if number_default != null:
				default_value = {"_base_number": true, "number": number_default.get_string(1).to_float()}
			# 默认值是数字对象时记成可写进 JSON 的形状，界面按它新建效果数字
			if default_value is BaseNumber:
				default_value = {"_base_number": true, "number": default_value.number}
			elif default_value is Object:
				default_value = null
			params.append({
				"name": str(arg.name),
				"type": type_name,
				"required": i < required,
				"default": default_value
			})
		return params
	return null


# 脚本改过就绕过缓存重新读，拿到新的形参；没改过走缓存。
func _load_op_script(path:String):
	var mtime := FileAccess.get_modified_time(path)
	var changed:bool = _op_mtimes.has(path) and int(_op_mtimes[path]) != mtime
	_op_mtimes[path] = mtime
	if changed:
		return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	return load(path)


func _reflect_return(class_name_text:String) -> String:
	var path := OPS_DIR + class_name_text + ".gd"
	if not ResourceLoader.exists(path):
		return ""
	var script = load(path)
	if not script is GDScript or not script.can_instantiate():
		return ""
	var inst = script.new()
	for method in inst.get_method_list():
		if method.name == "exec":
			var ret:Dictionary = method["return"]
			if str(ret.get("class_name", "")) != "":
				return str(ret.class_name)
			match int(ret.type):
				TYPE_BOOL, TYPE_ARRAY, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_DICTIONARY:
					return type_string(int(ret.type))
			return ""
	return ""


func _load_time_points() -> void:
	time_points.clear()
	var script := load("res://assets/scripts/system/time_points.gd")
	var constants:Dictionary = script.get_script_constant_map()
	var shown:Dictionary = constants.get("shown_time_points", {})
	for key in constants:
		var value = constants[key]
		if key.ends_with("_PREFIX") or not value is String:
			continue
		if str(value) == "" or str(value).find(" ") != -1:
			continue
		if not str(value).is_valid_identifier():
			continue
		time_points.append({"id": str(value), "shown": str(shown.get(value, value))})
	time_points.sort_custom(func(a, b): return a.shown < b.shown)


# 时机分组：按 types.json 的 time_point_groups 声明排，没列进任何一组的放进「未分类」。
func time_point_groups() -> Array:
	var out:Array = []
	var placed := {}
	for group in types.get("time_point_groups", []):
		var items:Array = []
		for point_id in group.get("points", []):
			var shown := _time_point_known(str(point_id))
			if shown == "":
				continue
			items.append({"id": str(point_id), "shown": shown})
			placed[str(point_id)] = true
		if not items.is_empty():
			out.append({"shown": str(group.get("shown", "")), "points": items})
	var rest:Array = time_points.filter(func(p): return not placed.has(p.id))
	if not rest.is_empty():
		out.append({"shown": "未分类", "points": rest})
	return out


func _time_point_known(point_id:String) -> String:
	for item in time_points:
		if item.id == point_id:
			return item.shown
	return ""


func _load_attributes() -> void:
	attributes.clear()
	for attr in Attributes.get_all_attributes():
		attributes.append({"id": str(attr), "shown": Attributes.get_shown_attribute(str(attr))})


func _load_player_keys() -> void:
	player_keys.clear()
	player_key_types.clear()
	var data := GameData.new_player_data()
	for key in data:
		player_keys.append(str(key))
		player_key_types[str(key)] = _value_type(data[key])
		if data[key] is Dictionary:
			for child in data[key]:
				var path := str(key) + "." + str(child)
				player_keys.append(path)
				player_key_types[path] = _value_type(data[key][child])
	player_keys.sort()


# 值的类型名：对象取脚本的 class_name（数字对象是 BaseNumber），其余用内置类型名，null 是 Nil。
func _value_type(value) -> String:
	if value is Object and value.get_script() != null and str(value.get_script().get_global_name()) != "":
		return str(value.get_script().get_global_name())
	return type_string(typeof(value))


# =============== 新手教程 ===============
# 教程全是数据：目录里每份 json 是一套，步骤的说明、配图、高亮的控件、完成条件都写在文件里，程序只负责显示与判定。

const TUTORIAL_DIR := "res://json_maker/tutorials"


# 目录里的教程，按 order 再按文件名排。没有 steps 列表的文件不算教程。
func list_tutorials(folder := TUTORIAL_DIR) -> Array:
	var out:Array = []
	var dir := DirAccess.open(folder)
	if dir == null:
		return out
	for name in dir.get_files():
		if name.get_extension().to_lower() != "json":
			continue
		var file_path := folder.path_join(name)
		var loaded = read_json(file_path)
		if not loaded is Dictionary or not loaded.get("steps") is Array:
			continue
		out.append({"path": file_path, "title": str(loaded.get("title", name.get_basename())), "order": float(loaded.get("order", 0)), "data": loaded})
	out.sort_custom(func(a, b): return a.order < b.order if a.order != b.order else str(a.path) < str(b.path))
	return out


# 一条完成条件。from 选数据来源：data（正在编辑的整张卡，默认）或 state（界面状态）。
# path 逐段往里走：文字是键名，数字是下标，字典表示「列表里第一个包含这些内容的那一项」。
# 走到之后按 has（期望值是实际值的一部分）或 not_empty 判断；都没写就只要求那里有值。
func tutorial_check(check:Dictionary, data, state:Dictionary) -> bool:
	var value = state if str(check.get("from", "data")) == "state" else data
	for part in check.get("path", []):
		value = _step_into(value, part)
	if check.has("has"):
		return value_has(value, check.has)
	if bool(check.get("not_empty", false)):
		return not _is_blank(value)
	return value != null


func _step_into(value, part):
	if part is Dictionary:
		if value is Array:
			for item in value:
				if value_has(item, part):
					return item
		return null
	if value is Dictionary:
		return value.get(str(part))
	if value is Array and (part is int or part is float) and int(part) >= 0 and int(part) < value.size():
		return value[int(part)]
	return null


# expected 是不是 actual 的一部分：字典逐键比较；列表里每一项都要能在实际列表里找到；数字按数值比较；其余要相等。
func value_has(actual, expected) -> bool:
	if expected is Dictionary:
		if not actual is Dictionary:
			return false
		for key in expected:
			if not actual.has(key) or not value_has(actual[key], expected[key]):
				return false
		return true
	if expected is Array:
		if not actual is Array:
			return false
		for want in expected:
			if not actual.any(func(got): return value_has(got, want)):
				return false
		return true
	if (expected is int or expected is float) and (actual is int or actual is float):
		return float(expected) == float(actual)
	return typeof(actual) == typeof(expected) and actual == expected


func _is_blank(value) -> bool:
	if value == null:
		return true
	if value is String:
		return value.strip_edges() == ""
	if value is Array or value is Dictionary:
		return value.is_empty()
	return false
