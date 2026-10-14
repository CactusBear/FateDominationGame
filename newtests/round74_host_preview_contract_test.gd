extends Node
const Inbox = preload("res://scripts/net/session/host_match_request_inbox.gd")
var checks:int = 0
var failures:Array = []

class PreviewCapability extends RefCounted:
	var calls:Array = []
	var reply:Dictionary = {"ok":true,"view_seq":7,"can_submit":false}
	func preview(sequence:int, cards:Array, hidden:Array) -> Dictionary:
		calls.append([sequence,cards.duplicate(true),hidden.duplicate(true)])
		return reply

func check(ok:bool, label:String) -> void:
	checks += 1
	if not ok: failures.append(label)
	print("CHECK ",label," ",ok)

func finish() -> void:
	print("RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)

func _ready() -> void:
	print("USER_PATH ",OS.get_user_data_dir())
	var inbox = Inbox.new()
	check(inbox.has_method("receive_preview"),"existing inbox owns preview request shape closure")
	if not inbox.has_method("receive_preview"):
		finish()
		return
	var capability = PreviewCapability.new()
	var args:Dictionary = {"request_id":11,"view_seq":7,"cards":[23,29],"hidden":[false,true],"legacy_extra":true}
	var original:Dictionary = args.duplicate(true)
	var result:Dictionary = inbox.receive_preview(args,capability.preview)
	check(result == {"ok":true,"request_id":11,"result":capability.reply},"positive result preserves request id and authority payload")
	check(capability.calls == [[7,[23,29],[false,true]]],"valid shape dispatches explicit preview exactly once")
	check(args == original,"does not mutate request or newly reject extras")
	for mutation in [{"request_id":11.0},{"request_id":true},{"request_id":null},{"view_seq":7.0},{"view_seq":false},{"view_seq":"7"},{"cards":{}},{"cards":null},{"hidden":false},{"hidden":null}]:
		var invalid:Dictionary = args.duplicate(true)
		invalid.merge(mutation,true)
		var before:int = capability.calls.size()
		result = inbox.receive_preview(invalid,capability.preview)
		check(result == {"ok":false,"reason":"组合预览请求无效"},"bad field type retains original error")
		check(capability.calls.size() == before,"invalid shape never calls preview")
	for key in ["request_id","view_seq","cards","hidden"]:
		var invalid:Dictionary = args.duplicate(true)
		invalid.erase(key)
		result = inbox.receive_preview(invalid,Callable())
		check(result == {"ok":false,"reason":"组合预览请求无效"},"missing required field rejects before callable")
	var empty:Dictionary = {"request_id":0,"view_seq":-1,"cards":[],"hidden":[]}
	result = inbox.receive_preview(empty,capability.preview)
	check(result.ok and capability.calls.back() == [-1,[],[]],"empty arrays and unrestricted ints retain legacy shape acceptance")
	capability.reply = {"ok":false,"authority_only":"private denial unchanged"}
	result = inbox.receive_preview(args,capability.preview)
	check(result == {"ok":true,"request_id":11,"result":capability.reply},"authority denial is reply payload not malformed request")
	args.cards = ["authority decides card types"]
	args.hidden = []
	result = inbox.receive_preview(args,capability.preview)
	check(result.ok and capability.calls.back() == [7,args.cards,[]],"inbox adds no card element or length rule")
	result.clear()
	var lifetime:WeakRef = weakref(capability)
	capability = null
	check(lifetime.get_ref() == null,"inbox does not retain scoped capability")
	finish()
