extends Node

const Inbox = preload("res://scripts/net/session/host_match_request_inbox.gd")
var checks:int = 0
var failures:Array = []
var calls:Array = [0,0,0]
var outcome:Dictionary = {"ok":true,"reason":""}
var seen:Array = []

func _ready() -> void:
	print("USER_DATA_PATH " + OS.get_user_data_dir())
	_test_finish()
	_test_confirm()
	print("RESULT " + JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)

func _check(value:bool, label:String) -> void:
	checks += 1
	if not value: failures.append(label)
	print("CHECK " + label + " " + ("true" if value else "false"))

func _finish(sequence:int) -> Dictionary:
	calls[1] += 1
	seen = [sequence]
	return outcome

func _confirm(sequence:int, batch:int, seats:Array) -> Dictionary:
	calls[2] += 1
	seen = [sequence,batch,seats]
	return outcome

func _test_finish() -> void:
	var inbox = Inbox.new()
	var method:String = "receive_match_finished_lobby"
	_check(inbox.has_method(method),"finish public method exists")
	if not inbox.has_method(method): return
	calls = [0,0,0]
	outcome = {"ok":true,"reason":"","code":"finished"}
	var result:Dictionary = inbox.call(method,{"view_seq":-7},_finish)
	_check(result.ok and result.dispatched and calls == [0,1,0],"finish only corresponding capability once")
	_check(seen == [-7] and is_same(result.result,outcome),"finish sequence and result unchanged")
	outcome = {"ok":false,"reason":"终局拒绝哨兵\n不应改写","code":"finish_denied"}
	result = inbox.call(method,{"view_seq":0},_finish)
	_check(result.ok and result.dispatched and not result.result.ok and is_same(result.result,outcome) and calls == [0,2,0],"finish rejection dictionary and reason unchanged")
	var before:Array = calls.duplicate()
	for args in [null,[],"wrong",{}, {"view_seq":"7"},{"view_seq":7.0},{"view_seq":true},{"view_seq":7,"extra":null}]:
		result = inbox.call(method,args,_finish)
		_check(not result.ok and not result.dispatched and result.code == "invalid_args" and result.reason == "只有在线房主能以有效终局视图返回大厅" and calls == before,"finish invalid shape " + str(args))
	result = inbox.call(method,{"view_seq":7},Callable())
	_check(not result.ok and not result.dispatched and result.code == "missing_capability" and not result.reason.is_empty() and calls == before,"finish missing capability explicit rejection")
	result = inbox.call(method,{},Callable())
	_check(result.code == "invalid_args" and calls == before,"finish shape rejection precedes capability availability")
	outcome = {"ok":false,"reason":"","code":"empty_reason"}
	result = inbox.call(method,{"view_seq":-999},_finish)
	_check(result.ok and result.dispatched and result.result.reason == "" and is_same(result.result,outcome) and seen == [-999] and calls == [0,3,0],"finish no invented fallback reason or sequence restriction")

func _test_confirm() -> void:
	var inbox = Inbox.new()
	var method:String = "receive_broadcast_confirm_absent"
	_check(inbox.has_method(method),"confirm public method exists")
	if not inbox.has_method(method): return
	calls = [0,0,0]
	outcome = {"ok":true,"reason":"","code":"confirmed"}
	var seats:Array = [4,1]
	var args:Dictionary = {"view_seq":-7,"batch_id":-9,"seats":seats}
	var result:Dictionary = inbox.call(method,args,_confirm)
	_check(result.ok and result.dispatched and calls == [0,0,1],"confirm only corresponding capability once")
	_check(seen == [-7,-9,seats] and is_same(seen[2],seats) and is_same(args.seats,seats) and is_same(result.result,outcome),"confirm sequence batch seats identity order and result unchanged")
	outcome = {"ok":false,"reason":"离线确认拒绝哨兵\n不应改写","code":"confirm_denied"}
	result = inbox.call(method,args,_confirm)
	_check(result.ok and result.dispatched and not result.result.ok and result.result.reason == outcome.reason and is_same(result.result,outcome) and calls == [0,0,2],"confirm rejection dictionary and reason unchanged")
	outcome = {"ok":false,"reason":"","code":"empty_reason"}
	result = inbox.call(method,args,_confirm)
	_check(result.result.reason == "" and is_same(result.result,outcome) and calls == [0,0,3],"confirm no invented fallback reason")
	outcome = {"ok":true,"reason":""}
	for candidate in [[],[4,4],[-1,"delegated",null,true,1.0]]:
		var count:int = calls[2]
		result = inbox.call(method,{"view_seq":0,"batch_id":0,"seats":candidate},_confirm)
		_check(result.ok and result.dispatched and calls == [0,0,count+1] and is_same(seen[2],candidate),"confirm seat contents emptiness duplicates left to capability " + str(candidate))
	var before:Array = calls.duplicate()
	var invalid:Array = [null,[],"wrong",7,true,{},
		{"batch_id":1,"seats":[]}, {"view_seq":1,"seats":[]}, {"view_seq":1,"batch_id":1},
		{"view_seq":1,"batch_id":1,"seats":[],"extra":null}]
	for field in ["view_seq","batch_id"]:
		for value in [null,"1",1.0,true,[],{}]:
			var malformed:Dictionary = args.duplicate()
			malformed[field] = value
			invalid.append(malformed)
	for value in [null,"seats",1,true,{},PackedInt32Array([1])]:
		var malformed:Dictionary = args.duplicate()
		malformed.seats = value
		invalid.append(malformed)
	for malformed in invalid:
		result = inbox.call(method,malformed,_confirm)
		_check(not result.ok and not result.dispatched and result.code == "invalid_args" and result.reason == "参数必须恰为 view_seq/batch_id/seats" and calls == before,"confirm invalid shape " + str(malformed))
	result = inbox.call(method,args,Callable())
	_check(not result.ok and not result.dispatched and result.code == "missing_capability" and not result.reason.is_empty() and calls == before,"confirm missing capability explicit rejection")
	result = inbox.call(method,{},Callable())
	_check(result.code == "invalid_args" and result.reason == "参数必须恰为 view_seq/batch_id/seats" and calls == before,"confirm shape rejection precedes capability availability")
