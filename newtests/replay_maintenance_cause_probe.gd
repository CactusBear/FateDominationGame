extends SceneTree

const ReplaySeam = preload("res://replay_seam.gd")
const Diagnostic = preload("res://diagnostic_seam.gd")
const Journal = preload("res://scripts/match/match_journal.gd")
var checks:int = 0
var failures:Array = []

func check(value:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", value)
	if not value: failures.append(label)

func _initialize() -> void:
	print("USER_DATA_PATH ", OS.get_user_data_dir())
	var replay = ReplaySeam.new()
	var diagnostic = Diagnostic.new()
	diagnostic.replay = replay
	var path:String = "user://maintenance-only.txt"
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("maintenance-only")
	file.close()
	check(Journal.reset_audit_memory(), "audit starts clean")
	Diagnostic.deadline = Time.get_ticks_msec() + 600000
	var digest:String = replay._file_hash(path, replay._maintenance_callback(diagnostic.maintain))
	check(not digest.is_empty() and replay.error.is_empty(), "future deadline allows real hash")
	var audit_revision:int = Journal.audit_revision
	var audit_identity:int = Journal._audit_identity
	Diagnostic.deadline = Time.get_ticks_msec() - 1
	diagnostic.last_index = -2
	digest = replay._file_hash(path, replay._maintenance_callback(diagnostic.maintain))
	check(digest.is_empty(), "expired deadline aborts before file read")
	check(replay.error == "维护回调取消了存档操作", "expired callback emits exact product message")
	check(Journal.audit_revision == audit_revision and Journal._audit_identity == audit_identity, "expired cancel needs no audit generation change")
	replay.error = ""
	diagnostic.last_index = -2
	digest = replay._file_hash(path, replay._maintenance_callback(diagnostic.maintain))
	check(digest.is_empty() and replay.error == "维护回调取消了存档操作", "retry with expired shared deadline cancels immediately")
	replay.error = ""
	digest = replay._file_hash(path)
	check(not digest.is_empty() and replay.error.is_empty(), "absent callback ignores fixture deadline")
	replay.error = ""
	Diagnostic.deadline = Time.get_ticks_msec() + 600000
	digest = replay._file_hash(path, replay._maintenance_callback(diagnostic.maintain))
	check(not digest.is_empty() and replay.error.is_empty(), "renewed deadline allows same seam without product patch")
	replay.error = ""
	var changed:Callable = func() -> bool:
		Journal._audit_identity += 1
		return false
	check(not replay._tick(replay._maintenance_callback(changed)), "audit mutation rejects callback")
	check(replay.error == "维护回调修改了事务审计，拒绝继续恢复", "audit generation change has different message")
	print("RESULT checks=", checks, " failures=", JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)
