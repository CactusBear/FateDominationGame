extends RefCounted

## 只管理权威候选目录及批准事务；下载、组装、校验共用 RoomDataPreparation。
var validation_seconds:float = 30.0
var max_selected_entries:int = 1000
var _session
var _entries:Array = []
var _base:Array = []

var _approved:Array = []
var _catalog_revision:int = 1
var _request_id:int = 0
var _actor:int = 0
var _prepared_revision:int = 0
var _selected:Array = []
var _mode:Dictionary = {}
var _stage:String = "idle"
var _last_text:String = ""
var _preparation = preload("res://scripts/net/validation/room_data_preparation.gd").new()

func configure(session, root:String, entries:Array, base:Array, workspace_root:String = "") -> void:
	_session = session
	_entries = entries.duplicate(true)
	_base = base.duplicate(true)

	if not session.room_files.is_empty():
		for entry in _entries: _approved.append({"provider":entry.provider, "key":entry.key})
	_preparation.session = session
	_preparation.source_root = root
	_preparation.workspace_root = workspace_root
	_preparation.source_provider = "server"
	session.data_management_requested.connect(_request)
	session.catalogs_changed.connect(_catalogs_changed)
	session.changed.connect(_room_changed)

func _available() -> Array:
	var result:Array = _entries.duplicate(true)
	for id in _session.catalogs:
		if _session.room.members.has(id) and _session.room.members[id].connected:
			result.append_array(_session.catalogs[id].filter(func(entry): return entry.category != "command_spells"))
	return result

func _catalogs_changed() -> void:
	_catalog_revision += 1
	# 已建立的请求使用自己的清单和校验副本，目录刷新只影响下一次选择。
	if _session.room.phase == "lobby" and _session.room.owner > 0:
		_publish_catalog(_session.room.owner)

func _publish_catalog(actor:int) -> void:
	var declared:Array = []
	for mode in _session.selection_modes: declared.append({"id":mode.id, "name":str(mode.get("name", mode.id))})
	var payload := {"kind":"server_data_catalog", "catalog_revision":_catalog_revision, "entries":_available(), "selected":_approved, "modes":declared, "validation_seconds":validation_seconds}
	if _session.send_catalog_message(actor, payload, 2) != OK:
		_session._fail(actor, "候选目录超过消息预算或连接不可用")

func _request(actor:int, action:String, args:Dictionary) -> void:
	if actor != _session.room.owner or _session.room.phase != "lobby" or not _session.room.members.has(actor) or not _session.room.members[actor].connected:
		_session._fail(actor, "无权管理服务端数据或数据已冻结")
		return
	match action:
		"server_data_catalog": _publish_catalog(actor)
		"server_data_prepare": _prepare(actor, args)
		"server_data_commit": _commit(actor, args)
		"server_data_cancel":
			if _actor == actor and (args.is_empty() or (args.size() == 1 and args.get("request_id") is int and args.request_id == _request_id)):
				_cancel("本次服务端数据批准已取消")
			elif _actor == 0 and (args.is_empty() or args.get("request_id") == _request_id): pass
			else: _session._fail(actor, "数据批准请求已过期")

func _prepare(actor:int, args:Dictionary) -> void:
	if _actor != 0:
		_session._fail(actor, "已有数据批准正在进行")
		return
	if args.keys().any(func(key): return key not in ["catalog_revision", "selected"]) or not args.get("catalog_revision") is int or args.catalog_revision != _catalog_revision or not args.get("selected") is Array or args.selected.size() > max_selected_entries:
		_session._fail(actor, "候选目录过期或条目选择超过预算")
		return
	var chosen:Array = []
	var identities:Dictionary = {}
	var available:Array = _available()
	for reference in args.selected:
		if not reference is Dictionary or reference.size() != 2 or not reference.get("provider") is String or not reference.get("key") is String:
			_session._fail(actor, "只接受已登记的提供者与条目键")
			return
		var identity:String = reference.provider + ":" + reference.key
		var found:Array = available.filter(func(entry): return entry.provider == reference.provider and entry.key == reference.key)
		if found.size() != 1 or identities.has(identity):
			_session._fail(actor, "所选条目不存在、重复或来源已离线")
			return
		identities[identity] = true
		chosen.append(found[0])
	_mode = {}
	for mode in _session.selection_modes:
		if mode.id == _session.room.settings.selection_mode: _mode = mode.duplicate(true)
	if _mode.is_empty():
		_session._fail(actor, "服务端未声明当前选人模式")
		return
	if not _preparation.start(chosen, _base, validation_seconds):
		_session._fail(actor, _preparation.error)
		return
	_actor = actor
	_request_id += 1
	_prepared_revision = _catalog_revision
	_selected = args.selected.duplicate(true)
	_stage = "preparing"
	_status("正在服务端准备所选数据")

func poll() -> void:
	if _actor == 0: return
	if not _proposal_is_current():
		_cancel("房间资格或候选目录变化，原批准请求已取消")
		return
	if _stage == "ready": return
	_preparation.poll()
	if not _preparation.error.is_empty():
		var recipient:int = _actor
		_actor = 0
		_stage = "error"
		_status(_preparation.error, recipient)
		return
	if _preparation.validation.complete:
		_stage = "ready"
		_status("服务端已完成隔离校验，等待房主确认", _actor, _preparation.validation.report.get("loop_analysis", {}))
	elif _preparation.status != _last_text:
		_status(_preparation.status)

func _commit(actor:int, args:Dictionary) -> void:
	if _actor != actor or _stage != "ready" or not args.get("request_id") is int or args.request_id != _request_id:
		_session._fail(actor, "数据批准请求已过期或尚未校验完成")
		return
	if not _proposal_is_current():
		_cancel("批准条件变化，原请求已取消")
		_session._fail(actor, "批准条件变化，不能确认旧请求")
		return
	if not _session.apply_room_data(_preparation.validation, _mode):
		var reason:String = _session.error
		_actor = 0
		_stage = "error"
		_status(reason, actor)
		return
	_approved = _selected.duplicate(true)
	_catalog_revision += 1
	_actor = 0
	_stage = "applied"
	_status("房间数据已应用。等待成员同步。", actor)
	_publish_catalog(actor)

func _status(text:String, recipient:int = 0, report:Dictionary = {}) -> void:
	if recipient == 0: recipient = _actor
	_last_text = text
	if recipient <= 0 or not _session.room.members.has(recipient) or not _session.room.members[recipient].connected: return
	var origins:Dictionary = {}
	report = report.duplicate(true)
	if _stage in ["ready", "applied"] and _preparation.validation.report.has("random_simulation"):
		report["random_simulation"] = _preparation.validation.report.random_simulation.duplicate(true)
	if _stage == "ready":
		for index in range(_preparation.plan.files.size()):
			origins[_preparation.plan.files[index].path] = _preparation.plan.sources[index].duplicate()
	var state := {"stage":_stage, "request_id":_request_id, "catalog_revision":_prepared_revision, "text":text, "report":report, "origins":origins}
	if _session._send(recipient, {"kind":"server_data_status", "state":state}, 2) != OK:
		if _actor != 0:
			_preparation.cancel()
			_actor = 0
			_stage = "error"
		_session._fail(recipient, "数据校验报告超过消息预算或连接不可用")

func _cancel(reason:String) -> void:
	var recipient:int = _actor
	_preparation.cancel()
	_actor = 0
	_stage = "cancelled"
	_status(reason, recipient)

func close() -> void:
	_preparation.cancel()
	_actor = 0
	_stage = "idle"
	if _session != null:
		_session.data_management_requested.disconnect(_request)
		_session.catalogs_changed.disconnect(_catalogs_changed)
		_session.changed.disconnect(_room_changed)
	_preparation.session = null
	_session = null

func _proposal_is_current() -> bool:
	return _actor > 0 and _session.room.owner == _actor and _session.room.phase == "lobby" and _session.room.members.has(_actor) and _session.room.members[_actor].connected and _session.room.settings.selection_mode == _mode.id and _preparation.simulation_is_current()

func _room_changed() -> void:
	if _actor > 0 and not _proposal_is_current(): _cancel("房间资格或模式变化，原批准请求已取消")
