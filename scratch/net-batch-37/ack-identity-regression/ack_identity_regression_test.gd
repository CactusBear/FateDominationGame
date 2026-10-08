extends Node

const LobbySession = preload("res://scripts/net/session/lobby_session.gd")
const IdentityBridge = preload("res://scripts/net/server/lan_worker_identity_bridge.gd")
const Channel = preload("res://scripts/net/server/server_console_channel.gd")

class FakeTransport:
	extends RefCounted
	var disconnected:Array[int] = []
	func disconnect_peer(peer:int) -> void:
		disconnected.append(peer)

class FakeLedger:
	extends RefCounted
	var sequence:int = 1
	func last_sequence() -> int:
		return sequence
	func context_for(peer:int, nonce:String, member:int) -> Dictionary:
		return {"peer":peer,"nonce":nonce,"member":member}

class FakeControl:
	extends RefCounted
	var identity_receipt_sequence:int = 1

class FakeSession:
	extends RefCounted
	var transport := FakeTransport.new()
	var _member_by_peer:Dictionary = {}
	var _restore_in_progress:bool = false
	var received:Array = []
	func _receive(peer:int, message:Dictionary) -> void:
		received.append({"peer":peer,"message":message.duplicate(true)})

var _failures:Array[String] = []
var _checks:int = 0
var _output_dir:String = "res://scratch/net-batch-37/ack-identity-regression"
var _evidence:Dictionary = {"cases":[], "module_paths": ["scripts/net/session/lobby_session.gd", "scripts/net/server/lan_worker_identity_bridge.gd"]}

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output_dir))
	await _run_ack_cases()
	await _run_identity_cases()
	_write_evidence()
	if _failures.is_empty():
		print("RESULT ack_identity_regression PASS checks=%d" % _checks)
	else:
		for failure in _failures:
			push_error(failure)
		print("RESULT ack_identity_regression FAIL checks=%d failures=%d" % [_checks, _failures.size()])
	get_tree().quit(0 if _failures.is_empty() else 1)

func _run_ack_cases() -> void:
	var session = LobbySession.new()
	session._host = true
	session.authority_host_mode = ""
	_check(session.room.configure(1, {"capacity":2,"minimum":1,"ai_count":0,"spectator_limit":0}), "真实 RoomState 初始化")
	_check(session.room.join(1, "host"), "真实 RoomState 加入房主")
	session.data_revision = 5
	session.room.error = "旧请求错误"

	var before_revision:int = session.room.revision
	var before_confirmed:Dictionary = session._data_confirmed.duplicate(true)
	_receive_ack(session, 1, 4)
	_check(session.room.revision == before_revision, "旧 ACK 不推进房间修订")
	_check(session._data_confirmed == before_confirmed, "旧 ACK 不确认新版本")
	_check(session.room.error.is_empty(), "旧 room.error 不串入后续请求")
	_evidence.cases.append({"name":"old_ack_no_confirm", "pass":true})

	_receive_ack(session, 2, 5)
	_check(session._data_confirmed.get(1, -1) == 5, "当前 ACK 确认当前数据版本")
	_check(session.room.revision == before_revision + 1, "当前 ACK 只推进一次房间修订")
	_evidence.cases.append({"name":"current_ack_confirm", "pass":true})

	var confirmed_after_current:Dictionary = session._data_confirmed.duplicate(true)
	var revision_after_current:int = session.room.revision
	_receive_ack(session, 3, 6)
	_check(session._data_confirmed == confirmed_after_current, "未来 ACK 不得确认")
	_check(session.room.revision == revision_after_current, "未来 ACK 不得推进修订")
	_check(session.error == "请求无效", "未来 ACK 使用当前请求错误而非旧错误")
	_receive_ack(session, 4, -1)
	_check(session._data_confirmed == confirmed_after_current, "非法负 ACK 不得确认")
	_check(session.room.revision == revision_after_current, "非法负 ACK 不得推进修订")
	_receive_ack_variant(session, 5, "5")
	_check(session._data_confirmed == confirmed_after_current, "非法类型 ACK 不得确认")
	_check(session.room.revision == revision_after_current, "非法类型 ACK 不得推进修订")
	_evidence.cases.append({"name":"future_and_invalid_ack_rejected", "pass":true})

func _receive_ack(session, sequence:int, revision:int) -> void:
	session._receive(1, {"v":1,"seq":sequence,"kind":"data_ack","args":{"revision":revision}})

func _receive_ack_variant(session, sequence:int, revision:String) -> void:
	session._receive(1, {"v":1,"seq":sequence,"kind":"data_ack","args":{"revision":revision}})

func _run_identity_cases() -> void:
	var bridge = IdentityBridge.new()
	var fake_session := FakeSession.new()
	bridge.session = fake_session
	bridge._control = FakeControl.new()
	bridge.ledger = FakeLedger.new()
	bridge.binding = {"room":"room-test","instance":"instance-test"}
	bridge.path = _output_dir.path_join("identity-observed.json")
	bridge.observed[7] = "nonce-7"
	bridge._published = ""
	bridge.max_pending_bytes = 100000
	bridge.timeout_msec = 1
	fake_session._member_by_peer[7] = 42
	bridge.pending[7] = [{"kind":"join","payload":"authenticated-pending"}]
	bridge.deadlines[7] = Time.get_ticks_msec() - 1
	fake_session._restore_in_progress = false
	bridge.poll()
	_check(fake_session.received.size() == 1, "已认证 pending 即使过 deadline 仍可处理")
	_check(bridge.pending.get(7, []).is_empty(), "已认证 pending 处理后才出队")
	_check(fake_session.transport.disconnected.is_empty(), "已认证 pending 不因 deadline 断开")
	_evidence.cases.append({"name":"authenticated_pending_after_deadline", "pass":true})

	var unauth_bridge = _new_bridge_for_case(8, false)
	unauth_bridge.session._member_by_peer.clear()
	unauth_bridge.pending[8] = [{"kind":"join","payload":"unauthenticated"}]
	unauth_bridge.deadlines[8] = Time.get_ticks_msec() - 1
	unauth_bridge.poll()
	_check(unauth_bridge.session.received.is_empty(), "未认证 pending 过 deadline 不得处理")
	_check(unauth_bridge.session.transport.disconnected == [8], "未认证 pending 仍按原 deadline 超时")
	_evidence.cases.append({"name":"unauthenticated_deadline_timeout", "pass":true})

	var restoring_bridge = _new_bridge_for_case(9, true)
	restoring_bridge.pending[9] = [{"kind":"match_command","payload":"must-survive-restore"}]
	restoring_bridge.deadlines[9] = Time.get_ticks_msec() - 1
	restoring_bridge.poll()
	_check(restoring_bridge.session.received.is_empty(), "恢复期间不处理业务 pending")
	_check(restoring_bridge.pending.has(9) and restoring_bridge.pending[9].size() == 1, "恢复期间 pending 不弹出丢消息")
	_check(restoring_bridge.session.transport.disconnected.is_empty(), "恢复期间不因 deadline 丢弃已认证消息")
	_evidence.cases.append({"name":"restore_pending_retained", "pass":true})

func _new_bridge_for_case(peer:int, restoring:bool):
	var bridge = IdentityBridge.new()
	var fake_session := FakeSession.new()
	fake_session._member_by_peer[peer] = peer + 100
	fake_session._restore_in_progress = restoring
	bridge.session = fake_session
	bridge._control = FakeControl.new()
	bridge.ledger = FakeLedger.new()
	bridge.binding = {"room":"room-test","instance":"instance-test"}
	bridge.path = _output_dir.path_join("identity-observed-%d.json" % peer)
	bridge.observed[peer] = "nonce-%d" % peer
	bridge.max_pending_bytes = 100000
	return bridge

func _write_evidence() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output_dir))
	var file := FileAccess.open(_output_dir.path_join("runtime_evidence.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"checks":_checks,"failures":_failures,"cases":_evidence.cases,"modules":_evidence.module_paths}, "  "))
		file.flush()
		file.close()

func _check(condition:bool, message:String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
