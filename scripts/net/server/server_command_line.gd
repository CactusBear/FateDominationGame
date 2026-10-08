extends RefCounted

## 仅拆分命令参数，不执行表达式、shell 或脚本。
static func parse(line:String) -> Dictionary:
	var tokens:PackedStringArray = []
	var current:String = ""
	var quote:String = ""
	var escaped:bool = false
	var started:bool = false
	for character in line:
		if escaped:
			current += character
			escaped = false
			started = true
			continue
		if character == "\\":
			escaped = true
			started = true
			continue
		if not quote.is_empty():
			if character == quote: quote = ""
			else: current += character
			continue
		if character in ["\"", "'"]:
			quote = character
			started = true
		elif character in [" ","\t","\r","\n"]:
			if started:
				tokens.append(current)
				current = ""
				started = false
		else:
			current += character
			started = true
	if escaped: return {"ok":false,"error":"命令末尾存在未完成的转义"}
	if not quote.is_empty(): return {"ok":false,"error":"命令引号未闭合"}
	if started: tokens.append(current)
	return {"ok":true,"tokens":tokens}
