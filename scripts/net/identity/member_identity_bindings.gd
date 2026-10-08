extends RefCounted

const Registry = preload("res://scripts/net/identity/player_registry.gd")

## 私有恢复状态的身份绑定验证。旧档不得从名字或首个持票者推断密钥。
static func valid_state(state:Dictionary, required:bool = false) -> bool:
	if not state.get("identity_binding_required",false) is bool: return false
	var protected:bool = state.get("identity_binding_required",false)
	if required and not protected: return false
	var identities = state.get("member_identities",{})
	if not identities is Dictionary: return false
	var saved = state.get("room")
	if not saved is Dictionary or not saved.get("members") is Dictionary: return false
	for member in identities:
		if not member is String or not member.is_valid_int() or int(member) <= 0 or str(int(member)) != member or not saved.members.has(member): return false
		if not identities[member] is String or not Registry.valid_id(identities[member]): return false
	if not protected: return identities.is_empty()
	for member in saved.members:
		if not identities.has(member): return false
	for field in ["resume_hashes","resume_previous"]:
		if not state.get(field,{}) is Dictionary: return false
		for member in state.get(field,{}):
			if not identities.has(member) or not state[field][member] is String or not Registry.valid_id(state[field][member]): return false
	if not state.get("inheritance_sequences",{}) is Dictionary or not state.get("inheritance_audit",[]) is Array: return false
	for actor in state.get("inheritance_sequences",{}):
		if not actor is String or not actor.is_valid_int() or int(actor) <= 0 or str(int(actor)) != actor or not valid_counter(state.inheritance_sequences[actor]): return false
	for fact in state.get("inheritance_audit",[]):
		if not fact is Dictionary or fact.size() != 5: return false
		for key in ["actor_member","target_member","successor_member","revision","request_seq"]:
			if not valid_counter(fact.get(key)): return false
	return true

static func prepare_legacy_bindings(state:Dictionary, actor:int, approved:Dictionary, trusted:Dictionary) -> Dictionary:
	# 仅供本机显式管理审批；普通网络请求从不传递 approved/legacy_approved。
	if state.get("identity_binding_required",false) or trusted.get("legacy_approved") != true or not valid_state(state,false):
		return {"ok":false,"error":"旧档绑定必须经显式房主审批"}
	if not trusted.get("profiles") is Dictionary or state.room.owner != actor or state.room.members.get(str(actor),{}).get("spectator") != false or approved.get(str(actor)) != trusted.get("actor_key"):
		return {"ok":false,"error":"旧档房主认证与批准映射不一致"}
	var replacements = trusted.get("replacement_hashes")
	if not replacements is Dictionary or replacements.size() != approved.size(): return {"ok":false,"error":"旧档迁移必须显式轮换全部恢复凭据"}
	for member in approved:
		if not replacements.get(member) is String or not Registry.valid_id(replacements[member]) or replacements[member] == state.get("resume_hashes",{}).get(member) or replacements[member] == state.get("resume_previous",{}).get(member):
			return {"ok":false,"error":"旧档新恢复哈希无效或未轮换"}
	var sequence = trusted.get("request_seq")
	if not valid_counter(sequence) or sequence <= int(state.get("inheritance_sequences",{}).get(str(actor),0)) or not valid_counter(state.room.get("revision")) or trusted.get("revision") != state.room.get("revision") or state.room.revision >= 2147483647:
		return {"ok":false,"error":"旧档迁移请求重复或修订无效"}
	var next:Dictionary = state.duplicate(true)
	next.identity_binding_required = true
	next.member_identities = approved.duplicate()
	next.resume_hashes = replacements.duplicate()
	next.resume_previous = {}
	next.room.revision = int(next.room.revision) + 1
	next.inheritance_sequences = next.get("inheritance_sequences",{}).duplicate()
	next.inheritance_sequences[str(actor)] = int(sequence)
	next.inheritance_audit = next.get("inheritance_audit",[]).duplicate(true)
	for member in approved:
		next.inheritance_audit.append({"actor_member":actor,"target_member":int(member),"successor_member":int(member),"revision":next.room.revision,"request_seq":int(sequence)})
	if not valid_state(next,true): return {"ok":false,"error":"必须显式批准全部成员绑定"}
	for key in approved.values():
		if not trusted.profiles.has(key): return {"ok":false,"error":"批准身份未认证或已禁用"}
	return {"ok":true,"state":next}

## 本机管理执行器传入由房间登记定位的路径；绝不注册远端路径输入。
## private_tickets 只供认证连接单播，不能写入管理公开回执或日志。
static func migrate_legacy_file(path:String, actor:int, approved:Dictionary, trusted:Dictionary) -> Dictionary:
	if trusted.get("legacy_approved") != true: return {"ok":false,"error":"缺少显式旧档审批"}
	var file = FileAccess.open(path,FileAccess.READ)
	if file == null: return {"ok":false,"error":"旧档无法读取"}
	var parser:JSON = JSON.new()
	var parsed:Error = parser.parse(file.get_as_text())
	file.close()
	if parsed != OK or not parser.data is Dictionary: return {"ok":false,"error":"旧档损坏，拒绝覆盖"}
	var context:Dictionary = trusted.duplicate(true)
	context.replacement_hashes = {}
	var tickets:Dictionary = {}
	for member in approved:
		var bytes:PackedByteArray = Crypto.new().generate_random_bytes(32)
		if bytes.size() != 32: return {"ok":false,"error":"无法生成新恢复凭据"}
		var token:String = bytes.hex_encode()
		context.replacement_hashes[member] = token.sha256_text()
		tickets[member] = {"member":int(member),"token":token}
	var prepared:Dictionary = prepare_legacy_bindings(parser.data,actor,approved,context)
	if not prepared.ok: return prepared
	if preload("res://scripts/net/server/server_console_channel.gd").write_json(path,prepared.state) != OK:
		return {"ok":false,"error":"旧档迁移写盘失败，原恢复档保留"}
	return {"ok":true,"revision":prepared.state.room.revision,"private_tickets":tickets}

static func valid_counter(value:Variant) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) and value >= 0 and value <= 2147483647 and floor(float(value)) == value

## trusted 是网关在每次请求时重新建立的上下文，不得从客户端 args 读取。
static func authorized_owner(state:Dictionary, actor:int, trusted:Dictionary) -> bool:
	if not valid_state(state,true): return false
	var member = state.room.members.get(str(actor),{})
	var identity:String = state.member_identities.get(str(actor),"")
	return state.room.owner == actor and member.get("connected") == true and member.get("spectator") == false and trusted.get("actor_key") == identity and trusted.get("profiles",{}) is Dictionary and trusted.profiles.has(identity)

## 纯事务准备：失败不改 state，持久化与私有票据交付由会话执行。
static func prepare_inheritance(state:Dictionary, actor:int, request_seq:int, args:Dictionary, trusted:Dictionary, token_hash:String) -> Dictionary:
	if not authorized_owner(state,actor,trusted): return {"ok":false,"error":"只有当前认证房主可以指定继承者"}
	if args.size() != 3 or not args.get("target_member") is int or not args.get("successor_member") is int or not args.get("revision") is int:
		return {"ok":false,"error":"继承请求字段无效"}
	if not valid_counter(request_seq) or request_seq <= int(state.get("inheritance_sequences",{}).get(str(actor),0)) or args.revision != state.room.revision or args.revision >= 2147483647:
		return {"ok":false,"error":"继承请求重复或房间状态已经改变"}
	var target:String = str(args.target_member)
	var successor:String = str(args.successor_member)
	var original = state.room.members.get(target,{})
	var candidate = state.room.members.get(successor,{})
	if target == successor or args.target_member == actor or original.get("connected") != false or original.get("spectator") != false or candidate.get("connected") != true or candidate.get("spectator") != true:
		return {"ok":false,"error":"原成员须离线且继承者须是房内在线成员"}
	var key:String = state.member_identities.get(successor,"")
	if not trusted.profiles.has(key) or not Registry.valid_id(token_hash): return {"ok":false,"error":"继承者认证已失效"}
	# 一个连接不能同时接管两个真人席位；观战成员可以被房主指定。
	for bound in state.get("bindings",{}).values():
		if bound == args.successor_member: return {"ok":false,"error":"继承者已经持有对局席位"}
	var next:Dictionary = state.duplicate(true)
	next.member_identities[target] = key
	next.resume_hashes[target] = token_hash
	next.resume_previous.erase(target)
	next.room.revision = int(next.room.revision) + 1
	next.inheritance_sequences = next.get("inheritance_sequences",{}).duplicate()
	next.inheritance_sequences[str(actor)] = request_seq
	next.inheritance_audit = next.get("inheritance_audit",[]).duplicate(true)
	next.inheritance_audit.append({"actor_member":actor,"target_member":args.target_member,"successor_member":args.successor_member,"revision":next.room.revision,"request_seq":request_seq})
	return {"ok":true,"state":next}
