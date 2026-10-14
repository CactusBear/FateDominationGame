extends Node

const Session = preload("res://scripts/net/session/lobby_session.gd")

class Master extends RefCounted:
	var _name:String
	func _init(value:String) -> void: _name = value
	func get_shown_name() -> String: return _name

class ObservedPool extends "res://scripts/selection/class_pool_selection.gd":
	var calls:int = 0
	func choose_master(seat:int, master) -> bool:
		calls += 1
		return super.choose_master(seat,master)

class ObservedSelection extends "res://scripts/net/authority/selection_authority.gd":
	var calls:int = 0
	func choose(actor:int, seat:int, name:String) -> bool:
		calls += 1
		return super.choose(actor,seat,name)

class ObservedInbox extends "res://scripts/net/session/host_room_inbox.gd":
	var calls:int = 0
	var reason_room
	func receive_choice(actor:int, args:Dictionary, choose:Callable) -> bool:
		calls += 1
		if reason_room != null: reason_room.error = "原房间拒因哨兵"
		return super.receive_choice(actor,args,choose)

var checks:int = 0
var failures:Array = []

func _ready() -> void: call_deferred("_run")

func _fixture() -> Dictionary:
	var session = Session.new()
	session._host = true
	_check(session.room.configure(1,{"capacity":3,"minimum":1,"ai_count":0}),"room configure")
	_check(session.room.join(1,"自造成员"),"room join without credentials")
	session.room.phase = "selecting"
	var authority = ObservedSelection.new()
	var rules = ObservedPool.new()
	var masters:Array = [Master.new("wire-a"),Master.new("wire-b"),Master.new("wire-c")]
	var servants:Array = [{"_name":"sa","_servant_class":"wire-class"},{"_name":"sb","_servant_class":"wire-class"},{"_name":"sc","_servant_class":"wire-class"}]
	_check(authority.setup(rules,{0:1,1:2,2:3},masters,servants,{"regular_classes":["wire-class"],"per_class_count":3,"special_count":0}),"real authority and pool setup")
	session.selection = authority
	var inbox = ObservedInbox.new()
	session._host_room_inbox = inbox
	var seen:Dictionary = {"rejected":[],"changed":0,"selection_published":false}
	session.request_rejected.connect(func(seq:int, reason:String): seen.rejected.append([seq,reason]))
	session.changed.connect(func():
		seen.changed += 1
		if session.selection_view.get("selected",[]).has({"seat":0,"master":"wire-a"}): seen.selection_published = true)
	return {"session":session,"authority":authority,"rules":rules,"inbox":inbox,"seen":seen}

func _dispose(f:Dictionary) -> void:
	# Disconnect the test observer that captures session before dropping the fixture.
	for connection in f.session.changed.get_connections(): f.session.changed.disconnect(connection.callable)
	f.inbox.reason_room = null
	f.session.close()

func _run() -> void:
	print("USER_PATH "+OS.get_user_data_dir())
	var f:Dictionary = _fixture()
	var args:Dictionary = {"seat":0,"name":"wire-a","extra":{"unchanged":[1,true]}}
	var before:Dictionary = args.duplicate(true)
	_check(f.session.request("choose_master",args) == OK,"legal public request transport result")
	_check(f.inbox.calls == 1 and f.authority.calls == 1 and f.rules.calls == 1,"legal request delegates once through real authority and rule")
	_check(f.authority.rules.assignments[0].master._name == "wire-a","legal request installs exact selected master")
	_check(f.seen.selection_published and f.session.selection_view.selected == [{"seat":0,"master":"wire-a"}],"real selection publish reaches changed and public selection view")
	_check(f.seen.changed == 2 and f.seen.rejected.is_empty(),"selection and room publish once each without refusal")
	_check(args == before,"legal args unchanged")
	_dispose(f)

	for bad in [{"seat":"0","name":"wire-a"},{"seat":0,"name":12},{"seat":0.0,"name":"wire-a"},{"seat":0,"name":StringName("wire-a")}]:
		f = _fixture()
		_check(f.session.request("choose_master",bad) == OK,"wrong shape public request submitted")
		_check(f.inbox.calls == 1 and f.authority.calls == 0 and f.rules.calls == 0,"wrong shape never calls choice capability")
		_check(f.seen.rejected == [[1,"请求无效"]] and f.seen.changed == 0,"wrong shape retains associated original rejection and no publish")
		_dispose(f)

	for phase in ["lobby","playing","restoring"]:
		f = _fixture()
		f.session.room.phase = phase
		_check(f.session.request("choose_master",{"seat":0,"name":"wire-a"}) == OK,"non-selecting public request submitted "+phase)
		_check(f.inbox.calls == 0 and f.authority.calls == 0 and f.rules.calls == 0,"non-selecting never invokes inbox or capability "+phase)
		_check(f.seen.rejected == [[1,"请求无效"]] and f.seen.changed == 0,"non-selecting original rejection "+phase)
		_dispose(f)

	f = _fixture()
	f.session.room.owner = 2
	_check(f.session.request("choose_master",{"seat":1,"name":"wire-a"}) == OK,"non-owner other-seat public request submitted")
	_check(f.authority.calls == 1 and f.rules.calls == 0,"seat ownership rejects in authority before rule, not an invented owner gate")
	_check(f.authority.error == "不能操作该座位" and f.seen.rejected == [[1,"请求无效"]],"selection error does not become wire refusal")
	_check(f.authority.rules.assignments.is_empty() and f.seen.changed == 0,"unauthorized seat no mutation or publish")
	_dispose(f)

	f = _fixture()
	f.session.room.owner = 2
	_check(f.session.request("choose_master",{"seat":0,"name":"wire-a"}) == OK,"non-owner own-seat public request submitted")
	_check(f.rules.calls == 1 and f.seen.rejected.is_empty() and f.seen.selection_published,"existing non-owner own-seat behavior remains legal")
	_dispose(f)

	f = _fixture()
	f.inbox.reason_room = f.session.room
	_check(f.session.request("choose_master",{"seat":"0","name":"wire-a"}) == OK,"room reason sentinel public request submitted")
	_check(f.seen.rejected == [[1,"原房间拒因哨兵"]] and f.authority.calls == 0,"original nonempty room reason retained")
	_dispose(f)
	print("RESULT "+JSON.stringify({"suite":"f09_session_choice_wire","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)

func _check(ok:bool, label:String) -> void:
	checks += 1
	print("CHECK "+str(checks)+" "+("PASS " if ok else "FAIL ")+label)
	if not ok: failures.append(label)
