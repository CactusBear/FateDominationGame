extends Node

var failures:Array = []
var checks:int = 0


## 分步落盘：卡死时最后一条标记就是卡住的位置（print 在管道里会被缓冲，读不到）
func mark(label:String) -> void:
	var file = FileAccess.open("res://debug_console_probe.txt", FileAccess.READ_WRITE if FileAccess.file_exists("res://debug_console_probe.txt") else FileAccess.WRITE)
	if file == null:
		return
	file.seek_end()
	file.store_line(label)
	file.flush()
	file.close()


func check(ok:bool, label:String) -> void:
	checks += 1
	if !ok:
		failures.append(label)
	print("CHECK ", label, " ", ok)


func _ready() -> void:
	call_deferred("run")


func capture_window(name:String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://tests/runtime_reports")
	var path:String = "res://tests/runtime_reports/%s.png" % name
	check(get_viewport().get_texture().get_image().save_png(path) == OK, "window screenshot saved " + name)


func press_console_key(host, event:InputEventKey) -> void:
	if DisplayServer.get_name() == "headless":
		host._input(event)
	else:
		get_tree().root.push_input(event, true)
	await get_tree().process_frame


## SpinBox 的数值框与 OptionButton 的内置下拉搜索框都是引擎自带的 LineEdit，
## 它们不算“命令行输入”：判断是否还存在命令行输入时要把这类内嵌控件排除掉。
func has_embedded_input_ancestor(node:Node) -> bool:
	var parent:Node = node.get_parent()
	while parent != null:
		if parent.is_class("SpinBox") or parent.is_class("OptionButton") \
				or parent.is_class("ItemList") or parent.is_class("MenuButton"):
			return true
		parent = parent.get_parent()
	return false


func run() -> void:
	mark("run:start")
	var host = load("res://assets/scenes/game_scene/tactical_board_ui.tscn").instantiate()
	get_tree().root.add_child(host)
	host.set_process(false)
	await get_tree().process_frame
	await get_tree().process_frame

	check(!host.is_debug_console_enabled(), "console is not preloaded by default")
	var toggle_key := InputEventKey.new()
	toggle_key.physical_keycode = KEY_QUOTELEFT
	toggle_key.pressed = true
	await press_console_key(host, toggle_key)
	check(host.is_debug_console_enabled(), "wave key lazily enables the console")
	var console:DebugConsoleUI = host._debug_console
	check(console != null and console.session != null, "console owns an initialized debug session")
	check(console.is_panel_open(), "wave key opens the console panel")
	check(console.session.is_paused() and host._is_debug_console_blocking_progress(), "opening console pauses automatic progress")
	check(console.get_node("InputBlocker").visible, "opening console shows the input blocker")
	await press_console_key(host, toggle_key)
	check(!console.is_panel_open() and !console.session.is_paused(), "pressing wave key again closes the console")
	await press_console_key(host, toggle_key)
	check(console.is_panel_open() and console.session.is_paused(), "wave key reopens the existing console session")
	await capture_window("debug_console_open")
	# 切到操作页再截一张：按钮面板的排版只有窗口模式看得出来
	var actions_tab:int = console._tabs.get_tab_idx_from_control(console._actions)
	check(actions_tab >= 0, "the action panel is a tab of the console")
	console._tabs.current_tab = actions_tab
	(console._actions._command_buttons["resource.number"] as Button).emit_signal("pressed")
	await capture_window("debug_console_actions")
	# 截完切回只读页，后续断言不受页签影响
	console._tabs.current_tab = 0

	var inspect_result:Dictionary = console.session.execute_action("inspect.player", {"player":"local"})
	check(bool(inspect_result.get("ok", false)), "inspect.player accepts the explicit local player alias")
	var invalid_player:Dictionary = console.session.execute_action("inspect.player", {"player":999999})
	check(!bool(invalid_player.get("ok", false)), "unknown player ids are rejected without creating players")
	check(!GameData.player_data_library.has(999999), "rejected ids do not create ghost players")
	var local_cards:Array = GameData.player_data_library[GameData.player_id].get("hand_cards", [])
	if !local_cards.is_empty():
		var inspect_card:Dictionary = console.session.execute_action("inspect.card", {"id":local_cards[0].get_instance_id()})
		check(bool(inspect_card.get("ok", false)), "inspect.card resolves an instance without an unrelated player parameter")
	var deploy_outside_phase:Dictionary = console.session.execute_action("map.deploy", {"player":"local", "area":MapData.areas[0]._area_name})
	check(!bool(deploy_outside_phase.get("ok", false)), "rule deployment is rejected outside the outpost action boundary")

	var local_id:int = GameData.player_id
	var local_data:Dictionary = GameData.player_data_library[local_id]
	var moved_card = null
	var old_order = local_data.order.number
	var edit_result:Dictionary = console.session.execute_action("resource.number", {"player":"local", "key":"order", "set":old_order + 1})
	check(bool(edit_result.get("ok", false)), "registered resource command executes through the registry")
	check(edit_result.has("validation"), "successful writes run debug validation")
	check(console.session.audit_entries().size() >= 3, "commands are recorded in the independent debug audit")
	var undo_result:Dictionary = console.session.execute_action("session.undo")
	check(bool(undo_result.get("ok", false)) and local_data.order.number == old_order,
		"session.undo restores an unchanged local edit without emitting a rule action")

	# 按钮路径：真实按下一个操作按钮、改控件、按“执行”，验证界面到 registry 的整条链，
	# 而不是只验证 session.execute_action 这个 API。
	var no_line_edit:int = 0
	for node in console.find_children("*", "LineEdit", true, false):
		if !has_embedded_input_ancestor(node):
			no_line_edit += 1
	check(no_line_edit == 0, "console panel exposes no command text input")
	var panel = console._actions
	check(panel != null, "action panel is wired into the console")
	# 面板默认对准本地玩家；这里按 id 反查下标，避免把「0 号玩家」当成默认目标
	var local_index:int = -1
	for i in range(panel._player_picker.item_count):
		if int(panel._player_picker.get_item_id(i)) == local_id:
			local_index = i
	check(local_index >= 0, "the target player picker lists the local player")
	panel._player_picker.select(local_index)
	panel._player_picker.emit_signal("item_selected", local_index)
	check(panel._selected_player_id == local_id, "player picker drives the panel target")
	(panel._command_buttons["resource.number"] as Button).emit_signal("pressed")
	check(panel._selected_command == "resource.number", "pressing an action button selects its command")
	check(panel._field_controls.has("amount") and panel._field_controls.has("key"), "the form builds typed controls for the command")
	var key_picker := panel._field_controls["key"] as OptionButton
	var key_index:int = 0
	for i in range(key_picker.item_count):
		if str(key_picker.get_item_metadata(i)) == "order":
			key_index = i
	key_picker.select(key_index)
	var mode_picker := panel._field_controls["mode"] as OptionButton
	mode_picker.select(0)
	(panel._field_controls["amount"] as SpinBox).value = float(old_order + 2)
	(panel._run_button as Button).emit_signal("pressed")
	mark("panel:resource.number executed")
	check(local_data.order.number == old_order + 2, "pressing the run button applies the chosen parameters")
	check(console.session.audit_entries().back().command == "resource.number", "button executions are audited like any other action")
	check(bool(console.session.execute_action("session.undo").get("ok", false)) and local_data.order.number == old_order,
		"the button-driven edit stays undoable")

	if !local_cards.is_empty():
		moved_card = local_cards[0]
		var move_result:Dictionary = console.session.execute_action("zone.move",
			{"card_id":moved_card.get_instance_id(), "player":"local", "to":"discard"})
		check(bool(move_result.get("ok", false)) and local_data.discard.has(moved_card) \
			and !local_data.hand_cards.has(moved_card), "zone.move preserves unique card ownership")
		var undo_move:Dictionary = console.session.execute_action("session.undo")
		check(bool(undo_move.get("ok", false)) and local_data.hand_cards.has(moved_card) \
			and !local_data.discard.has(moved_card), "session.undo restores a card to its exact source zone")

	# 面板路径：按钮不传 player（zone.move 的 schema 不要求玩家），走的是从属主推断的那条分支。
	# 与上面显式传 player 的调用是两条不同的参数形态，必须都覆盖。
	(panel._command_buttons["zone.move"] as Button).emit_signal("pressed")
	check(panel._selected_command == "zone.move", "the move-card button selects zone.move")
	var card_picker := panel._field_controls["card_id"] as OptionButton
	var zone_picker := panel._field_controls["to"] as OptionButton
	check(card_picker != null and card_picker.item_count > 0, "the move-card form lists real cards")
	check(zone_picker != null and zone_picker.item_count > 0, "the move-card form lists real zone paths")
	var pick_index:int = -1
	for i in range(card_picker.item_count):
		if int(card_picker.get_item_metadata(i)) == moved_card.get_instance_id():
			pick_index = i
	check(pick_index >= 0, "the target card is offered by the form")
	card_picker.select(pick_index)
	var to_index:int = -1
	for i in range(zone_picker.item_count):
		if str(zone_picker.get_item_metadata(i)) == "played_cards":
			to_index = i
	check(to_index >= 0, "the played cards zone is offered by the form")
	zone_picker.select(to_index)
	mark("panel:zone.move form filled")
	(panel._run_button as Button).emit_signal("pressed")
	mark("panel:zone.move executed")
	check(local_data.played_cards.has(moved_card) and !local_data.hand_cards.has(moved_card),
		"the move-card button moves the card without an explicit player argument")
	check(bool(console.session.execute_action("session.undo").get("ok", false)) and local_data.hand_cards.has(moved_card),
		"a button-driven move outside the hand is undoable")

	var ids:Array = GameData.player_data_library.keys()
	ids.sort()
	if ids.size() >= 2:
		mark("identity:start")
		var first_id:int = int(ids[0])
		var second_id:int = int(ids[1])
		var occupied_master = GameData.player_data_library[first_id].get("master")
		var occupied_name:String = occupied_master._name if occupied_master != null else ""
		var identity_result:Dictionary = console.session.execute_action("identity.set_master",
			{"player":second_id, "master_name":occupied_name, "occupancy":"exclusive"})
		check(!bool(identity_result.get("ok", false)), "exclusive identity replacement rejects an occupied template")
		var steal_master:Dictionary = console.session.execute_action("identity.set_master",
			{"player":second_id, "master_name":occupied_name, "occupancy":"steal"})
		check(bool(steal_master.get("ok", false)), "steal identity policy performs the declared ownership transfer")
		check(GameData.player_data_library[first_id].get("master") == null \
			and GameData.player_data_library[second_id].get("master") == occupied_master,
			"master ownership is transferred without changing player ids")
		check(bool(steal_master.get("validation", {}).get("ok", false)), "master replacement preserves debug invariants")
		mark("identity:done")

	console.close_panel()
	check(!console.is_panel_open() and !console.session.is_paused(), "closing console releases only its pause tokens")
	check(!console.get_node("InputBlocker").visible, "closing console hides the input blocker")

	# 全量操作扫描：每个操作按钮都必须真正走到 registry（或由面板给出拒绝原因）。
	# 判据故意不看返回值对不对，只看「有没有发生」——脚本错误会把整段提交中断，
	# 结果既没有审计条目、也没有状态说明，正是用户看到的「点确认就断」。
	console.open_panel()
	mark("sweep:start")
	# 先单独确认「抽一张牌」真的抽得动：它返回成功却没有变化时，玩家会以为按钮坏了
	(panel._command_buttons["zone.draw"] as Button).emit_signal("pressed")
	var hand_before:int = local_data.hand_cards.size()
	var deck_before:int = local_data.deck.size()
	(panel._run_button as Button).emit_signal("pressed")
	print("DRAW hand ", hand_before, "->", local_data.hand_cards.size(), " deck ", deck_before, "->", local_data.deck.size())
	check(local_data.hand_cards.size() == hand_before + 1, "zone.draw really moves one card from deck to hand")

	var sweep_commands:Array = []
	for raw_name in console.session.registry.command_names():
		if panel._command_buttons.has(str(raw_name)):
			sweep_commands.append(str(raw_name))
	check(sweep_commands.size() >= 40, "every registered command has an action button (%d)" % sweep_commands.size())
	var silent_failures:Array = []
	var executed_count:int = 0
	for command_name in sweep_commands:
		mark("sweep:" + command_name)
		(panel._command_buttons[command_name] as Button).emit_signal("pressed")
		if command_name == "play.regular":
			# 常规整组出牌需要先挑牌；不挑的话面板会给出说明而不提交，扫不到这条链
			for key in ["faceup", "hidden"]:
				var list = panel._field_controls.get(key)
				if list is ItemList and (list as ItemList).item_count > 0:
					(list as ItemList).select(0)
					break
		var audits_before:int = console.session.audit_entries().size()
		(panel._run_button as Button).emit_signal("pressed")
		var reached:bool = console.session.audit_entries().size() > audits_before
		var explained:bool = (panel._status.text as String).strip_edges() != ""
		if !reached and !explained:
			silent_failures.append(command_name)
		if reached:
			executed_count += 1
			var entry:Dictionary = console.session.audit_entries().back()
			print("SWEEP ", command_name, " ok=", entry.ok, " changed=", entry.changed, " reason=", entry.reason)
			if bool(entry.get("changed", false)):
				check(entry.has("validation"), "%s ran the post-write validation" % command_name)
	print("SWEEP reached=", executed_count, " of ", sweep_commands.size())
	check(silent_failures.is_empty(), "no action button fails silently: %s" % str(silent_failures))

	# 跑完所有操作后局面仍要自洽（与写命令后跑的同一套检查）
	var final_validation:Dictionary = DebugValidate.validate_all(console.session._template_baseline)
	check(bool(final_validation.get("ok", true)),
		"the game stays consistent after every operation was exercised: %s" % str(final_validation.get("issues", [])))
	mark("sweep:done")
	console.close_panel()

	# 重复初始化（宿主再次启用控制台时会发生）不能让旧按钮引用残留：
	# 旧节点已被 free，留着就会在遍历/取值时碰到已释放对象。
	mark("reinit:start")
	console.initialize(host)
	await get_tree().process_frame
	check(console._actions._command_buttons.size() >= 40, "re-initializing rebuilds every action button")
	(console._actions._command_buttons["inspect.player"] as Button).emit_signal("pressed")
	(console._actions._run_button as Button).emit_signal("pressed")
	check(!console.session.audit_entries().is_empty(), "buttons rebuilt by re-initialization are still wired")
	mark("reinit:done")

	host.set_debug_console_enabled(false)
	await get_tree().process_frame
	check(!host.is_debug_console_enabled(), "disabling console frees the instance")
	host.set_debug_console_enabled(true)
	await get_tree().process_frame
	check(host.is_debug_console_enabled() and host._debug_console != console, "console can be enabled again without reusing stale state")
	host.set_debug_console_enabled(false)
	host.queue_free()
	await get_tree().process_frame

	print("RESULT checks=", checks, " failures=", failures)
	var file = FileAccess.open("res://debug_console_test_result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks, "failures":failures}))
	file.close()
	get_tree().quit(0 if failures.is_empty() else 1)
