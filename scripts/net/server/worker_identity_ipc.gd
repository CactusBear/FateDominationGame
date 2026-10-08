extends RefCounted

## 私有管理通道消费者；不注册网络 RPC，不修改大厅、恢复存档或规则。
const Channel = preload("res://scripts/net/server/server_console_channel.gd")
const Bindings = preload("res://scripts/net/identity/member_identity_bindings.gd")
const Registry = preload("res://scripts/net/identity/player_registry.gd")
var _binding:Dictionary = {}
var _path:String = ""
var _state:Dictionary = {}
var _observed:Dictionary = {}
var _usable:bool = false

## 只能由 room control 用主管批准的路径配置；旧实例账本必须显式处理，不能自动覆盖。
func configure(binding:Dictionary, path:String) -> bool:
	_usable = false
	_observed.clear()
	_state.clear()
	if not _valid_binding(binding) or path.is_empty(): return false
	_binding = binding.duplicate(true)
	_path = path
	if FileAccess.file_exists(path):
		var file = FileAccess.open(path,FileAccess.READ)
		if file == null: return false
		if file.get_length() > 4096:
			file.close()
			return false
		var parsed = JSON.parse_string(file.get_as_text())
		file.close()
		if not parsed is Dictionary or parsed.size() != 4 or not same_binding(parsed.get("binding"),_binding) or not Bindings.valid_counter(parsed.get("request_seq")) or parsed.request_seq <= 0 or not _valid_snapshot(parsed.get("connections"),parsed.get("profiles"),false): return false
		_state = parsed.duplicate(true)
	_usable = true
	return true

## worker 认证适配器在真实传输连接世代建立时调用。nonce 必须 worker 随机生成并经握手交付主管。
## 不能把网络消息自报的 peer/nonce 直接传入本函数。
func observe_connection(peer:int, nonce:String) -> bool:
	if not _usable or peer <= 0 or not Channel.valid_id(nonce): return false
	_observed[str(peer)] = nonce
	return true

func forget_connection(peer:int) -> void:
	_observed.erase(str(peer))

func last_sequence() -> int:
	return int(_state.get("request_seq",0))

func install(request:Dictionary) -> Dictionary:
	if not _usable: return _reject("identity_ledger_unavailable")
	if request.size() != 8 or request.get("action") != "identity_context" or JSON.stringify(request).to_utf8_buffer().size() > 4096: return _reject("invalid_identity_request")
	for field in ["room","pid","instance","authority_host_mode"]:
		if request.get(field) != _binding.get(field): return _reject("stale_identity_instance")
	if not Bindings.valid_counter(request.get("request_seq")) or request.request_seq <= last_sequence(): return _reject("replayed_identity_request")
	if not _valid_snapshot(request.get("connections"),request.get("profiles"),true): return _reject("invalid_authenticated_snapshot")
	var next:Dictionary = {"binding":_binding.duplicate(true),"request_seq":int(request.request_seq),"connections":request.connections.duplicate(true),"profiles":request.profiles.duplicate(true)}
	# 复用现有临时写入/rename；失败不消费序号、不发布、不回成功。
	if Channel.write_json(_path,next) != OK: return _reject("identity_persistence_failed")
	_state = next
	return {"ok":true,"result":{"identity_context_installed":true,"request_seq":int(request.request_seq)},"executed":false}

## worker 内部消费接口；peer 与 nonce 来自当前 worker 连接注册表，而非客户端 args。
## 返回 batch15 AuthorityRestoreContract.prepare 所需 trusted；不等于授权恢复。
func context_for(peer:int, nonce:String, expected_member:int) -> Dictionary:
	if not _usable or _observed.get(str(peer)) != nonce: return {}
	var item = _state.get("connections",{}).get(str(peer),{})
	if expected_member <= 0 or item.get("member") != expected_member or item.get("nonce") != nonce: return {}
	var profiles:Dictionary = _state.get("profiles",{})
	if not _approved_profile(profiles.get(item.get("key"))): return {}
	return {"binding":_binding.duplicate(true),"authenticated":true,"actor_key":item.key,"actor_member":int(item.member),"profiles":profiles.duplicate(true)}

## JSON 数值读回为 float；Dictionary 深比较区分 int/float，不能比较整个绑定。
## 只接受四字段完整绑定，PID 验证后逐字段比较；不归一化任意身份或路由。
static func same_binding(value:Variant, expected:Dictionary, instance_field:String = "instance") -> bool:
	if instance_field not in ["instance","instance_id"] or not value is Dictionary or value.size() != 4 or expected.size() != 4: return false
	for field in ["room",instance_field,"authority_host_mode"]:
		if not value.get(field) is String or not expected.get(field) is String or value[field] != expected[field]: return false
	if not Channel.valid_id(value.room) or not Channel.valid_id(value[instance_field]) or value.authority_host_mode not in ["lan","p2p"]: return false
	return Bindings.valid_counter(value.get("pid")) and Bindings.valid_counter(expected.get("pid")) and value.pid > 0 and value.pid == expected.pid

static func _valid_binding(binding:Dictionary) -> bool:
	return binding.size() == 4 and binding.get("room") is String and binding.get("instance") is String and Channel.valid_id(binding.room) and Channel.valid_id(binding.instance) and Bindings.valid_counter(binding.get("pid")) and binding.pid > 0 and binding.get("authority_host_mode") in ["lan","p2p"]

func _valid_snapshot(connections:Variant, profiles:Variant, live:bool) -> bool:
	if not connections is Dictionary or not profiles is Dictionary: return false
	var members:Dictionary = {}
	var keys:Dictionary = {}
	for peer in connections:
		if not peer is String or not peer.is_valid_int() or str(int(peer)) != peer or not Bindings.valid_counter(int(peer)) or int(peer) <= 0: return false
		var item = connections[peer]
		if not item is Dictionary or item.size() != 3 or not item.get("nonce") is String or not Channel.valid_id(item.nonce) or not Bindings.valid_counter(item.get("member")) or item.member <= 0 or not item.get("key") is String or not Registry.valid_id(item.key): return false
		if not _approved_profile(profiles.get(item.key)) or members.has(int(item.member)): return false
		if live and _observed.get(peer) != item.nonce: return false
		members[int(item.member)] = true
		keys[item.key] = true
	if profiles.size() != keys.size(): return false
	for key in profiles:
		if not key is String or not Registry.valid_id(key) or not _approved_profile(profiles[key]) or not keys.has(key): return false
	return true

static func _approved_profile(value:Variant) -> bool:
	if value is bool: return value
	if not value is Dictionary or value.size() != 2 or not value.get("username") is String or not value.get("nickname") is String: return false
	return preload("res://scripts/net/identity/player_name_rules.gd").username_error(value.username).is_empty()

static func _reject(code:String) -> Dictionary:
	return {"ok":false,"code":code,"executed":false}
