class_name MatchLobbySession
extends RefCounted

const Transport = preload("res://scripts/net/enet_transport.gd")
const Room = preload("res://scripts/net/room_state.gd")
signal changed
signal catalogs_changed
signal rejected(reason: String)
signal group_preview_received(request_id: int, result: Dictionary)
var transport = Transport.new()
var connection_driver: RefCounted
var blobs = preload("res://scripts/net/blob_receiver.gd").new()
var _published_blobs: Dictionary = {}
var _blob_sends: Array = []
var blob_chunks_per_poll: int = 2
var max_blob_requests: int = 64
var room = Room.new()
var selection = preload("res://scripts/net/selection_authority.gd").new()
var selection_view: Dictionary = {}
var match_authority = preload("res://scripts/net/match_authority.gd").new()
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
var catalogs: Dictionary = {}
var data_revision: int = 0
var _data_confirmed: Dictionary = {}
var _assets = preload("res://scripts/net/room_assets.gd").new()
var require_room_data: bool = false
var dedicated: bool = false
var server_room_id: String = ""
var server_rooms: Array = []
var _server_request: Dictionary = {}
var _server_sent: bool = false
var _server_peer_id: int = 0
var _rules_revision: int = 0
var _room_rules_active: bool = false
var _previous_data_root: String = ""
var _previous_cache_path: String = ""

func _init() -> void:
	transport.message_received.connect(_receive)
	transport.peer_connected.connect(_connected)
	transport.peer_disconnected.connect(_disconnected)

func host(port: int, name: String, settings: Dictionary, bind_address: String = "*") -> Error:
	close()
	var result: Error = transport.listen(port, bind_address)
	if result != OK:
		return result
	return _initialize_host(name, settings)

func _initialize_host(name: String, settings: Dictionary) -> Error:
	_host = true
	if not room.configure(1, settings) or not room.join(1, name):
		error = room.error
		transport.close()
		return ERR_INVALID_PARAMETER
	_publish()
	return OK

func host_peer(peer: MultiplayerPeer, name: String, settings: Dictionary) -> Error:
	if peer == null or peer.get_unique_id() != 1:
		return ERR_INVALID_PARAMETER
	close()
	var result: Error = transport.attach_peer(peer)
	return _initialize_host(name, settings) if result == OK else result

func join_peer(peer: MultiplayerPeer, name: String, spectator: bool = false) -> Error:
	if peer == null or peer.get_unique_id() <= 1:
		return ERR_INVALID_PARAMETER
	close()
	_hello = {"name": name, "spectator": spectator}
	return transport.attach_peer(peer)

func join(address: String, port: int, name: String, spectator: bool = false) -> Error:
	close()
	_hello = {"name": name, "spectator": spectator}
	return transport.connect_to(address, port)

## 网关分配的内部连接身份是房间管理与素材来源的统一标识。
func peer_id() -> int:
	return _server_peer_id if _server_peer_id > 0 else transport.peer_id()

func join_server(address: String, port: int, name: String, room_id: String = "", room_name: String = "", settings: Dictionary = {}, spectator: bool = false) -> Error:
	var result: Error = join(address, port, name, spectator)
	if result != OK:
		return result
	_server_request = {"kind": "server_join", "args": {"room": room_id}} if not room_id.is_empty() else {"kind": "server_create", "args": {"name": room_name, "settings": settings.duplicate(true)}}
	return OK

func poll(delta: float = 0.0) -> void:
	if connection_driver != null:
		connection_driver.call("poll")
	transport.poll()
	_pump_blobs()
	if not _server_request.is_empty() and not _server_sent and transport.is_connected_to_host():
		_server_sent = true
		request(_server_request.kind, _server_request.args)
	if _host and room.phase == "playing" and match_authority.step(delta):
		_publish_match()
	if not _host and not _hello_sent and not _hello.is_empty() and transport.is_connected_to_host() and (_server_request.is_empty() or _server_peer_id > 0):
		_hello_sent = true
		request("join", _hello)

func request(kind: String, args: Dictionary) -> Error:
	_seq += 1
	var message := {"v": 1, "seq": _seq, "kind": kind, "args": args}
	if _host:
		_receive(1, message)
		return OK
	return transport.send(1, message)

func close() -> void:
	var owns_match: bool = _host and match_authority.started
	var restores_rules: bool = _room_rules_active
	transport.close()
	if connection_driver != null:
		connection_driver.call("close")
	connection_driver = null
	blobs.cancel_peer(1)
	_published_blobs.clear()
	_blob_sends.clear()
	room = Room.new()
	selection = preload("res://scripts/net/selection_authority.gd").new()
	selection_view.clear()
	match_authority = preload("res://scripts/net/match_authority.gd").new()
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
	catalogs.clear()
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
	_server_request.clear()
	_server_sent = false
	_server_peer_id = 0
	_rules_revision = 0

func _connected(id: int) -> void:
	if _host and not _peers.has(id):
		_peers.append(id)

func _disconnected(id: int) -> void:
	_peers.erase(id)
	_data_confirmed.erase(id)
	blobs.cancel_peer(id)
	_blob_sends = _blob_sends.filter(func(job): return job.peer != id)
	if _host:
		room.mark_disconnected(id)
		_publish()
	else:
		error = "与房主连接中断"
		rejected.emit(error)

func _receive(sender: int, message: Dictionary) -> void:

	if not _host:
		if sender != 1:
			return
		if message.get("kind") == "server_attached" and not _server_request.is_empty() and _server_peer_id == 0:
			if message.get("room") is String and message.get("peer_id") is int and message.peer_id > 1:
				server_room_id = message.room
				_server_peer_id = message.peer_id
				changed.emit()
			return
		if message.get("kind") == "server_rooms" and message.get("rooms") is Array:
			server_rooms = message.rooms.duplicate(true)
			changed.emit()
			return
		if message.get("kind") == "provider_blob_request":
			if not message.get("key") is String or not message.get("offset") is int or not _queue_blob(sender, message.key, message.offset):
				transport.send(1, {"kind": "provider_blob_error", "key": str(message.get("key", ""))}, 2)
			return
		if message.get("kind") == "room_files":
			if message.get("revision") is int and message.revision > data_revision and message.get("files") is Array:
				var validator = preload("res://scripts/net/room_data_assembler.gd").new()
				if validator.validate(message.files, blobs.cache.max_file_bytes):
					room_files = message.files.duplicate(true)
					data_revision = message.revision
					_assets.clear()
					changed.emit()
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
				changed.emit()
		elif message.get("kind") == "error" and message.get("reason") is String:
			error = message.reason
			rejected.emit(error)
		return
	if message.get("kind") in ["blob_chunk", "provider_blob_error"]:
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
	if message.get("v") != 1 or not message.get("seq") is int or not message.get("args") is Dictionary or not message.get("kind") is String:
		_fail(sender, "协议字段无效")
		return
	if message.seq <= int(_received_seq.get(sender, 0)):
		_fail(sender, "重复或过期请求")
		return
	if message.kind != "join" and (not room.members.has(sender) or not room.members[sender].connected):
		_fail(sender, "连接已无房间操作权限")
		return
	_received_seq[sender] = message.seq
	var args: Dictionary = message.args
	var ok := false
	match message.kind:
		"catalog":
			if room.phase != "lobby" or not args.get("entries") is Array:
				_fail(sender, "只能在大厅上报条目清单")
				return
			var catalog = preload("res://scripts/net/data_catalog.gd").new()
			var accepted = catalog.accept(args.entries, str(sender))
			if accepted == null:
				_fail(sender, "\n".join(catalog.errors))
				return
			catalogs[sender] = accepted
			catalogs_changed.emit()
			return
		"data_ack":
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
					transport.send(sender, {"kind": "group_preview", "request_id": args.request_id, "result": result}, 1)
			else:
				_fail(sender, "组合预览请求无效")
			return
		"begin_match":
			if sender == room.owner and room.phase == "selecting" and data_ready() and match_authority.start(selection, room.settings.get("runtime_guard", {})):
				room.phase = "playing"
				room.revision += 1
				_bind_match()
				_publish_match()
				ok = true
		"match_command":
			if room.phase == "playing" and args.get("view_seq") is int and args.get("command") is String and args.get("params") is Dictionary:
				ok = match_authority.submit(sender, args.view_seq, args.command, args.params)
				# 引擎拒绝也可能清除等待或续行；失败后同样发布实际状态。
				_publish_match()
		"guard_continue", "guard_skip", "guard_restart", "guard_lobby":
			if sender != room.owner or room.phase != "playing" or args.size() != 1 or not args.get("view_seq") is int:
				_fail(sender, "只有房主可以继续暂停的规则执行")
				return
			if not match_authority.continue_runtime_guard(sender, args.view_seq, message.kind):
				_fail(sender, match_authority.error)
				return
			if message.kind == "guard_lobby":
				room.return_to_lobby(sender)
				selection = preload("res://scripts/net/selection_authority.gd").new()
				_masters = GameStart.get_masters_can_use()
				_servants = GameStart.get_servants_can_use()
				_clear_match_views()
				for id in _peers:
					if room.members.has(id): transport.send(id, {"kind":"match_reset"}, 1)
				_publish()
			else:
				_publish_match()
			return
		"blob_request":
			if args.get("key") is String and args.get("offset") is int:
				ok = _queue_blob(sender, args.key, args.offset)
				if not ok:
					transport.send(sender, {"kind": "blob_error", "key": args.key})
			return
		"join":
			if args.get("name") is String and args.get("spectator") is bool:
				ok = room.join(sender, args.name, args.spectator)
				if ok and dedicated and room.owner == 0 and not args.spectator:
					room.owner = sender
					room.revision += 1
				if ok and data_revision > 0:
					_send_room_files(sender)
				if ok and room.phase == "playing":
					transport.send(sender, {"kind": "match_bind", "observer": match_authority.observer_for(sender)}, 1)
					_publish_match()
		"ready":
			if args.get("ready") is bool:
				ok = room.set_ready(sender, args.ready)
		"settings":
			if args.get("changes") is Dictionary:
				ok = room.set_settings(sender, args.changes)
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
					transport.disconnect_peer(args.target)
	if not ok:
		_fail(sender, room.error if not room.error.is_empty() else "请求无效")
		return
	_publish()

func _publish() -> void:
	var state: Dictionary = room.snapshot()
	state.can_start = room.can_start() and data_ready()
	state.data_ready = data_ready()
	state.data_revision = data_revision
	# 协议字典键只允许字符串，成员列表用显式 id 字段而不是整数键。
	var members: Array = []
	for id in state.members:
		var member: Dictionary = state.members[id].duplicate(true)
		member.id = id
		members.append(member)
	state.members = members
	view = state.duplicate(true)

	for id in _peers:
		if room.members.has(id):
			transport.send(id, {"kind": "room", "state": state})
	changed.emit()

## 文件列表必须由调用方显式选择，且字节已经由主机批准发布。
func submit_catalog(entries: Array) -> bool:
	if not transport.is_connected_to_host():
		return false
	var catalog = preload("res://scripts/net/data_catalog.gd").new()
	var accepted = catalog.accept(entries, str(peer_id()))
	if accepted == null:
		error = "\n".join(catalog.errors)
		return false
	if var_to_bytes({"v": 1, "seq": _seq + 1, "kind": "catalog", "args": {"entries": accepted}}).size() > transport.max_packet_bytes:
		error = "条目清单超过消息预算"
		return false
	return request("catalog", {"entries": accepted}) == OK

## 主动分享时读取本机路径；远端仅能请求这份显式登记的哈希字节。
func share_catalog(directory: String, entries: Array) -> bool:
	var catalog = preload("res://scripts/net/data_catalog.gd").new()
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
	if transport.send(provider, {"kind": "provider_blob_request", "key": key, "offset": blobs.offset_for(provider, key)}, 2) != OK:
		blobs.cancel_blob(provider, key)
		return false
	return true

func set_room_files(files: Array) -> bool:
	if not _host or room.phase != "lobby":
		return false
	var validator = preload("res://scripts/net/room_data_assembler.gd").new()
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
	if var_to_bytes({"kind": "room_files", "revision": data_revision + 1, "files": manifest}).size() > transport.max_packet_bytes:
		error = "房间文件清单超过消息预算"
		return false
	room_files = manifest
	_assets.clear()
	data_revision += 1
	_data_confirmed.clear()
	_data_confirmed[1] = data_revision
	for member in room.members.values():
		member.ready = false
	room.revision += 1
	for id in _peers:
		if room.members.has(id) and room.members[id].connected:
			_send_room_files(id)
	_publish()
	return true

func data_ready() -> bool:
	if require_room_data and (data_revision == 0 or _rules_revision != data_revision):
		return false
	if data_revision == 0:
		return true
	for id in room.members:
		if room.members[id].connected and _data_confirmed.get(id, 0) != data_revision:
			return false
	return true

func _send_room_files(id: int) -> void:
	var result: Error = transport.send(id, {"kind": "room_files", "revision": data_revision, "files": room_files}, 2)
	if result != OK:
		error = "房间文件清单发送失败：" + error_string(result)
		rejected.emit(error)

func _fail(sender: int, reason: String) -> void:
	if sender == 1:
		error = reason
		rejected.emit(reason)
	else:
		transport.send(sender, {"kind": "error", "reason": reason})

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
	var authorized: bool = room.members.has(sender) and room.members[sender].connected if _host else sender == 1 and transport.is_connected_to_host()
	if not authorized or not _published_blobs.has(key):
		return false
	if offset < 0 or offset >= _published_blobs[key].size() or _blob_sends.size() >= max_blob_requests:
		return false
	for job in _blob_sends:
		if job.peer == sender and job.key == key:
			return false
	_blob_sends.append({"peer": sender, "key": key, "offset": offset})
	return true

func _pump_blobs() -> void:
	for _index in range(blob_chunks_per_poll):
		if _blob_sends.is_empty():
			return
		var job: Dictionary = _blob_sends.pop_front()
		var bytes: PackedByteArray = _published_blobs[job.key]
		var end: int = mini(job.offset + blobs.max_chunk_bytes, bytes.size())
		var result: Error = transport.send(job.peer, {"kind": "blob_chunk", "key": job.key, "offset": job.offset, "bytes": bytes.slice(job.offset, end)}, 2)
		if result == OK and end < bytes.size():
			job.offset = end
			_blob_sends.append(job)

## 配置只来自本地可信代码，不从网络接收 script 路径。
func adopt_room_data(task, config: Dictionary) -> bool:
	if not _host or room.phase != "lobby" or not task.complete or task.approved_files != room_files or not config.get("script") is String:
		error = "校验结果与当前房间批准清单不一致"
		return false
	var directory: String = task.directory.path_join("validation-data")
	var validator = preload("res://scripts/net/room_data_validator.gd").new()
	if not validator.validate(directory, room_files):
		error = "\n".join(validator.errors)
		return false
	if not _room_rules_active:
		_previous_data_root = LoadHelper.session_data_dir
		_previous_cache_path = LoadGame.stored_jsons_path
		_room_rules_active = true
	LoadHelper.session_data_dir = directory
	LoadGame.stored_jsons_path = task.directory.path_join("stored_jsons.dat")
	GameStart.end_session()
	var masters: Array = GameStart.get_masters_can_use()
	var servants: Array = GameStart.get_servants_can_use()
	var rules = load(config.script).new()
	if not room.configure_rules({"capacity": rules.capacity(masters, servants, config)}):
		error = room.error
		_restore_room_rules()
		return false
	if not configure_selection(config, masters, servants) or not install_room_assets(directory):
		_restore_room_rules()
		return false
	require_room_data = true
	_rules_revision = data_revision
	_publish()
	return true

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

func _prepare_selection() -> bool:
	if _selection_config.is_empty():
		room.error = "主机尚未注册选人规则"
		return false
	var script = load(_selection_config.script)
	if not script is Script or not script.can_instantiate():
		return false
	var seats: Dictionary = {}
	for id in room.members:
		if not room.members[id].spectator:
			seats[seats.size()] = id
	for _i in range(int(room.settings.ai_count)):
		seats[seats.size()] = 0
	if not selection.setup(script.new(), seats, _masters, _servants, _selection_config):
		room.error = selection.error
		return false
	return true

func _publish_selection() -> void:
	selection_view = selection.view_for(1)
	for id in _peers:
		if room.members.has(id):
			transport.send(id, {"kind": "selection", "state": selection.view_for(id)})
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

func _match_actions_for(peer: int) -> Dictionary:
	var actions: Dictionary = match_authority.actions_for(peer)
	var status: Dictionary = EffectManager.runtime_guard_status()
	# 只有当前房主收到异常效果归属，其他连接仅知道等待状态。
	actions["guard"] = {"paused": status.paused, "can_continue": status.paused and peer == room.owner}
	if status.paused and peer == room.owner:
		actions["guard"]["diagnostic"] = match_authority.guard_diagnostic()
	return actions

func _bind_match() -> void:
	_mirror.reset(match_authority.observer_for(1))
	_match_bound = true
	for peer in _peers:
		if room.members.has(peer):
			transport.send(peer, {"kind": "match_bind", "observer": match_authority.observer_for(peer)}, 1)

func _publish_match() -> void:
	var state: Dictionary = match_authority.view_for(1)
	var pending: Dictionary = match_authority.pending_for(1)
	_mirror.accept(_map_assets(state, true) if data_revision > 0 else state)
	_pending_view = _map_assets(pending, true) if data_revision > 0 else pending
	_action_view = _match_actions_for(1)
	for peer in _peers:
		if room.members.has(peer):
			state = match_authority.view_for(peer)
			pending = match_authority.pending_for(peer)
			transport.send(peer, {"kind": "match_view", "state": _map_assets(state, true) if data_revision > 0 else state, "pending": _map_assets(pending, true) if data_revision > 0 else pending, "actions": _match_actions_for(peer)}, 1)
	changed.emit()
