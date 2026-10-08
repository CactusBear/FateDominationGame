extends Node

const Gateway = preload("res://scripts/net/server/server_gateway.gd")
const Manager = preload("res://scripts/net/server/server_room_manager.gd")

class LinkFixture extends RefCounted:
	var closed:bool = false
	func close() -> void:
		closed = true

var checks:int = 0
var failures:Array[String] = []

func _check(value:bool,label:String) -> void:
	checks += 1
	if not value: failures.append(label)

func _ready() -> void:
	var manager = Manager.new()
	manager.rooms["room-a"] = {"id":"room-a","pid":77,"instance_id":"11111111111111111111111111111111","authority_host_mode":"dedicated","ready":true}
	var binding:Dictionary = manager.instance_binding("room-a")
	_check(manager.binding_matches(binding),"有效静态绑定")
	_check(not manager.binding_matches(binding,true),"未提供 OS 句柄验证时拒绝 ready")
	manager.process_identity_verifier = func(_binding:Dictionary): return 1
	_check(not manager.process_identity_verified(binding),"非 bool 验证结果拒绝")
	# 注入仅用于隔离消费者反例，不构成真实 OS 句柄验证证据。
	manager.process_identity_verifier = func(_binding:Dictionary): return true
	_check(manager.binding_matches(binding,true),"可信提供者消费者接线")
	manager.rooms["room-a"].instance_id = "22222222222222222222222222222222"
	_check(not manager.binding_matches(binding,true),"PID 相同而实例更换拒绝")
	manager.rooms["room-a"].instance_id = binding.instance_id
	manager.rooms["room-a"].authority_host_mode = "p2p"
	_check(not manager.binding_matches(binding,true),"实例相同而权威模式更换拒绝")
	manager.rooms["room-a"].authority_host_mode = "dedicated"
	var other:Dictionary = binding.duplicate(true)
	other.room = "room-b"
	_check(not manager.binding_matches(other),"房间更换拒绝")
	manager.rooms["room-a"].pid = -1
	_check(not manager.binding_matches(binding,true),"进程退出后旧 PID 拒绝")
	manager.rooms["room-a"].pid = 77
	var gateway = Gateway.new()
	gateway.manager = manager
	var old_link = LinkFixture.new()
	var new_link = LinkFixture.new()
	var old_route:Dictionary = binding.duplicate(true)
	old_route.merge({"link":old_link,"attached":true})
	var new_route:Dictionary = binding.duplicate(true)
	new_route.merge({"link":new_link,"attached":true})
	gateway.routes[9] = old_route
	gateway._queue_route_disconnect(9,old_route)
	gateway.routes[9] = new_route
	gateway.authenticated_identities[9] = "authenticated-fixture"
	gateway._room_response(9,old_route,1,{"kind":"room","state":{"members":[1]}})
	gateway._room_disconnected(9,old_route)
	_check(gateway._disconnected_routes.size() == 1,"旧断线回调不得添加新路由回收项")
	var queued:Dictionary = gateway._disconnected_routes[0]
	gateway._detach_route(queued.peer,queued.route)
	_check(gateway.routes.has(9) and not new_link.closed,"旧排队回收不得关闭新 link")
	_check(gateway.last_send_failure.is_empty(),"旧消息/断线回调不得转发到公网")
	gateway._detach_route(9,new_route)
	_check(new_link.closed and not gateway.routes.has(9),"当前路由正常清理")
	_check(gateway.authenticated_identities.has(9),"内部断线保留公网认证身份")
	gateway._disconnected_routes.clear()
	# 夹具不得向实际 OS 进程调用 kill；销毁前清除合成登记。
	manager.rooms.clear()
	gateway.close()
	print("RESULT gateway_instance_binding checks=%d failures=%d" % [checks,failures.size()])
	for failure in failures: push_error(failure)
	get_tree().quit(0 if failures.is_empty() else 1)
