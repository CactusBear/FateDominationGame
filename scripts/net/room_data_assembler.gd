class_name RoomDataAssembler
extends RefCounted

const Catalog = preload("res://scripts/net/data_catalog.gd")
const Cache = preload("res://scripts/net/content_cache.gd")
var max_total_bytes: int = 2 * 1024 * 1024 * 1024
var max_files: int = 20000
var error: String = ""

## destination 由本机会话管理分配，不接受网络消息提供的绝对路径。
## 只组装数据字节，不加载 JSON 指定的脚本，不切换全局 data 根目录。
func assemble(destination: String, files: Array, cache) -> bool:
	error = ""
	if DirAccess.dir_exists_absolute(destination) or FileAccess.file_exists(destination):
		return _reject("会话目录已存在，不覆盖")
	if not validate(files, cache.max_file_bytes):
		return false
	# 在创建任何目录前确认全部缓存可用。
	for item in files:
		var bytes: PackedByteArray = cache.fetch(item.hash)
		if bytes.size() != item.size or Cache.digest(bytes) != item.hash:
			return _reject("缓存缺失或内容校验失败：" + item.path)
	var staging := destination + ".building-" + str(Time.get_ticks_usec())
	if DirAccess.make_dir_recursive_absolute(staging) != OK:
		return _reject("无法创建会话临时目录")
	var created: Array = []
	for item in files:
		var target: String = staging.path_join(item.path)
		if DirAccess.make_dir_recursive_absolute(target.get_base_dir()) != OK:
			_cleanup(staging, created)
			return _reject("无法创建数据子目录")
		var bytes: PackedByteArray = cache.fetch(item.hash)
		if bytes.size() != item.size or Cache.digest(bytes) != item.hash:
			_cleanup(staging, created)
			return _reject("组装期间缓存失效")
		var file := FileAccess.open(target, FileAccess.WRITE)
		if file == null:
			_cleanup(staging, created)
			return _reject("无法写入数据文件")
		created.append(item.path)
		file.store_buffer(bytes)
		file.flush()
		var result := file.get_error()
		file.close()
		if result != OK or FileAccess.get_sha256(target) != item.hash:
			_cleanup(staging, created)
			return _reject("会话文件写入校验失败")
	if DirAccess.rename_absolute(staging, destination) != OK:
		_cleanup(staging, created)
		return _reject("无法发布完整会话目录")
	return true

func validate(files: Array, max_file_bytes: int) -> bool:
	error = ""
	if files.is_empty() or files.size() > max_files:
		return _reject("文件清单数量无效")
	var paths: Dictionary = {}
	var total: int = 0
	for item in files:
		if not item is Dictionary or not item.get("path") is String or not item.get("hash") is String or not item.get("size") is int:
			return _reject("文件清单字段无效")
		if not _portable_path(item.path) or not Cache.valid_key(item.hash):
			return _reject("文件路径或校验值无效")
		if item.size < 0 or item.size > max_file_bytes or item.size > max_total_bytes - total:
			return _reject("文件大小超过接收预算")
		var key: String = item.path.to_lower()
		if paths.has(key):
			return _reject("文件路径重复或大小写冲突")
		paths[key] = true
		total += item.size
	for path in paths:
		var parent: String = path.get_base_dir()
		while not parent.is_empty():
			if paths.has(parent):
				return _reject("文件与目录路径冲突")
			parent = parent.get_base_dir()
	return true

static func _portable_path(path: String) -> bool:
	if not Catalog.safe_path(path) or path.get_extension().to_lower() not in Catalog.EXTENSIONS:
		return false
	for part in path.split("/"):
		if part.ends_with(".") or part.ends_with(" "):
			return false
		for character in part:
			if character.unicode_at(0) < 32 or character in "<>\"|?*":
				return false
		var stem: String = part.split(".")[0].to_upper()
		if stem in ["CON", "PRN", "AUX", "NUL"] or (stem.length() == 4 and (stem.begins_with("COM") or stem.begins_with("LPT")) and stem[3] in "123456789"):
			return false
	return true

func _cleanup(staging: String, created: Array) -> void:
	# 只删除本次建立的目录，不遍历外部链接或原始 data。
	var directories: Array = []
	for relative in created:
		DirAccess.remove_absolute(staging.path_join(relative))
		var parent: String = relative.get_base_dir()
		while not parent.is_empty():
			if not directories.has(parent):
				directories.append(parent)
			parent = parent.get_base_dir()
	directories.sort_custom(func(a, b): return a.length() > b.length())
	for relative in directories:
		DirAccess.remove_absolute(staging.path_join(relative))
	DirAccess.remove_absolute(staging)

func _reject(reason: String) -> bool:
	error = reason
	return false
