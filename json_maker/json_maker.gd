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
var issues:Array = []
# 用户自己的导出设置（存在 user://，不动源码与 types.json）：{种类或子牌类型: {root, folder_name, serial_digits, pattern_defaults, sub_image_prefix, images:{字段: 命名}, zip_layout}, "_global": {zip_dir}}
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
	# 有找不到的图就一张都不搬，免得留下半套文件
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


# 空位用什么控件：先看这个操作的逐个声明，再看按形参名的总表，都没有就是普通输入框。
func param_kind(func_name:String, param_name:String) -> String:
	var own:Dictionary = block_spec(func_name).get("kinds", {})
	if own.has(param_name):
		return str(own[param_name])
	return str(types.get("param_kinds", {}).get(param_name, ""))


func kind_choices(kind:String) -> Array:
	return types.get("kind_choices", {}).get(kind, [])


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
	if node is Dictionary:
		if node.has("number_index") and int(node.number_index) >= count:
			issues.append(_where(where) + "引用了不存在的效果数字")
		for key in node:
			_walk_refs(node[key], count, where)
	elif node is Array:
		for item in node:
			_walk_refs(item, count, where)


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
			return "bool" if int(method["return"].type) == TYPE_BOOL else ""
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
	var data := GameData.new_player_data()
	for key in data:
		player_keys.append(str(key))
		if data[key] is Dictionary:
			for child in data[key]:
				player_keys.append(str(key) + "." + str(child))
	player_keys.sort()
