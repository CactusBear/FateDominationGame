extends RefCounted

## 纯授权准备；不读存档、不落盘、不执行规则。trusted 必须由认证主管构建。
const Bindings = preload("res://scripts/net/identity/member_identity_bindings.gd")
const Channel = preload("res://scripts/net/server/server_console_channel.gd")
const BLOCKER:String = "atomic_restore_and_authenticated_binding_unavailable"

static func blocked() -> Dictionary:
	return {"ok":false,"code":BLOCKER,"error":"权威恢复已安全阻断：认证绑定与失败原子事务未完成；原档及连接保留","executed":false}

## 仅生成校验后的提案；authorized 不代表恢复成功或允许解除现有门槛。
static func prepare(request:Dictionary, current:Dictionary, state:Dictionary, trusted:Dictionary, last_sequence:Variant) -> Dictionary:
	if request.size() != 10 or request.get("action") != "restore": return _reject("invalid_request")
	for field in ["room","instance"]:
		if not request.get(field) is String or not Channel.valid_id(request[field]): return _reject("invalid_instance")
	if not Bindings.valid_counter(request.get("pid")) or request.pid <= 0: return _reject("invalid_instance")
	if request.get("authority_host_mode") not in ["lan","p2p"]: return _reject("invalid_host_mode")
	if not trusted.get("binding") is Dictionary or not trusted.get("profiles") is Dictionary: return _reject("invalid_trusted_context")
	for field in ["room","pid","instance","authority_host_mode"]:
		if request.get(field) != current.get(field): return _reject("stale_instance")
		if trusted.get("binding",{}).get(field) != current.get(field): return _reject("untrusted_instance")
	if trusted.get("authenticated") != true: return _reject("unauthenticated")
	if not Bindings.valid_counter(request.get("actor_member")) or request.actor_member <= 0: return _reject("invalid_actor")
	if not Bindings.valid_state(state,true): return _reject("missing_member_key_bindings")
	if not Bindings.valid_counter(state.room.get("owner")) or not Bindings.valid_counter(state.room.get("revision")): return _reject("invalid_room_state")
	for member in state.room.members.values():
		if not member is Dictionary: return _reject("invalid_room_state")
	var actor:int = int(request.actor_member)
	# 在序号/存档/席位检查前先拒绝错误认证密钥；不信任请求里的自报 key。
	if state.member_identities.get(str(actor),"") != trusted.get("actor_key"): return _reject("key_mismatch")
	if not Bindings.authorized_owner(state,actor,trusted): return _reject("not_authenticated_owner")
	if not Bindings.valid_counter(request.get("revision")) or request.revision != state.room.get("revision"): return _reject("stale_revision")
	if not Bindings.valid_counter(last_sequence) or not Bindings.valid_counter(request.get("request_seq")) or request.request_seq <= last_sequence: return _reject("replayed_request")
	# 只允许主管登记中的本地存档标识；不接受绝对/相对路径。
	if not request.get("archive_id") is String or not Channel.valid_id(request.archive_id): return _reject("invalid_archive_id")
	if not request.get("bindings") is Dictionary or not state.get("bindings") is Dictionary or request.bindings.is_empty() or request.bindings.size() != state.bindings.size(): return _reject("invalid_bindings")
	var normalized:Dictionary = {}
	var humans:Dictionary = {}
	for player in request.bindings:
		if not player is String or not player.is_valid_int() or str(int(player)) != player or not Bindings.valid_counter(int(player)): return _reject("invalid_player")
		var member = request.bindings[player]
		if not Bindings.valid_counter(member) or not Bindings.valid_counter(state.bindings.get(player)) or member != state.bindings[player]: return _reject("binding_mismatch")
		var member_id:int = int(member)
		if member_id > 0:
			if humans.has(member_id): return _reject("duplicate_human_binding")
			var saved:Dictionary = state.room.members.get(str(member_id),{})
			var key:String = state.member_identities.get(str(member_id),"")
			if saved.get("connected") != true or saved.get("spectator") != false or not trusted.profiles.has(key): return _reject("member_not_authenticated")
			humans[member_id] = true
		normalized[int(player)] = member_id
	return {"authorized":true,"executed":false,"proposal":{"archive_id":request.archive_id,"bindings":normalized,"actor_member":actor,"revision":int(request.revision),"request_seq":int(request.request_seq)}}

static func _reject(code:String) -> Dictionary:
	return {"authorized":false,"executed":false,"code":code}
