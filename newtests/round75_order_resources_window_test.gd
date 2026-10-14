extends Node
## 只投递公开快照；生产 presenter/process 与 GUI 路由保持原样。
var board
var session
var checks := 0
var failures: Array = []
var motion_count := 0
var down_count := 0
var up_count := 0
var gui_down := 0
var gui_up := 0
var captures: Array = []
var traces: Array = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
	print("CHECK ", label, " ", ok)

func frames(n: int) -> void:
	for i in n: await get_tree().process_frame

func _ready() -> void:
	call_deferred("run")

func deliver(view: Dictionary, label: String) -> void:
	session.transport.message_received.emit(1, {"kind":"match_view", "state":view, "pending":{}, "actions":{}})
	check(session.read_match() == view, label + " 正式session镜像接收")
	await frames(5)

func observe(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed: gui_down += 1
		else: gui_up += 1

func click(target: Control, label: String) -> void:
	var point := target.get_global_rect().get_center()
	var ev := InputEventMouseMotion.new()
	ev.position = point
	ev.global_position = point
	ev.relative = Vector2(1, 0)
	motion_count += 1
	get_viewport().push_input(ev, true)
	await frames(1)
	check(get_viewport().gui_get_hovered_control() == target, label + " hovered真实命中")
	for down in [true, false]:
		var button := InputEventMouseButton.new()
		button.position = point
		button.global_position = point
		button.pressed = down
		button.button_index = MOUSE_BUTTON_LEFT
		button.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		if down: down_count += 1
		else: up_count += 1
		get_viewport().push_input(button, true)
		await frames(1)

func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "res://tests/runtime_reports/" + label + ".png"
	check(get_viewport().get_texture().get_image().save_png(path) == OK, label + " 窗口截图保存")
	captures.append(path)

func text_at(root: Node, path: String) -> String:
	var node := root.get_node_or_null(path)
	return node.text if node is Label else "<missing-node>"

func resource_check(view: Dictionary, label: String) -> void:
	var player: Dictionary = view.players[1]
	var rival: Control = board._rival_card(1)
	check(rival != null and rival.is_visible_in_tree(), label + " 敌方信息可见")
	if rival == null: return
	var mana: Array = []
	for node in rival.get_node("MagicSigil").find_children("*", "Label", true, false):
		if node.is_visible_in_tree(): mana.append(node.text)
	var spell: Array = []
	for node in rival.get_node("Stats/Spells").find_children("*", "Label", true, false):
		if node.is_visible_in_tree(): spell.append(node.text)
	check(mana.has(BaseNumber.display_text(player.magic)), label + " 敌魔力文本等于快照")
	check(text_at(rival, "Stats/PowerStat/V") == BaseNumber.display_text(player.total_power), label + " 敌总威力文本等于快照")
	check(text_at(rival, "Stats/ScoreStat/V") == BaseNumber.display_text(player.score), label + " 敌战果文本等于快照")
	check(spell.has("×%d" % player.command_spell_count) or spell.has("× %d" % player.command_spell_count), label + " 敌令咒文本等于快照")
	var drawer: Control = board._opponent_drawer
	var texts: Array = []
	if drawer.visible:
		for node in drawer.find_children("*", "Label", true, false):
			if node.is_visible_in_tree(): texts.append({"path":str(drawer.get_path_to(node)),"text":node.text})
	traces.append({"label":label,"snapshot":{"magic":player.magic,"total_power":player.total_power,"score":player.score,"command_spell_count":player.command_spell_count},"mana":mana,"power":text_at(rival,"Stats/PowerStat/V"),"score":text_at(rival,"Stats/ScoreStat/V"),"spells":spell,"drawer":texts})

func run() -> void:
	check(DisplayServer.get_name() != "headless" and OS.get_cmdline_user_args().has("window"), "真实窗口分支")
	GameStart.reset()
	EffectManager.reset_runtime()
	GameLog.reset()
	GameData.player_data_library.clear()
	for pid in range(3):
		var data: Dictionary = GameData.new_player_data()
		data.player_name = ["顺位甲", "顺位乙", "顺位丙"][pid]
		data.order.set_num(BaseNumber.new(pid))
		GameData.player_data_library[pid] = data
	GameProgress.reset_progress()
	var builder = preload("res://scripts/match/view_builder.gd").new()
	var view: Dictionary = builder.build(0)
	view.seq = 101
	view.current_player = 0
	view.players[1].magic = 5
	view.players[1].total_power = 7.5
	view.players[1].score = 3
	view.players[1].command_spell_count = 2
	session = preload("res://scripts/net/session/lobby_session.gd").new()
	session.transport.message_received.emit(1, {"kind":"match_bind", "observer":0})
	await deliver(view, "初始快照")
	board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	board.network_session = session
	add_child(board)
	await frames(90)
	var visible_buttons: Array = []
	for node in board.find_children("*", "BaseButton", true, false):
		if node.is_visible_in_tree(): visible_buttons.append({"path":str(board.get_path_to(node)),"text":node.text if node is Button else ""})
	var order_toggle: Control = null
	for item in visible_buttons:
		if "顺位" in item.text or "行动顺序" in item.text: order_toggle = board.get_node(item.path)
	check(order_toggle != null, "A 行动顺位表真实展开折叠入口存在")
	var rows: Array = []
	for index in view.players.size():
		var player: Dictionary = view.players[index]
		var row: Control = board._rival_card(player.id)
		check(row != null and row.is_visible_in_tree(), "A 顺位%d节点可见" % (index + 1))
		if row == null: continue
		check(text_at(row,"Order/Label") == str(index + 1), "A 顺位%d序号与快照顺序一致" % (index + 1))
		check(text_at(row,"Name") == player.player_name, "A 顺位%d显示真实玩家名" % (index + 1))
		var geometry: Array = []
		for node in row.find_children("*", "Label", true, false):
			if node.is_visible_in_tree(): geometry.append({"path":str(row.get_path_to(node)),"text":node.text,"font":node.get_theme_font_size("font_size"),"rect":str(node.get_global_rect())})
		rows.append({"id":player.id,"rect":str(row.get_global_rect()),"labels":geometry})
	traces.append({"order_rows":rows,"visible_buttons":visible_buttons,"toggle_found":order_toggle != null})
	await capture("order-resources-initial")
	var rival: Control = board._rival_card(1)
	if rival == null:
		print("RESULT ", JSON.stringify({"suite":"round75_order_resources_window","checks":checks,"failures":failures,"fixture_blocked":true}))
		get_tree().quit(1)
		return
	rival.gui_input.connect(observe)
	await click(rival, "B 打开对手抽屉")
	check(board._opponent_drawer.visible and board._selected_opponent_id == 1, "B 真实点击打开对手信息")
	resource_check(view, "B 初始")
	var updated: Dictionary = view.duplicate(true)
	updated.seq = 102
	updated.players[1].magic = 9
	updated.players[1].total_power = 12.75
	updated.players[1].score = 11
	updated.players[1].command_spell_count = 1
	await deliver(updated, "变更快照")
	resource_check(updated, "B 更新")
	check(board._opponent_drawer.visible and board._selected_opponent_id == 1, "B 更新保留打开抽屉")
	await capture("order-resources-updated")
	await click(rival, "B 关闭对手抽屉")
	check(not board._opponent_drawer.visible, "B 再次真实点击关闭")
	var missing: Dictionary = updated.duplicate(true)
	missing.seq = 103
	# 数值魔力/战果/令咒是严格协议必需项，不能伪造为可缺省项。
	for field in ["total_power","special_command_spells"]: missing.players[1].erase(field)
	await deliver(missing, "缺字段快照")
	var rubbish: Array = []
	var absent_power: Label = rival.get_node("Stats/PowerStat/V")
	if absent_power.is_visible_in_tree() and not absent_power.text.is_empty(): rubbish.append({"path":"Stats/PowerStat/V","text":absent_power.text})
	check(rubbish.is_empty(), "B 缺字段不显示占位垃圾数值")
	traces.append({"missing_visible_fields":rubbish})
	await capture("order-resources-missing")
	check(gui_down == down_count and gui_up == up_count, "单路输入down/up全部进入真实GUI")
	print("TRACE ", JSON.stringify(traces))
	print("GUIINPUT ", JSON.stringify({"motion":motion_count,"down":down_count,"up":up_count,"gui_down":gui_down,"gui_up":gui_up}))
	print("VISUAL ", JSON.stringify(captures))
	board.queue_free()
	await frames(2)
	board = null
	session.close()
	session = null
	GameStart.reset()
	print("RESULT ", JSON.stringify({"suite":"round75_order_resources_window","checks":checks,"failures":failures,"window":true,"input_path":"single Viewport.push_input motion/frame/down/frame/up/frame; no warp/pressed.emit; transport snapshot delivery not ENet"}))
	get_tree().quit(0 if failures.is_empty() else 1)
