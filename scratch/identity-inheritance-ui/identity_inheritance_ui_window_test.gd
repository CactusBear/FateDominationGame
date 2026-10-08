extends Node

## 仅窗口控件契约夹具，不连接网络、不读身份文件、不替代认证/落盘测试。
const PanelScene = preload("res://assets/scenes/main_menu/identity_inheritance_panel.tscn")
class FakeTransport extends RefCounted:
	var connected:bool = true
	func is_connected_to_host() -> bool:
		return connected
class FakeSession extends RefCounted:
	signal inheritance_candidates_received(model:Dictionary)
	var transport = FakeTransport.new()
	var identity_authenticated:bool = true
	var sent:Array = []
	var view:Dictionary = {"dedicated":true,"owner":2,"revision":10,"members":[
		{"id":2,"name":"房主","connected":true,"spectator":false},
		{"id":9,"name":"原昵称","connected":false,"spectator":false}]}
	func peer_id() -> int:
		return 2
	func request(kind:String, args:Dictionary) -> Error:
		sent.append({"kind":kind,"args":args.duplicate(true)})
		return OK
var failures:Array[String] = []
var checks:int = 0

func _ready() -> void:
	call_deferred("_run")

func _check(condition:bool, description:String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)

func _frames() -> void:
	for index in range(3):
		await get_tree().process_frame

func _click(window:Window, control:Control, local_position:Vector2) -> void:
	var point:Vector2 = control.get_global_transform() * local_position
	var motion := InputEventMouseMotion.new()
	motion.position = point
	window.get_viewport().push_input(motion, true)
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	window.get_viewport().push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	window.get_viewport().push_input(event, true)

func _reply(fake, revision:int) -> void:
	fake.inheritance_candidates_received.emit({"revision":revision,"request_floor":4,"candidates":[
		{"member_id":31,"label":"同名（alice）"},
		{"member_id":42,"label":"同名（bob）"}]})

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().has("window"):
		push_error("本专项要求非 headless 且携带 -- window；未执行窗口段")
		get_tree().quit(2)
		return
	var fake = FakeSession.new()
	var panel = PanelScene.instantiate()
	add_child(panel)
	panel.open_for(fake, 9, "原昵称")
	await _frames()
	_check(fake.sent.back().kind == "identity_candidates" and fake.sent.back().args.is_empty(), "查询仅发送空参数")
	_reply(fake, 10)
	await _frames()
	var list:ItemList = panel.get_node("Content/Candidates")
	var confirm:Button = panel.get_node("Content/Buttons/Confirm")
	_check(list.item_count == 2 and list.get_item_text(0) == "同名（alice）" and list.get_item_text(1) == "同名（bob）", "逐字使用服务端标签，不猜重名")
	_check(list.get_item_metadata(1) == 42 and list.get_selected_items().is_empty() and confirm.disabled, "metadata 稳定身份，不自动选首项")
	_click(panel, list, list.get_item_rect(1).get_center())
	await _frames()
	_check(not confirm.disabled, "真实鼠标选择解锁确认")
	_click(panel, confirm, confirm.size / 2.0)
	await _frames()
	_check(fake.sent.back() == {"kind":"identity_inherit","args":{"target_member":9,"successor_member":42,"revision":10}}, "按稳定身份及 revision 提交")
	_check(list.item_count == 0 and confirm.disabled, "提交后立即清理选择，禁止双击")
	var submitted:int = fake.sent.size()
	panel._submit()
	_check(fake.sent.size() == submitted, "重复确认没有第二个请求")
	fake.view.revision = 11
	panel.refresh_context()
	_check(panel._input.revision == -1 and confirm.disabled, "房间版本变化清理选择")
	panel._query_candidates()
	_reply(fake, 10)
	_check(list.item_count == 0 and panel._input.revision == -1, "迟到版本候选不显示")
	panel._query_candidates()
	_reply(fake, 11)
	await _frames()
	_click(panel, list, list.get_item_rect(0).get_center())
	await _frames()
	panel.request_failed()
	_check(list.item_count == 0 and confirm.disabled, "失败清理选择")
	panel._query_candidates()
	_reply(fake, 11)
	fake.transport.connected = false
	panel.refresh_context()
	_check(not panel.visible and panel._input.selected_member == 0, "断线关闭窗口并清理选择")
	fake.transport.connected = true
	panel.open_for(fake, 9, "原昵称")
	_reply(fake, 11)
	fake.view.owner = 9
	panel.refresh_context()
	_check(not panel.visible and list.item_count == 0, "房主权限丢失清理选择")
	fake.view.owner = 2
	fake.identity_authenticated = false
	panel.open_for(fake, 9, "原昵称")
	_check(not panel.visible, "未认证不允许打开")
	fake.identity_authenticated = true
	fake.view.members[1].connected = true
	panel.open_for(fake, 9, "原昵称")
	_check(not panel.visible, "原成员已在线不允许继承")
	fake.view.members[1].connected = false
	panel.open_for(fake, 9, "原昵称")
	panel.close_panel()
	_reply(fake, 11)
	_check(list.item_count == 0 and not fake.inheritance_candidates_received.is_connected(panel._accept_candidates), "关闭解绑，迟到回复不能复活窗口")
	panel.queue_free()
	await _frames()
	print("RESULT identity_inheritance_ui_window checks=%d failures=%d" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
