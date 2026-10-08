extends RefCounted
## 只读校验；读取量由调用方已生成的期望字节限定，不发布或清理文件。
static func matches_bytes(path: String, expected: PackedByteArray) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	if file.get_length() != expected.size():
		file.close()
		return false
	var actual := file.get_buffer(expected.size())
	var result := file.get_error()
	file.close()
	return result == OK and actual == expected
