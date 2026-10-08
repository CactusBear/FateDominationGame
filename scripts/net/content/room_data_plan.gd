class_name RoomDataPlan
extends RefCounted

## 条目选择、来源冲突与依赖均显式给出；不自动补牌或按玩家优先级选版本。
func build(selected: Array, base_files: Array, source_choices: Dictionary = {}) -> Dictionary:
	var catalog = preload("res://scripts/net/content/data_catalog.gd").new()
	var result := {"ok": false, "files": [], "sources": [], "conflicts": [], "dependencies": [], "error": ""}
	var merged: Dictionary = catalog.merge(selected, source_choices)
	result.conflicts = merged.conflicts
	if not result.conflicts.is_empty():
		result.error = "条目来源冲突尚未选择"
		return result
	result.dependencies = catalog.dependencies(merged.entries)
	result.entries = merged.entries.duplicate(true)
	if not result.dependencies.is_empty():
		result.error = "选中条目的依赖缺失或冲突"
		return result
	for entry in merged.entries:
		if not entry.category is String or not entry.provider is String or not entry.key is String or not entry.files is Array or not catalog.NAMES.has(entry.category):
			result.error = "所选条目声明无效"
			return result
		var prefix: String = entry.category.path_join(entry.provider.sha256_text()).path_join(entry.key.sha256_text())
		for file in entry.files:
			if not file is Dictionary or not file.get("local") is String or not file.get("path") is String or not catalog.safe_path(file.local) or not catalog.safe_path(file.path):
				result.error = "所选条目的文件路径无效"
				return result
			result.files.append({"path": prefix.path_join(file.local), "hash": file.get("hash"), "size": file.get("size")})
			result.sources.append({"provider": entry.provider, "path": file.path})
	for file in base_files:
		if not file is Dictionary or not file.get("provider") is String:
			result.error = "基础文件来源缺失"
			return result
		result.files.append({"path": file.get("path"), "hash": file.get("hash"), "size": file.get("size")})
		result.sources.append({"provider": file.provider, "path": file.get("path")})
	var assembler = preload("res://scripts/net/content/room_data_assembler.gd").new()
	var cache = preload("res://scripts/net/content/content_cache.gd").new()
	if not assembler.validate(result.files, cache.max_file_bytes):
		result.error = assembler.error
		return result
	result.ok = true
	return result
