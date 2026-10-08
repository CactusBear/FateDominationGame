extends SceneTree

# 直接调用生产网关；底层夹具只注入真实 send 契约的 Error。
class FailingTransport extends RefCounted:
	var max_packet_bytes:int = 1024
	var _connected_peers:Dictionary = {7:true,8:true}
	var replies:Array = []
	var results:Array = []
	func send(peer:int, message:Dictionary, channel:int = 0) -> Error:
		replies.append({"peer":peer,"message":message.duplicate(true),"channel":channel})
		if not results.is_empty(): return results.pop_front()
		return ERR_OUT_OF_MEMORY if var_to_bytes(message).size() > max_packet_bytes else OK

class Console extends RefCounted:
	var calls:int = 0
	func execute(_command:String) -> Dictionary:
		calls += 1
		return {"ok":true,"result":{"large": "x".repeat(4096)}}

var checks:int = 0
var failures:Array[String] = []

func check(value:bool, label:String) -> void:
	checks += 1
	if not value: failures.append(label)

func _init() -> void:
	var gateway = preload("res://scripts/net/server_gateway.gd").new()
	var wire = FailingTransport.new()
	gateway.transport = wire
	var diagnostics:Array = []
	gateway.send_failed.connect(func(value:Dictionary): diagnostics.append(value))
	# 任意隐藏载荷不能进入发送诊断；真实超预算返回必须被消费。
	var secret:String = "SECRET_TOKEN_HIDDEN_CARD"
	check(gateway._send_client(7,{"kind":"private","token":secret,"face":secret,"data":"x".repeat(4096)},2,"room_response") == ERR_OUT_OF_MEMORY,"超预算返回值")
	check(not str(diagnostics).contains(secret),"诊断不泄漏载荷")
	check(diagnostics.back().error_code == ERR_OUT_OF_MEMORY and not diagnostics.back().queued,"失败不称入队")
	# 错误回执本身拒发不得递归；仅有一次发送。
	wire.results = [ERR_UNAVAILABLE]
	var before:int = wire.replies.size()
	gateway._fail(7,"安全错误")
	check(wire.replies.size() == before + 1,"失败回执不递归")
	check(gateway.last_send_failure.stage == "error_receipt","失败回执可诊断")
	# 上行失败不能声称权威执行成功，且不能改变路由/权限。
	var upstream = FailingTransport.new()
	upstream.results = [ERR_UNAVAILABLE]
	gateway.routes[7] = {"attached":true,"link":upstream,"room":"test"}
	gateway._receive(7,{"kind":"match_request","args":{"token":secret}})
	check(upstream.replies.size() == 1 and gateway.routes.has(7),"上行失败保留路由")
	check(wire.replies.back().message.kind == "error" and wire.replies.back().message.reason.contains("未确认"),"上行失败安全回执")
	check(not str(diagnostics).contains(secret),"上行诊断不泄密")
	# 正式管理员权限校验仍执行；超预算完整结果触发同序号小回执。
	gateway.identity_registry.path = "fixture"
	gateway.identity_registry.users["admin"] = {"admin":true}
	gateway.authenticated_identities[7] = "admin"
	gateway.admin_console = Console.new()
	gateway._receive_admin_command(7,{"v":1,"seq":1,"args":{"command":"status"}})
	check(gateway.admin_console.calls == 1,"回执失败不重执行")
	var fallback:Dictionary = wire.replies.back().message
	check(fallback.kind == "server_admin_result" and fallback.request_seq == 1,"回执保留请求序号")
	check(not fallback.response.ok and fallback.response.result.execution_returned and not fallback.response.result.result_available,"执行与结果传输分离")
	gateway._receive_admin_command(7,{"v":1,"seq":1,"args":{"command":"status"}})
	check(gateway.admin_console.calls == 1,"重复序号仍被拒")
	gateway._receive_admin_command(8,{"v":1,"seq":2,"args":{"command":"status"}})
	check(gateway.admin_console.calls == 1,"非管理员仍被拒")
	# 完整和最小回执均失败时仍只有两次尝试，不再次执行。
	wire.results = [ERR_UNAVAILABLE,ERR_UNAVAILABLE]
	before = wire.replies.size()
	gateway._receive_admin_command(7,{"v":1,"seq":2,"args":{"command":"status"}})
	check(wire.replies.size() == before + 2 and gateway.admin_console.calls == 2,"最小回执失败有界")
	check(gateway.last_send_failure.stage == "admin_result_fallback","最小回执失败可诊断")
	wire.results = [OK,ERR_UNAVAILABLE]
	var notice:Dictionary = gateway.broadcast_notice("通知")
	check(not notice.ok and notice.result.queued == 1 and notice.result.failed == 1,"广播只报告入队和失败")
	# 夹具不是网络验收，不调用 close 的真实连接清理路径。
	gateway.routes.clear()
	print("RESULT gateway_send_diagnostics checks=%d failures=%s" % [checks,str(failures)])
	quit(0 if failures.is_empty() else 1)
