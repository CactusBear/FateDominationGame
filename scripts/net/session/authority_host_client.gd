extends RefCounted

## 只做房主机器上的传输路由与进程监督；规则始终由现有 room worker 执行。
var gateway = preload("res://scripts/net/server/server_gateway.gd").new()
var room_id:String = ""
var error:String = ""
var _session:WeakRef
var _name:String = ""
var _joining:bool = false
var _owner_bound:bool = false
var _crash_waiting:bool = false
var _closing_target:Dictionary = {}
var _close_response:String = ""
var _close_request_id:String = ""
var _close_error_reported:bool = false
var _pending_joins:Dictionary = {}
var lan_identity = preload("res://scripts/net/identity/lan_identity_challenge.gd").new()
var _identity_bridge = preload("res://scripts/net/server/lan_supervisor_identity_bridge.gd").new()
var _archive_restore = preload("res://scripts/net/server/lan_archive_restore.gd").new()

func _init() -> void:
	gateway.transport.message_received.disconnect(gateway._receive)
	gateway.transport.message_received.connect(_receive)
	gateway.transport.peer_disconnected.connect(_peer_disconnected)
	gateway.lan_identity = lan_identity
	gateway.accepting_rooms = false

func _peer_disconnected(peer:int) -> void:
	_pending_joins.erase(peer)
	lan_identity.forget(peer)

func start(session:RefCounted, name:String, settings:Dictionary, host_mode:String, port:int = 0, bind_address:String = "*", peer:MultiplayerPeer = null, storage_root:String = "user://authority_rooms") -> Error:
	if host_mode not in ["lan", "p2p"] or name.strip_edges().is_empty(): return ERR_INVALID_PARAMETER
	if host_mode == "p2p" and (peer == null or peer.get_unique_id() != 1): return ERR_INVALID_PARAMETER
	# 不开启注定无法完成 OS 所有权验证的监听，也不接管外部 P2P peer。
	if not gateway.manager.process_ownership_available():
		error = gateway.manager.PROCESS_OWNERSHIP_UNAVAILABLE
		return ERR_UNAVAILABLE
	if session.identity_profile.is_empty() or session.player_identity.public_key() != session.identity_profile.get("public_key"):
		error = "LAN/P2P 房主必须先配置密钥身份"
		return ERR_UNAUTHORIZED
	_name = name
	_session = weakref(session)
	session.authority_host_mode = host_mode
	gateway.manager.authority_host_mode = host_mode
	gateway.manager.storage_root = storage_root # 本机调用方指定隔离目录，不接受网络 args。
	# 保留既有录制开关；事务审计独立启用，不伪装成可恢复的对局存档。
	gateway.manager.record_matches = session.record_matches
	gateway.manager.transaction_log = true
	gateway.data_root = LoadHelper.get_data_dir()
	var result:Error = gateway.transport.listen(port, bind_address) if host_mode == "lan" else gateway.transport.attach_peer(peer)
	if result != OK:
		error = "房主直连监听失败：" + error_string(result)
		return result
	var authenticated_settings:Dictionary = settings.duplicate(true)
	authenticated_settings["_gateway_identity_required"] = true
	room_id = gateway.manager.create_room(name, authenticated_settings, gateway.data_root)
	if room_id.is_empty():
		error = gateway.manager.error
		gateway.transport.close()
		return ERR_CANT_CREATE
	return OK

func poll() -> void:
	if room_id.is_empty(): return
	gateway.poll()
	var session = _session.get_ref() if _session != null else null
	if session == null: return
	var target:Dictionary = gateway.manager.rooms.get(room_id, {})
	if target.is_empty():
		_fail(session, "权威房间登记丢失")
		return
	if not target.get("error", "").is_empty():
		# 崩溃不关闭外部监听、不删除恢复登记；只撤销已死 worker 的回环连接。
		_crash_waiting = true
		if session.transport.is_connected_to_host() or session.transport.is_connecting(): session.transport.close()
		return
	if not gateway.manager.is_ready(room_id): return
	lan_identity.expire(Time.get_ticks_msec())
	if lan_identity.room_id.is_empty():
		if not lan_identity.configure(room_id, str(target.get("instance_id", ""))):
			_fail(session,"权威房间实例缺失")
			return
	elif lan_identity.instance_id != target.get("instance_id", ""):
		_fail(session,"权威房间实例已替换，请重新建立认证连接")
		return
	if not _joining:
		_joining = true
		# UI 不调用 host/host_peer、不持有规则执行权；只有回环连接进入 worker。
		# 恢复时保留 _prepare_reconnect 写入的原房主票据。
		session._hello["name"] = session.identity_profile.nickname
		session._hello["spectator"] = false
		lan_identity.profiles[session.player_identity.fingerprint(session.identity_profile.public_key)] = session.identity_profile.duplicate(true)
		session._join_endpoint = {"address":"127.0.0.1","port":target.port}
		var result:Error = session.transport.connect_to("127.0.0.1", target.port)
		if result != OK:
			_fail(session, "无法连接本机权威子进程：" + error_string(result))
			return
	# 房主先取得权威成员快照，再处理外来 join；不让首个客机抢占房主。
	_identity_bridge.poll(gateway,room_id,session)
	if not _owner_bound:
		if session.view.is_empty() or session.view.get("owner") != session.peer_id(): return
		_owner_bound = true
	for connection in _pending_joins.keys():
		if not gateway.routes.has(connection):
			gateway._attach(connection, room_id)
		elif gateway.routes[connection].attached:
			gateway._receive(connection, _pending_joins[connection])
			_pending_joins.erase(connection)

## 本机显式恢复同一登记，不从网络管理消息触发；原生 manager 校验退出及新实例。
func recover_worker() -> bool:
	var session = _session.get_ref() if _session != null else null
	if session == null or not session.has_resume_identity() or not _closing_target.is_empty(): return false
	var old:Dictionary = gateway.manager.instance_binding(room_id)
	if old.is_empty(): return false
	# manager.poll 已确认 EXITED 并 release 后 PID 为 -1；正 PID 仍须句柄证实退出。
	if old.pid > 0 and gateway.manager.process_state_for_binding(old) != 0: return false
	if old.pid != -1 and old.pid <= 0: return false
	var directory:String = str(gateway.manager.rooms[room_id].directory)
	var path:String = directory.path_join("recovery.json")
	if not preload("res://scripts/net/server/recovery_path_safety.gd").checked(gateway.manager.storage_root,path): return false
	var saved = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not saved is Dictionary or not preload("res://scripts/net/identity/member_identity_bindings.gd").valid_state(saved,true): return false
	var member:int = session.peer_id()
	var key:String = session.player_identity.fingerprint(session.player_identity.public_key())
	# 先验证密钥，再验证原房主稳定 member 及票据；拒绝首个持票客机夺权。
	if saved.member_identities.get(str(member)) != key or saved.room.owner != member: return false
	var proof:String = str(session._resume_ticket.get("token","")).sha256_text()
	if proof != saved.resume_hashes.get(str(member)) and proof != saved.resume_previous.get(str(member)): return false
	if not gateway.manager.recover_room(room_id,old.pid,old.instance_id):
		error = gateway.manager.error
		return false
	# 新世代只在显式、经原生 manager 确认的实例替换后建立，旧认证不能搬运。
	for peer in gateway.routes.keys():
		gateway._detach_route(peer,gateway.routes[peer])
	# gateway.poll 可能已删路由；仍须撤销所有旧外部活连接，要求真人新握手。
	for peer in gateway.transport._connected_peers.keys():
		gateway.transport.disconnect_peer(peer)
	_pending_joins.clear()
	lan_identity = preload("res://scripts/net/identity/lan_identity_challenge.gd").new()
	gateway.lan_identity = lan_identity
	_identity_bridge = preload("res://scripts/net/server/lan_supervisor_identity_bridge.gd").new()
	_joining = false
	_owner_bound = false
	_crash_waiting = false
	error = ""
	session._prepare_reconnect()
	session.view.clear()
	session.selection_view.clear()
	session.changed.emit()
	return true

func _receive(connection:int, message:Dictionary) -> void:
	# LAN/P2P 保持普通 join 契约，不开放网关建房、选房或管理控制台。
	# worker 未就绪或新挑战未配置时拒绝授权，不接受旧实例 proof/join。
	if not gateway.manager.is_ready(room_id) or lan_identity.instance_id != gateway.manager.instance_binding(room_id).get("instance_id"):
		gateway._fail(connection,"权威新实例尚未完成认证准备，请重新连接")
		gateway.transport.disconnect_peer(connection)
		return
	if message.get("kind") in ["lan_identity_begin","lan_identity_proof"]:
		if message.get("v") != 1 or not message.get("seq") is int or message.seq <= 0 or not message.get("args") is Dictionary:
			gateway._fail(connection,"身份协议字段无效")
			return
		var response:Dictionary = lan_identity.begin(connection,message.args,Time.get_ticks_msec()) if message.kind == "lan_identity_begin" else lan_identity.prove(connection,message.args,Time.get_ticks_msec())
		if response.is_empty(): gateway._fail(connection,lan_identity.error)
		elif gateway.transport.send(connection,response) != OK:
			lan_identity.forget(connection)
			gateway.transport.disconnect_peer(connection)
		return
	if message.get("kind") == "join" and not lan_identity.authenticated.has(connection):
		gateway._fail(connection,"入房要求完成 LAN 密钥身份认证")
		return
	if message.get("kind") == "join" and not gateway.routes.has(connection):
		if _pending_joins.has(connection):
			gateway._fail(connection, "连接已有待处理的入房请求")
			return
		_pending_joins[connection] = message.duplicate(true)
		return
	if str(message.get("kind", "")).begins_with("server_") and message.get("kind") not in ["server_data_catalog", "server_data_prepare", "server_data_commit", "server_data_cancel"]:
		gateway._fail(connection, "直连房间不提供服务端管理入口")
		return
	if _pending_joins.has(connection):
		gateway._fail(connection, "权威房间尚未完成连接")
		return
	gateway._receive(connection, message)

func _fail(session, reason:String) -> void:
	if not error.is_empty(): return
	error = reason
	session.error = reason
	session.rejected.emit(reason)
	session.changed.emit()
	gateway.transport.close()

## 本机房主手选存档：只登记本机路径，经实例绑定私有 IPC 请求独立 worker 恢复。
## selected 为房主显式选择的 player_id→当前 member_id；metadata_source 仅供本机显式批准旧档元数据。
func restore_local_match(source:String, selected:Dictionary = {}, metadata_source:String = "") -> bool:
	var session = _session.get_ref() if _session != null else null
	if session == null: return false
	var metadata:String = ProjectSettings.globalize_path(metadata_source) if not metadata_source.is_empty() else ""
	return await _archive_restore.submit(self,session,ProjectSettings.globalize_path(source),selected,metadata)

## 仅本机UI公开候选投影；不选择恢复座位，不返回身份键或恢复凭据。
func restore_member_candidates() -> Array:
	var session = _session.get_ref() if _session != null else null
	if session == null or not _identity_bridge.confirmed: return []
	var target:Dictionary = gateway.manager.instance_binding(room_id)
	var snapshot:Dictionary = _identity_bridge.snapshot_for(gateway, target, session)
	if snapshot.is_empty(): return []
	var members:Dictionary = {}
	for member in session.view.get("members", []):
		if member.get("connected") == true and member.get("spectator") == false:
			members[int(member.id)] = {"name":member.name}
	var identities:Dictionary = {}
	for connection in snapshot.connections.values():
		if members.has(connection.member): identities[str(connection.member)] = connection.key
	return preload("res://scripts/net/identity/player_registry.gd").public_member_labels(members, identities, snapshot.profiles)

func diagnostics() -> Dictionary:
	var target:Dictionary = gateway.manager.rooms.get(room_id, {})
	return {"room_id":room_id,"pid":target.get("pid", -1),"instance_id":target.get("instance_id", ""),
		"authority_host_mode":gateway.manager.authority_host_mode,"worker_ready":gateway.manager.is_ready(room_id),
		"authenticated_context_delivered":_identity_bridge.confirmed,"identity_delivery_error":_identity_bridge.error,
		"archive_restore_available":true,"archive_restore_busy":_archive_restore.busy,"worker_crash_waiting":_crash_waiting,
		"game_forwarding_via_signaling":false,"error":error}

func close() -> void:
	# 重复关闭不另建请求、不替换等待中的旧实例身份。
	if not _closing_target.is_empty():
		var retired:Dictionary = gateway.manager.retired_binding_for_request(room_id,_close_request_id)
		if retired.is_empty() or gateway.manager.instance_binding(room_id).get("instance_id") == _closing_target.instance_id: return
		# 已退出旧请求仍在 manager 的回执档案；不能阻止关闭新恢复实例。
		_closing_target.clear()
		_close_request_id = ""
		_close_response = ""
	# 不直接 kill 正在结算的 worker；保存/退出走原有实例绑定的控制请求。
	var target:Dictionary = gateway.manager.rooms.get(room_id, {})
	if not target.is_empty() and target.get("pid", -1) > 0:
		var binding:Dictionary = gateway.manager.instance_binding(room_id)
		var id:String = Crypto.new().generate_random_bytes(16).hex_encode()
		if not gateway.manager.hold_process_supervision(room_id,id):
			push_warning("权威关闭句柄不可用；保留子进程与目录，不伪报已关闭")
			return
		var directory:String = str(target.directory).path_join("control")
		if DirAccess.make_dir_recursive_absolute(directory) != OK:
			gateway.manager.cancel_process_supervision(binding,id)
			push_warning("权威关闭管理目录不可写；保留连接，允许重试")
			return
		_closing_target = target.duplicate(true)
		_closing_target["room"] = room_id
		_closing_target["binding"] = binding
		_close_request_id = id
		_close_error_reported = false
		_close_response = directory.path_join(id + ".response.json")
		var result:Error = preload("res://scripts/net/server/server_console_channel.gd").write_json(directory.path_join(id + ".request.json"),
			{"room":room_id,"pid":target.pid,"instance":target.instance_id,"authority_host_mode":target.authority_host_mode,"action":"close"})
		if result != OK:
			gateway.manager.cancel_process_supervision(binding,id)
			_closing_target.clear()
			_close_request_id = ""
			_close_response = ""
			push_warning("权威关闭请求未落盘；保留连接，允许重试")
			return
		var tree = Engine.get_main_loop() as SceneTree
		if tree != null and not tree.process_frame.is_connected(_drain_close): tree.process_frame.connect(_drain_close)
	gateway.transport.close()
	for route in gateway.routes.values(): gateway._close_route_link(route.link)
	gateway.routes.clear()
	_pending_joins.clear()
	_session = null
	# room_id 只在最终回执与句柄退出、release 都成功后清空。

func _drain_close() -> void:
	# UI 场景移交/关闭之后仍泵送心跳，直到权威安全退出；不以丢心跳强杀替代保存。
	gateway.manager.poll()
	if _closing_target.is_empty():
		var tree = Engine.get_main_loop() as SceneTree
		if tree != null and tree.process_frame.is_connected(_drain_close): tree.process_frame.disconnect(_drain_close)
		return
	# 不等待无限期保存确认来占用已 EXITED 的句柄；仍继续读取原请求。
	if not FileAccess.file_exists(_close_response):
		if gateway.manager.process_state_for_binding(_closing_target.binding) == 0:
			gateway.manager.retire_unconfirmed_close(_closing_target.binding,_close_request_id)
		return
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(_close_response)) != OK or not parser.data is Dictionary:
		if gateway.manager.process_state_for_binding(_closing_target.binding) == 0: gateway.manager.retire_unconfirmed_close(_closing_target.binding,_close_request_id)
		return
	var response:Dictionary = parser.data
	if response.get("room") != _closing_target.room or response.get("pid") != _closing_target.pid or response.get("instance") != _closing_target.instance_id or response.get("authority_host_mode") != _closing_target.authority_host_mode or response.get("request_id") != _close_request_id:
		if gateway.manager.process_state_for_binding(_closing_target.binding) == 0: gateway.manager.retire_unconfirmed_close(_closing_target.binding,_close_request_id)
		return
	if response.get("ok") == false:
		gateway.manager.cancel_process_supervision(_closing_target.binding,_close_request_id)
		push_warning("权威安全关闭被拒，子进程保留，可重试：" + str(response.get("error", "未确认")))
		_closing_target.clear()
		_close_request_id = ""
		_close_response = ""
		return
	if response.get("ok") != true: return
	if not response.get("result",{}).get("closing",false): return
	var historical:Dictionary = _closing_target.binding.merged({"request_id":_close_request_id})
	var retired:bool = gateway.manager.retired_binding_for_request(room_id,_close_request_id) == historical
	var process_state:int = 0 if retired else gateway.manager.process_state_for_binding(_closing_target.binding)
	if process_state < 0:
		if not _close_error_reported:
			_close_error_reported = true
			push_warning("权威关闭回执成功但原生句柄不可用，仍收取原请求并等待句柄恢复")
		return
	if process_state != 0: return
	if not retired and not gateway.manager.release_process_for_binding(_closing_target.binding,_close_request_id):
		push_warning("权威进程已退出但原生所有权释放失败，未确认完整关闭")
		return
	var tree = Engine.get_main_loop() as SceneTree
	if tree != null and tree.process_frame.is_connected(_drain_close): tree.process_frame.disconnect(_drain_close)
	var current_instance:String = str(gateway.manager.instance_binding(room_id).get("instance_id",""))
	if current_instance == _closing_target.instance_id: room_id = ""
	_closing_target.clear()
	_close_response = ""
	_close_request_id = ""
