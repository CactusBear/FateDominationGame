class_name NetworkGroupSelection
extends RefCounted

## 只维护客机暂选与请求关联，不读取任何引擎规则。
signal changed
var _session
var _cards: Array = []
var _hidden: Array = []
var _preview: Dictionary = {}
var _request_id: int = 0
var _view_seq: int = 0
var _waiting: bool = false
var _submitted: bool = false
var _submit_sequence: int = 0
var _preview_sequence: int = 0

func bind_session(session) -> void:
	if _session != null:
		_session.changed.disconnect(_state_changed)
		_session.group_preview_received.disconnect(_received)
		_session.request_rejected.disconnect(_rejected)
	_submit_sequence = 0
	_preview_sequence = 0
	_session = session
	_cards.clear()
	_hidden.clear()
	_preview.clear()
	_view_seq = 0
	_submitted = false
	_waiting = false
	if _session != null:
		_session.changed.connect(_state_changed)
		_session.group_preview_received.connect(_received)
		_session.request_rejected.connect(_rejected)
		_state_changed()

func snapshot() -> Dictionary:
	return {"cards": _cards.duplicate(), "hidden": _hidden.duplicate(), "preview": _preview.duplicate(true), "waiting": _waiting, "submitted": _submitted}

func modes_for(id: int) -> Array:
	if _waiting or _submitted:
		return []
	for item in _preview.get("candidates", []):
		if item.id == id:
			return item.modes.duplicate()
	return []

func add(id: int, hidden: bool) -> bool:
	# 暂选与合法性独立；只允许当前观察者的已声明持有牌。
	if _session == null or _submitted or _cards.has(id):
		return false
	var owned: bool = false
	for player in _session.read_match().get("players", []):
		if player.id != _session.read_match().get("observer", -1):
			continue
		for entry in player.get("held_cards", []):
			if entry.card.id == id and entry.card.get("visible", false) and not entry.played and entry.card.concealed == hidden:
				owned = true
	if not owned:
		return false
	_cards.append(id)
	_hidden.append(hidden)
	_request_preview()
	return true

func remove(id: int) -> bool:
	var index := _cards.find(id)
	if index < 0 or _submitted:
		return false
	_cards.remove_at(index)
	_hidden.remove_at(index)
	_request_preview()
	return true

func can_confirm() -> bool:
	return _session != null and not _waiting and not _submitted and bool(_preview.get("ok", false)) and bool(_preview.get("can_submit", false))

func confirm() -> bool:
	if not can_confirm():
		return false
	_submitted = true
	var result: Error = _session.request("match_command", {"view_seq": _view_seq, "command": "play_group", "params": {"cards": _cards.duplicate(), "hidden": _hidden.duplicate()}}, _register_submit)
	if result != OK:
		_submitted = false
	changed.emit()
	return result == OK

func _state_changed() -> void:
	var sequence: int = int(_session.read_match().get("seq", 0))
	if sequence == _view_seq:
		return
	_submit_sequence = 0
	_preview_sequence = 0
	_view_seq = sequence
	# 非提交刷新（例如右键翻面）保留仍持有的选择，并采用权威最新朝向。
	var live: Dictionary = {}
	for player in _session.read_match().get("players", []):
		if player.id == _session.read_match().get("observer", -1):
			for entry in player.get("held_cards", []):
				if entry.card.get("visible", false) and not entry.played:
					live[entry.card.id] = entry.card.concealed
	var preserved: Array = []
	var flags: Array = []
	if not _submitted:
		for id in _cards:
			if live.has(id):
				preserved.append(id)
				flags.append(live[id])
	_cards = preserved
	_hidden = flags
	_submitted = false
	if int(_session.read_match().get("observer", -1)) < 0:
		_preview.clear()
		_waiting = false
		changed.emit()
		return
	_request_preview()

func _request_preview() -> void:
	_preview.clear()
	_preview_sequence = 0
	_waiting = true
	var args:Dictionary = {"request_id": 0, "view_seq": _view_seq, "cards": _cards.duplicate(), "hidden": _hidden.duplicate()}
	var result: Error = _session.request("preview_group", args, _register_preview.bind(args))
	if result != OK:
		_waiting = false
	changed.emit()

## 序号属于会话信封；与预览 request_id、视图 view_seq 各自独立。
func _register_submit(sequence: int) -> void:
	_submit_sequence = sequence

func _register_preview(sequence: int, args:Dictionary) -> void:
	_preview_sequence = sequence
	_request_id = sequence
	args.request_id = sequence

func _rejected(sequence: int, _reason: String) -> void:
	if sequence <= 0:
		return
	if _submitted and sequence == _submit_sequence:
		_submitted = false
		_submit_sequence = 0
	elif _waiting and sequence == _preview_sequence:
		_waiting = false
		_preview_sequence = 0
		_preview.clear()
	else:
		return
	changed.emit()

func _received(request_id: int, result: Dictionary) -> void:
	if request_id != _request_id or _session == null or _submitted or not _waiting:
		return
	if result.get("ok", false) and int(result.get("view_seq", -1)) != _view_seq:
		return
	_waiting = false
	_preview = result.duplicate(true)
	changed.emit()
