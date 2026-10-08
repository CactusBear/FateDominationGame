extends Node

# 专项反例：只替换写入器/检查点边界，调用真实 EffectManager 与 Authority 消费者。
# 本轮仅交付源码；须在主代理全部写入者退出后串行执行。
class FaultWriter extends RefCounted:
	var error:String = ""
	var fail_event:String = ""
	var fail_flush:bool = false
	func append(record:Dictionary) -> bool:
		if record.event == fail_event:
			error = "专项注入 append 失败"
			return false
		return true
	func flush() -> bool:
		if fail_flush:
			error = "专项注入 flush 失败"
			return false
		return true

class AuditOwner extends RefCounted:
	var root:BaseEffect
	var transaction_id:int = 101
	var ready:bool = true
	var settled:bool = false
	var restores:int = 0
	func _init(effect:BaseEffect) -> void:
		root = effect
	func audit(event:String, _effect:BaseEffect = null, reason:String = "", _parent:BaseEffect = null) -> bool:
		return MatchJournal.audit_event(event, {"root_id":transaction_id, "effect_id":transaction_id, "reason":reason})
	func restore() -> bool:
		restores += 1
		return true

class FaultRecorder extends RefCounted:
	var _recording:bool = true
	var error:String = ""
	var closed:bool = false
	func perform(_kind:String, _args:Array):
		error = "专项注入录制提交失败"
		return true
	func close() -> void:
		closed = true
		_recording = false

class SubmitAuthority extends NetworkMatchAuthority:
	var writer
	func _submit(_peer:int, _sequence:int, _kind:String, _args:Dictionary) -> bool:
		writer.fail_flush = true
		return true

var failures:int = 0
var checks:int = 0
var tail_calls:int = 0

func _check(condition:bool, label:String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func _reset() -> void:
	MatchJournal.audit_writer = null
	MatchJournal.reset_audit_memory()
	EffectManager._runtime_guard.paused = false
	EffectManager._runtime_guard.reason = ""
	EffectManager._guard_run = {}
	EffectManager._guard_transactions.clear()
	EffectManager._transaction_scope = null
	EffectManager._guard_continuations.clear()
	EffectManager._continuation_transactions.clear()
	EffectManager._batch_transactions.clear()
	EffectManager._active_runs.clear()
	EffectManager._paused_runs.clear()
	EffectManager._pending_choices.clear()
	EffectManager.decision_queue.clear()
	EffectManager.activation_pool.clear()
	EffectManager.waiting_effect = null
	EffectManager.waiting_selection = null
	EffectManager.waiting_location = null
	EffectManager.waiting_players = null
	EffectManager.is_running = false
	GameLog._fact_delivery.reset()

func _tail() -> void:
	tail_calls += 1

func _ready() -> void:
	_reset()
	var writer := FaultWriter.new()
	writer.fail_event = "start"
	MatchJournal.audit_writer = writer
	var effect := BaseEffect.new()
	_check(not EffectManager._begin_guard_transaction(effect), "start append 失败不得接受根事务")
	_check(EffectManager.runtime_guard_status().paused, "start 失败必须暂停")

	_reset()
	writer = FaultWriter.new()
	writer.fail_event = "child"
	MatchJournal.audit_writer = writer
	EffectManager._transaction_scope = AuditOwner.new(effect)
	_check(not EffectManager._inherit_guard_transaction(BaseEffect.new()), "child append 失败不得接受子事务")

	_reset()
	writer = FaultWriter.new()
	writer.fail_event = "tail_registered"
	MatchJournal.audit_writer = writer
	EffectManager._runtime_guard.paused = true
	_check(EffectManager.defer_until_runtime_guard_complete(_tail), "登记失败仍必须拦住调用方同步尾部")
	EffectManager._drain_guard_continuations()
	_check(tail_calls == 0 and EffectManager._guard_continuations.size() == 1, "登记写失败不得执行或丢弃尾部")
	_check(not MatchJournal.audit_error.is_empty(), "延期布尔值不是审计成功回执")

	_reset()
	writer = FaultWriter.new()
	writer.fail_event = "commit"
	MatchJournal.audit_writer = writer
	var owner := AuditOwner.new(effect)
	EffectManager._guard_transactions[effect] = owner
	GameLog.begin_fact_transaction(owner.transaction_id)
	var token:Dictionary = GameLog._fact_delivery._transactions[owner.transaction_id]
	EffectManager._settle_idle_guard_transactions()
	_check(not owner.settled and token.state == "pending", "commit append 失败不得放行事实 generation")
	_check(EffectManager._guard_transactions.has(effect), "commit 失败必须保留事务")

	_reset()
	writer = FaultWriter.new()
	writer.fail_event = "commit"
	MatchJournal.audit_writer = writer
	owner = AuditOwner.new(effect)
	EffectManager._guard_transactions[effect] = owner
	GameLog.begin_fact_transaction(owner.transaction_id)
	token = GameLog._fact_delivery._transactions[owner.transaction_id]
	EffectManager._release_guard_transactions()
	_check(not owner.settled and token.state == "pending", "整批释放路径 commit 失败不得放行 generation")

	_reset()
	writer = FaultWriter.new()
	writer.fail_event = "resume"
	MatchJournal.audit_writer = writer
	owner = AuditOwner.new(effect)
	EffectManager._guard_transactions[effect] = owner
	EffectManager._runtime_guard.paused = true
	EffectManager._guard_run = {"effect":effect}
	_check(not EffectManager.resume_runtime_guard(), "resume append 失败不得报告成功")
	_check(EffectManager.runtime_guard_status().paused and not EffectManager._guard_run.is_empty(), "resume 失败必须保留暂停片")

	_reset()
	writer = FaultWriter.new()
	writer.fail_event = "rollback_intent"
	MatchJournal.audit_writer = writer
	owner = AuditOwner.new(effect)
	EffectManager._guard_transactions[effect] = owner
	EffectManager._runtime_guard.paused = true
	EffectManager._guard_run = {"effect":effect}
	_check(not EffectManager.skip_runtime_guard() and owner.restores == 0, "intent 写失败不得执行恢复")

	_reset()
	writer = FaultWriter.new()
	writer.fail_event = "rollback"
	MatchJournal.audit_writer = writer
	owner = AuditOwner.new(effect)
	EffectManager._guard_transactions[effect] = owner
	EffectManager._runtime_guard.paused = true
	EffectManager._guard_run = {"effect":effect}
	GameLog.begin_fact_transaction(owner.transaction_id)
	token = GameLog._fact_delivery._transactions[owner.transaction_id]
	_check(not EffectManager.skip_runtime_guard(), "rollback 完成回执写失败不得报告成功")
	_check(owner.restores == 1 and token.state == "aborted", "规则已恢复时旧事实 generation 必须 abort")

	_reset()
	writer = FaultWriter.new()
	MatchJournal.audit_writer = writer
	var authority := SubmitAuthority.new()
	authority.writer = writer
	_check(not authority.submit(1, 1, "fault", {}), "动作返回 true 后 flush 失败不得伪报成功")
	_check(authority._revision > 0 and not authority.error.is_empty(), "写失败必须废弃旧视图并给出原因")

	_reset()
	var recorded := NetworkMatchAuthority.new()
	var fault_recorder := FaultRecorder.new()
	recorded.recorder = fault_recorder
	_check(not bool(recorded._run_recorded_driver("fault")), "perform 返回 true 但录制失败不得报告成功")
	_check(fault_recorder.closed and not recorded.error.is_empty(), "失败必须关闭录制且保留原因")
	_reset()
	print("RESULT transaction_return_consumers checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
