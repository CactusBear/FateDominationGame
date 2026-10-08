extends RefCounted

const MAX_USERNAME_LENGTH:int = 32

static func username_error(value:String) -> String:
	if value.is_empty(): return "请输入用户名"
	if value.length() > MAX_USERNAME_LENGTH: return "用户名最多32字符"
	for index in value.length():
		var code:int = value.unicode_at(index)
		var letter:bool = (code >= 65 and code <= 90) or (code >= 97 and code <= 122)
		var digit:bool = code >= 48 and code <= 57
		if not letter and code != 95 and not digit: return "用户名只允许英文字母、下划线和数字"
		if index == 0 and digit: return "用户名不能以数字开头"
	return ""
