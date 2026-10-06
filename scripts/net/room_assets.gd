class_name RoomAssets
extends RefCounted

const Catalog = preload("res://scripts/net/data_catalog.gd")
const Assembler = preload("res://scripts/net/room_data_assembler.gd")
const PREFIX := "room://"
var error: String = ""
var _paths: Dictionary = {}

func clear() -> void:
	_paths.clear()
	error = ""

## 安装本机已组装目录，不接受网络提供的本机绝对目录。
func install(files: Array, directory: String, max_file_bytes: int) -> bool:
	var validator = Assembler.new()
	if not validator.validate(files, max_file_bytes):
		error = validator.error
		return false
	var paths: Dictionary = {}
	for item in files:
		var path: String = directory.path_join(item.path)
		if not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != item.hash:
			error = "房间素材文件校验失败：" + item.path
			return false
		paths[item.path] = path
	_paths = paths
	error = ""
	return true

func resolve(reference: String) -> String:
	if not reference.begins_with(PREFIX):
		return reference if reference.begins_with("res://assets/") else ""
	var relative := reference.trim_prefix(PREFIX)
	if not Catalog.safe_path(relative):
		return ""
	return str(_paths.get(relative, ""))

static func encode_path(path: String, root: String, files: Array) -> String:
	var prefix := root.trim_suffix("/") + "/"
	if not path.begins_with(prefix):
		return path if path.begins_with("res://assets/") else ""
	var relative := path.trim_prefix(prefix)
	if not Catalog.safe_path(relative):
		return ""
	for item in files:
		if item.path == relative:
			return PREFIX + relative
	return ""
