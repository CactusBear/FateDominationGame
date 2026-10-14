extends RefCounted

## 只解释本机请求的数据形状；不扫描目录、执行命令、授权或管理生命周期。
## 所有预算/白名单/整数范围均由原 owner 传入，不在 codec 发明政策。
static func valid_id(id:String) -> bool:
	if id.length() != 32: return false
	for character in id:
		if character not in "0123456789abcdef": return false
	return true

static func parse_object(text:String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary: return {"ok":false}
	return {"ok":true,"value":parser.data}

func read_request(file:FileAccess,expected_instance:String,max_bytes:int) -> Dictionary:
	if file == null or file.get_length() > max_bytes: return {"ok":false}
	var decoded:Dictionary = parse_object(file.get_as_text())
	if not decoded.ok: return decoded
	var request:Dictionary = decoded.value
	# 现有 console 信封恰为 instance+command；不接受自报权限/action/args。
	if request.size() != 2 or request.get("instance") != expected_instance or not request.get("command") is String: return {"ok":false}
	return {"ok":true,"command":request.command}

func decode_command(line:String,max_bytes:int) -> Dictionary:
	if line.to_utf8_buffer().size() > max_bytes: return {"ok":false,"error":"命令超过长度预算"}
	var parsed:Dictionary = preload("res://scripts/net/server/server_command_line.gd").parse(line)
	if not parsed.ok: return parsed
	var parts:PackedStringArray = parsed.tokens
	if parts.is_empty(): return {"ok":false,"error":"命令为空"}
	var action:String = parts[0]
	var offset:int = 1
	if action in ["relay","whitelist"] and parts.size() > 1:
		action += " " + parts[1]
		offset = 2
	elif action == "room" and parts.size() > 1 and parts[1] == "create":
		action += " create"
		offset = 2
	elif action == "room" and parts.size() > 2:
		action += " " + parts[2]
		parts = PackedStringArray([parts[0],parts[2],parts[1]]) + parts.slice(3)
		offset = 2
	return {"ok":true,"action":action,"args":parts.slice(offset)}

static func valid_arguments(args:PackedStringArray,expected_count:int) -> bool:
	return args.size() == expected_count

static func valid_integer(text:String,canonical:bool = false) -> bool:
	return text.is_valid_int() and (not canonical or str(text.to_int()) == text)

static func integer_in_range(text:String,minimum:int,maximum:int) -> bool:
	return valid_integer(text) and text.to_int() >= minimum and text.to_int() <= maximum

## JSON 原语将数值读作 float；保留既有字段相等合同，不强加新数字类型门。
static func ready_matches(value:Dictionary,room_id:String,pid:int) -> bool:
	return value.get("id") == room_id and value.get("pid") == pid and valid_id(str(value.get("instance","")))

static func binding_matches(value:Dictionary,room_id:String,binding:Dictionary) -> bool:
	return value.get("room") == room_id and value.get("pid") == binding.get("pid") and value.get("instance") == binding.get("instance_id") and value.get("authority_host_mode") == binding.get("authority_host_mode")

static func response_matches(value:Dictionary,room_id:String,request_id:String,binding:Dictionary) -> bool:
	return value.get("request_id") == request_id and binding_matches(value,room_id,binding)
