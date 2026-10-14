extends Node

const Inbox = preload("res://scripts/net/session/host_room_inbox.gd")
var checks:int = 0
var failures:Array = []

# 只观察显式能力的调用契约；不建立房间、选人、数据或规则替身。
class Capabilities extends RefCounted:
	var trace:Array = []
	var gates:Array = [true,true,true,true]
	var owner_actor:int = 17
	var owner_check_actor:int = 0
	var start_actor:int = 0
	var start_result:bool = true
	func is_owner(actor:int) -> bool:
		trace.append("owner")
		owner_check_actor = actor
		return gates[0] and actor == owner_actor
	func can_start() -> bool:
		trace.append("can_start")
		return gates[1]
	func data_ready() -> bool:
		trace.append("data_ready")
		return gates[2]
	func prepare_selection() -> bool:
		trace.append("prepare_selection")
		return gates[3]
	func start(actor:int) -> bool:
		trace.append("start")
		start_actor = actor
		return start_result

func _check(value:bool, label:String) -> void:
	checks += 1
	print("CHECK ", checks, " ", label, " ", value)
	if not value: failures.append(label)

func _invoke(inbox, actor:int, caps:Capabilities) -> bool:
	return inbox.call("receive_start",actor,caps.is_owner,caps.can_start,caps.data_ready,caps.prepare_selection,caps.start)

func _released_capability(inbox) -> WeakRef:
	var caps = Capabilities.new()
	var reference = weakref(caps)
	_invoke(inbox,caps.owner_actor,caps)
	return reference

func _ready() -> void:
	print("USER_PATH ",OS.get_user_data_dir())
	var inbox = Inbox.new()
	_check(inbox.has_method("receive_start"),"independent start API exists")
	if inbox.has_method("receive_start"):
		var caps = Capabilities.new()
		_check(_invoke(inbox,caps.owner_actor,caps),"all prerequisites true returns start result")
		_check(caps.trace == ["owner","can_start","data_ready","prepare_selection","start"],"legal request calls each capability once in original order")
		_check(caps.owner_check_actor == caps.owner_actor and caps.start_actor == caps.owner_actor,"sender reaches owner predicate and start unchanged")
		for index in range(4):
			caps = Capabilities.new()
			caps.gates[index] = false
			_check(not _invoke(inbox,caps.owner_actor,caps),"false prerequisite %d returns false" % index)
			_check(caps.trace == ["owner","can_start","data_ready","prepare_selection"].slice(0,index+1),"false prerequisite %d stops later capabilities" % index)
			_check(caps.start_actor == 0,"false prerequisite %d never calls start" % index)
		caps = Capabilities.new()
		_check(not _invoke(inbox,29,caps),"wrong actor rejected by supplied predicate")
		_check(caps.owner_check_actor == 29 and caps.trace == ["owner"],"wrong actor not replaced or wrapped before predicate")
		_check(caps.start_actor == 0,"wrong actor never calls start")
		caps = Capabilities.new()
		caps.start_result = false
		_check(not _invoke(inbox,caps.owner_actor,caps),"start failure remains false")
		_check(caps.trace == ["owner","can_start","data_ready","prepare_selection","start"],"start failure has no retry or extra capability")
		caps = Capabilities.new()
		caps.owner_actor = -7
		_check(_invoke(inbox,-7,caps) and caps.start_actor == -7,"adapter adds no actor range restriction")
		_check(_released_capability(inbox).get_ref() == null,"adapter retains no request capability")
		_check(not inbox.handles("start"),"existing handles routing unchanged")
	print("RESULT ",JSON.stringify({"suite":"host_room_start_request","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
