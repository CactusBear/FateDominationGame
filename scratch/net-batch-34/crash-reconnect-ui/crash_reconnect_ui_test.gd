extends "res://scripts/net/ui/lobby_screen.gd"

## 真实 Control/Button 入口测试：不直接调用 recover_worker()。
## 通过 Reconnect.pressed 进入生产 _reconnect()，用最小 session double 隔离网络。
class CrashHost:
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

class UiSession:
	var authority_host
	var error:String = ""
	var reconnect_calls:int = 0
	var result:Error = OK

	func reconnect_after_worker_crash() -> Error:
		if authority_host != null and authority_host.diagnostics().get("worker_crash_waiting", false):
			if not authority_host.recover_worker():
				error = "本机权威恢复未获批准"
				return ERR_UNAUTHORIZED
			error = ""
		reconnect_calls += 1
		return result

var _refresh_count:int = 0
var _failures:Array[String] = []

func _ready() -> void:
	$Margin/Content/Reconnect.pressed.connect(_reconnect)
	await _case_recovery_then_reconnect()
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

func _press(session_value:UiSession) -> void:
	session = session_value
	$Margin/Content/Reconnect.emit_signal("pressed")
	await get_tree().process_frame

func _case_recovery_then_reconnect() -> void:
	var host := CrashHost.new(true, true)
	var value := UiSession.new()
	value.authority_host = host
	await _press(value)
	_check(host.recover_calls == 1, "worker 崩溃等待状态必须先调用既有 recover_worker")
	_check(value.reconnect_calls == 1, "恢复成功后才允许进入原 reconnect")

func _case_wrong_key_is_sanitized() -> void:
	var host := CrashHost.new(true, false)
	var value := UiSession.new()
	value.authority_host = host
	await _press(value)
	_check(host.recover_calls == 1, "恢复拒绝仍需经过既有恢复入口")
	_check(value.reconnect_calls == 0, "恢复拒绝不得继续重连")
	_check(value.error == "本机权威恢复未获批准", "错密钥拒绝只显示脱敏通用文案")

func _case_without_worker_crash_uses_normal_reconnect() -> void:
	var host := CrashHost.new(false, false)
	var value := UiSession.new()
	value.authority_host = host
	await _press(value)
	_check(host.recover_calls == 0, "非崩溃状态不得调用恢复")
	_check(value.reconnect_calls == 1, "非崩溃状态保持原重连路径")

func _check(condition:bool, message:String) -> void:
	if not condition:
		_failures.append(message)
