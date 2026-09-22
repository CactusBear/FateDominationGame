extends Node

# RED 交给主代理串行运行；本场景不自动修改生产代码。
const UI_SCENE = preload("res://assets/scenes/game_scene/tactical_board_ui.tscn")
const TOTAL_SCRIPT = preload("res://assets/scripts/system/operations/GetPlayerTotalPower.gd")
const BOARD_SCRIPT = preload("res://assets/scripts/system/global/board_power_query.gd")
var failures:Array = []
var checks:int = 0
var scene

func check(ok:bool, label:String):
	checks += 1
	if not ok: failures.append(label)
	print("CHECK ", label, " ", ok)

func _ready():
	call_deferred("run")

func template(pool:Array, key:String):
	for card in pool:
		if card._name == key: return card
	return null

func attack(key:String, attrs:Array = ["strength"], power:int = 2):
	var card = BaseAttack.new(key, "", attrs, BaseNumber.new(1), BaseNumber.new(power))
	card._category = "basic"
	return card

func setup(event_key:String = "", situation_key:String = "") -> Dictionary:
	EffectManager.reset_runtime()
	GameLog.reset()
	GameProgress.current_round = 1
	GameProgress.current_phase_index = 2
	GameProgress.current_player_id = 0
	GameLog.set_context(1, "action")
	TimePointChecker.phase_time_points.clear()
	for area in MapData.areas:
		area._events.clear()
		for loc in area._locations: loc._players.clear()
	MapData.active_situation = null
	# 保留 UI 启动时建立的身份，清理所有玩家的回合资源与区域。
	for id in GameData.player_data_library.keys():
		var old:Dictionary = GameData.player_data_library[id]
		var fresh:Dictionary = GameData.new_player_data()
		fresh.master = old.master
		fresh.servant = old.servant
		fresh.order.number = int(id)
		fresh.is_out = false
		fresh.magic.number = 10
		GameData.player_data_library[id] = fresh
	var area = MapData.miyama0.get_from()
	check(Deploy.new().exec(MapData.miyama0, 0), "fixture deploys local player")
	check(Deploy.new().exec(MapData.miyama1, 1), "fixture deploys other player")
	if not event_key.is_empty():
		var source = template(LoadEvent.events, event_key)
		check(source != null, "fixture event exists: " + event_key)
		if source != null:
			var event = CloneObject.new().exec(source)
			event.from = area
			event._is_concealed = false
			area._events.append(event)
	if not situation_key.is_empty():
		var source = template(LoadSituation.situations, situation_key)
		check(source != null, "fixture situation exists: " + situation_key)
		if source != null: MapData.active_situation = CloneObject.new().exec(source)
	scene._local_player_id = 0
	scene._regular_play_pending_cards.clear()
	scene._regular_play_pending_hidden.clear()
	scene._pending_tactical_action.clear()
	scene._confirm_alert_mode = false
	if scene.tactical_confirm_modal: scene.tactical_confirm_modal.visible = false
	return GameData.player_data_library[0]

# 值快照只用于断言，不克隆世界、不回滚查询。对象身份与可变卡面另行记录。
func freeze(value):
	if value is BaseNumber: return [value.get_instance_id(), value.number]
	if value is Array:
		var result:Array = []
		for item in value: result.append(freeze(item))
		return result
	if value is Dictionary:
		var result:Dictionary = {}
		for key in value: result[key] = freeze(value[key])
		return result
	if value is Object: return value.get_instance_id()
	return value

func snapshot() -> Dictionary:
	var cards:Array = []
	for obj in GameData.objects:
		if obj is BaseHandCard:
			cards.append([obj.get_instance_id(), obj._is_concealed, freeze(obj._power), freeze(obj._cost), freeze(obj._attributes), freeze(obj._effects)])
	var seats:Array = []
	for area in MapData.areas:
		for loc in area._locations: seats.append(freeze(loc._players))
	return {"players":freeze(GameData.player_data_library), "cards":cards,
		"objects":freeze(GameData.objects), "seats":seats,
		"logs":freeze(GameLog.query({}, null)), "messages":freeze(EffectManager.messages),
		"announcements":freeze(EffectManager._pending_announcements),
		"activating":freeze(EffectManager.activating_eff)}

func ui_total(expected:int, board:int, label:String):
	scene.refresh_all_ui()
	check(scene.total_power_label != null, label + ": total label exists")
	if scene.total_power_label == null: return
	check(scene.total_power_label.text == "当前合计威力: %d" % expected, label + ": displayed total")
	# 真实绑定的鼠标进入信号，不能直接另算一份文本冒充浮层已接线。
	scene.total_power_label.emit_signal("mouse_entered")
	var panel = scene._power_tooltip_panel
	check(panel != null and panel.visible, label + ": instant tooltip opens")
	if panel != null:
		var desc = panel.get_node_or_null("VBox/Desc")
		check(desc != null and desc.text.split("\n").has("合计 %d" % expected), label + ": tooltip total")
		if board != 0:
			check(desc != null and desc.text.split("\n").has("场上牌加成 %+d" % board), label + ": tooltip board contribution")
	scene.total_power_label.emit_signal("mouse_exited")

func withdraw(card):
	var target = null
	for slot in scene.played_cards_row.get_children():
		if slot.has_meta("pending_regular_card") and slot.get_meta("pending_regular_card") == card:
			target = slot
	check(target != null, "withdraw finds the exact pending card slot")
	if target != null:
		var click = InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		target.emit_signal("gui_input", click)

func test_ui():
	for config in [["glorious_duel", "", 2], ["", "outrage", 2], ["glorious_duel", "outrage", 4]]:
		var d = setup(config[0], config[1])
		var a = attack("pending_strength")
		var b = attack("pending_hidden")
		d.hand_cards.assign([a, b])
		var base:int = GetPlayerTotalPower.new().exec(0)
		var other:int = GetPlayerTotalPower.new().exec(1)
		var before = snapshot()
		scene._choose_regular_play_mode(a, false)
		check(scene._regular_play_pending_cards == [a], "real UI stages faceup card")
		ui_total(base + 2 + int(config[2]), int(config[2]), "faceup " + str(config))
		scene._choose_regular_play_mode(b, true)
		check(scene._regular_play_pending_cards == [a, b], "real UI stages hidden second card")
		ui_total(base + 2 + int(config[2]), int(config[2]), "hidden second card")
		check(scene._pending_tactical_action.get("type", "") == "regular_play", "full group opens confirmation")
		scene._on_tactical_confirm_cancel()
		check(scene._regular_play_pending_cards == [a, b], "cancel returns to editing and retains preview cards")
		check(scene._pending_tactical_action.is_empty(), "cancel clears submission action")
		ui_total(base + 2 + int(config[2]), int(config[2]), "cancel retains preview")
		withdraw(b)
		check(scene._regular_play_pending_cards == [a], "hidden withdrawal removes only selected card")
		ui_total(base + 2 + int(config[2]), int(config[2]), "withdraw hidden")
		withdraw(a)
		ui_total(base, 0, "withdraw all")
		check(GetPlayerTotalPower.new().exec(0) == base and GetPlayerTotalPower.new().exec(1) == other, "preview never leaks into committed or opponent totals")
		check(snapshot() == before, "selection refresh tooltip cancel withdrawal leave engine state unchanged")

	var d = setup("cooperation")
	var a = attack("shared_strength")
	var b = attack("different_magic", ["magic"])
	d.hand_cards.assign([a, b])
	var base:int = GetPlayerTotalPower.new().exec(0)
	var before = snapshot()
	scene._choose_regular_play_mode(a, false)
	ui_total(base + 6, 4, "cooperation becomes true from pending attack")
	scene._choose_regular_play_mode(b, false)
	ui_total(base + 4, 0, "different pending attribute breaks cooperation")
	scene._on_tactical_confirm_cancel()
	withdraw(b)
	ui_total(base + 6, 4, "withdraw mismatch restores cooperation")
	scene._choose_regular_play_mode(b, true)
	ui_total(base + 6, 4, "hidden mismatch does not break cooperation")
	check(snapshot() == before, "cooperation condition evaluation is read-only")

func supports(script:Script, method_name:String, count:int) -> bool:
	for method in script.get_script_method_list():
		if method.name == method_name: return method.args.size() >= count
	return false

func board(cards:Array, hidden:Array) -> int:
	return int(Callable(BOARD_SCRIPT, "total").callv([0, cards, hidden]))

func test_engine():
	# 能力门槛产生普通失败断言，而非旧签名上调用新参数导致解析/运行错误。
	var ready:bool = supports(BOARD_SCRIPT, "total", 3) and supports(TOTAL_SCRIPT, "breakdown", 4) and supports(TOTAL_SCRIPT, "breakdown_lines", 4)
	check(ready, "engine query accepts explicit preview cards and hidden context")
	if not ready: return
	var d = setup("glorious_duel", "outrage")
	var a = attack("engine_preview")
	d.hand_cards.assign([a])
	var before = snapshot()
	var base:int = GetPlayerTotalPower.new().exec(0)
	for i in range(3):
		check(board([a], [false]) == 4, "engine combines event and situation for pending attack")
		var result:Dictionary = Callable(TOTAL_SCRIPT, "breakdown").callv([0, 2, [a], [false]])
		check(result.board == 4 and result.preview == 2 and result.power == 0 and result.total == base + 6, "breakdown keeps board and numeric preview separate")
		var lines:Array = Callable(TOTAL_SCRIPT, "breakdown_lines").callv([0, 2, [a], [false]])
		check(lines.has("场上牌加成 +4") and lines.has("合计 %d" % (base + 6)), "engine breakdown lines use same context")
	check(board([a], [true]) == 0, "ordinary hidden preview gets no board bonus")
	check(GetPlayerTotalPower.new().exec(0, 2) == base + 2, "legacy numeric-only preview remains compatible")
	check(BoardPowerQuery.total(1) == 0, "other player has no borrowed preview cards")
	check(snapshot() == before, "repeated engine queries do not mutate cards resources logs or messages")
	a._effects.append(CountsPowerWhileConcealedEffect.new())
	check(board([a], [true]) == 4, "hidden-counting exception participates in preview bonus")
	a._effects.append(NeverCountsPowerEffect.new())
	check(board([a], [false]) == 0 and board([a], [true]) == 0, "never-counting exception wins for both preview modes")

	d = setup("cooperation")
	a = attack("committed")
	var b = attack("pending_mismatch", ["magic"])
	d.played_cards.assign([a])
	d.power.number = 2
	d.hand_cards.assign([b])
	check(BoardPowerQuery.total(0) == 4, "committed shared attribute baseline")
	check(board([b], [false]) == 0, "pending mismatch invalidates committed cooperation")
	check(board([b], [true]) == 4, "hidden pending mismatch is excluded from shared attributes")
	check(BoardPowerQuery.total(0) == 4, "shared attribute query leaves committed state intact")

	d = setup("fate_battle")
	a = attack("pending_printed_two")
	d.hand_cards.assign([a])
	before = snapshot()
	check(board([a], [false]) == 3, "played-card reader and set-power contribution both see preview")
	check(board([a], [true]) == 0, "set-power contribution excludes hidden preview")
	check(snapshot() == before, "set-power preview never rewrites card or player state")
	var event = MapData.miyama0.get_from()._events[0]
	MapData.miyama0.get_from()._events.append(CloneObject.new().exec(event))
	before = snapshot()
	check(board([a], [false]) == 3, "duplicate set-to-five declarations compose without double counting")
	check(snapshot() == before, "composed set-power preview remains read-only")

func run():
	# 先让真实 UI 完成启动，再铺夹具；避免 _ready 的 GameStart 覆盖测试牌。
	scene = UI_SCENE.instantiate()
	get_tree().root.add_child(scene)
	scene.set_process(false)
	test_ui()
	test_engine()
	print("RESULT ", JSON.stringify({"checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
