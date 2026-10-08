extends RefCounted

const Names = preload("res://scripts/net/identity/player_name_rules.gd")
const Files = preload("res://scripts/net/server/server_console_channel.gd")
var users:Dictionary = {}
var path:String = ""
var error:String = ""
var whitelist_enabled:bool = false

static func valid_id(value:String) -> bool:
	if value.length() != 64: return false
	for character in value:
		if character not in "0123456789abcdef": return false
	return true

func open(filename:String) -> bool:
	error = ""
	var candidate:Dictionary = {}
	var candidate_whitelist:bool = false
	if FileAccess.file_exists(filename):
		var file = FileAccess.open(filename,FileAccess.READ)
		if file == null: return _fail("身份登记库无法读取")
		var parser:JSON = JSON.new()
		var status:Error = parser.parse(file.get_as_text())
		file.close()
		if status != OK or not parser.data is Dictionary or parser.data.get("version") != 1 or not parser.data.get("users") is Dictionary: return _fail("身份登记库损坏，拒绝覆盖")
		candidate = parser.data.users
		if not parser.data.get("whitelist_enabled",false) is bool: return _fail("白名单开关无效")
		candidate_whitelist = parser.data.get("whitelist_enabled",false)
		var names:Dictionary = {}
		for id in candidate:
			var record = candidate[id]
			if not id is String or not valid_id(id) or not record is Dictionary or not record.get("username") is String or not record.get("nickname") is String: return _fail("身份记录无效")
			if not Names.username_error(record.username).is_empty() or names.has(record.username): return _fail("身份库用户名非法或重复")
			for flag in ["admin","banned","whitelisted"]:
				if not record.get(flag,false) is bool: return _fail("身份权限记录无效")
			names[record.username] = id
	users = candidate.duplicate(true)
	whitelist_enabled = candidate_whitelist
	path = filename
	return true

## 调用者必须先验证私钥持有证明；此入口不接受自报 UUID 作为身份。
func register_authenticated(id:String,username:String,nickname:String) -> Dictionary:
	if not valid_id(id): return {"ok":false,"error":"密钥身份无效"}
	var reason:String = Names.username_error(username)
	if not reason.is_empty(): return {"ok":false,"error":reason}
	for other in users:
		if other != id and users[other].username == username: return {"ok":false,"error":"用户名已被使用"}
	if users.has(id) and users[id].username == username and users[id].nickname == nickname:
		return {"ok":true,"result":{"identity":id,"username":username,"nickname":nickname}}
	var candidate:Dictionary = users.duplicate(true)
	var record:Dictionary = candidate.get(id,{}).duplicate(true)
	record.username = username
	record.nickname = nickname
	candidate[id] = record
	if not _commit(candidate,whitelist_enabled): return {"ok":false,"error":"身份登记保存失败，原记录未改变"}
	users = candidate
	return {"ok":true,"result":{"identity":id,"username":username,"nickname":nickname}}

func _fail(reason:String) -> bool:
	error = reason
	return false

func _commit(candidate:Dictionary,enabled:bool) -> bool:
	if path.is_empty() or Files.write_json(path,{"version":1,"users":candidate,"whitelist_enabled":enabled}) != OK: return false
	users = candidate
	whitelist_enabled = enabled
	return true

func set_permission(id:String,permission:String,enabled:bool) -> Dictionary:
	if not users.has(id): return {"ok":false,"error":"密钥身份尚未登记"}
	if permission not in ["admin","banned","whitelisted"]: return {"ok":false,"error":"未声明的身份权限"}
	var candidate:Dictionary = users.duplicate(true)
	candidate[id][permission] = enabled
	if not _commit(candidate,whitelist_enabled): return {"ok":false,"error":"权限保存失败，原状态未改变"}
	return {"ok":true,"result":{"identity":id,"permission":permission,"enabled":enabled}}

func set_whitelist(enabled:bool) -> Dictionary:
	if not _commit(users.duplicate(true),enabled): return {"ok":false,"error":"白名单开关保存失败，原状态未改变"}
	return {"ok":true,"result":{"whitelist_enabled":enabled}}

## 输入仅来自网关认证登记；返回严格公开白名单，不返回身份键。
static func public_member_labels(members:Dictionary, identities:Dictionary, profiles:Dictionary) -> Array:
	var counts:Dictionary = {}
	var rows:Array = []
	for member in members:
		var profile = profiles.get(identities.get(str(member),identities.get(member,"")),{})
		var label:String = str(members[member].get("name",""))
		if profile is Dictionary and profile.get("username") is String and profile.get("nickname") is String:
			var nickname:String = profile.nickname.strip_edges()
			label = nickname if not nickname.is_empty() else profile.username
		counts[label] = int(counts.get(label,0)) + 1
		if not profile is Dictionary or not profile.get("username") is String or not profile.get("nickname") is String: continue
		rows.append({"member_id":int(member),"label":label,"username":profile.username})
	for row in rows:
		if counts[row.label] > 1: row.label += "（%s）" % row.username
		row.erase("username")
	rows.sort_custom(func(a,b): return a.member_id < b.member_id)
	return rows

func can_access(id:String) -> bool:
	if not users.has(id) or users[id].get("banned",false): return false
	return not whitelist_enabled or users[id].get("whitelisted",false)
