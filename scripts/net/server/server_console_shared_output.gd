extends RefCounted

## 仅用于可共享 stdout；不修改本机管理回执、命令或身份登记。
## 不传自由文本、身份、错误详情、路径、房间/请求/实例 ID。
static func render(text: String, shared_log: bool = false) -> String:
	if not shared_log:
		return text
	var parser := JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary:
		return JSON.stringify({"response_valid": false, "ok": false})
	return JSON.stringify(project(parser.data))

static func project(response: Dictionary) -> Dictionary:
	var result := {"response_valid": true, "ok": response.get("ok") is bool and response.get("ok") == true}
	var payload = response.get("result")
	if payload is Array:
		result["result_count"] = payload.size()
	elif payload is Dictionary:
		# pending 是计算出的 bool，不复制原 status 字符串。
		result["pending"] = payload.get("status") is String and payload.get("status") == "pending"
	return result