class_name MatchLobbySession
extends RefCounted

const Transport = preload("res://scripts/net/transport/enet_transport.gd")
const Room = preload("res://scripts/net/session/room_state.gd")
const RECOVERY_SCHEMA_VERSION:int = 2
const APPROVED_DATA_SNAPSHOT_VERSION:int = 1
signal changed
signal catalogs_changed
signal data_management_requested(actor:int, action:String, args:Dictionary)
signal rejected(reason: String)
## 仅有明确请求序号的拒绝可用于解除该请求的锁。
signal request_rejected(sequence: int, reason: String)
signal group_preview_received(request_id: int, result: Dictionary)
var transport = Transport.new()
var connection_driver: RefCounted
## 仅普通房主 UI 使用；worker 内部 host()/host_peer() 契约保持不变。
var authority_host: RefCounted

func host_authority(port:int, name:String, settings:Dictionary, bind_address:String = "*") -> Error:
	if _restore_failed_closed or _restore_in_progress or _begin_in_progress: return ERR_UNAVAILABLE
	close()
	var client = load("res://scripts/net/session/authority_host_client.gd").new()
	var result:Error = client.start(self, name, settings, "lan", port, bind_address)
	if result != OK:
		error = client.error
		client.close()
		return result
	authority_host = client
	return OK

func host_authority_peer(peer:MultiplayerPeer, name:String, settings:Dictionary) -> Error:
	if _restore_failed_closed or _restore_in_progress or _begin_in_progress: return ERR_UNAVAILABLE
	close()
	var client = load("res://scripts/net/session/authority_host_client.gd").new()
	var result:Error = client.start(self, name, settings, "p2p", 0, "*", peer)
	if result != OK:
		error = client.error
		client.close()
		return result
	authority_host = client
	return OK
var blobs = preload("res://scripts/net/content/blob_receiver.gd").new()
var _published_blobs: Dictionary = {}
var _blob_sends: Array = []
var blob_chunks_per_poll: int = 2
var max_blob_requests: int = 64
var room = Room.new()
var selection = preload("res://scripts/net/authority/selection_authority.gd").new()
var selection_view: Dictionary = {}
var match_authority = preload("res://scripts/net/authority/match_authority.gd").new()
var _mirror = preload("res://scripts/match/view_mirror.gd").new()
var _match_bound: bool = false
var _pending_view: Dictionary = {}
var _action_view: Dictionary = {}
var _selection_config: Dictionary = {}
var _masters: Array = []
var _servants: Array = []
var view: Dictionary = {}
var error: String = ""
var _host: bool = false
var _hello: Dictionary = {}
var _hello_sent: bool = false
var _seq: int = 0
var _received_seq: Dictionary = {}
var _peers: Array = []
var room_files: Array = []
var _manifest_transfer = preload("res://scripts/net/transport/room_manifest_transfer.gd").new()
var _catalog_transfer = preload("res://scripts/net/transport/catalog_message_transfer.gd").new()
var catalogs: Dictionary = {}
var server_data:Dictionary = {}
var selection_modes:Array = []
var data_revision: int = 0
var _data_confirmed: Dictionary = {}
var _assets = preload("res://scripts/net/content/room_assets.gd").new()
var require_room_data: bool = false
var dedicated: bool = false
var server_room_id: String = ""
var server_rooms: Array = []
var server_info:Dictionary = {}
signal server_notice_received(text:String)
var _server_request: Dictionary = {}
var _server_sent: bool = false
var _server_peer_id: int = 0
var _rules_revision: int = 0
var _room_rules_active: bool = false
var _restore_in_progress:bool = false
var _restore_cancelled:bool = false
var _begin_in_progress:bool = false
var _begin_cancelled:bool = false
var _restore_failed_closed:bool = false
var record_matches:bool = false
var archive_root:String = "user://match_saves"
var recovery_state_path:String = ""
var management_paused:bool = false
var join_password:String = ""
var room_password = preload("res://scripts/net/identity/room_password.gd").new()
var player_identity = preload("res://scripts/net/identity/player_identity.gd").new()
var identity_profile:Dictionary = {}
var identity_authenticated:bool = false
var identity_is_admin:bool = false
signal server_admin_result_received(response:Dictionary)
var _identity_sent:bool = false
var _lan_identity_context:Dictionary = {}
var _recovery_bindings:Dictionary = {}
var _recovery_seat_kinds:Dictionary = {}


## 私有恢复能力与传输地址分离，凭据不进入公开快照。
const RESUME_TOKEN_BYTES:int = 32
var _resume_ticket:Dictionary = {}
var _resume_hashes:Dictionary = {}
var _resume_previous:Dictionary = {}
var _member_identities:Dictionary = {}
var _lan_restore_authorized:bool = false
var lan_context:Callable
var lan_gate:Callable
var authority_host_mode:String = ""
var _identity_binding_required:bool = false
var _inheritance_sequences:Dictionary = {}
var _inheritance_audit:Array = []
signal inheritance_candidates_received(model:Dictionary)
signal inheritance_ticket_received(member:int)
var _inheritance_ticket:Dictionary = {}
var _member_by_peer:Dictionary = {}
var _peer_by_member:Dictionary = {}
var _join_endpoint:Dictionary = {}
var _resume_inflight:bool = false
var _previous_data_root: String = ""
var _previous_cache_path: String = ""

func _init() -> void:
	transport.message_received.connect(_receive)
	transport.peer_connected.connect(_connected)
	transport.peer_disconnected.connect(_disconnected)

func host(port: int, name: String, settings: Dictionary, bind_address: String = "*") -> Error:
	if _restore_failed_closed or _restore_in_progress or _begin_in_progress: return ERR_UNAVAILABLE
	close()
	var result: Error = transport.listen(port, bind_address)
	if result != OK:
		error = "无法创建房间监听：" + error_string(result)
		return result
	return _initialize_host(name, settings)

func _initialize_host(name: String, settings: Dictionary) -> Error:
	if _restore_failed_closed: return ERR_UNAVAILABLE
	_host = true
	if not room.configure(1, settings) or not room.join(1, name):
		error = room.error
		transport.close()
		return ERR_INVALID_PARAMETER
	_publish()
	return OK

func host_peer(peer: MultiplayerPeer, name: String, settings: Dictionary) -> Error:
	if _restore_failed_closed or _restore_in_progress or _begin_in_progress: return ERR_UNAVAILABLE
	if peer == null or peer.get_unique_id() != 1:
		return ERR_INVALID_PARAMETER
	close()
	var result: Error = transport.attach_peer(peer)
	return _initialize_host(name, settings) if result == OK else result

func join_peer(peer: MultiplayerPeer, name: String, spectator: bool = false) -> Error:
	if _restore_failed_closed or _restore_in_progress or _begin_in_progress: return ERR_UNAVAILABLE
	if peer == null or peer.get_unique_id() <= 1:
		return ERR_INVALID_PARAMETER
	close()
	_hello = {"name": name, "spectator": spectator}
	return transport.attach_peer(peer)

func join(address: String, port: int, name: String, spectator: bool = false) -> Error:
	if _restore_failed_closed or _restore_in_progress or _begin_in_progress: return ERR_UNAVAILABLE
	close()
	_hello = {"name": name, "spectator": spectator}
	_join_endpoint = {"address":address,"port":port}
	return transport.connect_to(address, port)

## 网关分配的内部连接身份是房间管理与素材来源的统一标识。
## 服务端明确完成 worker 验证及内部路由连接后，才会授予逻辑 peer。
## 这不是数据 ACK，也不意味着大厅快照或完整对局已经就绪。
func server_worker_ready() -> bool:
	return not _server_request.is_empty() and _server_peer_id > 1 and transport.is_connected_to_host() and error.is_empty()

func peer_id() -> int:
	if not _host and not _resume_ticket.is_empty():
		return _resume_ticket.member
	return _server_peer_id if _server_peer_id > 0 else transport.peer_id()

func has_resume_identity() -> bool:
	return not _host and not _resume_ticket.is_empty()

func can_reconnect() -> bool:
	if not has_resume_identity() or transport.is_connected_to_host() or transport.is_connecting(): return false
	if connection_driver != null and connection_driver.has_method("can_reconnect_session"):
		return connection_driver.can_reconnect_session(self)
	return not _join_endpoint.is_empty()

func reconnect_available() -> bool:
	return has_resume_identity() and (not _join_endpoint.is_empty() or (connection_driver != null and connection_driver.has_method("reconnect")))

func is_reconnecting() -> bool:
	return _resume_inflight and not transport.is_connected_to_host() and not can_reconnect()

func fail_reconnect(reason:String) -> void:
	if not _resume_inflight or transport.is_connected_to_host(): return
	transport.close()
	_resume_inflight = false
	error = reason
	rejected.emit(reason)
	changed.emit()

func _prepare_reconnect() -> void:
	identity_is_admin = false
	identity_authenticated = false
	_identity_sent = false
	_lan_identity_context.clear()
	transport.close()
	_manifest_transfer.reset()
	blobs.cancel_peer(1)
	_blob_sends.clear()
	_hello["resume"] = _resume_ticket.duplicate(true)
	_hello_sent = false
	_seq = 0
	_match_bound = false
	_mirror.reset(-1)
	_resume_inflight = true
	error = ""

func reconnect() -> Error:
	if not can_reconnect(): return ERR_UNAVAILABLE
	if connection_driver != null and connection_driver.has_method("reconnect"):
		var driver = connection_driver
		return driver.reconnect(self)
	_prepare_reconnect()
	if not server_room_id.is_empty():
		_server_request = {"kind":"server_join","args":{"room":server_room_id, "resume":_resume_ticket.duplicate(true)}}
		_server_sent = false
		_server_peer_id = 0
	var result:Error = transport.connect_to(_join_endpoint.address,_join_endpoint.port)
	changed.emit()
	return result


## 崩溃恢复已由 authority_host_client 完成原 worker 校验、换代和 _prepare_reconnect。
## 成功后必须等待 authority_host.poll() 接入新 loopback，不能再次调用 reconnect()。
func reconnect_after_worker_crash() -> Error:
	if authority_host != null and authority_host.has_method("diagnostics"):
		var diagnostic:Dictionary = authority_host.diagnostics()
		if diagnostic.get("worker_crash_waiting", false):
			if not authority_host.has_method("recover_worker") or not authority_host.recover_worker():
				error = "本机权威恢复未获批准"
				return ERR_UNAUTHORIZED
			error = ""
		changed.emit()
		return OK
	return reconnect()

## 调用方重新完成 P2P 握手后接入新直连，不使用信令转发对局。
func resume_peer(peer:MultiplayerPeer) -> Error:
	if not has_resume_identity() or transport.is_connected_to_host() or peer == null or peer.get_unique_id() <= 1:
		return ERR_INVALID_PARAMETER
	_prepare_reconnect()
	var result:Error = transport.attach_peer(peer)
	changed.emit()
	return result

func _send(member:int, message:Dictionary, channel:int = 0) -> Error:
	if _restore_failed_closed or _restore_in_progress or _begin_in_progress: return ERR_UNAVAILABLE
	return transport.send(int(_peer_by_member.get(member,member)) if _host else member,message,channel)

func send_catalog_message(member:int, message:Dictionary, channel:int = 0) -> Error:
	if _restore_failed_closed or _restore_in_progress or _begin_in_progress: return ERR_UNAVAILABLE
	var parts:Array = _catalog_transfer.encode(message, transport.max_packet_bytes)
	if parts.is_empty():
		error = _catalog_transfer.error
		return ERR_INVALID_PARAMETER
	for part in parts:
		var result:Error = _send(member, part, channel)
		if result != OK: return result
	return OK

func _new_resume_token() -> String:
	var bytes:PackedByteArray = Crypto.new().generate_random_bytes(RESUME_TOKEN_BYTES)
	return bytes.hex_encode() if bytes.size() == RESUME_TOKEN_BYTES else ""

## 先把新身份绑定写入候选，再落盘；落盘失败时恢复全部内存绑定。
## 返回值仅表示持久化提交；发送失败撤销连接授权，调用者须检查成员在线状态。
## 票据交付只能发生在持久化成功之后；不能依赖第二次写盘回滚已提交的哈希。
func _accept_identity(connection:int, member:int, token:String, previous:String = "") -> bool:
	var old_peer_by_member:Dictionary = _peer_by_member.duplicate()
	var old_member_by_peer:Dictionary = _member_by_peer.duplicate()
	var old_peers:Array = _peers.duplicate()
	var old_hashes:Dictionary = _resume_hashes.duplicate()
	var old_previous:Dictionary = _resume_previous.duplicate()
	var old_recovery_bindings:Dictionary = _recovery_bindings.duplicate()
	_member_by_peer[connection] = member
	_peer_by_member[member] = connection
	if not _peers.has(member): _peers.append(member)
	_resume_hashes[member] = token.sha256_text()
	if previous.is_empty(): _resume_previous.erase(member)
	else: _resume_previous[member] = previous
	if not recovery_state_path.is_empty() and not _persist_recovery_state():
		_peer_by_member = old_peer_by_member
		_member_by_peer = old_member_by_peer
		_peers = old_peers
		_resume_hashes = old_hashes
		_resume_previous = old_previous
		_recovery_bindings = old_recovery_bindings
		error = "恢复身份保存失败，原成员绑定和票据未改变"
		return false
	var sent:Error = _send(member,{"kind":"identity","member":member,"token":token,"data_revision":data_revision})
	if sent != OK:
		_peer_by_member = old_peer_by_member
		_member_by_peer = old_member_by_peer
		_peers = old_peers
		room.mark_disconnected(member)
		error = "恢复身份已保存但票据发送失败，可用原票据重试：" + error_string(sent) if not previous.is_empty() else "新成员身份已保存但票据发送失败，尚未交付恢复凭据：" + error_string(sent)
	return true

func _join_identity(connection:int, args:Dictionary) -> bool:
	if _member_by_peer.has(connection): return room._reject("连接已经绑定房间成员")
	var identity:String = ""
	var require_identity:bool = _identity_binding_required
	if authority_host_mode in ["lan","p2p"]:
		if not lan_context.is_valid(): return room._reject("LAN 主管认证上下文不可用")
		var trusted:Dictionary = lan_context.call(connection,connection,true)
		identity = str(trusted.get("actor_key",""))
		var profile = trusted.get("profiles",{}).get(identity)
		if trusted.get("authenticated") != true or not profile is Dictionary: return room._reject("LAN 连接尚未安装已认证身份")
		args = args.duplicate(true)
		args.name = profile.nickname
		require_identity = true
		for member in room.members:
			if not _member_identities.has(member): return room._reject("旧房间缺少成员密钥绑定，拒绝认证恢复")
	elif dedicated:
		# worker 只监听回环；字段由网关重建，不从普通客户端直接接收。
		var context = args.get("gateway_identity")
		if not context is Dictionary or not context.get("required") is bool or not context.get("key") is String:
			return room._reject("缺少网关认证上下文")
		if _identity_binding_required and not context.required:
			return room._reject("房间密钥认证不能降级")
		if context.required:
			identity = context.key
			if not preload("res://scripts/net/identity/player_registry.gd").valid_id(identity): return room._reject("网关密钥身份无效")
			# 已有无绑定成员不能在切换认证时被静默认领。
			for member in room.members:
				if not _member_identities.has(member): return room._reject("旧房间缺少成员密钥绑定，拒绝认证恢复")
			require_identity = true
	var token:String = _new_resume_token()
	if token.is_empty(): return room._reject("无法生成私有恢复凭据")
	if args.has("resume"):
		var ticket = args.resume
		if not ticket is Dictionary or not ticket.get("member") is int or not ticket.get("token") is String or ticket.token.length() != RESUME_TOKEN_BYTES * 2:
			return room._reject("恢复凭据无效")
		var member:int = ticket.member
		if require_identity and (_member_identities.get(member,"") != identity or identity.is_empty()):
			return room._reject("恢复凭据与当前认证密钥不匹配")
		var proof:String = ticket.token.sha256_text()
		if not _resume_hashes.has(member) or (proof != _resume_hashes[member] and proof != _resume_previous.get(member,"")):
			return room._reject("恢复凭据无效")
		var old_member:Dictionary = room.members[member].duplicate(true)
		var old_revision:int = room.revision
		if not room.reconnect(member): return false
		if not _accept_identity(connection,member,token,proof):
			room.members[member] = old_member
			room.revision = old_revision
			return room._reject("恢复身份保存失败，原成员绑定和票据未改变")
		if not room.members[member].connected: return room._reject(error)
		return true
	if not room_password.accepts(args.get("password","")): return room._reject("房间密码错误")
	var old_members:Dictionary = room.members.duplicate(true)
	var old_room_revision:int = room.revision
	var had_identity:bool = _member_identities.has(connection)
	var old_identity:String = _member_identities.get(connection,"")
	if not room.join(connection,args.name,args.spectator): return false
	var old_required:bool = _identity_binding_required
	_identity_binding_required = require_identity
	if _identity_binding_required: _member_identities[connection] = identity
	if not _accept_identity(connection,connection,token):
		room.members = old_members
		room.revision = old_room_revision
		_identity_binding_required = old_required
		if had_identity: _member_identities[connection] = old_identity
		else: _member_identities.erase(connection)
		return room._reject("恢复身份保存失败，原成员绑定和票据未改变")
	if not room.members[connection].connected: return room._reject(error)
	return true

func _inheritance_snapshot() -> Dictionary:
	var state:Dictionary = {"room":room.snapshot(),"identity_binding_required":_identity_binding_required,"member_identities":{},"resume_hashes":{},"resume_previous":{},"bindings":{},"inheritance_sequences":_inheritance_sequences.duplicate(),"inheritance_audit":_inheritance_audit.duplicate(true)}
	var saved_members:Dictionary = {}
	for id in room.members: saved_members[str(id)] = room.members[id].duplicate(true)
	state.room.members = saved_members
	for id in _member_identities: state.member_identities[str(id)] = _member_identities[id]
	for id in _resume_hashes: state.resume_hashes[str(id)] = _resume_hashes[id]
	for id in _resume_previous: state.resume_previous[str(id)] = _resume_previous[id]
	var bindings:Dictionary = match_authority.controllers if match_authority.started else _recovery_bindings
	for id in bindings: state.bindings[str(id)] = bindings[id]
	return state

## 票据只能在旧观战连接断开后启用；不在原连接上切换授权席位。
func activate_inheritance_ticket() -> bool:
	if _inheritance_ticket.is_empty() or transport.is_connected_to_host() or transport.is_connecting(): return false
	_resume_ticket = _inheritance_ticket.duplicate(true)
	_inheritance_ticket.clear()
	return true

func _inherit_identity(actor:int, sequence:int, args:Dictionary, trusted:Dictionary) -> bool:
	if not dedicated or recovery_state_path.is_empty(): return room._reject("身份继承要求认证服务端及可持久化恢复文件")
	var original:Dictionary = _inheritance_snapshot()
	var original_bindings:Dictionary = _recovery_bindings.duplicate()
	var token:String = _new_resume_token()
	if token.is_empty(): return room._reject("无法生成继承恢复凭据")
	var result:Dictionary = preload("res://scripts/net/identity/member_identity_bindings.gd").prepare_inheritance(original,actor,sequence,args,trusted,token.sha256_text())
	if not result.ok: return room._reject(result.error)
	var target:int = args.target_member
	var old_identity:String = _member_identities[target]
	var old_hash:String = _resume_hashes.get(target,"")
	var old_previous:String = _resume_previous.get(target,"")
	_member_identities[target] = result.state.member_identities[str(target)]
	_resume_hashes[target] = token.sha256_text()
	_resume_previous.erase(target)
	room.revision = result.state.room.revision
	_inheritance_sequences = result.state.inheritance_sequences
	_inheritance_audit = result.state.inheritance_audit
	if not _persist_recovery_state():
		_member_identities[target] = old_identity
		if original.resume_hashes.has(str(target)): _resume_hashes[target] = old_hash
		else: _resume_hashes.erase(target)
		if original.resume_previous.has(str(target)): _resume_previous[target] = old_previous
		room.revision = original.room.revision
		_inheritance_sequences = original.inheritance_sequences
		_inheritance_audit = original.inheritance_audit
		_recovery_bindings = original_bindings
		return room._reject("身份继承保存失败，原恢复档和凭据未改变")
	# 持久化后才交付新票据；发送失败保留审计，房主可再次显式指定并轮换。
	var sent:Error = _send(args.successor_member,{"kind":"inheritance_ticket","member":target,"token":token})
	if sent != OK:
		error = "身份继承已保存但票据发送失败；原密钥已撤销，房主须刷新修订并用新序号重新指定：" + error_string(sent)
		return room._reject(error)
	return true

func configure_identity(path:String,username:String,nickname:String) -> bool:
	var reason:String = preload("res://scripts/net/identity/player_name_rules.gd").username_error(username)
	if not reason.is_empty(): error = reason;return false
	if not player_identity.open(path): error = player_identity.error;return false
	identity_profile = {"public_key":player_identity.public_key(),"username":username,"nickname":nickname}
	identity_authenticated = false
	_identity_sent = false
	return true

func join_server(address: String, port: int, name: String, room_id: String = "", room_name: String = "", settings: Dictionary = {}, spectator: bool = false) -> Error:
	var result: Error = join(address, port, name, spectator)
	if result != OK:
		return result
	_server_request = {"kind": "server_join", "args": {"room": room_id}} if not room_id.is_empty() else {"kind": "server_create", "args": {"name": room_name, "settings": settings.duplicate(true)}}
	return OK

func poll(delta: float = 0.0) -> void:
	if _restore_failed_closed: return
	if _begin_in_progress:
		transport.keep_alive()
		return
	if _restore_in_progress:
		_maintain_restore_transport()
		return
	if authority_host != null:
		authority_host.call("poll")
	if connection_driver != null:
		connection_driver.call("poll")
	transport.poll()
	for connection in _catalog_transfer.fragments.expire():
		_fail(int(_member_by_peer.get(connection, connection)) if _host else 1, "候选目录分片接收超时")
	if not _host and _manifest_transfer.expire():
		error = _manifest_transfer.error
		rejected.emit(error)
	_pump_blobs()
	if not _host and authority_host == null and _server_request.is_empty() and not _hello.is_empty() and not _identity_sent and transport.is_connected_to_host():
		_identity_sent = true
		if identity_profile.is_empty():
			error = "LAN/P2P 客机必须先配置密钥身份"
			rejected.emit(error)
		else: request("lan_identity_begin",identity_profile.duplicate(true))
	if not _server_request.is_empty() and not identity_profile.is_empty() and not identity_authenticated and not _identity_sent and transport.is_connected_to_host():
		_identity_sent = true
		request("server_identity_begin",identity_profile.duplicate(true))
	if not _server_request.is_empty() and not _server_sent and transport.is_connected_to_host() and (identity_profile.is_empty() or identity_authenticated):
		_server_sent = true
		request("server_list", {})
		request(_server_request.kind, _server_request.args)
	if _host and room.phase == "playing" and not management_paused and _disconnected_players().is_empty() and match_authority.step(delta):
		_publish_match()
	if _host and room.phase == "restoring" and match_authority.started and data_ready() and _recovery_barrier_ready():
		room.phase = "playing"
		room.revision += 1
		_bind_match()
		_publish()
		_publish_match()
	if not _host and not _hello_sent and not _hello.is_empty() and transport.is_connected_to_host() and ((_server_request.is_empty() and (authority_host != null or identity_authenticated)) or (not _server_request.is_empty() and _server_peer_id > 0)):
		_hello_sent = true
		_hello["password"] = join_password
		request("join", _hello)

func request(kind: String, args: Dictionary, registered: Callable = Callable()) -> Error:
	if _restore_failed_closed or _restore_in_progress or _begin_in_progress: return ERR_UNAVAILABLE
	if _seq == 9223372036854775807:
		return ERR_OUT_OF_MEMORY
	_seq += 1
	var message := {"v": 1, "seq": _seq, "kind": kind, "args": args}
	# 房主 _receive 同步发回拒绝，必须在发送前登记序号。
	if registered.is_valid(): registered.call(_seq)
	if _host:
		_receive(1, message)
		return OK
	if kind == "catalog": return send_catalog_message(1, message)
	return transport.send(1, message)

func close() -> void:
	if _restore_in_progress and not _restore_failed_closed:
		_restore_cancelled = true # 不在维护栈中销毁规则；由事务出口失败关闭。
		return
	if _begin_in_progress:
		_begin_cancelled = true # 不在同步初始化栈内结束规则或关闭 transport。
		return
	if authority_host != null:
		authority_host.call("close")
		authority_host = null
	identity_is_admin = false
	identity_authenticated = false
	_identity_sent = false
	_lan_identity_context.clear()
	room_password.verifier = {}
	management_paused = false
	var owns_match: bool = _host and match_authority.started
	var restores_rules: bool = _room_rules_active
	match_authority.close_archive()
	transport.close()
	if connection_driver != null:
		connection_driver.call("close")
	connection_driver = null
	blobs.cancel_peer(1)
	_published_blobs.clear()
	_blob_sends.clear()
	room = Room.new()
	selection = preload("res://scripts/net/authority/selection_authority.gd").new()
	selection_view.clear()
	match_authority = preload("res://scripts/net/authority/match_authority.gd").new()
	_mirror.reset(-1)
	_match_bound = false
	_pending_view.clear()
	_action_view.clear()
	_selection_config.clear()
	_masters.clear()
	_servants.clear()
	view.clear()
	error = ""
	_host = false
	_hello.clear()
	_hello_sent = false
	_seq = 0
	_received_seq.clear()
	_peers.clear()
	room_files.clear()
	_manifest_transfer.reset()
	_catalog_transfer.fragments.reset()
	catalogs.clear()
	server_data.clear()
	selection_modes.clear()
	data_revision = 0
	_data_confirmed.clear()
	_assets.clear()
	_restore_room_rules()
	if owns_match and not restores_rules:
		GameStart.end_session()
	require_room_data = false
	dedicated = false
	server_room_id = ""
	server_rooms.clear()
	server_info.clear()
	_server_request.clear()
	_server_sent = false
	_server_peer_id = 0
	_rules_revision = 0
	_resume_ticket.clear()
	_recovery_bindings.clear()
	_recovery_seat_kinds.clear()
	_resume_hashes.clear()
	_resume_previous.clear()
	_member_identities.clear()
	_identity_binding_required = false
	_inheritance_sequences.clear()
	_inheritance_audit.clear()
	_inheritance_ticket.clear()
	_member_by_peer.clear()
	_peer_by_member.clear()
	_join_endpoint.clear()
	_resume_inflight = false

func _connected(id: int) -> void:
	if _host: _received_seq.erase(id)

func _disconnected(id: int) -> void:
	if _restore_in_progress: _restore_cancelled = true
	var connection:int = id
	_catalog_transfer.fragments.cancel_peer(connection)
	id = int(_member_by_peer.get(connection,connection))
	_member_by_peer.erase(connection)
	if _peer_by_member.get(id) == connection: _peer_by_member.erase(id)
	_received_seq.erase(connection)
	_peers.erase(id)
	_data_confirmed.erase(id)
	blobs.cancel_peer(id)
	_blob_sends = _blob_sends.filter(func(job): return job.peer != id)
	if _host:
		room.mark_disconnected(id)
		if match_authority.started:
			_publish_match()
		_publish()
	else:
		_manifest_transfer.reset()
		error = "与房主连接中断"
		identity_authenticated = false
		identity_is_admin = false
		rejected.emit(error)
		changed.emit()

func _receive(sender: int, message: Dictionary) -> void:
	if _restore_failed_closed or _restore_in_progress or _begin_in_progress: return
	var connection:int = sender
	if _host and authority_host_mode in ["lan","p2p"]:
		if not lan_gate.is_valid() or not lan_context.is_valid():
			transport.disconnect_peer(connection)
			return
		if lan_gate.call(connection,message): return
	if _host: sender = int(_member_by_peer.get(connection,connection))
	if message.get("kind") in ["catalog_part", "server_data_catalog_part"]:
		if _host:
			if (connection != 1 and not _member_by_peer.has(connection)) or room.phase != "lobby" or not room.members.has(sender) or not room.members[sender].connected:
				_catalog_transfer.fragments.cancel_peer(connection)
				transport.send(connection, {"kind":"error", "reason":"无权在当前阶段上报条目目录"})
				return
		elif sender != 1 or view.get("owner") != peer_id() or view.get("phase") != "lobby":
			_catalog_transfer.fragments.cancel_peer(connection)
			return
		message = _catalog_transfer.accept(connection, message, transport.max_packet_bytes, "catalog" if _host else "server_data_catalog")
		if message.is_empty():
			if not _catalog_transfer.error.is_empty(): _fail(sender if _host else 1, _catalog_transfer.error)
			return
	if not _host:
		if sender != 1:
			return
		if message.get("kind") == "lan_identity_challenge":
			if authority_host != null or not _server_request.is_empty() or not _identity_sent or identity_authenticated or identity_profile.is_empty() or not _lan_identity_context.is_empty(): return
			if not message.get("challenge") is PackedByteArray or message.challenge.size() != 32 or message.get("peer") != transport.peer_id() or not message.get("room") is String or message.room.is_empty() or not message.get("instance") is String or message.instance.is_empty(): return
			_lan_identity_context = {"peer":message.peer,"room":message.room,"instance":message.instance}
			var context:String = preload("res://scripts/net/identity/lan_identity_challenge.gd").context(identity_profile,message.room,message.instance,message.peer)
			var proof:Dictionary = _lan_identity_context.duplicate()
			proof.signature = player_identity.sign_challenge(message.challenge,context)
			request("lan_identity_proof",proof)
			return
		if message.get("kind") == "lan_identity_ready":
			if _server_request.is_empty() and not _lan_identity_context.is_empty() and message.get("peer") == _lan_identity_context.peer and message.get("room") == _lan_identity_context.room and message.get("instance") == _lan_identity_context.instance and message.get("identity") == player_identity.fingerprint(identity_profile.public_key) and message.get("username") == identity_profile.username and message.get("nickname") == identity_profile.nickname:
				identity_authenticated = true
				changed.emit()
			return
		if message.get("kind") == "server_identity_challenge":
			if not _server_request.is_empty() and _identity_sent and message.get("challenge") is PackedByteArray:
				var context:String = JSON.stringify([identity_profile.public_key,identity_profile.username,identity_profile.nickname])
				request("server_identity_proof",{"signature":player_identity.sign_challenge(message.challenge,context)})
			return
		if message.get("kind") == "server_identity_ready":
			if not identity_profile.is_empty() and message.get("identity") == player_identity.fingerprint(identity_profile.public_key) and message.get("username") == identity_profile.username and message.get("nickname") == identity_profile.nickname:
				identity_authenticated = true
				changed.emit()
			return
		if message.get("kind") == "server_identity_permissions":
			if identity_authenticated and message.get("admin") is bool:
				identity_is_admin = message.admin
				changed.emit()
			return
		if message.get("kind") == "server_admin_result":
			if identity_authenticated and message.get("response") is Dictionary: server_admin_result_received.emit(message.response)
			return
		if message.get("kind") == "server_notice":
			if not _server_request.is_empty() and message.get("text") is String:
				server_notice_received.emit(message.text)
			return
		if message.get("kind") == "inheritance_candidates":
			var input = preload("res://scripts/net/identity/identity_inheritance_input.gd").new()
			if message.get("model") is Dictionary and input.accept(message.model):
				_seq = maxi(_seq,int(message.model.request_floor))
				inheritance_candidates_received.emit(message.model.duplicate(true))
			return
		if message.get("kind") == "inheritance_ticket":
			if message.get("member") is int and message.member > 0 and message.get("token") is String and preload("res://scripts/net/identity/player_registry.gd").valid_id(message.token):
				_inheritance_ticket = {"member":message.member,"token":message.token}
				inheritance_ticket_received.emit(message.member)
			return
		if message.get("kind") == "identity":
			if message.get("member") is int and message.member > 1 and message.get("token") is String and message.token.length() == RESUME_TOKEN_BYTES * 2:
				_resume_ticket = {"member":message.member,"token":message.token}
				_resume_inflight = false
				request("identity_ack",{"token":message.token})
				if data_revision > 0 and message.get("data_revision") == data_revision and _assets.is_installed(): request("data_ack",{"revision":data_revision})
				changed.emit()
			return
		if message.get("kind") == "server_attached" and not _server_request.is_empty() and _server_peer_id == 0:
			if message.get("room") is String and message.get("peer_id") is int and message.peer_id > 1:
				server_room_id = message.room
				_server_peer_id = message.peer_id
				changed.emit()
			return
		if message.get("kind") == "server_rooms" and message.get("rooms") is Array:
			if not message.get("server_name", "") is String or not message.get("motd", "") is String: return
			server_info = {"server_name":message.get("server_name", ""),"motd":message.get("motd", "")}
			server_rooms = message.rooms.duplicate(true)
			changed.emit()
			return
		if message.get("kind") == "provider_blob_request":
			if not message.get("key") is String or not message.get("offset") is int or not _queue_blob(sender, message.key, message.offset):
				transport.send(1, {"kind": "provider_blob_error", "key": str(message.get("key", ""))}, 2)
			return
		if message.get("kind") == "room_files_part":
			var complete:Dictionary = _manifest_transfer.accept(message, data_revision, blobs.cache.max_file_bytes, transport.max_packet_bytes)
			if not complete.is_empty():
				_accept_room_files(complete.revision, complete.files)
			elif not _manifest_transfer.error.is_empty():
				error = _manifest_transfer.error
				rejected.emit(error)
			return
		if message.get("kind") == "server_data_catalog":
			if view.get("owner") == peer_id() and view.get("phase") == "lobby":
				if _accept_server_catalog(message): changed.emit()
				else:
					if error.is_empty(): error = "服务端候选目录无效"
					rejected.emit(error)
			return
		if message.get("kind") == "server_data_status":
			var state = message.get("state")
			if view.get("owner") == peer_id() and view.get("phase") == "lobby" and state is Dictionary and state.get("stage") in ["idle", "preparing", "ready", "error", "applied", "cancelled"] and state.get("request_id") is int and state.get("catalog_revision") is int and state.get("text") is String and state.get("report") is Dictionary and state.request_id >= int(server_data.get("status", {}).get("request_id", 0)):
				server_data["status"] = state.duplicate(true)
				changed.emit()
			return
		if message.get("kind") == "room_files":
			if message.get("revision") is int and message.revision > data_revision and message.get("files") is Array:
				if message.revision < _manifest_transfer.pending_revision: return
				if var_to_bytes(message.files).size() > _manifest_transfer.max_manifest_bytes:
					error = "文件清单超过累计传输预算"
					rejected.emit(error)
					return
				var validator = _manifest_transfer.validator
				if validator.validate(message.files, blobs.cache.max_file_bytes):
					_accept_room_files(message.revision, message.files)
				else:
					error = validator.error
					rejected.emit(error)
			return
		if message.get("kind") == "group_preview" and message.get("request_id") is int and message.get("result") is Dictionary:
			group_preview_received.emit(message.request_id, message.result.duplicate(true))
			return
		if message.get("kind") == "match_bind" and message.get("observer") is int and not _match_bound:
			_mirror.reset(message.observer)
			_match_bound = true
			return
		if message.get("kind") == "match_reset":
			_clear_match_views()
			changed.emit()
			return
		if message.get("kind") == "match_view" and message.get("state") is Dictionary:
			if _match_bound and message.get("pending") is Dictionary and message.get("actions") is Dictionary and _mirror.accept(message.state):
				_pending_view = message.pending.duplicate(true)
				_action_view = message.actions.duplicate(true)
				changed.emit()
			return
		if message.get("kind") == "selection" and message.get("state") is Dictionary:
			selection_view = message.state.duplicate(true)
			changed.emit()
			return
		if message.get("kind") == "blob_error" and message.get("key") is String:
			blobs.cancel_blob(sender, message.key)
			error = "请求的文件不可用"
			rejected.emit(error)
			return
		if message.get("kind") == "blob_chunk":
			if message.get("key") is String and message.get("offset") is int and message.get("bytes") is PackedByteArray:
				if not blobs.accept(sender, message.key, message.offset, message.bytes):
					error = blobs.error
					rejected.emit(error)
			return
		if message.get("kind") == "room" and message.get("state") is Dictionary:
			var state: Dictionary = message.state
			if not state.get("revision") is int or not state.get("members") is Array:
				return
			if state.revision > int(view.get("revision", -1)):
				view = state.duplicate(true)
				if view.get("owner") != peer_id() or view.get("phase") != "lobby": server_data.clear()
				elif view.get("dedicated") == true and server_data.is_empty():
					server_data["requested"] = true
					request("server_data_catalog", {})
				changed.emit()
		elif message.get("kind") == "error" and message.get("reason") is String:
			error = message.reason
			if _resume_inflight:
				transport.close()
				_resume_inflight = false
			if message.get("seq") is int and message.seq > 0:
				request_rejected.emit(message.seq, error)
			rejected.emit(error)
			changed.emit()
		return
	if message.get("kind") in ["blob_chunk", "provider_blob_error"]:
		if connection != 1 and not _member_by_peer.has(connection): return
		if not room.members.has(sender) or not room.members[sender].connected:
			return
		if message.get("kind") == "provider_blob_error" and message.get("key") is String:
			blobs.cancel_blob(sender, message.key)
			error = "提供者的文件不可用"
			rejected.emit(error)
		elif message.get("key") is String and message.get("offset") is int and message.get("bytes") is PackedByteArray:
			if not blobs.accept(sender, message.key, message.offset, message.bytes):
				error = blobs.error
				rejected.emit(error)
		return
	if message.get("kind") != "join" and connection != 1 and not _member_by_peer.has(connection):
		transport.send(connection,{"kind":"error","seq":_request_sequence(message),"reason":"连接已无房间操作权限"})
		return
	if message.get("v") != 1 or not message.get("seq") is int or not message.get("args") is Dictionary or not message.get("kind") is String:
		if connection == 1: _fail(sender,"协议字段无效", _request_sequence(message))
		else: transport.send(connection,{"kind":"error","seq":_request_sequence(message),"reason":"协议字段无效"})
		return
	if message.seq <= int(_received_seq.get(connection, 0)):
		if connection == 1: _fail(sender,"重复或过期请求", _request_sequence(message))
		else: transport.send(connection,{"kind":"error","seq":_request_sequence(message),"reason":"重复或过期请求"})
		return
	if message.kind != "join" and (not room.members.has(sender) or not room.members[sender].connected):
		_fail(sender, "连接已无房间操作权限", _request_sequence(message))
		return
	_received_seq[connection] = message.seq
	var args: Dictionary = message.args
	var ok := false
	room.error = ""
	match message.kind:
		"identity_candidates", "identity_inherit":
			var trusted = message.get("gateway_inheritance",{})
			if authority_host_mode in ["lan","p2p"]:
				trusted = lan_context.call(connection,sender,false)
			var state:Dictionary = _inheritance_snapshot()
			var model = preload("res://scripts/net/identity/member_identity_bindings.gd")
			if not dedicated or not trusted is Dictionary or not model.authorized_owner(state,sender,trusted):
				_fail(sender,"只有当前认证房主可以管理身份继承", _request_sequence(message))
				return
			if message.kind == "identity_candidates":
				if not args.is_empty():
					_fail(sender,"候选查询不接受身份参数", _request_sequence(message))
					return
				var eligible:Dictionary = {}
				for id in room.members:
					if id != sender and room.members[id].connected and room.members[id].spectator and not state.bindings.values().has(id): eligible[id] = room.members[id]
				var all_labels:Array = preload("res://scripts/net/identity/player_registry.gd").public_member_labels(room.members,_member_identities,trusted.profiles)
				var labels:Array = []
				for label in all_labels:
					if eligible.has(label.member_id): labels.append(label)
				_send(sender,{"kind":"inheritance_candidates","model":{"revision":room.revision,"request_floor":int(_inheritance_sequences.get(str(sender),0)),"candidates":labels}})
				return
			ok = _inherit_identity(sender,message.seq,args,trusted)
		"room_password":
			if sender != room.owner or room.phase != "lobby" or not args.get("password") is String:
				_fail(sender,"只有房主能在大厅设置房间密码", _request_sequence(message))
				return
			var previous:Dictionary = room_password.verifier.duplicate(true)
			if not room_password.set_password(args.password) or (not recovery_state_path.is_empty() and not _persist_recovery_state()):
				room_password.verifier = previous
				_fail(sender,"房间密码保存失败，原设置未改变", _request_sequence(message))
				return
			room.revision += 1
			ok = true
		"server_data_catalog", "server_data_prepare", "server_data_commit", "server_data_cancel":
			if not dedicated or sender != room.owner or room.phase != "lobby" or data_management_requested.get_connections().is_empty():
				_fail(sender, "无权管理服务端数据或数据已冻结", _request_sequence(message))
				return
			data_management_requested.emit(sender, message.kind, args)
			return
		"identity_ack":
			if args.get("token") is String and args.token.sha256_text() == _resume_hashes.get(sender,"") and _resume_previous.has(sender):
				var previous:String = _resume_previous[sender]
				_resume_previous.erase(sender)
				if not recovery_state_path.is_empty() and not _persist_recovery_state():
					_resume_previous[sender] = previous
					_fail(sender,"恢复凭据确认保存失败，原凭据状态未改变", _request_sequence(message))
			return
		"catalog":
			if room.phase != "lobby" or not args.get("entries") is Array:
				_fail(sender, "只能在大厅上报条目清单", _request_sequence(message))
				return
			if var_to_bytes(message).size() > _catalog_transfer.max_message_bytes:
				_fail(sender, "条目清单超过累计消息预算", _request_sequence(message))
				return
			var catalog = preload("res://scripts/net/content/data_catalog.gd").new()
			var accepted = catalog.accept(args.entries, str(sender))
			if accepted == null:
				_fail(sender, "\n".join(catalog.errors), _request_sequence(message))
				return
			catalogs[sender] = accepted
			catalogs_changed.emit()
			return
		"data_ack":
			# 旧清单的可靠消息可能在恢复发布新修订后到达；不确认新数据，也不污染身份状态。
			if args.get("revision") is int and args.revision >= 0 and args.revision < data_revision: return
			if data_revision > 0 and args.get("revision") is int and args.revision == data_revision:
				_data_confirmed[sender] = data_revision
				room.revision += 1
				ok = true
		"preview_group":
			if room.phase == "playing" and args.get("request_id") is int and args.get("view_seq") is int and args.get("cards") is Array and args.get("hidden") is Array:
				var result: Dictionary = match_authority.preview_group(sender, args.view_seq, args.cards, args.hidden)
				if sender == 1:
					group_preview_received.emit(args.request_id, result)
				else:
					_send(sender, {"kind": "group_preview", "request_id": args.request_id, "result": result}, 1)
			else:
				_fail(sender, "组合预览请求无效", _request_sequence(message))
			return
		"begin_match":
			if sender == room.owner and room.phase == "selecting" and data_ready():
				ok = _begin_selected_match()
				if ok:
					room.phase = "playing"
					room.revision += 1
					_bind_match()
					_publish()
					_publish_match()
				else:
					_fail(sender, match_authority.error if not match_authority.error.is_empty() else "权威对局启动失败", _request_sequence(message))
					return
		"match_command":
			if management_paused:
				_fail(sender,"管理员已暂停对局", _request_sequence(message))
				return
			if not _disconnected_players().is_empty():
				_fail(sender, "有玩家掉线，对局已暂停", _request_sequence(message))
				return
			if room.phase == "playing" and args.get("view_seq") is int and args.get("command") is String and args.get("params") is Dictionary:
				ok = match_authority.submit(sender, args.view_seq, args.command, args.params)
				# 引擎拒绝也可能清除等待或续行；失败后同样发布实际状态。
				_publish_match()
				if not ok:
					_fail(sender, match_authority.error if not match_authority.error.is_empty() else "引擎拒绝该对局操作", _request_sequence(message))
					return
		"guard_continue", "guard_skip", "guard_restart", "guard_lobby":
			if management_paused:
				_fail(sender,"管理员已暂停对局", _request_sequence(message))
				return
			if sender != room.owner or room.phase != "playing" or args.size() != 1 or not args.get("view_seq") is int:
				_fail(sender, "只有房主可以继续暂停的规则执行", _request_sequence(message))
				return
			if not match_authority.continue_runtime_guard(sender, args.view_seq, message.kind):
				_fail(sender, match_authority.error, _request_sequence(message))
				return
			if message.kind == "guard_lobby":
				room.return_to_lobby(sender)
				selection = preload("res://scripts/net/authority/selection_authority.gd").new()
				_masters = GameStart.get_masters_can_use()
				_servants = GameStart.get_servants_can_use()
				_clear_match_views()
				for id in _peers:
					if room.members.has(id): _send(id, {"kind":"match_reset"}, 1)
				_publish()
			else:
				_publish_match()
			return
		"blob_request":
			if args.get("key") is String and args.get("offset") is int:
				ok = _queue_blob(sender, args.key, args.offset)
				if not ok:
					_send(sender, {"kind": "blob_error", "key": args.key})
			return
		"join":
			if args.get("name") is String and args.get("spectator") is bool:
				ok = _join_identity(connection,args)
				if not ok:
					transport.send(connection,{"kind":"error","seq":_request_sequence(message),"reason":room.error})
					return
				sender = int(_member_by_peer.get(connection,connection))
				if ok and dedicated and room.owner == 0 and not args.spectator:
					room.owner = sender
					room.revision += 1
				if ok and data_revision > 0:
					_send_room_files(sender)
				if ok and room.phase == "playing":
					_send(sender, {"kind": "match_bind", "observer": match_authority.observer_for(sender)}, 1)
					_publish_match()
				elif ok and room.phase == "selecting":
					_publish_selection()
		"ready":
			if args.get("ready") is bool:
				ok = room.set_ready(sender, args.ready)
		"settings":
			if args.get("changes") is Dictionary:
				ok = _set_room_settings(sender, args.changes)
		"start":
			if sender == room.owner and room.can_start() and data_ready() and _prepare_selection():
				ok = room.start(sender)
				if ok:
					_publish_selection()
		"choose_master":
			if room.phase == "selecting" and args.get("seat") is int and args.get("name") is String:
				ok = selection.choose(sender, args.seat, args.name)
				if ok:
					_publish_selection()
		"transfer":
			if args.get("target") is int:
				ok = room.transfer_owner(sender, args.target)
				if ok and room.phase == "playing":
					_publish_match()
		"kick":
			if args.get("target") is int:
				ok = room.kick(sender, args.target)
				if ok:
					_resume_hashes.erase(args.target)
					_resume_previous.erase(args.target)
					_member_identities.erase(args.target)
					transport.disconnect_peer(int(_peer_by_member.get(args.target,args.target)))
	if not ok:
		_fail(sender, room.error if not room.error.is_empty() else "请求无效", _request_sequence(message))
		return
	_publish()

func _publish(persist_recovery:bool = true) -> void:
	if _restore_failed_closed or _restore_in_progress or _begin_in_progress: return
	var state: Dictionary = room.snapshot()
	state.password_required = not room_password.verifier.is_empty()
	state.can_start = room.can_start() and data_ready()
	state.data_ready = data_ready()
	state.data_revision = data_revision
	state.dedicated = dedicated
	state.authority_host_mode = authority_host_mode
	# 协议字典键只允许字符串，成员列表用显式 id 字段而不是整数键。
	var members: Array = []
	for id in state.members:
		var member: Dictionary = state.members[id].duplicate(true)
		member.id = id
		members.append(member)
	state.members = members
	view = state.duplicate(true)
	if persist_recovery: _persist_recovery_state()

	for id in _peers:
		if room.members.has(id):
			_send(id, {"kind": "room", "state": state})
	changed.emit()

## 文件列表必须由调用方显式选择，且字节已经由主机批准发布。
func submit_catalog(entries: Array) -> bool:
	if not transport.is_connected_to_host():
		return false
	var catalog = preload("res://scripts/net/content/data_catalog.gd").new()
	var accepted = catalog.accept(entries, str(peer_id()))
	if accepted == null:
		error = "\n".join(catalog.errors)
		return false
	if var_to_bytes({"v": 1, "seq": _seq + 1, "kind": "catalog", "args": {"entries": accepted}}).size() > _catalog_transfer.max_message_bytes:
		error = "条目清单超过累计消息预算"
		return false
	return request("catalog", {"entries": accepted}) == OK

func _accept_server_catalog(message:Dictionary) -> bool:
	error = ""
	if var_to_bytes(message).size() > _catalog_transfer.max_message_bytes:
		error = "候选目录超过累计消息预算"
		return false
	if not message.get("catalog_revision") is int or message.catalog_revision <= 0 or not message.get("entries") is Array or not message.get("selected") is Array:
		return false
	var grouped:Dictionary = {}
	for entry in message.entries:
		if not entry is Dictionary or not entry.get("provider") is String: return false
		var provider:String = entry.provider
		if provider != "server" and not view.get("members", []).any(func(member): return member is Dictionary and str(member.get("id")) == provider and member.get("connected") == true): return false
		if not grouped.has(provider): grouped[provider] = []
		grouped[provider].append(entry)
	var entries:Array = []
	var catalog = preload("res://scripts/net/content/data_catalog.gd").new()
	for provider in grouped:
		var accepted = catalog.accept(grouped[provider], provider)
		if accepted == null:
			error = "\n".join(catalog.errors)
			return false
		entries.append_array(accepted)
	var identities:Dictionary = {}
	for reference in message.selected:
		if not reference is Dictionary or reference.size() != 2 or not reference.get("provider") is String or not reference.get("key") is String: return false
		var identity:String = reference.provider + ":" + reference.key
		if identities.has(identity): return false
		identities[identity] = true
	if not message.get("modes") is Array: return false
	for mode in message.modes:
		if not mode is Dictionary or not mode.get("id") is String or not mode.get("name") is String: return false
	server_data["catalog_revision"] = message.catalog_revision
	server_data["modes"] = message.modes.duplicate(true)
	server_data["entries"] = entries
	server_data["selected"] = message.selected.duplicate(true)
	return true

## 主动分享时读取本机路径；远端仅能请求这份显式登记的哈希字节。
func share_catalog(directory: String, entries: Array) -> bool:
	var catalog = preload("res://scripts/net/content/data_catalog.gd").new()
	var accepted = catalog.accept(entries, str(peer_id()))
	if accepted == null:
		error = "\n".join(catalog.errors)
		return false
	var shared: Dictionary = {}
	for entry in accepted:
		for file in entry.files:
			var bytes := FileAccess.get_file_as_bytes(directory.path_join(file.path))
			if bytes.size() != file.size or blobs.cache.digest(bytes) != file.hash:
				error = "本机共享文件已经变化：" + file.path
				return false
			shared[file.hash] = bytes
	if not submit_catalog(accepted):
		return false
	_published_blobs = shared
	_blob_sends.clear()
	return true

func download_provider_blob(provider: int, key: String, size: int) -> bool:
	if not _host or room.phase != "lobby" or not room.members.has(provider) or not room.members[provider].connected or not catalogs.has(provider):
		return false
	var advertised := false
	for entry in catalogs[provider]:
		for file in entry.files:
			advertised = advertised or (file.hash == key and file.size == size)
	if not advertised:
		return false
	var existing: PackedByteArray = blobs.cache.fetch(key)
	if existing.size() == size and not existing.is_empty():
		return true
	if not blobs.expect_blob(provider, key, size):
		return false
	if _send(provider, {"kind": "provider_blob_request", "key": key, "offset": blobs.offset_for(provider, key)}, 2) != OK:
		blobs.cancel_blob(provider, key)
		return false
	return true

func set_room_files(files: Array) -> bool:
	if not _host or room.phase not in ["lobby", "restoring"]:
		return false
	if not _can_publish_room_files(files): return false
	_commit_room_files(files, preload("res://scripts/net/content/room_assets.gd").new())
	return true

func _can_publish_room_files(files:Array) -> bool:
	var validator = preload("res://scripts/net/content/room_data_assembler.gd").new()
	if not validator.validate(files, blobs.cache.max_file_bytes):
		error = validator.error
		return false
	for item in files:
		if not _published_blobs.has(item.hash) or _published_blobs[item.hash].size() != item.size:
			error = "批准清单包含尚未发布的内容"
			return false
	var manifest: Array = []
	for item in files:
		manifest.append({"path": item.path, "hash": item.hash, "size": item.size})
	if _manifest_transfer.encode(manifest, data_revision + 1, transport.max_packet_bytes, blobs.cache.max_file_bytes).is_empty():
		error = _manifest_transfer.error
		return false
	return true

func _commit_room_files(files:Array, assets, announce:bool = true) -> void:
	room_files = []
	for item in files:
		room_files.append({"path":item.path, "hash":item.hash, "size":item.size})
	_assets = assets
	data_revision += 1
	_data_confirmed.clear()
	_data_confirmed[1] = data_revision
	for member in room.members.values():
		member.ready = false
	room.revision += 1
	if not announce: return
	for id in _peers:
		if room.members.has(id) and room.members[id].connected:
			_send_room_files(id)
	_publish()

## 从存档头和当前显式控制绑定构造屏障；无效与合法全 AI 的空集合分开。
func _recovery_members() -> Dictionary:
	if room.phase != "restoring" or not match_authority.started or match_authority.recorder == null:
		return {"ok":false, "required":[], "error":"恢复存档尚未就绪"}
	return preload("res://scripts/net/session/recovery_seat_bindings.gd").validate(match_authority.recorder.initial, match_authority.controllers, room.members)

func _recovery_barrier_ready() -> bool:
	var validation:Dictionary = _recovery_members()
	if not validation.ok:
		error = validation.error
		return false
	return preload("res://scripts/net/session/recovery_seat_bindings.gd").ready(validation, room.members, _data_confirmed, data_revision)

func data_ready() -> bool:
	if require_room_data and (data_revision == 0 or _rules_revision != data_revision):
		return false
	if room.phase == "restoring":
		return _recovery_barrier_ready()
	if data_revision == 0:
		return true
	for id in room.members:
		if room.members[id].connected and _data_confirmed.get(id, 0) != data_revision:
			return false
	return true

func _send_room_files(id: int) -> void:
	var messages:Array = _manifest_transfer.encode(room_files, data_revision, transport.max_packet_bytes, blobs.cache.max_file_bytes)
	if messages.is_empty():
		error = _manifest_transfer.error
		rejected.emit(error)
		return
	for message in messages:
		var result:Error = _send(id, message, 2)
		if result != OK:
			error = "房间文件清单发送失败：" + error_string(result)
			rejected.emit(error)
			return

func _accept_room_files(revision:int, files:Array) -> void:
	_manifest_transfer.reset()
	room_files = files.duplicate(true)
	data_revision = revision
	_assets.clear()
	changed.emit()

func _request_sequence(message: Dictionary) -> int:
	var sequence = message.get("seq")
	return sequence if sequence is int and sequence > 0 else 0

func _fail(sender: int, reason: String, sequence: int = 0) -> void:
	if sender == 1:
		error = reason
		if sequence > 0: request_rejected.emit(sequence, reason)
		rejected.emit(reason)
	else:
		var receipt := {"kind": "error", "reason": reason}
		if sequence > 0: receipt["seq"] = sequence
		_send(sender, receipt)

## 仅发布主机已选中的内容，不将客户端文件路径暴露成远程读取接口。
func publish_blob(bytes: PackedByteArray) -> String:
	if not _host or bytes.is_empty() or bytes.size() > blobs.cache.max_file_bytes:
		return ""
	var key: String = blobs.cache.digest(bytes)
	_published_blobs[key] = bytes.duplicate()
	return key

func download_blob(key: String, size: int) -> bool:
	if _host or view.is_empty() or not transport.is_connected_to_host():
		return false
	var existing: PackedByteArray = blobs.cache.fetch(key)
	if existing.size() == size and not existing.is_empty():
		return true
	if not blobs.expect_blob(1, key, size):
		return false
	if request("blob_request", {"key": key, "offset": blobs.offset_for(1, key)}) != OK:
		blobs.cancel_blob(1, key)
		return false
	return true

func _queue_blob(sender: int, key: String, offset: int) -> bool:
	# 候选发布不代表批准；提供者仍可向权威上传未批准内容。
	var authorized: bool
	if _host:
		authorized = room.members.has(sender) and room.members[sender].connected and _approved_blob_key(key)
	else:
		authorized = sender == 1 and transport.is_connected_to_host()
	if not authorized or not _published_blobs.has(key):
		return false
	if offset < 0 or offset >= _published_blobs[key].size() or _blob_sends.size() >= max_blob_requests:
		return false
	for job in _blob_sends:
		if job.peer == sender and job.key == key:
			return false
	_blob_sends.append({"peer": sender, "key": key, "offset": offset, "data_revision":data_revision})
	return true

func _approved_blob_key(key: String) -> bool:
	if key.is_empty(): return false
	for item in room_files:
		if item is Dictionary and item.get("hash") is String and item.hash == key:
			return true
	return false

func _pump_blobs() -> void:
	for _index in range(blob_chunks_per_poll):
		if _blob_sends.is_empty():
			return
		var job: Dictionary = _blob_sends.pop_front()
		if _host:
			if not room.members.has(job.peer) or not room.members[job.peer].connected:
				continue
			if job.get("data_revision", -1) != data_revision:
				if not _approved_blob_key(job.key):
					_send(job.peer, {"kind":"blob_error", "key":job.key}, 2)
					continue
				job.data_revision = data_revision
		elif job.peer != 1 or not transport.is_connected_to_host():
			continue
		if not _published_blobs.has(job.key):
			_send(job.peer, {"kind":"blob_error", "key":job.key}, 2)
			continue
		var bytes: PackedByteArray = _published_blobs[job.key]
		var end: int = mini(job.offset + blobs.max_chunk_bytes, bytes.size())
		var result: Error = _send(job.peer, {"kind": "blob_chunk", "key": job.key, "offset": job.offset, "bytes": bytes.slice(job.offset, end)}, 2)
		if result == OK and end < bytes.size():
			job.offset = end
			_blob_sends.append(job)

## 配置只来自本地可信代码，不从网络接收 script 路径。
func adopt_room_data(task, config: Dictionary) -> bool:
	if task.approved_files != room_files:
		error = "校验结果与当前房间批准清单不一致"
		return false
	var candidate:Dictionary = _prepare_rule_data(task, config)
	if candidate.is_empty(): return false
	_commit_rule_data(candidate)
	_rules_revision = data_revision
	_publish()
	return true

## 所有可拒绝步骤完成后才同步提交规则与清单，不提前发布半成功版本。
func apply_room_data(task, config:Dictionary) -> bool:
	if not _host or room.phase != "lobby" or not task.complete:
		error = "当前房间无法采用此次校验结果"
		return false
	if not _can_publish_room_files(task.approved_files): return false
	var candidate:Dictionary = _prepare_rule_data(task, config)
	if candidate.is_empty(): return false
	_commit_rule_data(candidate)
	_rules_revision = data_revision + 1
	_commit_room_files(task.approved_files, candidate.assets)
	return true

func _prepare_rule_data(task, config:Dictionary) -> Dictionary:
	error = ""
	if not _host or room.phase != "lobby" or not task.complete:
		error = "校验结果或本机选人配置无效"
		return {}
	var rules = _selection_rules(config)
	if rules == null: return {}
	var directory: String = task.directory.path_join("validation-data")
	var validator = preload("res://scripts/net/validation/room_data_validator.gd").new()
	if not validator.validate(directory, task.approved_files):
		error = "\n".join(validator.errors)
		return {}
	var assets = preload("res://scripts/net/content/room_assets.gd").new()
	if not assets.install(task.approved_files, directory, blobs.cache.max_file_bytes):
		error = assets.error
		return {}
	var previous_root:String = LoadHelper.session_data_dir
	var previous_cache:String = LoadGame.stored_jsons_path
	LoadHelper.session_data_dir = directory
	LoadGame.stored_jsons_path = task.directory.path_join("stored_jsons.dat")
	GameStart.end_session()
	var masters: Array = GameStart.get_masters_can_use()
	var servants: Array = GameStart.get_servants_can_use()
	var candidate_room = _copy_room()
	if not candidate_room.configure_rules({"capacity": rules.capacity(masters, servants, config)}):
		error = candidate_room.error
		LoadHelper.session_data_dir = previous_root
		LoadGame.stored_jsons_path = previous_cache
		GameStart.end_session()
		_masters = GameStart.get_masters_can_use()
		_servants = GameStart.get_servants_can_use()
		return {}
	return {"room":candidate_room, "assets":assets, "masters":masters, "servants":servants, "config":config.duplicate(true), "previous_root":previous_root, "previous_cache":previous_cache}

func _commit_rule_data(candidate:Dictionary) -> void:
	if not _room_rules_active:
		_previous_data_root = candidate.previous_root
		_previous_cache_path = candidate.previous_cache
		_room_rules_active = true
	room.settings = candidate.room.settings
	room.members = candidate.room.members
	room.revision = candidate.room.revision
	_selection_config = candidate.config
	_masters = candidate.masters
	_servants = candidate.servants
	_assets = candidate.assets
	require_room_data = true

func _restore_room_rules() -> void:
	if not _room_rules_active:
		return
	LoadHelper.session_data_dir = _previous_data_root
	LoadGame.stored_jsons_path = _previous_cache_path
	GameStart.end_session()
	_room_rules_active = false
	_rules_revision = 0

func configure_selection(config: Dictionary, masters: Array, servants: Array) -> bool:
	if not _host or room.phase != "lobby" or not config.get("script") is String:
		return false
	_selection_config = config.duplicate(true)
	_masters = masters.duplicate()
	_servants = servants.duplicate()
	return true

func _copy_room():
	var candidate = Room.new()
	candidate.owner = room.owner
	candidate.phase = room.phase
	candidate.settings = room.settings.duplicate(true)
	candidate.members = room.members.duplicate(true)
	candidate.revision = room.revision
	return candidate

func _selection_rules(config:Dictionary):
	if not config.get("script") is String or not ResourceLoader.exists(config.script):
		error = "本机选人规则未声明"
		return null
	var script = load(config.script)
	if not script is Script or not script.can_instantiate():
		error = "本机选人规则无法实例化"
		return null
	var rules = script.new()
	if not rules.has_method("capacity"):
		error = "本机选人规则未声明容量入口"
		return null
	return rules

func _set_room_settings(actor:int, changes:Dictionary) -> bool:
	if not changes.has("selection_mode") or changes.selection_mode == room.settings.selection_mode or _selection_config.is_empty():
		return room.set_settings(actor, changes)
	var candidate = _copy_room()
	if not candidate.set_settings(actor, changes):
		room.error = candidate.error
		return false
	var configs:Array = selection_modes.filter(func(config): return config is Dictionary and config.get("id") == changes.selection_mode)
	if configs.size() != 1:
		room.error = "选人模式未声明或声明重复"
		return false
	var rules = _selection_rules(configs[0])
	if rules == null:
		room.error = error
		return false
	if not candidate.configure_rules({"capacity":rules.capacity(_masters, _servants, configs[0])}):
		room.error = candidate.error
		return false
	if not configure_selection(configs[0], _masters, _servants): return false
	room.settings = candidate.settings
	room.members = candidate.members
	room.revision = candidate.revision
	return true

func _prepare_selection() -> bool:
	if _selection_config.is_empty():
		room.error = "主机尚未注册选人规则"
		return false
	var script = load(_selection_config.script)
	if not script is Script or not script.can_instantiate():
		return false
	var seats:Dictionary = _room_seats()
	if not selection.setup(script.new(), seats, _masters, _servants, _selection_config):
		room.error = selection.error
		return false
	return true

func _room_seats() -> Dictionary:
	var seats:Dictionary = {}
	for id in room.members:
		if not room.members[id].spectator: seats[seats.size()] = id
	for _index in range(int(room.settings.ai_count)): seats[seats.size()] = 0
	return seats

func new_archive_folder() -> String:
	return archive_root.path_join(Time.get_datetime_string_from_system().replace(":", "-") + "_" + Crypto.new().generate_random_bytes(12).hex_encode())

func load_recovery_state(path:String) -> bool:
	if not FileAccess.file_exists(path): return false
	var state = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not state is Dictionary or not state.get("room") is Dictionary: return false
	# 旧格式没有批准快照；不能猜 data_revision、room_files 或 provider 的含义。
	var schema:Dictionary = preload("res://scripts/net/session/recovery_seat_json.gd").integer(state.get("recovery_schema_version"), RECOVERY_SCHEMA_VERSION)
	if not schema.ok or schema.value != RECOVERY_SCHEMA_VERSION:
		error = "恢复文件格式不兼容，拒绝猜测旧字段"
		return false
	var approved:Dictionary = decode_approved_data_snapshot(state.get("approved_data_snapshot"))
	if not approved.ok:
		error = "恢复文件缺少有效的已批准数据清单快照"
		return false
	if not state.get("management_paused",false) is bool: return false
	if not preload("res://scripts/net/identity/room_password.gd").valid_state(state.get("room_password",{})): return false
	var saved:Dictionary = state.room
	var decoded_revision:Dictionary = preload("res://scripts/net/session/recovery_seat_json.gd").integer(state.get("data_revision"), 2147483646)
	if not decoded_revision.ok or approved.snapshot.revision != decoded_revision.value:
		error = "批准清单快照版本与数据版本不一致"
		return false
	var saved_data_revision:int = decoded_revision.value
	if saved.get("phase") in ["playing", "restoring"] and approved.snapshot.files.is_empty():
		error = "活动恢复缺少已采用数据"
		return false
	for key in ["owner", "revision"]:
		var number = saved.get(key)
		if not (number is int or number is float) or not is_finite(float(number)) or number < 0 or number > 2147483647 or floor(float(number)) != number: return false
	if not saved.get("settings") is Dictionary: return false
	var decoded_settings:Dictionary = Room.decode_json_settings(saved.settings)
	if not decoded_settings.ok:
		error = decoded_settings.error
		return false
	saved.settings = decoded_settings.settings
	if not saved.get("members") is Dictionary or saved.get("phase") not in ["lobby", "selecting", "playing", "restoring"]: return false
	for raw_id in saved.members:
		if not str(raw_id).is_valid_int() or int(raw_id) <= 0 or int(raw_id) > 2147483647: return false
		var member = saved.members[raw_id]
		if not member is Dictionary or not member.get("name") is String or not member.get("spectator") is bool: return false
	if int(saved.owner) > 0 and not saved.members.has(str(int(saved.owner))): return false
	var decoded_seats:Dictionary = preload("res://scripts/net/session/recovery_seat_json.gd").decode(state)
	if not decoded_seats.ok:
		error = decoded_seats.error
		return false
	for field in ["resume_hashes", "resume_previous"]:
		if not state.get(field) is Dictionary: return false
		for raw_id in state[field]:
			if not str(raw_id).is_valid_int(): return false
			var value = state[field][raw_id]
			if not value is String: return false
	if not preload("res://scripts/net/identity/member_identity_bindings.gd").valid_state(state,_identity_binding_required):
		error = "恢复文件缺少或包含无效成员密钥绑定，拒绝覆盖既有状态"
		return false
	recovery_state_path = path
	_identity_binding_required = state.get("identity_binding_required",false)
	_inheritance_sequences = state.get("inheritance_sequences",{}).duplicate()
	_inheritance_audit = state.get("inheritance_audit",[]).duplicate(true)
	_member_identities.clear()
	for raw_id in state.get("member_identities",{}):
		_member_identities[int(raw_id)] = state.member_identities[raw_id]
	management_paused = state.get("management_paused",false)
	room_password.verifier = state.get("room_password",{}).duplicate(true)
	data_revision = int(saved_data_revision)
	if saved.get("settings") is Dictionary: room.settings = saved.settings.duplicate(true)
	room.owner = int(saved.owner)
	room.revision = int(saved.revision)
	if saved.get("members") is Dictionary:
		room.members.clear()
		for raw_id in saved.members:
			if str(raw_id).is_valid_int() and saved.members[raw_id] is Dictionary:
				var member:Dictionary = saved.members[raw_id].duplicate(true)
				member.connected = false
				member.ready = false
				room.members[int(raw_id)] = member
		if saved.get("phase") == "playing": room.phase = "restoring"
		elif saved.get("phase") is String: room.phase = saved.phase
	_resume_hashes.clear()
	for raw_id in state.get("resume_hashes", {}):
		if str(raw_id).is_valid_int() and state.resume_hashes[raw_id] is String: _resume_hashes[int(raw_id)] = state.resume_hashes[raw_id]
	_resume_previous.clear()
	for raw_id in state.get("resume_previous", {}):
		if str(raw_id).is_valid_int() and state.resume_previous[raw_id] is String: _resume_previous[int(raw_id)] = state.resume_previous[raw_id]
	_recovery_bindings = decoded_seats.bindings.duplicate()
	_recovery_seat_kinds = decoded_seats.seat_kinds.duplicate()
	room_files = approved.snapshot.files.duplicate(true)

	return true

func decode_approved_data_snapshot(value:Variant) -> Dictionary:
	var numbers = preload("res://scripts/net/session/recovery_seat_json.gd")
	if not value is Dictionary or value.size() != 3: return {"ok":false}
	var version:Dictionary = numbers.integer(value.get("version"), APPROVED_DATA_SNAPSHOT_VERSION)
	var revision:Dictionary = numbers.integer(value.get("revision"), 2147483646)
	if not version.ok or version.value != APPROVED_DATA_SNAPSHOT_VERSION or not revision.ok or not value.get("files") is Array: return {"ok":false}
	var files:Array = []
	for item in value.files:
		if not item is Dictionary or item.size() != 3 or not item.get("path") is String or not item.get("hash") is String: return {"ok":false}
		var size:Dictionary = numbers.integer(item.get("size"), blobs.cache.max_file_bytes)
		if not size.ok: return {"ok":false}
		files.append({"path":item.path, "hash":item.hash, "size":size.value})
	# 未批准的初始大厅明确 revision=0、files=[]；不能让该表示恢复活动对局。
	if files.is_empty():
		if revision.value != 0: return {"ok":false}
	elif revision.value <= 0 or not preload("res://scripts/net/content/room_data_assembler.gd").new().validate(files, blobs.cache.max_file_bytes): return {"ok":false}
	return {"ok":true, "snapshot":{"version":version.value, "revision":revision.value, "files":files}}

func _persist_recovery_state() -> bool:
	if recovery_state_path.is_empty() or not _host: return false
	var temporary:String = recovery_state_path + ".%d.tmp" % OS.get_process_id()
	var paths = preload("res://scripts/net/server/recovery_path_safety.gd")
	var directory:String = recovery_state_path.get_base_dir()
	if not paths.checked(directory, recovery_state_path, true) or not paths.checked(directory, temporary, true): return false
	var snapshot:Dictionary = room.snapshot()
	if snapshot.settings.has("runtime_guard"):
		snapshot.settings.runtime_guard = preload("res://scripts/match/rule_budget.gd").encode_json_config(snapshot.settings.runtime_guard)
	var bindings:Dictionary = _recovery_bindings.duplicate()
	var seat_kinds:Dictionary = _recovery_seat_kinds.duplicate()
	if match_authority.started:
		bindings = match_authority.controllers.duplicate()
		if match_authority.recorder == null or not match_authority.recorder.initial.get("seat_kinds") is Dictionary: return false
		seat_kinds = match_authority.recorder.initial.seat_kinds.duplicate()
	# 只保存存档显式类型；用同一 JSON 解码契约校验，失败不打开或覆盖恢复文件。
	var seat_state:Dictionary = JSON.parse_string(JSON.stringify({"room":snapshot, "bindings":bindings, "seat_kinds":seat_kinds}))
	var decoded_seats:Dictionary = preload("res://scripts/net/session/recovery_seat_json.gd").decode(seat_state)
	if not decoded_seats.ok:
		error = decoded_seats.error
		return false
	var approved:Dictionary = decode_approved_data_snapshot({"version":APPROVED_DATA_SNAPSHOT_VERSION, "revision":data_revision, "files":room_files.duplicate(true)})
	if not approved.ok or (snapshot.phase in ["playing", "restoring"] and approved.snapshot.files.is_empty()):
		error = "恢复状态缺少有效已采用数据快照"
		return false
	if authority_host_mode in ["lan","p2p"] and match_authority.started and match_authority.recorder != null:
		var recorder = match_authority.recorder
		if recorder == null or recorder.journal._file == null: return false
		var archive:String = recorder.journal._file.get_path_absolute().get_base_dir()
		var identity_path:String = archive.path_join("restore-identity.json")
		if not paths.checked(archive_root,identity_path,true) or not paths.checked(archive_root,identity_path+".tmp",true): return false
		if not FileAccess.file_exists(identity_path):
			var identity_state:Dictionary = {"room":snapshot,"bindings":bindings,"seat_kinds":seat_kinds,"identity_binding_required":true,"member_identities":_member_identities.duplicate(),"resume_hashes":_resume_hashes.duplicate(),"resume_previous":_resume_previous.duplicate(),"inheritance_sequences":_inheritance_sequences.duplicate(),"inheritance_audit":_inheritance_audit.duplicate(true),"approved_data_snapshot":approved.snapshot}
			if preload("res://scripts/net/server/server_console_channel.gd").write_json(identity_path,identity_state) != OK: return false
	var file:=FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return false
	var encoded:PackedByteArray = JSON.stringify({"recovery_schema_version":RECOVERY_SCHEMA_VERSION, "approved_data_snapshot":approved.snapshot, "room":snapshot, "room_password":room_password.verifier.duplicate(true), "management_paused":management_paused, "data_revision":data_revision, "resume_hashes":_resume_hashes.duplicate(), "resume_previous":_resume_previous.duplicate(), "bindings":bindings, "seat_kinds":seat_kinds, "identity_binding_required":_identity_binding_required, "member_identities":_member_identities.duplicate(), "inheritance_sequences":_inheritance_sequences.duplicate(), "inheritance_audit":_inheritance_audit.duplicate(true)}).to_utf8_buffer()
	file.store_buffer(encoded)
	file.flush()
	var result:Error = file.get_error()
	file.close()
	var committed:bool = false
	if result == OK and paths.checked(directory, temporary) and paths.checked(directory, recovery_state_path, true) and preload("res://scripts/io/validated_file_content.gd").matches_bytes(temporary, encoded):
		if FileAccess.file_exists(recovery_state_path):
			committed = preload("res://scripts/io/atomic_file_replace.gd").replace_validated_file(temporary, recovery_state_path, encoded.size()).get("ok", false) == true
		elif not DirAccess.dir_exists_absolute(recovery_state_path) and DirAccess.rename_absolute(temporary, recovery_state_path) == OK:
			committed = true
	if committed:
		_recovery_bindings = decoded_seats.bindings.duplicate()
		_recovery_seat_kinds = decoded_seats.seat_kinds.duplicate()
		return true
	if paths.checked(directory, temporary): DirAccess.remove_absolute(temporary)
	return false

## 崩溃自动恢复的许可来自当前 worker 身份 IPC 活连接账本，不来自旧 connected 标志。
func authenticated_crash_recovery_ready() -> bool:
	if not dedicated or not _host or room.phase != "restoring" or match_authority.started or _restore_failed_closed or _restore_in_progress or _begin_in_progress: return false
	if authority_host_mode not in ["lan","p2p"] or not _identity_binding_required or not lan_context.is_valid() or recovery_state_path.is_empty(): return false
	var required:Dictionary = {room.owner:true}
	for member in _recovery_bindings.values():
		if int(member) > 0: required[int(member)] = true
	for member in required:
		if member <= 1 or not room.members.has(member) or not room.members[member].connected or not _peer_by_member.has(member): return false
		var trusted:Dictionary = lan_context.call(int(_peer_by_member[member]),member,false)
		var key:String = str(_member_identities.get(member,""))
		if key.is_empty() or trusted.get("authenticated") != true or trusted.get("actor_key") != key or not trusted.get("profiles",{}).has(key): return false
	return true

## 原生主管重启后的自动恢复与手选恢复分开授权，复用同一失败原子事务。
func restore_crashed_match(source:String) -> bool:
	if authority_host_mode in ["lan","p2p"]:
		if not authenticated_crash_recovery_ready():
			error = "崩溃恢复须等待当前实例认证房主及全部原真人"
			return false
		_lan_restore_authorized = true # 只有当前活世代检查通过才授予一次性许可。
	return await restore_local_match(source)

## 仅供本机房主界面调用；不注册远端路径消息，不在重放中运行房间 AI。
func restore_local_match(source:String) -> bool:
	if authority_host_mode in ["lan","p2p"] and not _lan_restore_authorized:
		error = "LAN/P2P 恢复必须经过本机实例绑定 IPC 授权"
		return false
	_lan_restore_authorized = false
	if _restore_failed_closed or _restore_in_progress or _begin_in_progress:
		return false
	error = ""
	# 共享UI进程无法撤销全局RNG/原生await栈；只允许可退出的独立权威工作进程。
	if not dedicated:
		error = "共享进程不能原子恢复存档；请使用独立权威工作进程"
		return false
	if not _host or room.phase not in ["lobby", "restoring"] or match_authority.started:
		error = "只有独立权威工作进程能在大厅恢复存档"
		return false
	var journal_script = preload("res://scripts/match/match_journal.gd")
	if GameStart._started or journal_script.audit_writer != null or journal_script.audit_replaying:
		error = "当前全局规则或录制器仍活跃，不能原子恢复；须先结束原局"
		return false
	var bindings:Dictionary = _recovery_bindings.duplicate()
	var parsed:Dictionary = journal_script.new().read_all(source.path_join("match.log"))
	if not parsed.ok or parsed.records.is_empty():
		error = str(parsed.error) if not parsed.ok else "恢复存档没有初始记录"
		return false
	var validation:Dictionary = preload("res://scripts/net/session/recovery_seat_bindings.gd").validate(parsed.records[0], bindings, room.members)
	if not validation.ok:
		error = validation.error
		return false
	if not validation.required.is_empty() and room.owner <= 0:
		error = "原真人恢复须等待已重连房主"
		return false
	for member in validation.required:
		if not room.members[member].get("connected", false):
			error = "等待全部原真人重连后恢复"
			return false
	if recovery_state_path.is_empty():
		error = "独立恢复必须配置持久化回执路径"
		return false
	var approved:Dictionary = decode_approved_data_snapshot({"version":APPROVED_DATA_SNAPSHOT_VERSION, "revision":data_revision, "files":room_files.duplicate(true)})
	if not approved.ok or approved.snapshot.files.is_empty():
		error = "恢复必须提供已采用数据快照，不能从存档重建批准清单"
		return false
	var approved_files:Array = approved.snapshot.files.duplicate(true)
	var approved_manifest:Dictionary = {}
	for item in approved_files:
		# MatchReplay 的正式存档枚举显式排除 tag_list.json。
		if item.path.get_file() != "tag_list.json": approved_manifest[item.path] = item.hash
	if parsed.records[0].get("data") != approved_manifest:
		error = "恢复存档与已采用数据快照不一致"
		return false
	var fixed_root:String = LoadHelper.get_data_dir()
	if not preload("res://scripts/net/validation/room_data_validator.gd").new().validate(fixed_root, approved_files):
		error = "已采用固定数据副本校验失败"
		return false
	var previous_root:String = LoadHelper.session_data_dir
	var previous_cache:String = LoadGame.stored_jsons_path
	var original_room = room
	var original_snapshot:Dictionary = room.snapshot().duplicate(true)
	var target:String = new_archive_folder()
	var marker:String = target + ".restore-pending"
	if FileAccess.file_exists(marker) or DirAccess.dir_exists_absolute(marker) or FileAccess.file_exists(target) or DirAccess.dir_exists_absolute(target):
		error = "恢复目标或未提交哨兵已存在，不覆盖"
		return false
	# 同级哨兵先于任何重放副作用；未提交副本不能被重启扫描选为源。
	if DirAccess.make_dir_recursive_absolute(archive_root) != OK:
		error = "无法建立恢复隔离目录"
		return false
	var pending := FileAccess.open(marker, FileAccess.WRITE)
	if pending == null:
		error = "无法建立恢复未提交哨兵"
		return false
	pending.store_string("pending")
	pending.flush()
	var marker_error:Error = pending.get_error()
	pending.close()
	if marker_error != OK:
		error = "恢复未提交哨兵写入失败"
		return false
	_restore_cancelled = false
	_restore_in_progress = true
	var maintenance:Callable = _restore_checkpoint.bind(original_room, original_snapshot)
	_restore_stage("archive_begin")
	var candidate = preload("res://scripts/net/authority/match_authority.gd").new()
	var recovered:bool = await candidate.restore_archive(source, bindings, target, maintenance)
	_restore_stage("archive_return")
	if not maintenance.call():
		return _fail_closed_restore(candidate, previous_root, previous_cache, "恢复期间房间已变化，原子恢复不可用")
	if not recovered:
		return _fail_closed_restore(candidate, previous_root, previous_cache, candidate.error)
	# 副本只作为规则重放源；对外仍发布事务输入的固定快照，不扫描 provider。
	var files:Array = approved_files.duplicate(true)
	_restore_stage("blob_publish_begin")
	for item in files:
		if not maintenance.call():
			return _fail_closed_restore(candidate, previous_root, previous_cache, "固定数据发布期间恢复取消或房间变化")
		var bytes:PackedByteArray = FileAccess.get_file_as_bytes(fixed_root.path_join(item.path))
		if bytes.size() != item.size or publish_blob(bytes) != item.hash:
			return _fail_closed_restore(candidate, previous_root, previous_cache, "恢复期间固定数据副本变化")
	_restore_stage("blob_publish_end")
	if not maintenance.call():
		return _fail_closed_restore(candidate, previous_root, previous_cache, "固定数据发布后恢复取消或房间变化")
	var assets = preload("res://scripts/net/content/room_assets.gd").new()
	_restore_stage("assets_install_begin")
	if not _can_publish_room_files(files) or not assets.install(files, fixed_root, blobs.cache.max_file_bytes, maintenance):
		var reason:String = error if not error.is_empty() else (assets.error if not assets.error.is_empty() else "无法发布完整已采用数据")
		return _fail_closed_restore(candidate, previous_root, previous_cache, reason)
	_restore_stage("assets_install_end")
	if not maintenance.call():
		return _fail_closed_restore(candidate, previous_root, previous_cache, "固定数据提交前恢复取消或房间变化")
	_restore_stage("room_commit_begin")
	if not _room_rules_active:
		_previous_data_root = previous_root
		_previous_cache_path = previous_cache
		_room_rules_active = true
	match_authority = candidate
	selection = preload("res://scripts/net/authority/selection_authority.gd").new()
	_clear_match_views()
	require_room_data = true
	_rules_revision = data_revision + 1
	room.phase = "restoring"
	_commit_room_files(files, assets, false)
	# 此后的快照包含本事务合法的 phase/revision/ready 变更，不比较旧快照。
	var committed_snapshot:Dictionary = room.snapshot().duplicate(true)
	_restore_stage("room_commit_end")
	if not _restore_checkpoint(original_room, committed_snapshot):
		return _fail_closed_restore(candidate, previous_root, previous_cache, "恢复持久化前连接中断或取消")
	_restore_stage("persist_begin")
	if not recovery_state_path.is_empty() and not _persist_recovery_state():
		return _fail_closed_restore(candidate, previous_root, previous_cache, "恢复状态保存失败，候选未发布")
	_restore_stage("persist_end")
	if not _restore_checkpoint(original_room, committed_snapshot):
		return _fail_closed_restore(candidate, previous_root, previous_cache, "恢复持久化期间中断；磁盘可能已提交，候选未发布")
	# recovery.json 可能已提交；哨兵删除失败不假称磁盘回滚。
	if DirAccess.remove_absolute(marker) != OK:
		return _fail_closed_restore(candidate, previous_root, previous_cache, "恢复回执提交失败，磁盘可能已提交；候选未发布")
	_restore_in_progress = false
	# 已在上方提交，避免第二次落盘失败却广播。
	_publish(false)
	for id in _peers:
		if room.members.has(id) and room.members[id].connected:
			_send_room_files(id)
	return true

func _fail_closed_restore(candidate, previous_root:String, previous_cache:String, reason:String) -> bool:
	_restore_failed_closed = true
	candidate.close_archive()
	close()
	_recovery_bindings.clear()
	LoadHelper.session_data_dir = previous_root
	LoadGame.stored_jsons_path = previous_cache
	GameStart.end_session()
	preload("res://scripts/match/match_journal.gd").reset_audit_memory()
	_restore_in_progress = false
	error = "恢复失败并关闭会话（未回滚原对局）；请丢弃此会话并重启权威：" + reason
	return false

func _maintain_restore_transport() -> bool:
	if not _host or _restore_failed_closed or not _restore_in_progress or _restore_cancelled: return false
	# 不解码/分派业务消息，不弹出被 _send 恢复守卫拒绝的 blob 队列。
	# 原生连接事件仍可同步发出；close/断线只锁存取消，外层事务负责清理。
	transport.keep_alive()
	return _host and _restore_in_progress and not _restore_failed_closed and not _restore_cancelled

func _restore_checkpoint(original_room, original_snapshot:Dictionary) -> bool:
	if room != original_room or not _host or room.snapshot() != original_snapshot: return false
	if not _maintain_restore_transport(): return false
	return room == original_room and _host and room.snapshot() == original_snapshot

func _restore_stage(stage:String) -> void:
	if OS.get_environment("FD_RESTORE_STAGE_TIMING") != "1": return
	print("RESTORE_SEGMENT pid=", OS.get_process_id(), " ticks_usec=", Time.get_ticks_usec(), " stage=", stage)

func _publish_selection() -> void:
	if _restore_failed_closed or _restore_in_progress or _begin_in_progress: return
	selection_view = selection.view_for(1)
	for id in _peers:
		if room.members.has(id):
			_send(id, {"kind": "selection", "state": selection.view_for(id)})
	changed.emit()

func _clear_match_views() -> void:
	_mirror.reset(-1)
	_match_bound = false
	_pending_view.clear()
	_action_view.clear()
	selection_view.clear()

func read_match() -> Dictionary:
	return _map_assets(_mirror.read(), false) if data_revision > 0 else _mirror.read()

func read_pending() -> Dictionary:
	return _map_assets(_pending_view, false) if data_revision > 0 else _pending_view.duplicate(true)

func match_commands_available() -> bool:
	if not _host and not transport.is_connected_to_host(): return false
	var actions:Dictionary = read_actions()
	return not actions.get("guard",{}).get("paused",false) and not actions.get("connection_wait",{}).get("paused",false) and not actions.get("management_paused",false)

func install_room_assets(directory: String) -> bool:
	if data_revision <= 0 or not _assets.install(room_files, directory, blobs.cache.max_file_bytes):
		error = _assets.error
		return false
	changed.emit()
	return true

## 只转换协议显式的图片字段；既不查询本机模板，也不改权威源对象。
func _map_assets(value, encode: bool):
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_map_assets(item, encode))
		return result
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value:
			if key in ["image", "back_image", "avatar"] and value[key] is String:
				result[key] = _assets.encode_path(value[key], LoadHelper.get_data_dir(), room_files) if encode else _assets.resolve(value[key])
			else:
				result[key] = _map_assets(value[key], encode)
		return result
	return value

func read_actions() -> Dictionary:
	return _action_view.duplicate(true)

func _disconnected_players() -> Array:
	var players:Array = []
	if not _host or not match_authority.started or GameProgress.is_game_over:
		return players
	for pid in match_authority.controllers:
		var controller:int = match_authority.controllers[pid]
		var data:Dictionary = GameData.player_data_library.get(pid, {})
		if controller <= 0 or data.is_empty() or data.get("is_out", false):
			continue
		if not room.members.has(controller) or not room.members[controller].connected:
			players.append(pid)
	players.sort()
	return players

func _match_actions_for(peer: int) -> Dictionary:
	var waiting:Array = _disconnected_players()
	var actions:Dictionary = match_authority.actions_for(peer) if waiting.is_empty() and not management_paused else {}
	actions["management_paused"] = management_paused
	var names:Array = []
	for pid in waiting:
		names.append(str(GameData.player_data_library[pid].get("player_name", "玩家")))
	actions["connection_wait"] = {"paused":not waiting.is_empty(), "players":waiting, "names":names}
	var status: Dictionary = EffectManager.runtime_guard_status()
	# 只有当前房主收到异常效果归属，其他连接仅知道等待状态。
	actions["guard"] = {"paused": status.paused, "can_continue": status.paused and peer == room.owner and not management_paused}
	if status.paused and peer == room.owner:
		actions["guard"]["diagnostic"] = match_authority.guard_diagnostic()
	if peer == room.owner and match_authority.recorder != null:
		actions["recording"] = {"active":match_authority.recorder._recording, "error":match_authority.recorder.error}
	return actions

func _bind_match() -> void:
	_mirror.reset(match_authority.observer_for(1))
	_match_bound = true
	for peer in _peers:
		if room.members.has(peer):
			_send(peer, {"kind": "match_bind", "observer": match_authority.observer_for(peer)}, 1)

func _publish_match() -> void:
	if _restore_failed_closed or _restore_in_progress or _begin_in_progress: return
	var state: Dictionary = match_authority.view_for(1)
	var pending: Dictionary = match_authority.pending_for(1)
	_mirror.accept(_map_assets(state, true) if data_revision > 0 else state)
	_pending_view = _map_assets(pending, true) if data_revision > 0 else pending
	_action_view = _match_actions_for(1)
	for peer in _peers:
		if room.members.has(peer):
			state = match_authority.view_for(peer)
			pending = match_authority.pending_for(peer)
			_send(peer, {"kind": "match_view", "state": _map_assets(state, true) if data_revision > 0 else state, "pending": _map_assets(pending, true) if data_revision > 0 else pending, "actions": _match_actions_for(peer)}, 1)
	changed.emit()

# 不调用 session.poll/transport.poll：原生包保留到外层正常 poll 再鉴权、分派。
# 维护期间 close 只锁存取消；任何录制启动失败均不声称回滚，禁止继续规则推进。
func _begin_selected_match() -> bool:
	if _restore_failed_closed or _restore_in_progress or _begin_in_progress: return false
	var recorded:bool = record_matches
	var original_room = room
	var revision:int = room.revision
	var approved_revision:int = data_revision
	var authority = match_authority
	var original_selection = selection
	_begin_cancelled = false
	_begin_in_progress = true
	var maintenance:Callable = func() -> bool:
		if _begin_cancelled or _restore_failed_closed or not _host or management_paused: return false
		if room != original_room or match_authority != authority or selection != original_selection: return false
		if room.revision != revision or room.phase != "selecting" or data_revision != approved_revision: return false
		if not transport.keep_alive(): return false
		# peer.poll 可同步产生断开/changed；再次校验，不能用入口快照授权返回成功。
		return not _begin_cancelled and not _restore_failed_closed and _host and not management_paused and room == original_room and match_authority == authority and selection == original_selection and room.revision == revision and room.phase == "selecting" and data_revision == approved_revision
	var accepted:bool = authority.start(original_selection, room.settings.get("runtime_guard", {}), new_archive_folder() if recorded else "", maintenance if recorded else Callable())
	_begin_in_progress = false
	if _begin_cancelled:
		accepted = false
		authority.error = "开局期间收到关闭请求，拒绝提交"
	if not accepted and (recorded or _begin_cancelled):
		_restore_failed_closed = true
		error = "录制开局失败并关闭会话（未回滚规则状态）；请重启权威：" + authority.error
	return accepted
