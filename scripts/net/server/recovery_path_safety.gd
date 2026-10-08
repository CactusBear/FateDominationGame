class_name RecoveryPathSafety
extends RefCounted

## 授权检查不是路径修复；任何非规范输入直接拒绝。
static func absolute(path:String) -> String:
	if path.is_empty() or "\\" in path: return ""
	# globalize_path 可能规范化虚拟路径，必须在调用前拒绝点段和重复分隔。
	if path.begins_with("res://") or path.begins_with("user://"):
		var relative:String = path.substr(path.find("://") + 3).trim_suffix("/")
		if not relative.is_empty():
			for part in relative.split("/", true):
				if not component(part): return ""
	else:
		var raw:String = path
		if raw.length() >= 3 and raw[1] == ":" and raw[2] == "/":
			raw = raw.substr(3)
		elif raw.begins_with("/") and not raw.begins_with("//"):
			raw = raw.substr(1)
		else: return ""
		raw = raw.trim_suffix("/")
		if not raw.is_empty():
			for part in raw.split("/", true):
				if not component(part): return ""
	var native:String = ProjectSettings.globalize_path(path)
	if not native.is_absolute_path(): return ""
	if OS.get_name() == "Windows" and not (native.length() >= 3 and native[1] == ":" and native[2] == "/"): return ""
	var body:String = native
	if body.length() >= 3 and body[1] == ":" and body[2] == "/":
		if body[0].to_lower() not in "abcdefghijklmnopqrstuvwxyz": return ""
		body = body.substr(3)
	elif body.begins_with("/") and not body.begins_with("//"):
		body = body.substr(1)
	else:
		return ""
	# 根目录末尾斜线允许；内部重复斜线、点段不允许。
	body = body.trim_suffix("/")
	if body.is_empty(): return native
	for part in body.split("/", true):
		if not component(part): return ""
	return native.trim_suffix("/")

static func component(part:String) -> bool:
	if part.is_empty() or part in [".", ".."] or part.ends_with(".") or part.ends_with(" "): return false
	for character in part:
		if character.unicode_at(0) < 32 or character in "/\\:<>\"|?*": return false
	var stem:String = part.split(".")[0].to_upper()
	if stem in ["CON", "PRN", "AUX", "NUL", "CLOCK$", "CONIN$", "CONOUT$"]: return false
	if stem.length() == 4 and (stem.begins_with("COM") or stem.begins_with("LPT")) and stem[3] in "123456789¹²³": return false
	return true

static func same(left:String, right:String) -> bool:
	var a:String = absolute(left)
	var b:String = absolute(right)
	if a.is_empty() or b.is_empty(): return false
	if OS.get_name() == "Windows": return a.to_lower() == b.to_lower()
	return a == b

static func contained(root:String, path:String) -> bool:
	var a:String = absolute(root)
	var b:String = absolute(path)
	if a.is_empty() or b.is_empty(): return false
	if OS.get_name() == "Windows":
		a = a.to_lower()
		b = b.to_lower()
	return b == a or b.begins_with(a.trim_suffix("/") + "/")

## 所有祖先逐层检查，不只检查房间最后一层；不可检查的祖先失败关闭。
## allow_missing 只用于还未创建的内部写入目标，不能用于读取源。
static func checked(root:String, path:String, allow_missing:bool = false) -> bool:
	if not contained(root, path): return false
	var target:String = absolute(path)
	var filesystem_root:String = "/"
	if target.length() >= 3 and target[1] == ":" and target[2] == "/":
		filesystem_root = target.substr(0, 3)
	# 一个调用内只打开文件系统根；不持有跨调用批准或 DirAccess。
	var directory := DirAccess.open(filesystem_root)
	if directory == null: return false
	var current:String = target
	while current != filesystem_root:
		# 绝对路径是 API 原生支持的，不拼接、不修复、不解析链接。
		if directory.is_link(current): return false
		if not allow_missing and not directory.file_exists(current) and not directory.dir_exists(current):
			return false
		var parent:String = current.get_base_dir()
		if parent.length() == 2 and parent[1] == ":": parent += "/"
		if parent == current or parent.is_empty(): return false
		current = parent
	# 保留授权根必须存在；根本身也不省略检查。
	return not directory.is_link(filesystem_root) and directory.dir_exists(absolute(root)) and not target.is_empty()

static func tree(root:String, directory:String, remaining:Array, depth:int = 0, maintenance:Callable = Callable()) -> bool:
	if maintenance.is_valid(): maintenance.call()
	if depth > 128 or remaining.size() != 1 or remaining[0] <= 0 or not checked(root, directory): return false
	var dir := DirAccess.open(directory)
	if dir == null: return false
	dir.include_hidden = true
	dir.include_navigational = false
	if dir.list_dir_begin() != OK: return false
	var name:String = dir.get_next()
	while not name.is_empty():
		if maintenance.is_valid(): maintenance.call()
		remaining[0] -= 1
		if remaining[0] < 0 or not component(name) or dir.is_link(name):
			dir.list_dir_end()
			return false
		var child:String = directory.path_join(name)
		if not checked(root, child) or (dir.current_is_dir() and not tree(root, child, remaining, depth + 1, maintenance)):
			dir.list_dir_end()
			return false
		name = dir.get_next()
	dir.list_dir_end()
	return true
