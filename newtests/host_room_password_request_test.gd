extends Node

const Password = preload("res://scripts/net/identity/room_password.gd")
const MODULE_PATH:String = "res://scripts/net/session/host_room_password_request.gd"
const SAVE_FAILURE:String = "房间密码保存失败，原设置未改变"
var checks:int = 0
var failures:Array = []

class EntropyFailure extends Password:
	var attempts:int = 0
	func set_password(_value:String) -> bool:
		attempts += 1
		return false

func _ready() -> void:
	if not ResourceLoader.exists(MODULE_PATH):
		_check(false,"password transaction module exists")
		_finish()
		return
	var transaction = load(MODULE_PATH).new()
	_legal_setting(transaction)
	_entropy_failure(transaction)
	_persist_failure(transaction,"test-only-replacement")
	_persist_failure(transaction,"")
	_legal_cancellation(transaction)
	_missing_persist(transaction)
	_finish()

func _legal_setting(transaction) -> void:
	var password = Password.new()
	var observer = password
	var calls:Dictionary = {"persist":0,"sees_change":false}
	var persist:Callable = func() -> bool:
		calls.persist += 1
		calls.sees_change = observer.accepts("test-only-new-password") and not observer.verifier.is_empty()
		return true
	var result:Dictionary = transaction.receive(password,"test-only-new-password",persist)
	_check(result == {"ok":true,"reason":""},"setting success result")
	_check(calls.persist == 1,"setting persists exactly once")
	_check(calls.sees_change,"persist observes original object after setting")
	_check(is_same(password,observer),"setting retains password object binding")
	_check(Password.valid_state(password.verifier),"setting preserves verifier schema")
	_check(password.accepts("test-only-new-password"),"setting accepts new password")
	_check(not password.accepts("test-only-wrong-password"),"setting rejects another password")

func _entropy_failure(transaction) -> void:
	var password = EntropyFailure.new()
	password.verifier = {"salt":"a".repeat(64),"hash":"b".repeat(64)}
	var previous:Dictionary = password.verifier.duplicate(true)
	var calls:Dictionary = {"persist":0}
	var persist:Callable = func() -> bool:
		calls.persist += 1
		return true
	var result:Dictionary = transaction.receive(password,"test-only-password",persist)
	_check(result == {"ok":false,"reason":SAVE_FAILURE},"entropy failure preserves caller error text")
	_check(password.attempts == 1,"entropy failure attempts setting once")
	_check(calls.persist == 0,"entropy failure never invokes persist")
	_check(password.verifier == previous,"entropy failure retains exact previous verifier")

func _persist_failure(transaction, value:String) -> void:
	var password = Password.new()
	_check(password.set_password("test-only-previous"),"persist failure fixture setting succeeds")
	var observer = password
	var previous:Dictionary = password.verifier.duplicate(true)
	var original_verifier:Dictionary = password.verifier
	var calls:Dictionary = {"persist":0,"sees_change":false}
	var persist:Callable = func() -> bool:
		calls.persist += 1
		calls.sees_change = observer.verifier.is_empty() if value.is_empty() else observer.accepts(value)
		# 同时污染外部持有的旧字典，证明事务保存的是快照而非原字典别名。
		original_verifier["hash"] = "test-only-old-alias-mutation"
		# 故障能力返回 false；不抛异常、不替换密码对象。
		observer.verifier["salt"] = "test-only-persist-mutation"
		observer.verifier["extra"] = {"nested":[1,2]}
		return false
	var result:Dictionary = transaction.receive(password,value,persist)
	_check(result == {"ok":false,"reason":SAVE_FAILURE},"persist failure preserves exact caller error text")
	_check(calls.persist == 1,"persist failure never retries")
	_check(calls.sees_change,"failed persist observed requested setting or cancellation")
	_check(is_same(password,observer),"persist rollback retains original object binding")
	_check(observer.verifier == previous,"persist failure restores exact previous verifier")
	_check(Password.valid_state(observer.verifier) and observer.accepts("test-only-previous"),"persist failure restores previous acceptance")

func _legal_cancellation(transaction) -> void:
	var password = Password.new()
	_check(password.set_password("test-only-old"),"cancellation fixture setting succeeds")
	var calls:Dictionary = {"persist":0,"sees_clear":false}
	var persist:Callable = func() -> bool:
		calls.persist += 1
		calls.sees_clear = password.verifier.is_empty()
		return true
	var result:Dictionary = transaction.receive(password,"",persist)
	_check(result == {"ok":true,"reason":""},"empty password is legitimate cancellation")
	_check(calls.persist == 1,"cancellation persists exactly once")
	_check(calls.sees_clear,"persist observes cancellation")
	_check(password.verifier.is_empty(),"cancellation leaves empty verifier")
	_check(password.accepts("test-only-anything"),"cancelled password accepts any input")

func _missing_persist(transaction) -> void:
	var password = EntropyFailure.new()
	password.verifier = {"salt":"c".repeat(64),"hash":"d".repeat(64)}
	var previous:Dictionary = password.verifier.duplicate(true)
	var result:Dictionary = transaction.receive(password,"test-only-password",Callable())
	_check(result == {"ok":false,"reason":SAVE_FAILURE},"missing persist is not implicit success")
	_check(password.attempts == 0,"missing persist rejects before setting")
	_check(password.verifier == previous,"missing persist retains exact previous state")
	var real_password = Password.new()
	_check(real_password.set_password("test-only-before-missing-persist"),"missing persist real fixture setting succeeds")
	var real_previous:Dictionary = real_password.verifier.duplicate(true)
	var real_result:Dictionary = transaction.receive(real_password,"",Callable())
	_check(real_result == {"ok":false,"reason":SAVE_FAILURE},"missing persist cannot silently clear real password")
	_check(real_password.verifier == real_previous,"missing persist leaves real verifier unchanged")
	_check(real_password.accepts("test-only-before-missing-persist"),"missing persist preserves original acceptance")

func _check(condition:bool, label:String) -> void:
	checks += 1
	if not condition: failures.append(label)

func _finish() -> void:
	print("RESULT "+JSON.stringify({"suite":"host_room_password_request","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
