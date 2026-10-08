extends RefCounted

# 只由房主 authority_host_client 调用；从真实路由及认证登记生成全量快照。
const Sequence = preload("res://scripts/net/server/supervisor_management_sequence.gd")
const Paths = preload("res://scripts/net/server/recovery_path_safety.gd")
const Channel = preload("res://scripts/net/server/server_console_channel.gd")
const Bindings = preload("res://scripts/net/identity/member_identity_bindings.gd")
var sender = preload("res://scripts/net/server/supervisor_identity_ipc.gd").new()
var allocator = Sequence.new()
var _pending:String = ""
var _pending_text:String = ""
var _pending_deadline:int = 0
var confirmation_timeout_msec:int = 10000
var _confirmed_text:String = ""
var _binding:Dictionary = {}
var _next_attempt:int = 0
var retry_msec:int = 250
var error:String = ""
var confirmed:bool = false

func poll(gateway, room:String, owner) -> void:
	var target:Dictionary = gateway.manager.instance_binding(room)
	confirmed = false
	if not gateway.manager.binding_matches(target,true):
		error = "unverified_lan_supervisor"
		return
	if not _binding.is_empty() and _binding != target:
		error = "lan_worker_instance_changed"
		return # 不把旧实例认证自动转交新 worker。
	_binding = target.duplicate(true)
	if not _pending.is_empty():
		var result:Dictionary = sender.confirmation(gateway.manager,_pending)
		if result.get("pending") == true and Time.get_ticks_msec() < _pending_deadline: return
		sender.abandon(_pending)
		_pending = ""
		if result.get("confirmed") == true:
			_confirmed_text = _pending_text
		else:
			error = str(result.get("code","identity_delivery_unconfirmed"))
		_next_attempt = Time.get_ticks_msec() + retry_msec
	var snapshot:Dictionary = snapshot_for(gateway,target,owner)
	if snapshot.is_empty(): return
	var text:String = JSON.stringify(snapshot)
	if text == _confirmed_text:
		confirmed = true
		error = ""
		return
	if Time.get_ticks_msec() < _next_attempt: return
	var sequence:int = allocator.reserve(gateway.manager,room)
	if sequence <= 0:
		error = "durable_management_sequence_unavailable"
		return
	# submit 回调重读实际登记，防止序号落盘期间认证/路由变化。
	var captured:Dictionary = {}
	var result:Dictionary = sender.submit(gateway.manager,room,sequence,func(binding:Dictionary):
		var current:Dictionary = snapshot_for(gateway,binding,owner)
		captured["snapshot"] = current
		return current)
	_next_attempt = Time.get_ticks_msec() + retry_msec
	if result.get("queued") == true:
		_pending = result.request_id
		_pending_text = JSON.stringify(captured.snapshot)
		_pending_deadline = Time.get_ticks_msec() + confirmation_timeout_msec
	else: error = str(result.get("code","identity_delivery_failed"))

func snapshot_for(gateway, target:Dictionary, owner) -> Dictionary:
	if not gateway.manager.binding_matches(target,true) or target != _binding: return {}
	var directory:String = str(gateway.manager.rooms.get(target.room,{}).get("directory","")).path_join("control")
	var path:String = directory.path_join("identity-observed.%s.json" % target.instance_id)
	if not Paths.checked(gateway.manager.storage_root,directory) or not Paths.checked(directory,path): return {}
	var report:Dictionary = Sequence.read_bounded(path)
	var binding:Dictionary = {"room":target.room,"pid":target.pid,"instance":target.instance_id,"authority_host_mode":target.authority_host_mode}
	if report.size() != 2 or not preload("res://scripts/net/server/worker_identity_ipc.gd").same_binding(report.get("binding"),binding) or not report.get("connections") is Dictionary: return {}
	var identities:Dictionary = {}
	if owner.transport.is_connected_to_host() and not owner.identity_profile.is_empty() and owner.player_identity.public_key() == owner.identity_profile.public_key:
		identities[str(owner.transport.peer_id())] = {"key":owner.player_identity.fingerprint(owner.identity_profile.public_key),"profile":owner.identity_profile}
	for external in gateway.routes:
		var route:Dictionary = gateway.routes[external]
		if route.get("room") != target.room or not gateway._route_is_current(external,route) or not route.link.is_connected_to_host(): continue
		var key:String = gateway.lan_identity.authenticated.get(external,"")
		if key.is_empty() or not gateway.lan_identity.profiles.has(key): continue
		var peer:String = str(route.link.peer_id())
		if identities.has(peer): return {}
		identities[peer] = {"key":key,"profile":gateway.lan_identity.profiles[key]}
	var connections:Dictionary = {}
	var profiles:Dictionary = {}
	for peer in report.connections:
		if not peer is String or not peer.is_valid_int() or str(int(peer)) != peer or int(peer) <= 1: return {}
		var fact = report.connections[peer]
		if not fact is Dictionary or fact.size() != 3 or not Channel.valid_id(str(fact.get("nonce",""))) or not Bindings.valid_counter(fact.get("member")) or fact.member <= 1 or not fact.get("joined") is bool: return {}
		if not fact.joined and fact.member != int(peer): return {}
		if not identities.has(peer): continue # 未认证连接永不授予身份。
		var identity:Dictionary = identities[peer]
		connections[peer] = {"nonce":fact.nonce,"member":int(fact.member),"key":identity.key}
		profiles[identity.key] = {"username":identity.profile.username,"nickname":identity.profile.nickname}
	if not gateway.manager.binding_matches(target,true): return {}
	return {"connections":connections,"profiles":profiles}
