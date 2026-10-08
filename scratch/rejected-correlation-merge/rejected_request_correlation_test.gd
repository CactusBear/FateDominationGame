extends Node
## 放入 tests/ 后配合同名 tscn 串行运行；未打补丁时以下隔离断言应真实变红。
## 使用真实生产控制器，FakeSession 只控制传输时序，不重写锁算法或规则。
const Group = preload("res://scripts/net/group_selection.gd")
const Presenter = preload("res://scripts/net/v2_view_presenter.gd")
const Lobby = preload("res://scripts/net/lobby_session.gd")
const Choice = preload("res://scripts/net/network_choice_panel.gd")
var checks: int = 0
var failures: Array[String] = []

class FakeSession extends RefCounted:
	signal changed
	signal rejected(reason: String)
	signal request_rejected(sequence: int, reason: String)
	signal group_preview_received(request_id: int, result: Dictionary)
	signal server_notice_received(text: String)
	var seq: int = 0
	var sent: Array = []
	var match_view: Dictionary = {"seq": 8, "observer": 0}
	var pending: Dictionary = {}
	var sync_reject: bool = false
	var local_failure: bool = false
	func read_match() -> Dictionary: return match_view
	func read_pending() -> Dictionary: return pending
	func read_actions() -> Dictionary:
		return {"guard": {"paused": true, "can_continue": true, "diagnostic": {"can_skip": true, "can_restart": true}}}
	func match_commands_available() -> bool: return true
	func request(kind: String, args: Dictionary, registered: Callable = Callable()) -> Error:
		seq += 1
		if registered.is_valid(): registered.call(seq)
		sent.append({"kind": kind, "seq": seq, "args": args.duplicate(true)})
		if sync_reject: reject(seq)
		return ERR_CANT_CONNECT if local_failure else OK
	func reject(sequence: int) -> void:
		request_rejected.emit(sequence, "该请求被拒绝")
		rejected.emit("该请求被拒绝")
		changed.emit()

class ChoiceStub extends Control:
	func bind_session(_session) -> void: pass

class BoardStub extends Control:
	func _confirm_held_cards() -> void: pass
	func _clear(node: Node) -> void:
		for child in node.get_children(): child.free()
	func _say(_text: String) -> void: pass

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func _ready() -> void:
	_group_cases()
	_guard_cases()
	_choice_cases()
	_lobby_cases()
	print("RESULT rejected_request_correlation checks=%d failures=%d" % [checks, failures.size()])
	for failure in failures: print("FAIL ", failure)
	get_tree().quit(0 if failures.is_empty() else 1)

func _approve(session: FakeSession) -> void:
	var item: Dictionary = session.sent.back()
	session.group_preview_received.emit(item.args.request_id, {"ok": true, "view_seq": 8, "can_submit": true, "candidates": [{"id": 11, "modes": [false]}]})

func _group_cases() -> void:
	var session := FakeSession.new()
	var group = Group.new()
	group.bind_session(session)
	_approve(session)
	_check(group.add(11, false), "真实 add 入口发出组合预览")
	_approve(session)
	_check(group.confirm(), "真实 confirm 入口提交")
	var first_submit: int = session.seq
	session.request("ready", {"ready": true})
	session.reject(session.seq)
	_check(group.snapshot().submitted, "RED: 大厅拒绝不得解锁组合提交")
	_check(not group.confirm(), "RED: 他请求拒绝之后仍禁止再次确认")
	session.reject(first_submit)
	_check(not group.snapshot().submitted, "GREEN: 本次提交拒绝解除自己的锁")
	_check(group.confirm(), "手动再次提交，不自动重试")
	var second_submit: int = session.seq
	session.reject(first_submit)
	_check(group.snapshot().submitted, "RED: 旧提交迟到拒绝不得解锁新提交")
	session.reject(second_submit)
	_check(group.remove(11), "撤选产生新预览")
	var first_preview: int = session.seq
	_check(group.remove(11) == false, "不存在牌不生成请求")
	# 新视图会废弃旧预览并主动查询，只由状态变化驱动，非拒绝重试。
	session.match_view.seq = 9
	session.changed.emit()
	var current_preview: int = session.seq
	session.reject(first_preview)
	_check(group.snapshot().waiting, "迟到预览拒绝不得解锁最新预览")
	session.reject(current_preview)
	_check(not group.snapshot().waiting, "RED: 本次 preview 外层协议拒绝必须解除等待")
	session.group_preview_received.emit(session.sent.back().args.request_id, {"ok": true, "view_seq": 9, "can_submit": true})
	_check(not group.can_confirm(), "结束的预览不得被迟到成功回执复活")
	group.bind_session(null)
	var sync := FakeSession.new()
	sync.sync_reject = true
	group.bind_session(sync)
	_check(not group.snapshot().waiting, "RED: 发送前登记，同步预览拒绝不丢失")
	group.bind_session(null)
	var immediate := FakeSession.new()
	group.bind_session(immediate)
	_approve(immediate)
	immediate.sync_reject = true
	_check(group.confirm(), "同步业务拒绝与传输成功分开")
	_check(not group.snapshot().submitted, "同步提交拒绝解除自己的锁")
	group.bind_session(null)
	var offline := FakeSession.new()
	offline.local_failure = true
	group.bind_session(offline)
	_check(not group.snapshot().waiting, "本地发送失败不永久卡预览")
	group.bind_session(null)

func _ensure_path(board: Node, path: String, leaf: Node) -> void:
	var parts := path.split("/")
	var parent: Node = board
	for index in parts.size() - 1:
		var child := parent.get_node_or_null(NodePath(parts[index]))
		if child == null:
			child = Control.new()
			child.name = parts[index]
			parent.add_child(child)
		parent = child
	leaf.name = parts[parts.size() - 1]
	parent.add_child(leaf)

func _board() -> BoardStub:
	var board := BoardStub.new()
	for path in ["Main", "Events", "Seats", "Rivals", "Situation", "Piles", "Route", "Board", "Hand", "AreaTitle", "Hint", "Self/Spells", "Self/Me", "Self/CountBadge", "Master", "Top/Center/Dots", "Top/Center/Phases", "Banner/Avatar", "NetworkChoices/Guard/Margin/Row/Actions", "NetworkChoices/Guard/Margin/Row/Waiting", "NetworkChoices/Guard/Margin/Row/RestartChoices"]:
		_ensure_path(board, path, Control.new())
	for path in ["Top/Center/NightLabel", "Top/Center/RoundLabel", "Banner/Text", "NetworkChoices/Guard/Margin/Row/Message"]:
		_ensure_path(board, path, Label.new())
	for path in ["Ops/PlayButton", "Ops/EndButton", "Top/BoardButton", "Top/LogButton", "NetworkChoices/Guard/Margin/Row/Actions/Skip", "NetworkChoices/Guard/Margin/Row/Actions/Restart", "NetworkChoices/Guard/Margin/Row/RestartChoices/Current", "NetworkChoices/Guard/Margin/Row/RestartChoices/Lobby", "NetworkChoices/Guard/Margin/Row/RestartChoices/Cancel", "NetworkChoices/ConnectionWait/Margin/Row/Reconnect", "Piles/EventPile/Open"]:
		_ensure_path(board, path, Button.new())
	_ensure_path(board, "Ops/Discard", Control.new())
	_ensure_path(board, "NetworkChoices/Panel", ChoiceStub.new())
	return board

func _guard_cases() -> void:
	var session := FakeSession.new()
	var board := _board()
	var presenter = Presenter.new(board, session)
	presenter._sequence = 8
	presenter._request_guard_action("guard_skip")
	var own: int = session.seq
	session.request("match_command", {"command": "end_action"})
	session.reject(session.seq)
	_check(presenter._guard_requested_seq == 8, "RED: 其他对局请求拒绝不得解锁 guard")
	var before: int = session.sent.size()
	presenter._request_guard_action("guard_restart")
	_check(session.sent.size() == before, "guard 锁仍挡住第二提交")
	session.reject(own)
	_check(presenter._guard_requested_seq == -1, "本次 guard 拒绝解除自己的锁")
	presenter._request_guard_action("guard_restart")
	var second: int = session.seq
	session.reject(own)
	_check(presenter._guard_requested_seq == 8, "旧 guard 拒绝不得解锁新 guard")
	session.reject(second)
	session.sync_reject = true
	presenter._request_guard_action("guard_lobby")
	_check(presenter._guard_requested_seq == -1, "同步 guard 回执不丢失")
	presenter.release()
	board.free()

func _choice_cases() -> void:
	var session := FakeSession.new()
	session.pending = {"kind": "active_choice", "effect": 77, "label": "待答", "allow_cancel": true, "options": []}
	var panel = Choice.new()
	for path in ["Content/Actions/Confirm", "Content/Actions/Decline"]: _ensure_path(panel, path, Button.new())
	for path in ["Content/Title", "Content/Status"]: _ensure_path(panel, path, Label.new())
	_ensure_path(panel, "Content/Targets", ItemList.new())
	_ensure_path(panel, "Content/Options", VBoxContainer.new())
	add_child(panel)
	panel.bind_session(session)
	panel._submit(true)
	var own: int = session.seq
	session.changed.emit()
	_check(panel._submitted and panel.get_node("Content/Actions/Confirm").disabled, "无关 changed 保留私有待答提交锁")
	session.rejected.emit("旧服务端无 seq 错误")
	session.changed.emit()
	_check(panel._submitted, "旧无 seq 错误只提示，不解锁私有待答")
	session.request("ready", {})
	session.reject(session.seq)
	_check(panel._submitted, "RED: 他请求拒绝与 changed 不得解锁私有待答")
	session.reject(own)
	_check(not panel._submitted, "本次待答拒绝解除自己的锁")
	panel._submit(true)
	session.reject(own)
	_check(panel._submitted, "旧待答拒绝不得解锁新待答")
	session.reject(session.seq)
	session.sync_reject = true
	panel._submit(true)
	_check(not panel._submitted, "同步私有待答回执在发送前登记后精确解锁")
	session.sync_reject = false
	session.local_failure = true
	panel._submit(true)
	_check(not panel._submitted, "本地发送失败不永久锁住私有待答")
	session.local_failure = false
	panel._submit(true)
	session.match_view.seq += 1
	session.changed.emit()
	_check(not panel._submitted, "真实新视图废弃旧待答请求锁")
	panel.bind_session(null)
	panel.free()

func _lobby_cases() -> void:
	var lobby = Lobby.new()
	var receipt: Array = []
	if lobby.has_signal("request_rejected"):
		lobby.connect("request_rejected", func(sequence, reason): receipt.append([sequence, reason]))
	lobby._host = true
	lobby.room.members[1] = {"connected": true}
	lobby.room.phase = "playing"
	lobby.management_paused = true
	var registered: Array = []
	if lobby.has_signal("request_rejected"):
		lobby.request("match_command", {"view_seq": 1, "command": "play_group", "params": {}}, func(sequence): registered.append(sequence))
	else:
		lobby.request("match_command", {"view_seq": 1, "command": "play_group", "params": {}})
	_check(receipt.size() == 1 and registered.size() == 1 and receipt[0][0] == registered[0], "RED: 真实 Lobby 同步暂停拒绝保留请求序号")
	receipt.clear()
	lobby._host = false
	lobby._receive(2, {"kind": "error", "seq": 7, "reason": "伪造来源"})
	_check(receipt.is_empty(), "非房主来源不能产生精确拒绝")
	lobby._receive(1, {"kind": "error", "seq": 7, "reason": "权威拒绝"})
	_check(receipt.size() == 1 and receipt[0][0] == 7, "RED: 真实客户端读取 error.seq")
	receipt.clear()
	lobby._receive(1, {"kind": "error", "reason": "无关联通知"})
	lobby._receive(1, {"kind": "error", "seq": "7", "reason": "错误类型"})
	_check(receipt.is_empty(), "缺失或错误类型 seq 只发普通错误，不解锁请求")
	lobby.transport.close()
