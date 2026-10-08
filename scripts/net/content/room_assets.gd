class_name RoomAssets
extends RefCounted

const Catalog = preload("res://scripts/net/content/data_catalog.gd")
const Assembler = preload("res://scripts/net/content/room_data_assembler.gd")
const Cache = preload("res://scripts/net/content/content_cache.gd")
const PREFIX := "room://"
var error: String = ""
var _paths: Dictionary = {}

func clear() -> void:
	_paths.clear()
	error = ""

## 安装只在全部文件校验成功后原子提交路径表。
func is_installed() -> bool:
	return not _paths.is_empty()

## 安装本机已组装目录，不接受网络提供的本机绝对目录。
func install(files: Array, directory: String, max_file_bytes: int, maintenance:Callable = Callable()) -> bool:
	if not _install_checkpoint(maintenance): return false
	var validator = Assembler.new()
	if not validator.validate(files, max_file_bytes):
		error = validator.error
		return false
	var paths: Dictionary = {}
	for item in files:
		if not _install_checkpoint(maintenance): return false
		var path: String = directory.path_join(item.path)
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			error = "房间素材文件校验失败：" + item.path
			return false
		var size: int = file.get_length()
		# 本地清单原有语义允许零长度；网络下载的正长度限制独立保留。
		if size != item.size or size > max_file_bytes:
			file.close()
			error = "房间素材文件校验失败：" + item.path
			return false
		var bytes := file.get_buffer(size)
		var read_error := file.get_error()
		file.close()
		if read_error != OK or bytes.size() != size or Cache.digest(bytes) != item.hash:
			error = "房间素材文件校验失败：" + item.path
			return false
		paths[item.path] = path
	if not _install_checkpoint(maintenance): return false
	_paths = paths
	error = ""
	return true

func _install_checkpoint(maintenance:Callable) -> bool:
	if maintenance.is_valid() and maintenance.call() == false:
		error = "房间素材安装已取消"
		return false
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
