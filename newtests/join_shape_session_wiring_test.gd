extends Node

const Session = preload("res://scripts/net/session/lobby_session.gd")
var checks:int = 0
var failures:Array = []

# 仅替代传输边界，公开 request 仍生成真实信封；不记录凭据。
class FixtureTransport extends "res://scripts/net/transport/enet_transport.gd":
	var host:RefCounted
	var connection:int = 31
	var corrupt:String = ""
	var notices:Array = []
	func send(peer:int, message:Dictionary, _channel:int = 0) -> Error:
		if host != null:
			var envelope:Dictionary = message.duplicate(true)
			if corrupt == "version": envelope.v = 2
			if corrupt == "sequence_type": envelope.seq = "invalid"
			if corrupt == "args_type": envelope.args = []
			host._receive(connection,envelope)
		else:
			notices.append({"peer":peer,"kind":message.get("kind"),"seq":message.get("seq",0),"reason":message.get("reason","")})
		return OK

class ObservedCodec extends "res://scripts/net/identity/host_identity_request_codec.gd":
	var calls:int = 0
	var last_kind:String = ""
	var last_args:Dictionary = {}
	func validate(kind:String, args:Dictionary) -> Dictionary:
		calls += 1
		last_kind = kind
		last_args = args.duplicate(true)
		var result:Dictionary = super.validate(kind,args)
		# 专项哨兵：若 Session 将 reason 新增到 wire，断言必然失败。
		if not result.ok: result.reason = "codec-only-sentinel"
		return result

class ObservedSession extends "res://scripts/net/session/lobby_session.gd":
	var joins:int = 0
	var join_args:Dictionary = {}
	var publications:int = 0
	var auth_allowed:bool = true
	var gate_calls:int = 0
	func _join_identity(connection:int, args:Dictionary) -> bool:
		joins += 1
		join_args = args.duplicate(true)
		return super._join_identity(connection,args)
	func _publish(_persist_recovery:bool = true) -> void:
		publications += 1
	func fixture_gate(_connection:int, _message:Dictionary) -> bool:
		gate_calls += 1
		return not auth_allowed
	func fixture_context(connection:int, _member:int, _joining:bool) -> Dictionary:
		var key:String = ("%064x" % connection)
		return {"authenticated":auth_allowed,"actor_key":key,"profiles":{key:{"nickname":"fixture"}}}

func check(ok:bool, label:String) -> void:
	checks += 1
	print("CHECK ",checks," ",label," ",str(ok))
	if not ok: failures.append(label)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var host = ObservedSession.new()
	var client = Session.new()
	var codec = ObservedCodec.new()
	var inbound = FixtureTransport.new()
	var outbound = FixtureTransport.new()
	host.transport = outbound
	client.transport = inbound
	inbound.host = host
	host._host = true
	host.dedicated = true
	host.authority_host_mode = "lan"
	host.lan_gate = host.fixture_gate
	host.lan_context = host.fixture_context
	host._host_identity_request_codec = codec
	host.room.phase = "lobby"
	host.room.settings = {"ai_count":0,"capacity":2,"minimum":1,"spectator_limit":2}
	host.room.owner = 0
	var args:Dictionary = {"name":"client-name","spectator":false,"password":"","gateway_identity":{"required":false,"key":"fixture"},"member":999,"unknown":{"items":[1,{"value":true}]}}
	var original:Dictionary = args.duplicate(true)
	check(client.request("join",args) == OK,"合法加入经公开request")
	check(codec.calls == 1 and codec.last_kind == "join" and codec.last_args == original,"join shape调用已完成codec")
	check(host.joins == 1 and host.join_args == original and args == original,"全部额外字段原样传入真实join且调用者不变")
	check(host.room.members.has(31) and host.room.members[31].connected and host.room.members[31].name == "fixture","真实join采用认证昵称创建成员")
	check(host._member_by_peer.get(31) == 31 and host._peer_by_member.get(31) == 31 and not host.room.members.has(999),"成员绑定不采用客户端member")
	check(host.room.owner == 31 and host.publications == 1,"合法加入保留专用房间owner初始化及末尾发布")
	check(outbound.notices.size() == 1 and outbound.notices[0].kind == "identity","真实身份交付不新增响应")
	outbound.notices.clear()

	var members:Dictionary = host.room.members.duplicate(true)
	var revision:int = host.room.revision
	# 重放合法信封：seq门先于codec，不能再次创建或绑定。
	client._seq -= 1
	check(client.request("join",args) == OK,"旧seq公开request重送")
	check(codec.calls == 1 and host.joins == 1 and host.room.members == members and host.room.revision == revision,"旧seq在shape及真实join前拒绝")
	check(outbound.notices.size() == 1 and outbound.notices[0].reason == "重复或过期请求" and outbound.notices[0].seq == client._seq,"旧seq保留原关联拒绝")
	outbound.notices.clear()

	inbound.connection = 55
	for invalid in [{"name":123,"spectator":false},{"name":"fixture","spectator":"false"},{"spectator":false},{"name":"fixture"}]:
		var codec_before:int = codec.calls
		check(client.request("join",invalid) == OK,"错类型或缺字段公开request")
		check(codec.calls == codec_before + 1 and host.joins == 1,"非法shape由codec拒绝不进入身份入口")
		check(host.room.members == members and host.room.revision == revision and not host._member_by_peer.has(55) and host.publications == 1,"非法shape失败不创建member不发布")
		check(outbound.notices.size() == 1 and outbound.notices[0] == {"peer":55,"kind":"error","seq":client._seq,"reason":"请求无效"},"非法shape保留末尾原无效响应不泄露codec reason")
		outbound.notices.clear()

	# 认证和协议门必须先于codec，仍沿公开request进入。
	for denied in ["authentication","version","sequence_type","args_type"]:
		host.auth_allowed = denied != "authentication"
		inbound.corrupt = denied
		var codec_before:int = codec.calls
		check(client.request("join",args) == OK,denied+"经公开request")
		check(codec.calls == codec_before and host.joins == 1 and host.room.members == members,denied+"前置门不进入shape或身份入口")
		check(outbound.notices.is_empty() if denied == "authentication" else outbound.notices.size() == 1,denied+"保留原前置拒绝")
		outbound.notices.clear()
	host.auth_allowed = true
	inbound.corrupt = ""
	check(host.gate_calls > 0,"真实认证前置实际执行")
	# shape合法但现有身份原语拒绝：保持原具体错误，不转成codec成功响应。
	check(client.request("join",{"name":"fixture","spectator":true,"resume":{"member":55,"token":"invalid"}}) == OK,"合法shape带原额外恢复字段")
	check(host.joins == 2 and host.join_args.has("resume") and host.room.members == members and not host._member_by_peer.has(55),"额外恢复字段到达真实身份入口失败不创建member")
	check(outbound.notices.size() == 1 and outbound.notices[0].reason == "恢复凭据无效" and outbound.notices[0].seq == client._seq,"身份失败保留原错误处理")

	inbound.host = null
	host.lan_gate = Callable()
	host.lan_context = Callable()
	print("USER_PATH ",OS.get_user_data_dir())
	print("RESULT ",JSON.stringify({"suite":"join_shape_session_wiring","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
