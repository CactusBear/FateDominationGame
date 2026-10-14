extends Node

var checks := 0
var failures: Array = []
var path := "user://p1-journal-test.log"

func _ready() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
	print("CHECK ", label, " ", ok)

func finish() -> void:
	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func run() -> void:
	var source := "res://scripts/match/match_journal.gd"
	check(FileAccess.file_exists(source), "journal implementation exists")
	if not FileAccess.file_exists(source):
		finish()
		return
	var journal = load(source).new()
	check(journal.create(path, {"seed": 9223372036854775806, "ids": [7, 99]}), "create journal")
	check(journal.append({"kind": "move", "args": [7, 1]}), "append first action")
	check(journal.append({"kind": "wait", "args": []}), "append second action")
	journal.close()
	var result: Dictionary = journal.read_all(path)
	check(result.ok and result.records.size() == 3, "all committed records read")
	check(result.records[0].seed == 9223372036854775806, "integer seed preserves 64 bits")
	check(result.records[1].args == [7, 1], "arguments round trip")
	var bytes := FileAccess.get_file_as_bytes(path)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes.slice(0, bytes.size() - 5))
	f.close()
	result = journal.read_all(path)
	check(result.ok and result.truncated and result.records.size() == 2, "partial final frame recovers committed prefix")
	f = FileAccess.open(path, FileAccess.WRITE)
	bytes[bytes.size() - 8] ^= 1
	f.store_buffer(bytes)
	f.close()
	result = journal.read_all(path)
	check(not result.ok and result.error_index == 2, "corrupted complete frame rejected at exact index")
	DirAccess.remove_absolute(path)
	finish()
