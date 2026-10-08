extends RefCounted
## 通用单职责接口：只发布同目录、已完整校验的临时文件到已存在的普通目标。
## 调用方必须关闭写句柄、串行化目录写入，并在调用前确认内容/哈希。
## 不创建目标、不删除目标、不清理临时文件、不承诺崩溃或断电持久性。

const Paths = preload("res://scripts/net/server/recovery_path_safety.gd")

static func replace_validated_file(temporary: String, target: String, validated_size: int) -> Dictionary:
	if validated_size < 0:
		return _failure("invalid_size")
	var temporary_absolute: String = Paths.absolute(temporary)
	var target_absolute: String = Paths.absolute(target)
	if temporary_absolute.is_empty() or target_absolute.is_empty():
		return _failure("invalid_path")
	if not ClassDB.class_exists("FateAtomicFileReplace"):
		return _failure("native_extension_unavailable")
	var backend := ClassDB.instantiate("FateAtomicFileReplace") as RefCounted
	if backend == null or not backend.has_method("replace_validated_file"):
		return _failure("native_interface_unavailable")
	var result: Variant = backend.call("replace_validated_file", temporary_absolute, target_absolute, validated_size)
	if not result is Dictionary:
		return _failure("invalid_native_result")
	return result

static func _failure(stage: String) -> Dictionary:
	return {"ok": false, "stage": stage, "native_error": 0, "durability_guaranteed": false}
