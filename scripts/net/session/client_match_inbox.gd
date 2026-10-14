extends RefCounted

signal changed
signal group_preview_received(request_id: int, result: Dictionary)
signal selection_received(state: Dictionary)
signal selection_reset

var _mirror = preload("res://scripts/match/view_mirror.gd").new()
var _pending_view: Dictionary = {}
var _action_view: Dictionary = {}
var _match_bound: bool = false

## 来源认证属于 Session；识别但无效的消息仍消费，不落入其他分支。
func receive(message: Dictionary) -> bool:
	match message.get("kind"):
		"group_preview":
			if message.get("request_id") is int and message.get("result") is Dictionary:
				group_preview_received.emit(message.request_id, message.result.duplicate(true))
		"match_bind":
			if message.get("observer") is int and not _match_bound:
				bind_local(message.observer)
		"match_reset":
			reset()
			selection_reset.emit()
			changed.emit()
		"match_view":
			if _match_bound and message.get("state") is Dictionary and message.get("pending") is Dictionary and message.get("actions") is Dictionary and accept_local_state(message.state, message.pending):
				publish_local_details(message.pending, message.actions)
				changed.emit()
		"selection":
			if message.get("state") is Dictionary:
				selection_received.emit(message.state.duplicate(true))
				changed.emit()
		_:
			return false
	return true

func reset() -> void:
	reconnect_reset()
	_pending_view.clear()
	_action_view.clear()

## 重连只撤销观察者绑定；尚未替换的待答和动作保留原契约。
func reconnect_reset() -> void:
	_match_bound = false
	_mirror.reset(-1)

## 主机本地显式重新绑定，不受客户端首次 bind 去重约束。
func bind_local(observer: int) -> void:
	_mirror.reset(observer)
	_match_bound = true

## 主机仍在校验成功后生成/编码 pending 和 actions；不存入回调或 Session。
func accept_local_state(state: Dictionary, pending: Dictionary) -> bool:
	return _mirror.accepts_pending(pending) and _mirror.accept(state)

func publish_local_details(pending: Dictionary, actions: Dictionary) -> void:
	_pending_view = pending.duplicate(true)
	_action_view = actions.duplicate(true)

func read_match() -> Dictionary:
	return _mirror.read()

func read_pending() -> Dictionary:
	return _pending_view.duplicate(true)

func read_actions() -> Dictionary:
	return _action_view.duplicate(true)