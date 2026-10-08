extends RefCounted

## 仅本机控制台调用；连接编号是选择器，认证指纹由网关填充。
const Bindings = preload("res://scripts/net/identity/member_identity_bindings.gd")
const MAX_FILE_BYTES:int = 4194304

static func parse_approval(marker:String, text:String) -> Dictionary:
	if marker != "legacy_approved": return failure("必须明确输入 legacy_approved")
	var parser := JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary or parser.data.is_empty():
		return failure("批准映射必须是非空 JSON 对象")
	# JSON 对象重复键会被解析器覆盖；原始文本的键数量必须一致。
	var keys := RegEx.new()
	if keys.compile('"([0-9]+)"\\s*:') != OK: return failure("批准解析器不可用")
	var matches:Array[RegExMatch] = keys.search_all(text)
	if matches.size() != parser.data.size(): return failure("批准映射含重复或非规范成员键")
	var selected:Dictionary = {}
	var connections:Dictionary = {}
	for member in parser.data:
		if not member is String or not member.is_valid_int() or not Bindings.valid_counter(member.to_int()) or member.to_int() <= 0 or str(member.to_int()) != member:
			return failure("成员编号必须是规范正整数")
		var connection = parser.data[member]
		if not Bindings.valid_counter(connection) or connection <= 1 or connections.has(int(connection)):
			return failure("认证连接编号无效或重复")
		selected[member] = int(connection)
		connections[int(connection)] = true
	return {"ok":true,"selected":selected}

static func failure(message:String) -> Dictionary:
	return {"ok":false,"error":message}

static func read_legacy(path:String) -> Dictionary:
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null: return failure("旧恢复档不可读")
	if file.get_length() > MAX_FILE_BYTES:
		file.close()
		return failure("旧恢复档超过迁移预算")
	var bytes:PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	var parser := JSON.new()
	if parser.parse(bytes.get_string_from_utf8()) != OK or not parser.data is Dictionary or not Bindings.valid_state(parser.data,false) or parser.data.get("identity_binding_required",false):
		return failure("不是可显式迁移的未绑定旧档")
	for member in parser.data.room.members:
		if not member is String or not member.is_valid_int() or not Bindings.valid_counter(member.to_int()) or member.to_int() <= 0 or str(member.to_int()) != member or not parser.data.room.members[member] is Dictionary:
			return failure("旧成员编号或成员结构无效")
	return {"ok":true,"state":parser.data,"bytes":bytes}

static func prepare(state:Dictionary, approved:Dictionary, profiles:Dictionary) -> Dictionary:
	var owner = state.room.get("owner")
	if not Bindings.valid_counter(owner) or owner <= 0 or not approved.has(str(int(owner))):
		return failure("缺少旧房主的显式认证绑定")
	if not state.get("inheritance_sequences",{}) is Dictionary or not state.get("inheritance_audit",[]) is Array or not state.get("resume_hashes",{}) is Dictionary or not state.get("resume_previous",{}) is Dictionary:
		return failure("旧档迁移字段类型无效")
	var previous = state.get("inheritance_sequences",{}).get(str(int(owner)),0)
	if not Bindings.valid_counter(previous) or previous >= 2147483647: return failure("迁移审批序号无效")
	var hashes:Dictionary = {}
	var tickets:Dictionary = {}
	for member in approved:
		var bytes:PackedByteArray = Crypto.new().generate_random_bytes(32)
		if bytes.size() != 32: return failure("恢复票据生成失败")
		var token:String = bytes.hex_encode()
		hashes[member] = token.sha256_text()
		tickets[member] = {"kind":"inheritance_ticket","member":int(member),"token":token}
	var trusted:Dictionary = {"legacy_approved":true,"actor_key":approved[str(int(owner))],"profiles":profiles,"replacement_hashes":hashes,"request_seq":int(previous)+1,"revision":state.room.get("revision")}
	var result:Dictionary = Bindings.prepare_legacy_bindings(state,int(owner),approved,trusted)
	if not result.ok: return result
	result.state["legacy_identity_audit"] = [{"members":approved.keys(),"operator":"local-console","action":"approve"}]
	result["private_tickets"] = tickets
	return result

## Windows DirAccess.rename 覆盖先删除旧文件，必须使用原生原子替换。
static func commit(path:String, original:PackedByteArray, state:Dictionary) -> Dictionary:
	var suffix:String = Crypto.new().generate_random_bytes(16).hex_encode()
	if suffix.length() != 32: return failure("无法生成迁移事务编号")
	var temporary:String = path + ".legacy-" + suffix + ".tmp"
	var backup:String = path + ".legacy-" + suffix + ".bak"
	var encoded:PackedByteArray = JSON.stringify(state).to_utf8_buffer()
	if encoded.size() > MAX_FILE_BYTES: return failure("迁移结果超过预算")
	var file := FileAccess.open(temporary,FileAccess.WRITE)
	if file == null: return failure("迁移暂存文件不可写")
	file.store_buffer(encoded)
	file.flush()
	var error:Error = file.get_error()
	file.close()
	if error != OK or FileAccess.get_file_as_bytes(temporary) != encoded or FileAccess.get_file_as_bytes(path) != original:
		DirAccess.remove_absolute(temporary)
		return failure("写入失败或旧档已变化，原档未替换")
	if OS.get_name() == "Windows":
		# 路径只来自本机登记；单引号转义，绝不拼接网络 args。
		var script:String = "$ErrorActionPreference='Stop'; try { [System.IO.File]::Replace('%s','%s','%s'); exit 0 } catch { exit 1 }" % [ProjectSettings.globalize_path(temporary).replace("'","''"),ProjectSettings.globalize_path(path).replace("'","''"),ProjectSettings.globalize_path(backup).replace("'","''")]
		var output:Array = []
		if OS.execute("powershell.exe",PackedStringArray(["-NoProfile","-NonInteractive","-Command",script]),output,false) != 0:
			DirAccess.remove_absolute(temporary)
			return failure("原生原子替换失败，未确认迁移")
	else:
		# 同目录 POSIX rename 原子替换；保留原字节备份。
		var saved := FileAccess.open(backup,FileAccess.WRITE)
		if saved == null:
			DirAccess.remove_absolute(temporary)
			return failure("原档备份失败")
		saved.store_buffer(original)
		saved.flush()
		error = saved.get_error()
		saved.close()
		if error != OK or FileAccess.get_file_as_bytes(backup) != original or DirAccess.rename_absolute(temporary,path) != OK:
			DirAccess.remove_absolute(temporary)
			return failure("原子替换失败，原档保留")
	if FileAccess.get_file_as_bytes(path) != encoded: return failure("迁移落盘读回失败，保留原档备份且不交付票据")
	return {"ok":true}
