extends Node

const Inbox = preload("res://scripts/net/session/host_room_inbox.gd")
const Selection = preload("res://scripts/net/authority/selection_authority.gd")
const Pool = preload("res://scripts/selection/class_pool_selection.gd")
const Room = preload("res://scripts/net/session/room_state.gd")
var checks:int = 0
var failures:Array = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	print("USER_PATH "+OS.get_user_data_dir())
	var inbox = Inbox.new()
	if not inbox.has_method("receive_choice"):
		_check(false,"independent choice API exists")
		_finish()
		return
	_legal_dispatch(inbox)
	_wrong_shapes(inbox)
	_real_authority(inbox)
	_finish()

func _legal_dispatch(inbox) -> void:
	var seen:Array = []
	var choose:Callable = func(actor:int, seat:int, master_name:String) -> bool:
		seen.append([actor,seat,master_name])
		return true
	var args:Dictionary = {"seat":0,"name":"","extra":{"keep":true}}
	var before:Dictionary = args.duplicate(true)
	_check(inbox.receive_choice(17,args,choose),"zero seat and empty name are dispatched, not newly forbidden")
	_check(seen == [[17,0,""]],"trusted actor and exact payload reach capability once")
	_check(args == before,"choice leaves caller payload unchanged")
	_check(inbox.receive_choice(23,{"seat":-9,"name":"  原样名称  "},choose),"negative seat and whitespace name are not new adapter rules")
	_check(seen.back() == [23,-9,"  原样名称  "],"adapter preserves values without normalization")
	var rejected:Array = []
	var refuse:Callable = func(actor:int, seat:int, master_name:String) -> bool:
		rejected.append([actor,seat,master_name])
		return false
	_check(not inbox.receive_choice(31,{"seat":8,"name":"合法形状"},refuse),"authority false remains false")
	_check(rejected == [[31,8,"合法形状"]],"valid refused shape calls authority exactly once")
	var weak:WeakRef = _scoped_capability(inbox)
	_check(weak.get_ref() == null,"inbox does not retain scoped capability or its captured owner")
	_check(not inbox.handles("choose_master"),"room generic routing remains unchanged until dedicated Session branch wiring")

func _scoped_capability(inbox) -> WeakRef:
	# 返回后再观测，排除当前函数栈持有闭包捕获对象。
	var capability_owner = RefCounted.new()
	var weak = weakref(capability_owner)
	var local_choose:Callable = func(_actor:int, _seat:int, _name:String) -> bool:
		return is_instance_valid(capability_owner)
	_check(inbox.receive_choice(1,{"seat":2,"name":"生命周期"},local_choose),"scoped capability executes synchronously")
	return weak

func _wrong_shapes(inbox) -> void:
	var calls:Dictionary = {"count":0}
	var choose:Callable = func(_actor:int, _seat:int, _name:String) -> bool:
		calls.count += 1
		return true
	var invalid:Array = [
		{}, {"seat":1}, {"name":"m"},
		{"seat":null,"name":"m"}, {"seat":true,"name":"m"},
		{"seat":1.0,"name":"m"}, {"seat":"1","name":"m"},
		{"seat":[],"name":"m"}, {"seat":{},"name":"m"},
		{"seat":1,"name":null}, {"seat":1,"name":true},
		{"seat":1,"name":1}, {"seat":1,"name":1.0},
		{"seat":1,"name":[]}, {"seat":1,"name":{}},
		{"seat":1,"name":StringName("m")}
	]
	for index in invalid.size():
		var args:Dictionary = invalid[index]
		var before:Dictionary = args.duplicate(true)
		_check(not inbox.receive_choice(17,args,choose),"invalid shape %d returns false" % index)
		_check(calls.count == 0,"invalid shape %d never calls authority" % index)
		_check(args == before,"invalid shape %d leaves payload unchanged" % index)

func _real_authority(inbox) -> void:
	# 独立微型候选池，仍执行生产 Selection.setup/choose 与 ClassPool 规则。
	var selection = Selection.new()
	var masters:Array = [{"_name":"contract-master-a"},{"_name":"contract-master-b"}]
	var servants:Array = [{"_name":"contract-servant-a","_servant_class":"contract-class"},{"_name":"contract-servant-b","_servant_class":"contract-class"}]
	_check(selection.setup(Pool.new(),{0:17,1:23},masters,servants,{"regular_classes":["contract-class"],"per_class_count":2,"special_count":0}),"production authority and pool fixture setup")
	var room = Room.new()
	room.error = ""
	_check(inbox.receive_choice(17,{"seat":0,"name":"contract-master-a"},selection.choose),"legal choice reaches real authority")
	_check(selection.rules.assignments[0].master == masters[0],"real authority installs exact selected master")
	var before:Dictionary = selection.rules.assignments.duplicate(true)
	_check(not inbox.receive_choice(23,{"seat":0,"name":"contract-master-b"},selection.choose),"other member cannot choose controlled seat")
	_check(selection.error == "不能操作该座位","seat authority refusal keeps original authority error")
	_check(selection.rules.assignments == before,"authority seat refusal preserves assignments")
	_check(_caller_reason(room) == "请求无效","caller fallback does not replace room reason with selection error")
	_check(not inbox.receive_choice(23,{"seat":1,"name":"contract-master-a"},selection.choose),"real rule refuses already taken master")
	_check(selection.error == "御主不可选择","rule refusal keeps original authority error")
	_check(selection.rules.assignments == before,"rule refusal preserves assignments")
	_check(not inbox.receive_choice(23,{"seat":1,"name":"missing-master"},selection.choose),"real authority refuses undeclared master")
	_check(selection.error == "御主不可选择","undeclared master keeps original authority error")
	room.error = "原Room拒因"
	_check(not inbox.receive_choice(23,{"seat":"1","name":"contract-master-b"},selection.choose),"malformed payload refuses before authority")
	_check(selection.error == "御主不可选择","shape rejection does not mutate authority error")
	_check(_caller_reason(room) == "原Room拒因","caller preserves existing nonempty room error")
	_check(inbox.receive_choice(23,{"seat":1,"name":"contract-master-b"},selection.choose),"next valid choice is not poisoned by earlier refusal")
	_check(selection.rules.is_complete(),"production rules complete only after both valid choices")

func _caller_reason(room) -> String:
	# 对照已读 Session 收尾表达式；不是生产调用方已接线证明。
	return room.error if not room.error.is_empty() else "请求无效"

func _check(condition:bool, label:String) -> void:
	checks += 1
	if not condition: failures.append(label)

func _finish() -> void:
	print("RESULT "+JSON.stringify({"suite":"host_room_choice_request","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
