extends Node

const Codec = preload("res://scripts/net/identity/host_identity_request_codec.gd")
const Session = preload("res://scripts/net/session/lobby_session.gd")

const HOST_KEY:String = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
var checks:int = 0
var failures:Array = []
var previews:Array = []

class CodecProbe extends RefCounted:
	var calls:int = 0
	func validate(_kind:String, _args:Dictionary) -> Dictionary:
		calls += 1
		return {"ok":true}

class PreviewAuthority extends RefCounted:
	var calls:Array = []
	var reply:Dictionary = {"ok":false,"reason":"权威拒绝但仍是预览结果"}
	func preview_group(sender:int, sequence:int, cards:Array, hidden:Array) -> Dictionary:
		calls.append({"sender":sender,"sequence":sequence,"cards":cards.duplicate(true),"hidden":hidden.duplicate(true)})
		return reply.duplicate(true)

class ProbeSession extends "res://scripts/net/session/lobby_session.gd":
	var failures_seen:Array = []
	var outbound:Array = []
	var inherited:Array = []
	func _fail(sender:int, reason:String, sequence:int = 0) -> void:
		failures_seen.append({"sender":sender,"reason":reason,"sequence":sequence})
	func _reject_request(connection:int, sender:int, _message:Dictionary, reason:String) -> void:
		failures_seen.append({"sender":sender,"connection":connection,"reason":reason})
	func _send(member:int, message:Dictionary, channel:int = 0) -> Error:
		outbound.append({"member":member,"message":message.duplicate(true),"channel":channel})
		return OK
	func _inherit_identity(actor:int, sequence:int, args:Dictionary, _trusted:Dictionary) -> bool:
		inherited.append({"actor":actor,"sequence":sequence,"args":args.duplicate(true)})
		return true
	func _publish(_persist_recovery:bool = true) -> void:
		pass

func check(ok:bool, label:String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _on_preview(request_id:int, result:Dictionary) -> void:
	previews.append({"request_id":request_id,"result":result.duplicate(true)})

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var codec = Codec.new()
	check(codec.validate("identity_candidates", {}) == {"ok":true}, "合法候选空参数保持原语义")
	var inherit:Dictionary = {"target_member":3,"successor_member":4,"revision":8}
	check(codec.validate("identity_inherit", inherit) == {"ok":true}, "合法继承字段保持原语义")
	check(codec.validate("identity_inherit", {"target_member":3,"successor_member":4}) == {"ok":false,"reason":"继承请求字段无效"}, "继承缺字段沿用原拒绝")
	check(codec.validate("identity_inherit", {"target_member":3,"successor_member":4,"revision":8,"extra":true}) == {"ok":false,"reason":"继承请求字段无效"}, "继承额外字段沿用原拒绝")
	check(codec.validate("identity_inherit", {"target_member":3.0,"successor_member":4,"revision":8}) == {"ok":false,"reason":"继承请求字段无效"}, "继承数值类型严格保持")
	check(codec.validate("identity_candidates", {"nickname":"不是身份"}) == {"ok":false,"reason":"候选查询不接受身份参数"}, "候选拒绝身份参数")
	check(codec.validate("identity_inherit", {"target_member":-1,"successor_member":0,"revision":-3}).ok, "codec不复制member/在线/版本政策")
	check(inherit == {"target_member":3,"successor_member":4,"revision":8}, "codec不修改请求字典")

	var session = ProbeSession.new()
	var probe = CodecProbe.new()
	session._host_identity_request_codec = probe
	session._host = true
	# 未登记连接先被 Session 来源门拒绝，不能进入 codec。
	session._receive(77, {"v":1,"seq":1,"kind":"identity_candidates","args":{}})
	check(probe.calls == 0 and session.failures_seen.size() == 1, "bad source在Session外层拒绝且不进codec")
	# 已登记连接的旧序号同样在 codec 之前被消费门拒绝。
	session._member_by_peer[77] = 2
	session.room.members[2] = {"connected":true,"spectator":true}
	session._received_seq[77] = 9
	session._receive(77, {"v":1,"seq":9,"kind":"identity_candidates","args":{}})
	check(probe.calls == 0 and session.failures_seen.size() == 2, "旧seq在Session外层拒绝且不进codec")
	# 未认证/未授权房主在 codec 之前拒绝，不把授权复制到 codec。
	session._received_seq.clear()
	session.dedicated = true
	session.room.owner = 1
	session.room.members[1] = {"connected":true,"spectator":false}
	session._identity_binding_required = true
	session._member_identities[1] = HOST_KEY
	session._receive(1, {"v":1,"seq":1,"kind":"identity_candidates","args":{}})
	check(probe.calls == 0 and session.failures_seen.size() == 3, "noauth在Session授权门拒绝且不进codec")

	# 真实 Session 接线：合法候选仍沿原本地结果路径。
	session._host_identity_request_codec = Codec.new()
	session._received_seq.clear()
	session.failures_seen.clear()
	session.outbound.clear()
	session.room.members.clear()
	session.room.members[1] = {"connected":true,"spectator":false}
	session._member_identities.clear()
	session._member_identities[1] = HOST_KEY
	session.room.settings = {"ai_count":0,"minimum":1,"capacity":2}
	session.room.revision = 8
	session._receive(1, {"v":1,"seq":2,"kind":"identity_candidates","args":{},"gateway_inheritance":{"actor_key":HOST_KEY,"profiles":{HOST_KEY:{"username":"host","nickname":"仅展示"}}}})
	check(session.failures_seen.is_empty() and session.outbound.size() == 1 and session.outbound[0].message.kind == "inheritance_candidates", "合法身份候选真实Session接线结果一致")
	check(not JSON.stringify(session.outbound).contains(HOST_KEY), "身份候选回执不泄露密钥")
	session.failures_seen.clear()
	session.inherited.clear()
	session._receive(1, {"v":1,"seq":6,"kind":"identity_inherit","args":inherit,"gateway_inheritance":{"actor_key":HOST_KEY,"profiles":{HOST_KEY:{"username":"host","nickname":"仅展示"}}}})
	check(session.failures_seen.is_empty() and session.inherited == [{"actor":1,"sequence":6,"args":inherit}], "合法身份继承原请求真实Session接线")

	# 真实 Session 接线：preview 保留 local signal 与 remote channel 1，权威拒绝不走 _fail。
	var authority = PreviewAuthority.new()
	session.match_authority = authority
	session.room.phase = "playing"
	session.room.members[1] = {"connected":true,"spectator":false}
	session._received_seq.clear()
	previews.clear()
	session.failures_seen.clear()
	session.outbound.clear()
	session.group_preview_received.connect(_on_preview)
	var preview_args:Dictionary = {"request_id":11,"view_seq":7,"cards":[23],"hidden":[false]}
	session._receive(1, {"v":1,"seq":7,"kind":"preview_group","args":preview_args})
	check(authority.calls.size() == 1 and previews.size() == 1 and previews[0].request_id == 11, "local preview沿原signal返回权威结果")
	check(previews[0].result.get("ok") == false and session.failures_seen.is_empty(), "local权威拒绝不是Session请求失败")
	session._member_by_peer[44] = 2
	session._peer_by_member[2] = 44
	session.room.members[2] = {"connected":true,"spectator":true}
	session._receive(44, {"v":1,"seq":8,"kind":"preview_group","args":preview_args})
	check(authority.calls.size() == 2 and session.outbound.size() == 1 and session.outbound[0].channel == 1, "remote preview沿原channel 1发送")
	check(session.outbound[0].message.result.get("ok") == false and session.failures_seen.is_empty(), "remote权威拒绝仍原样回传")
	var calls_before:int = authority.calls.size()
	session.room.phase = "lobby"
	session._receive(1, {"v":1,"seq":9,"kind":"preview_group","args":preview_args})
	check(authority.calls.size() == calls_before and session.failures_seen.back().reason == "组合预览请求无效", "非playing阶段在Session拒绝且不调用权威")
	if session.group_preview_received.is_connected(_on_preview): session.group_preview_received.disconnect(_on_preview)
	print("RESULT ", JSON.stringify({"suite":"f09_identity_preview_session_contract","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
