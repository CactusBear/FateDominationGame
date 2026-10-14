extends Node

const Inbox = preload("res://scripts/net/session/host_match_request_inbox.gd")
var checks:int = 0
var failures:Array = []
var calls:Array = [0,0,0]
var outcome:Dictionary = {"ok":true,"reason":""}

func _ready() -> void:
	print("USER_DATA_PATH " + OS.get_user_data_dir())
	_test_begin()
	print("RESULT " + JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)

func _check(value:bool, label:String) -> void:
	checks += 1
	if not value: failures.append(label)
	print("CHECK " + label + " " + ("true" if value else "false"))

func _begin() -> Dictionary:
	calls[0] += 1
	return outcome

func _test_begin() -> void:
	var inbox = Inbox.new()
	var method:String = "receive_begin_match"
	_check(inbox.has_method(method),"begin public method exists")
	if not inbox.has_method(method): return
	calls = [0,0,0]
	var result:Dictionary = inbox.call(method,{},_begin)
	_check(result.ok and result.dispatched and calls == [1,0,0],"begin only corresponding capability once")
	_check(is_same(result.result,outcome),"begin result unchanged")
	result = inbox.call(method,{"ignored":[null,"legacy",-4]},_begin)
	_check(result.ok and calls == [2,0,0],"begin no new field restrictions")
	outcome = {"ok":false,"reason":"开局拒绝哨兵","code":"start_denied"}
	result = inbox.call(method,{},_begin)
	_check(result.ok and result.dispatched and not result.result.ok and result.result.reason == outcome.reason and is_same(result.result,outcome),"begin authority rejection reason unchanged")
	outcome = {"ok":false,"reason":"","code":"empty_reason"}
	result = inbox.call(method,{},_begin)
	_check(result.result.reason == "" and is_same(result.result,outcome) and calls == [4,0,0],"begin no invented fallback reason")
	var before:Array = calls.duplicate()
	result = inbox.call(method,{},Callable())
	_check(not result.ok and not result.dispatched and result.code == "missing_capability" and not result.reason.is_empty() and calls == before,"begin missing capability explicit rejection")
	# RED 阶段先报告旧 Dictionary 签名不满足契约，避免引擎调用错误使场景悬挂。
	var accepts_variant:bool = false
	for descriptor in inbox.get_method_list():
		if descriptor.name == method: accepts_variant = descriptor.args[0].type == TYPE_NIL
	_check(accepts_variant,"begin accepts invalid outer types for structured rejection")
	if accepts_variant:
		for args in [null,[],"wrong",7,7.0,true,PackedInt32Array([1])]:
			result = inbox.call(method,args,_begin)
			_check(not result.ok and not result.dispatched and result.code == "invalid_args" and result.reason == "协议字段无效" and calls == before,"begin invalid outer shape " + str(args))
		result = inbox.call(method,null,Callable())
		_check(result.code == "invalid_args" and result.reason == "协议字段无效" and calls == before,"begin shape rejection precedes capability availability")
	outcome = {"ok":true,"reason":""}
