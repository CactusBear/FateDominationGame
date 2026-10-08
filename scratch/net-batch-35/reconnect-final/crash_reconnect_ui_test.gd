extends "res://scripts/net/ui/lobby_screen.gd"

## 真实 Button.pressed 入口；session 使用生产 MatchLobbySession，host 仅替身网络边界。
class CrashHost:
	extends RefCounted
	var waiting:bool
	var recovery_result:bool
	var recover_calls:int = 0

	func _init(is_waiting:bool, result:bool) -> void:
		waiting = is_waiting
		recovery_result = result

	func diagnostics() -> Dictionary:
		return {"worker_crash_waiting": waiting}

	func recover_worker() -> bool:
		recover_calls += 1
		return recovery_result

	func poll() -> void:
		pass

	func close() -> void:
		pass

var _refresh_count:int = 0
var _failures:Array[String] = []

func _ready() -> void:
	set_process(false)
	$Margin/Content/Reconnect.pressed.connect(_reconnect)
	await _case_recovery_then_wait_for_poll()
	await _case_wrong_key_is_sanitized()
	await _case_without_worker_crash_uses_normal_reconnect()
	if _failures.is_empty():
		print("RESULT crash_reconnect_ui_test PASS checks=7")
	else:
		for failure in _failures:
			push_error(failure)
		print("RESULT crash_reconnect_ui_test FAIL checks=%d" % (7 - _failures.size()))
	get_tree().quit(0 if _failures.is_empty() else 1)

func _refresh_reconnect() -> void:
	_refresh_count += 1

func _press(session_value) -> void:
	session = session_value
	$Margin/Content/Reconnect.emit_signal("pressed")
	await get_tree().process_frame

func _new_session(host:CrashHost):
	var value = load("res://scripts/net/session/lobby_session.gd").new()
	value.authority_host = host
	return value

func _case_recovery_then_wait_for_poll() -> void:
	var host := CrashHost.new(true, true)
	var value = _new_session(host)
	await _press(value)
	_check(host.recover_calls == 1, "worker 崩溃等待状态必须先调用既有 recover_worker")
	_check(value.error.is_empty(), "恢复成功不得写入错误")
	_check(_refresh_count == 1, "真实 Button 入口必须刷新重连 UI")

func _case_wrong_key_is_sanitized() -> void:
	var host := CrashHost.new(true, false)
	var value = _new_session(host)
	await _press(value)
	_check(host.recover_calls == 1, "恢复拒绝仍需经过既有恢复入口")
	_check(value.error.begins_with("无法重新连接："), "错密钥拒绝只显示脱敏通用文案")

func _case_without_worker_crash_uses_normal_reconnect() -> void:
	var host := CrashHost.new(false, false)
	var value = _new_session(host)
	await _press(value)
	_check(host.recover_calls == 0, "非崩溃状态不得调用恢复")
	_check(not value.can_reconnect(), "非崩溃状态仍走原 reconnect 且不伪造成功")

func _check(condition:bool, message:String) -> void:
	if not condition:
		_failures.append(message)
