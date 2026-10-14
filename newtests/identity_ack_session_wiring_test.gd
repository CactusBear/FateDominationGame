extends Node

const Session = preload("res://scripts/net/session/lobby_session.gd")
const SAVE_FAILED:String = "恢复凭据确认保存失败，原凭据状态未改变"
const MEMBER:int = 7
const CONNECTION:int = 31
var checks:int = 0
var failures:Array = []

# 仅替代网络边界，不启动监听；客户端公开request生成真实协议信封。
class FixtureTransport extends "res://scripts/net/transport/enet_transport.gd":
	var host:RefCounted
	var connection:int = CONNECTION
	var notices:Array = []
	var corrupt:String = ""
	func send(peer:int, message:Dictionary, _channel:int = 0) -> Error:
		if host != null:
			var envelope:Dictionary = message.duplicate(true)
			if corrupt == "version": envelope.v = 2
			if corrupt == "sequence_type": envelope.seq = "invalid"
			if corrupt == "args_type": envelope.args = []
			host._receive(connection,envelope)
		else:
			# 不记录或输出任何凭据，身份交付只留种类。
			notices.append({"peer":peer,"kind":message.get("kind"),"seq":message.get("seq",0),"reason":message.get("reason","")})
		return OK

class ObservedSession extends "res://scripts/net/session/lobby_session.gd":
	var persist_calls:int = 0
	var persist_succeeds:bool = true
	var saved_previous:Dictionary = {}
	var published:int = 0
	var auth_allowed:bool = true
	var auth_gate_calls:int = 0
	func _persist_recovery_state() -> bool:
		persist_calls += 1
		saved_previous = _resume_previous.duplicate(true)
		return persist_succeeds
	func _publish(_persist_recovery:bool = true) -> void:
		published += 1
	func fixture_gate(_connection:int, _message:Dictionary) -> bool:
		auth_gate_calls += 1
		return not auth_allowed
	func fixture_context(_connection:int, _member:int, _joining:bool) -> Dictionary:
		return {"authenticated":auth_allowed,"actor_key":"a".repeat(64),"profiles":{"a".repeat(64):{"nickname":"fixture"}}}

func check(ok:bool, label:String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var host = ObservedSession.new()
	var client = Session.new()
	var outbound = FixtureTransport.new()
	var inbound = FixtureTransport.new()
	host.transport = outbound
	client.transport = inbound
	inbound.host = host
	host._host = true
	host.authority_host_mode = "lan"
	host.lan_gate = host.fixture_gate
	host.lan_context = host.fixture_context
	host.room.owner = MEMBER
	host.room.phase = "lobby"
	host.room.revision = 19
	host.room.members[MEMBER] = {"connected":true,"spectator":false,"ready":false,"name":"fixture"}
	host._member_by_peer[CONNECTION] = MEMBER
	host._peer_by_member[MEMBER] = CONNECTION
	host._member_identities[MEMBER] = "a".repeat(64)
	host._identity_binding_required = true
	host._peers = [MEMBER]
	host.recovery_state_path = "user://fixture-only-never-opened.json"
	var current:String = "c".repeat(64)
	var previous:String = "b".repeat(64)
	var wrong:String = "d".repeat(64)
	host._resume_hashes[MEMBER] = current.sha256_text()
	host._resume_previous = {MEMBER:previous.sha256_text(),99:"e".repeat(64)}
	var original:Dictionary = host._resume_previous.duplicate(true)
	var hashes:Dictionary = host._resume_hashes.duplicate(true)
	var mappings:Dictionary = host._member_by_peer.duplicate(true)
	var source:String = FileAccess.get_file_as_string("res://scripts/net/session/lobby_session.gd")
	check(source.contains('preload("res://scripts/net/identity/resume_ack_transaction.gd")') and source.contains(".acknowledge(sender,"),"Session calls static resume ack transaction")

	check(client.request("identity_ack",{"token":current,"member":99}) == OK,"合法ack沿公开request发送")
	check(not host._resume_previous.has(MEMBER) and host._resume_previous.get(99) == original[99],"ack按可信映射成员删除且不采纳args.member")
	check(host.persist_calls == 1 and not host.saved_previous.has(MEMBER) and host.saved_previous.get(99) == original[99],"合法ack候选删除后仅保存一次")
	check(host._resume_hashes == hashes and host._member_by_peer == mappings,"ack不改变hash或connection/member")
	check(host.room.revision == 19 and host.published == 0 and outbound.notices.is_empty(),"确认不新增revision发布回执广播")

	# 成功后的重复信封必须在事务前拒绝，即使重新放入previous也不能再次确认。
	host._resume_previous = original.duplicate(true)
	client._seq -= 1
	check(client.request("identity_ack",{"token":current}) == OK,"重复seq通过公开入口重送")
	check(host.persist_calls == 1 and host._resume_previous == original,"重复seq拒绝不得再次确认")
	check(outbound.notices.size() == 1 and outbound.notices.back().reason == "重复或过期请求" and outbound.notices.back().seq == client._seq,"重复seq沿原错误协议")
	outbound.notices.clear()

	for invalid in [123,null,{},wrong]:
		check(client.request("identity_ack",{"token":invalid}) == OK,"错误类型或token经公开入口")
		check(host.persist_calls == 1 and host._resume_previous == original and outbound.notices.is_empty(),"错误类型或token静默且不保存")
	check(client.request("identity_ack",{}) == OK,"缺失token经公开入口")
	check(host.persist_calls == 1 and host._resume_previous == original and outbound.notices.is_empty(),"缺失token静默且不保存")
	host._resume_previous.erase(MEMBER)
	check(client.request("identity_ack",{"token":current}) == OK,"无previous经公开入口")
	check(host.persist_calls == 1 and not host._resume_previous.has(MEMBER) and outbound.notices.is_empty(),"无previous静默且不保存")

	host._resume_previous = original.duplicate(true)
	host.persist_succeeds = false
	check(client.request("identity_ack",{"token":current}) == OK,"保存失败经公开入口")
	check(host.persist_calls == 2 and not host.saved_previous.has(MEMBER),"保存失败仍仅调用一次现持久化能力")
	check(host._resume_previous == original and host._resume_hashes == hashes,"保存失败恢复exact previous及当前hash")
	check(outbound.notices.size() == 1 and outbound.notices.back() == {"peer":CONNECTION,"kind":"error","seq":client._seq,"reason":SAVE_FAILED},"只有保存失败发原_fail关联文本")
	check(host.room.revision == 19 and host.published == 0,"保存失败无revision发布")
	outbound.notices.clear()

	# 直接使用刚刚保存失败的内存状态，不重建previous/hash；只标记离线和换连接。
	host.recovery_state_path = ""
	host.room.members[MEMBER].connected = false
	host._member_by_peer.erase(CONNECTION)
	host._peer_by_member.erase(MEMBER)
	inbound.connection = 55
	check(client.request("join",{"name":"fixture","spectator":false,"resume":{"member":MEMBER,"token":previous}}) == OK,"原凭据经公开join入口")
	check(host.room.members[MEMBER].connected and host._member_by_peer.get(55) == MEMBER and host._peer_by_member.get(MEMBER) == 55,"回滚保留原凭据可通过真实join绑定")
	check(outbound.notices.size() == 1 and outbound.notices.back().kind == "identity" and host.error.is_empty(),"原凭据实际交付身份而非仅比较hash")

	# 后续前置门用独立重布置fixture；上面原凭据断言已由失败状态直接验证。
	host._resume_previous = original.duplicate(true)
	host._resume_hashes = hashes.duplicate(true)
	host._member_by_peer = mappings.duplicate(true)
	host._peer_by_member = {MEMBER:CONNECTION}
	host.room.revision = 19
	host.published = 0
	host.recovery_state_path = "user://fixture-only-never-opened.json"
	inbound.connection = CONNECTION
	outbound.notices.clear()

	# 前置门保留：lan认证、连接映射、稳定member存在、在线与协议字段。
	for denied in ["authentication","connection","member","offline","version","sequence_type","args_type"]:
		host.auth_allowed = denied != "authentication"
		inbound.connection = 55 if denied == "connection" else CONNECTION
		host._member_by_peer[CONNECTION] = 88 if denied == "member" else MEMBER
		host.room.members[MEMBER].connected = denied != "offline"
		inbound.corrupt = denied
		check(client.request("identity_ack",{"token":current,"member":MEMBER}) == OK,denied+"经公开request")
		check(host.persist_calls == 2 and host._resume_previous == original and host._resume_hashes == hashes,denied+"前置拒绝不进入确认事务")
		if denied == "authentication":
			check(outbound.notices.is_empty(),"认证门消费请求不泄漏事务失败通知")
		else:
			check(outbound.notices.size() == 1 and outbound.notices.back().reason != SAVE_FAILED,denied+"保留原前置拒绝")
		outbound.notices.clear()
	host.auth_allowed = true
	inbound.connection = CONNECTION
	inbound.corrupt = ""
	host._member_by_peer[CONNECTION] = MEMBER
	host.room.members[MEMBER].connected = true
	check(host.auth_gate_calls > 0,"真实Session认证前置实际经过")

	# 无路径显式成功，不得调用返回失败的真实保存入口。
	host.recovery_state_path = ""
	check(client.request("identity_ack",{"token":current}) == OK,"无路径ack公开请求")
	check(host.persist_calls == 2 and not host._resume_previous.has(MEMBER) and host._resume_previous.get(99) == original[99] and outbound.notices.is_empty(),"无路径显式成功能力确认且不保存")
	check(host.room.revision == 19 and host.published == 0,"无路径成功仍不revision或发布")

	# 拆除测试边界的强引用；生产模块不保存实例或回调。
	inbound.host = null
	host.lan_gate = Callable()
	host.lan_context = Callable()
	print("USER_PATH ",OS.get_user_data_dir())
	print("RESULT ",JSON.stringify({"suite":"identity_ack_session_wiring","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
