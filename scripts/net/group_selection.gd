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

func bind_session(session) -> void:
	if _session != null:
		_session.changed.disconnect(_state_changed)
		_session.group_preview_received.disconnect(_received)
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
	if _cards.has(id) or not modes_for(id).has(hidden):
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
	var result: Error = _session.request("match_command", {"view_seq": _view_seq, "command": "play_group", "params": {"cards": _cards.duplicate(), "hidden": _hidden.duplicate()}})
	if result != OK:
		_submitted = false
	changed.emit()
	return result == OK

func _state_changed() -> void:
	var sequence: int = int(_session.read_match().get("seq", 0))
	if sequence == _view_seq:
		return
	_view_seq = sequence
	_cards.clear()
	_hidden.clear()
	_submitted = false
	_request_preview()

func _request_preview() -> void:
	_preview.clear()
	_request_id += 1
	_waiting = true
	var result: Error = _session.request("preview_group", {"request_id": _request_id, "view_seq": _view_seq, "cards": _cards.duplicate(), "hidden": _hidden.duplicate()})
	if result != OK:
		_waiting = false
	changed.emit()

func _received(request_id: int, result: Dictionary) -> void:
	if request_id != _request_id or _session == null or _submitted:
		return
	if result.get("ok", false) and int(result.get("view_seq", -1)) != _view_seq:
		return
	_waiting = false
	_preview = result.duplicate(true)
	changed.emit()
