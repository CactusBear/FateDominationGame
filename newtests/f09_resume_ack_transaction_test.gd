extends Node

const TRANSACTION_PATH:String = "res://scripts/net/identity/resume_ack_transaction.gd"
var checks:int = 0
var failures:Array = []

class Persistence extends RefCounted:
	var calls:int = 0
	var previous:Dictionary
	var saw_removed:bool = false
	var path:String = "user://resume_ack_transaction_synthetic.json"
	func _init(state:Dictionary) -> void:
		previous = state
	func save() -> bool:
		calls += 1
		saw_removed = not previous.has(7)
		var file = FileAccess.open(path,FileAccess.WRITE)
		if file == null: return false
		file.store_string(JSON.stringify(previous))
		file.close()
		return true
	func reject() -> bool:
		calls += 1
		saw_removed = not previous.has(7)
		return false
	func accept_without_file() -> bool:
		calls += 1
		saw_removed = not previous.has(7)
		return true

func check(condition:bool, label:String) -> void:
	checks += 1
	if not condition: failures.append(label)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	if not ResourceLoader.exists(TRANSACTION_PATH):
		check(false,"确认事务入口缺失")
		finish()
		return
	var transaction = load(TRANSACTION_PATH)
	var token:String = "synthetic-ack-fixture"
	var previous:Dictionary = {7:"synthetic-previous",8:"synthetic-other"}
	var persistence = Persistence.new(previous)
	var result:int = transaction.acknowledge(7,token,token.sha256_text(),previous,persistence.save)
	check(result == transaction.Status.CONFIRMED,"匹配成功回执")
	check(not previous.has(7) and previous.get(8) == "synthetic-other","仅删除目标旧状态")
	check(persistence.calls == 1 and persistence.saw_removed,"保存恰一次且观察到删除后状态")
	var saved = JSON.parse_string(FileAccess.get_file_as_string(persistence.path))
	check(saved is Dictionary and not saved.has("7") and saved.get("8") == "synthetic-other","真实落盘状态仅删除目标")
	check(DirAccess.remove_absolute(ProjectSettings.globalize_path(persistence.path)) == OK,"清理自造保存文件")
	result = transaction.acknowledge(7,token,token.sha256_text(),previous,persistence.save)
	check(result == transaction.Status.UNMATCHED and persistence.calls == 1,"重复确认静默且不再次保存")

	var exact_previous:String = "  SYNTHETIC/旧状态\nCaseSensitive  "
	var rejected:Dictionary = {7:exact_previous,8:"synthetic-other"}
	var before:Dictionary = rejected.duplicate(true)
	var alias:Dictionary = rejected
	var refusal = Persistence.new(rejected)
	result = transaction.acknowledge(7,token,token.sha256_text(),rejected,refusal.reject)
	check(result == transaction.Status.PERSIST_FAILED,"保存拒绝与未匹配回执分离")
	check(refusal.calls == 1 and refusal.saw_removed,"保存拒绝恰一次且先删除")
	check(rejected == before and alias == before and is_same(alias,rejected),"保存拒绝原字典及exact previous复原")
	result = transaction.acknowledge(7,token,token.sha256_text(),rejected,refusal.accept_without_file)
	check(result == transaction.Status.CONFIRMED and refusal.calls == 2 and not rejected.has(7),"失败后原凭据可原样重新确认")

	var skipped:Dictionary = {7:exact_previous,8:"synthetic-other"}
	var skipped_before:Dictionary = skipped.duplicate(true)
	var no_calls = Persistence.new(skipped)
	result = transaction.acknowledge(7,"synthetic-wrong",token.sha256_text(),skipped,no_calls.reject)
	check(result == transaction.Status.UNMATCHED and skipped == skipped_before and no_calls.calls == 0,"错凭据静默且无状态或保存副作用")
	for wrong_type in [null,7,7.0,true,[],{},StringName(token),token.to_utf8_buffer()]:
		result = transaction.acknowledge(7,wrong_type,token.sha256_text(),skipped,no_calls.reject)
		check(result == transaction.Status.UNMATCHED and skipped == skipped_before and no_calls.calls == 0,"非String不转换且静默无副作用")
	result = transaction.acknowledge(7,token,"",skipped,no_calls.reject)
	check(result == transaction.Status.UNMATCHED and skipped == skipped_before and no_calls.calls == 0,"缺当前凭据哈希不匹配")
	var missing_previous:Dictionary = {8:"synthetic-other","7":exact_previous}
	var missing_before:Dictionary = missing_previous.duplicate(true)
	var absent = Persistence.new(missing_previous)
	result = transaction.acknowledge(7,token,token.sha256_text(),missing_previous,absent.reject)
	check(result == transaction.Status.UNMATCHED and missing_previous == missing_before and absent.calls == 0,"无previous静默且不转换成员键")
	result = transaction.acknowledge(9,token,token.sha256_text(),skipped,no_calls.reject)
	check(result == transaction.Status.UNMATCHED and skipped == skipped_before and no_calls.calls == 0,"只确认指定成员不扫描其他成员")

	var no_path:Dictionary = {7:exact_previous,8:"synthetic-other"}
	var explicit_success = Persistence.new(no_path)
	result = transaction.acknowledge(7,token,token.sha256_text(),no_path,explicit_success.accept_without_file)
	check(result == transaction.Status.CONFIRMED and no_path == {8:"synthetic-other"} and explicit_success.calls == 1,"调用方显式无存档成功能力")
	var invalid_persist:Dictionary = {7:exact_previous,8:"synthetic-other"}
	result = transaction.acknowledge(7,token,token.sha256_text(),invalid_persist,Callable())
	check(result == transaction.Status.PERSIST_FAILED and invalid_persist == skipped_before,"缺保存能力不得隐式成功且原状态保留")
	finish()

func finish() -> void:
	print("RESULT " + JSON.stringify({"suite":"f09_resume_ack_transaction","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
