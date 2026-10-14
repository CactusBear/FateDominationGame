extends Node

signal management_requested(actor:int, kind:String, args:Dictionary)

const MANAGEMENT_KINDS := ["server_data_catalog", "server_data_prepare", "server_data_commit", "server_data_cancel"]
var checks:int = 0
var failures:Array = []
var calls:Array = []

func _ready() -> void:
	var inbox = load("res://scripts/net/session/host_content_inbox.gd").new()
	_check(inbox.has_method("handles_management") and inbox.has_method("receive_management"), "独立管理入口存在")
	if not failures.is_empty():
		_finish()
		return
	management_requested.connect(_record)
	for kind in MANAGEMENT_KINDS:
		_check(inbox.handles_management(kind), kind + "被管理入口分类")
		_check(not inbox.handles(kind), kind + "不被普通内容入口吞掉")
		var args:Dictionary = {"unexpected": [null, {"nested":true}], "token":17, "request_id":"不替approval校验", "selected":false}
		var previous:Dictionary = args.duplicate(true)
		var count:int = calls.size()
		_check(inbox.receive_management(73,kind,args,management_requested.emit), kind + "同步分派")
		_check(calls.size() == count + 1, kind + "只回调一次")
		_check(calls.back().actor == 73 and calls.back().kind == kind, kind + "可信actor与kind原样传递")
		_check(is_same(calls.back().args,args) and args == previous, kind + "args原引用不清字段")
		_check(not inbox.receive_management(73,kind,args,Callable()), kind + "无显式能力不分派")
		_check(calls.size() == count + 1, kind + "缺能力不回调")
	for kind in ["", "server_data_unknown", "server_data_catalog_part", "catalog", "data_ack", "blob_request"]:
		var count:int = calls.size()
		_check(not inbox.handles_management(kind), kind + "不属管理请求")
		_check(not inbox.receive_management(73,kind,{},management_requested.emit), kind + "不分派")
		_check(calls.size() == count, kind + "不回调")
	# 空args也必须交给现有approval决定，不在dispatcher猜参数或token。
	_check(inbox.receive_management(73,"server_data_cancel",{},management_requested.emit), "空args仍原样委托")
	_check(calls.back().args.is_empty(), "空args不补字段")
	# 普通内容入口的分类与ACK/blob行为保持原状。
	for kind in ["catalog", "data_ack", "blob_request"]:
		_check(inbox.handles(kind), kind + "普通入口保留")
	var room:Dictionary = {"phase":"lobby", "revision":4}
	var confirmed:Dictionary = {}
	var result:Dictionary = inbox.receive(room,73,"data_ack",{"revision":2},0,1000,{},confirmed,2,Callable())
	_check(result.ok and result.get("publish",false) and confirmed.get(73) == 2 and room.revision == 5, "普通ACK仍写原确认表")
	var queued:Array = []
	var queue:Callable = func(actor:int, key:String, offset:int) -> bool:
		queued.append([actor,key,offset])
		return true
	result = inbox.receive(room,73,"blob_request",{"key":"declared-key","offset":0},0,1000,{},confirmed,2,queue)
	_check(result.ok and queued == [[73,"declared-key",0]], "普通blob仍走原队列能力")
	var catalogs:Dictionary = {}
	result = inbox.receive(room,73,"catalog",{"entries":[]},0,1000,catalogs,confirmed,2,queue)
	_check(result.ok and result.get("catalog_changed",false) and catalogs.get(73) == [], "普通catalog仍复用原清单accept")
	result = inbox.receive(room,73,"catalog",{"entries":[]},1001,1000,catalogs,confirmed,2,queue)
	_check(not result.ok and result.reason == "条目清单超过累计消息预算", "普通catalog仍保留原预算拒绝")
	var source:String = inbox.get_script().source_code
	var management_body:String = source.substr(source.find("func receive_management("))
	_check(not "token" in management_body and not "args.get" in management_body and not "args[" in management_body and not "args." in management_body, "管理委托不读token或args字段")
	_finish()

func _record(actor:int, kind:String, args:Dictionary) -> void:
	calls.append({"actor":actor,"kind":kind,"args":args})

func _check(ok:bool, label:String) -> void:
	checks += 1
	if not ok: failures.append(label)
	print("CHECK ", label, " ", str(ok))

func _finish() -> void:
	print("RESULT ", JSON.stringify({"suite":"host_content_management_inbox","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
