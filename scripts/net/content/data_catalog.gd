class_name MatchDataCatalog
extends RefCounted

## 目录类别与 JSON 模板字段显式对应；不加载客机脚本，不推断缺少的 requires。
const NAMES := {"masters": "master_name", "servants": "servant_name", "attacks": "attack_name", "events": "card_name", "situations": "card_name", "command_spells": "card_name"}
const SHOWN_NAMES := {"masters": "shown_master_name", "servants": "shown_servant_name", "attacks": "shown_attack_name", "events": "shown_name", "situations": "shown_name", "command_spells": "shown_name"}
const EXTENSIONS := ["json", "png", "jpg", "jpeg", "webp"]
var errors: Array = []
var max_entries: int = 1000

## 接收清单仅是可供选择的索引，不是批准或可执行数据。
func accept(entries: Array, provider: String):
	errors.clear()
	if entries.size() > max_entries:
		errors.append("条目清单超过预算")
		return null
	var result: Array = []
	var identities: Dictionary = {}
	var assembler = preload("res://scripts/net/content/room_data_assembler.gd").new()
	var cache = preload("res://scripts/net/content/content_cache.gd").new()
	for entry in entries:
		if not entry is Dictionary or not entry.get("category") is String or not NAMES.has(entry.category) or not entry.get("name") is String or entry.name.is_empty() or not entry.get("key") is String or entry.key != entry.category + "/" + entry.name or identities.has(entry.key) or not entry.get("json") is String or not safe_path(entry.json) or not entry.json.begins_with(entry.category + "/") or entry.json.get_extension() != "json" or not entry.get("files") is Array or not entry.get("requires", []) is Array or not entry.get("query", {}) is Dictionary:
			errors.append("条目声明无效")
			return null
		var local_files: Array = []
		var source_files: Array = []
		var fingerprint := ""
		var has_json := false
		var ordered: Array = entry.files.duplicate(true)
		for file in ordered:
			if not file is Dictionary or not file.get("path") is String or not file.get("local") is String or not safe_path(file.local) or file.path != entry.json.get_base_dir().path_join(file.local):
				errors.append("条目文件不属于声明目录")
				return null
		ordered.sort_custom(func(a, b): return a.path < b.path)
		for file in ordered:
			local_files.append({"path": file.local, "hash": file.get("hash"), "size": file.get("size")})
			source_files.append({"path": file.path, "local": file.local, "hash": file.get("hash"), "size": file.get("size")})
			fingerprint += file.local + ":" + str(file.get("hash")) + "\n"
			has_json = has_json or file.path == entry.json
		if not has_json or not assembler.validate(local_files, cache.max_file_bytes) or not entry.get("hash") is String or entry.hash != fingerprint.sha256_text():
			errors.append("条目文件清单或内容指纹无效")
			return null
		identities[entry.key] = true
		result.append({"key": entry.key, "category": entry.category, "name": entry.name, "label": str(entry.get("label", entry.name)), "provider": provider, "json": entry.json, "files": source_files, "hash": entry.hash, "requires": entry.get("requires", []).duplicate(true), "query": entry.get("query", {}).duplicate(true)})
	return result

func verify_content(entry: Dictionary, cache) -> bool:
	errors.clear()
	for file in entry.files:
		if not verify_content_file(file, cache): return false
	return verify_content_identity(entry, cache)

## 分步准备复用同一校验，不以“缓存曾存在”替代本轮逐文件验证。
func verify_content_file(file: Dictionary, cache) -> bool:
	var bytes: PackedByteArray = cache.fetch(file.hash)
	if bytes.size() != file.size or bytes.is_empty():
		errors.append("条目内容缺失或校验失败")
		return false
	return true

func verify_content_identity(entry: Dictionary, cache) -> bool:
	var json_file: Dictionary = {}
	for file in entry.files:
		if file.path == entry.json:
			json_file = file
	if json_file.is_empty():
		errors.append("条目主 JSON 缺失")
		return false
	var data = JSON.parse_string(cache.fetch(json_file.hash).get_string_from_utf8())
	if not data is Dictionary or data.get(NAMES[entry.category]) != entry.name or data.get("requires", []) != entry.requires:
		errors.append("条目真实身份或依赖与上报清单不一致")
		return false
	var query: Dictionary = {}
	if entry.category == "attacks":
		if not data.get("power", {}) is Dictionary:
			errors.append("攻击牌威力声明无效")
			return false
		query = {"category": data.get("category", ""), "attributes": data.get("attributes", []), "power": data.get("power", {}).get("number")}
	if query != entry.query:
		errors.append("条目真实牌库查询与上报清单不一致")
		return false
	return true

func scan(root: String, provider: String) -> Array:
	errors.clear()
	var result: Array = []
	for category in NAMES:
		for relative in _files(root, category):
			if relative.get_extension() != "json":
				continue
			var file := FileAccess.open(root.path_join(relative), FileAccess.READ)
			if file == null:
				errors.append("无法读取 " + relative)
				continue
			var data = JSON.parse_string(file.get_as_text())
			if not data is Dictionary or not data.get(NAMES[category]) is String:
				errors.append("模板标识缺失 " + relative)
				continue
			var files: Array = []
			var fingerprint := ""
			for path in _files(root, relative.get_base_dir()):
				var local: String = path.trim_prefix(relative.get_base_dir() + "/")
				if path.get_extension() not in EXTENSIONS:
					continue
				var content := FileAccess.open(root.path_join(path), FileAccess.READ)
				var digest := FileAccess.get_sha256(root.path_join(path))
				if content == null or digest.is_empty():
					errors.append("无法校验 " + path)
					continue
				files.append({"path": path, "local": local, "size": content.get_length(), "hash": digest})
				fingerprint += local + ":" + digest + "\n"
			var entry := {"key": category + "/" + str(data[NAMES[category]]), "category": category, "name": data[NAMES[category]], "provider": provider, "json": relative, "files": files, "hash": fingerprint.sha256_text(), "requires": data.get("requires", []).duplicate(true), "query": {}}
			entry.label = str(data.get(SHOWN_NAMES[category], entry.name))
			if category == "attacks":
				entry.query = {"category": data.get("category", ""), "attributes": data.get("attributes", []), "power": data.get("power", {}).get("number")}
			result.append(entry)
	return result

## 输入已经是房主勾选的条目，不按提供者自动增加其他内容。
func merge(selected: Array, source_choices: Dictionary = {}) -> Dictionary:
	var groups: Dictionary = {}
	for entry in selected:
		if not groups.has(entry.key):
			groups[entry.key] = []
		groups[entry.key].append(entry)
	var result := {"entries": [], "conflicts": []}
	for key in groups:
		var candidates: Array = groups[key]
		var hashes: Array = []
		for entry in candidates:
			if not hashes.has(entry.hash):
				hashes.append(entry.hash)
		if hashes.size() == 1:
			result.entries.append(candidates[0].duplicate(true))
			continue
		var chosen: Array = candidates.filter(func(entry): return entry.provider == source_choices.get(key))
		if chosen.size() == 1:
			result.entries.append(chosen[0].duplicate(true))
		else:
			result.conflicts.append({"key": key, "candidates": candidates.duplicate(true)})
	return result

func dependencies(entries: Array) -> Array:
	var problems: Array = []
	for entry in entries:
		if not entry.requires is Array:
			problems.append({"key": entry.key, "reason": "依赖声明必须是数组"})
			continue
		for requirement in entry.requires:
			if not requirement is Dictionary or not requirement.get("category") is String:
				problems.append({"key": entry.key, "reason": "依赖声明无效"})
				continue
			var candidates: Array = entries.filter(func(candidate): return candidate.category == requirement.category)
			if requirement.has("name"):
				candidates = candidates.filter(func(candidate): return candidate.name == requirement.name)
			elif requirement.has("query") and requirement.category == "attacks" and requirement.query is String:
				var parts: PackedStringArray = requirement.query.split(":")
				if parts.size() != 2:
					candidates = []
				elif parts[0] == "special":
					candidates = candidates.filter(func(candidate): return candidate.name == parts[1])
				elif parts[1].is_valid_int():
					candidates = candidates.filter(func(candidate): return parts[0] in candidate.query.get("attributes", []) and candidate.query.get("power") == int(parts[1]))
					var basic: Array = candidates.filter(func(candidate): return candidate.query.get("category") == "basic")
					if not basic.is_empty():
						candidates = basic
				else:
					candidates = []
			else:
				candidates = []
			if candidates.size() != 1:
				problems.append({"key": entry.key, "requirement": requirement.duplicate(true), "reason": "缺少依赖" if candidates.is_empty() else "依赖查询冲突"})
	return problems

static func safe_path(path: String) -> bool:
	if path.is_empty() or path.is_absolute_path() or path.contains(":") or path.contains("\\"):
		return false
	for part in path.split("/"):
		if part in ["", ".", ".."]:
			return false
	return true

func _files(root: String, relative: String) -> Array:
	var result: Array = []
	if not safe_path(relative):
		errors.append("目录路径无效 " + relative)
		return result
	var dir := DirAccess.open(root.path_join(relative))
	if dir == null:
		return result
	for folder in dir.get_directories():
		if not folder.begins_with(".") and not dir.is_link(folder):
			result.append_array(_files(root, relative.path_join(folder)))
	for file in dir.get_files():
		if not dir.is_link(file):
			result.append(relative.path_join(file))
	result.sort()
	return result
