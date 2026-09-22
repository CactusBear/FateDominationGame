extends Node
## 场景级 RED：只经真实入口信号打开浏览器，不直接调用打开回调。
## 由主执行者串行运行本场景；pressed 级接线验证可用于 headless，非鼠标命中测试。
var failures: Array = []
var checks := 0
var ui
const BOARD := "Middle_MainPlayground/Battlefields_CenterContainer/"
const BROWSER := "Modal_CardBrowser"

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
	print("CHECK ", label, " ", ok)

func _ready() -> void:
	call_deferred("run")

func frames(count := 2) -> void:
	for i in range(count):
		await get_tree().process_frame

func run() -> void:
	# _ready 会初始化对局，必须在实例化之后布置数据。
	ui = load("res://assets/scenes/game_scene/tactical_board_ui.tscn").instantiate()
	add_child(ui)
	ui.set_process(false)
	GameProgress.is_game_over = true
	EffectManager.reset_runtime()
	await frames()
	await test_event_discard_entries()
	await test_player_removed_cards()
	await test_browser_count_badge_and_outside_close()
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	get_tree().quit(0 if failures.is_empty() else 1)

func mark_card(card, key: String):
	card._name = key
	card._shown_name = key
	card._zoom_kind = "card"
	card._is_concealed = false
	if card is BaseSkill:
		card._is_awakened = true
	return card

func attack(key: String):
	return mark_card(BaseAttack.new(key, "", [], BaseNumber.new(0), BaseNumber.new(1)), key)

func skill(key: String):
	return mark_card(BaseSkill.new(key, "", []), key)

func other_card(key: String):
	var card := BaseCard.new()
	card.add_object()
	return mark_card(card, key)

func event_card(key: String):
	return mark_card(BaseEvent.new(key, ""), key)

## 浏览器没有对象指针 metadata；用唯一显示名读取实际渲染卡位，
## 与期望对象的 get_shown_name 对账，不把控制器内部过滤结果冒充展示结果。
func shown_cards(root: Node) -> Array:
	var result: Array = []
	if root == null:
		return result
	if root is Control and not root.is_visible_in_tree():
		return result
	if root is TextureRect and root.has_meta("zoom_title"):
		result.append(str(root.get_meta("zoom_title")))
	for child in root.get_children():
		result.append_array(shown_cards(child))
	return result

func names(cards: Array) -> Array:
	var result: Array = []
	for card in cards:
		result.append(card.get_shown_name())
	result.sort()
	return result

func expect_cards(root: Node, expected: Array, label: String) -> void:
	var actual := shown_cards(root)
	actual.sort()
	check(actual == names(expected), label + " expected=" + str(names(expected)) + " got=" + str(actual))

func browser_matches(expected: Array, label: String) -> void:
	var panel := ui.get_node_or_null(BROWSER) as Control
	check(panel != null and panel.is_visible_in_tree(), label + " opens browser")
	if panel == null:
		return
	expect_cards(panel.get_node_or_null("Box/CardScroll/CardRow"), expected, label + " rendered cards")
	var title := panel.get_node_or_null("Box/Title") as Label
	check(title != null and title.text.ends_with("×%d" % expected.size()), label + " count excludes other zones")
	if expected.is_empty():
		var has_empty_text := false
		for empty_label in panel.get_node("Box/CardScroll/CardRow").find_children("*", "Label", true, false):
			if empty_label.is_visible_in_tree() and not str(empty_label.text).is_empty():
				has_empty_text = true
		check(has_empty_text, label + " empty row explains absence of cards")

func close_browser() -> void:
	var button := ui.get_node_or_null(BROWSER + "/Box/Buttons/BtnCloseBrowser") as Button
	if button != null:
		button.pressed.emit()
	var panel := ui.get_node_or_null(BROWSER) as Control
	check(panel != null and not panel.visible, "browser close signal hides panel")


func test_browser_count_badge_and_outside_close() -> void:
	var first = attack("repeated_badge_card")
	var second = attack("repeated_badge_card")
	ui._show_card_browser("重复牌", [first, second])
	await frames()
	var panel := ui.get_node_or_null(BROWSER) as Control
	var row := panel.get_node_or_null("Box/CardScroll/CardRow") if panel != null else null
	var slot: TextureRect = null
	if row != null:
		for child in row.get_children():
			if child is TextureRect:
				slot = child
				break
	var badge := slot.get_node_or_null(ui.COUNT_BADGE_NAME) as Label if slot != null else null
	check(badge != null and badge.visible and badge.text == "×2", "repeated card has one count badge")
	if slot != null and badge != null:
		var card_rect := slot.get_global_rect()
		var badge_rect := badge.get_global_rect()
		check(card_rect.encloses(badge_rect), "count badge stays fully inside card art")
		check(badge_rect.get_center().x > card_rect.get_center().x and badge_rect.get_center().y < card_rect.get_center().y,
			"count badge sits on the card's top-right corner")
	var inside := InputEventMouseButton.new()
	inside.button_index = MOUSE_BUTTON_LEFT
	inside.pressed = true
	inside.position = panel.get_global_rect().get_center()
	inside.global_position = inside.position
	ui._input(inside)
	check(panel.visible, "clicking inside card browser keeps it open")
	var outside := InputEventMouseButton.new()
	outside.button_index = MOUSE_BUTTON_LEFT
	outside.pressed = true
	outside.position = Vector2(1, 1)
	outside.global_position = outside.position
	ui._input(outside)
	check(not panel.visible, "clicking outside card browser closes it")

func press_browser(button: Button, expected: Array, label: String) -> void:
	check(button != null, label + " entry exists")
	if button == null:
		return
	check(button.is_visible_in_tree() and not button.disabled, label + " entry available")
	check(not button.pressed.get_connections().is_empty(), label + " pressed is connected")
	button.pressed.emit()
	browser_matches(expected, label)
	close_browser()

func event_button(area_node: String) -> Button:
	return ui.get_node_or_null(BOARD + area_node + "/VBox/EventDiscardRow/BtnEventDiscard") as Button

func test_event_discard_entries() -> void:
	EventResolver.new().clear_all()
	MapData.event_discard.clear()
	var old_deck: Array = MapData.event_deck.duplicate()
	var miyama_card = event_card("zone_miyama_event")
	var shinto_card = event_card("zone_shinto_event")
	MapData.event_deck.assign([miyama_card, shinto_card])
	EventResolver.new().place([
		{"area_name": MapData.miyama._area_name, "concealed": false},
		{"area_name": MapData.shinto._area_name, "concealed": true}
	])
	check(MapData.miyama._events.size() == 1 and MapData.shinto._events.size() == 1, "fixture places one event in each real battlefield")
	if MapData.miyama._events.is_empty() or MapData.shinto._events.is_empty():
		MapData.event_deck.assign(old_deck)
		return
	var m = MapData.miyama._events[0]
	var s = MapData.shinto._events[0]
	EventResolver.new().clear_all()
	check(m.get_from() == MapData.miyama and s.get_from() == MapData.shinto, "discard preserves event source battlefield")
	check(MapData.event_discard.has(m) and MapData.event_discard.has(s), "one shared discard holds both original event objects")
	# 用新一轮场上事件验证可见布局，不能比较隐藏 EventSlot 的旧矩形。
	EventResolver.new().place([
		{"area_name": MapData.miyama._area_name, "concealed": false},
		{"area_name": MapData.shinto._area_name, "concealed": true}
	])
	ui.refresh_all_ui()
	await frames()
	for node_name in ["Area_Miyama", "Area_Shinto"]:
		var button := event_button(node_name)
		check(button != null, node_name + " has its own discard entry")
		if button != null:
			var event_slot: Control = ui.get_node(BOARD + node_name + "/VBox/EventSlot")
			check(event_slot.is_visible_in_tree(), node_name + " layout fixture has visible events")
			check(button.is_visible_in_tree(), node_name + " discard entry is visible")
			check(button.get_global_rect().position.y >= event_slot.get_global_rect().end.y - 1.0, node_name + " entry sits below own event cards")
	press_browser(event_button("Area_Miyama"), [m], "miyama history")
	press_browser(event_button("Area_Shinto"), [s], "shinto history")
	# 改共享源数组后再次点击，必须现场过滤，不能只缓存首次打开的数据。
	MapData.event_discard.erase(m)
	press_browser(event_button("Area_Miyama"), [], "empty miyama does not show shinto")
	press_browser(event_button("Area_Shinto"), [s], "shinto remains independent")
	MapData.event_discard.append(m)
	press_browser(event_button("Area_Miyama"), [m], "reopening reads current shared history")
	MapData.event_deck.assign(old_deck)

func removed_button(root: Node) -> Button:
	# 入口具体节点名不作为规则接口；只在对应玩家的 UI 区域找实际按钮。
	for button in root.find_children("*", "Button", true, false):
		if str(button.text).contains("游戏外"):
			return button as Button
	return null

func player_slot(id: int) -> Control:
	for child in ui.get_node(ui.ORDER_BOX_PATH).get_children():
		if child.has_meta("turn_order_player_id") and int(child.get_meta("turn_order_player_id")) == id:
			return child as Control
	return null

func open_drawer(id: int) -> void:
	var slot := player_slot(id)
	check(slot != null, "opponent has real identity-bound slot")
	if slot != null:
		ui._update_drawer_visuals(slot)
		ui.opponent_drawer.show()

func clear_removed(data: Dictionary) -> void:
	var zone: Dictionary = data.out_of_game
	for key in ["attacks", "skills", "others", "buffs"]:
		zone[key].clear()
	zone.master = null
	zone.servant = null
	# command_spell 特意保留：这里是效果登记，不是移除区。

func test_player_removed_cards() -> void:
	var local_id: int = ui._local_player_id
	var ids: Array = GameData.player_data_library.keys()
	ids.erase(local_id)
	check(ids.size() >= 2, "fixture has two distinct opponents")
	if ids.size() < 2:
		return
	var first_id: int = int(ids[0])
	var second_id: int = int(ids[1])
	var local: Dictionary = GameDataManager.get_player_data(local_id)
	var first: Dictionary = GameDataManager.get_player_data(first_id)
	var second: Dictionary = GameDataManager.get_player_data(second_id)
	for data in [local, first, second]:
		clear_removed(data)
		data.out_of_game.command_spell = [other_card("registered_command_" + str(data.order.number))]
	ui.refresh_all_ui()
	var dock: Control = ui.get_node("Bottom_PlayerDock")
	var button := removed_button(dock)
	check(button == null or not button.is_visible_in_tree(), "command spell registration alone does not show local out-of-game entry")
	open_drawer(first_id)
	button = removed_button(ui.opponent_drawer)
	check(button == null or not button.is_visible_in_tree(), "command spell registration alone does not show opponent entry")
	ui.opponent_drawer.hide()

	var local_attack = attack("local_removed_attack")
	var local_skill = skill("local_removed_skill")
	var local_item = other_card("local_removed_item")
	var retained = other_card("local_retained_item")
	local.out_of_game.attacks = [local_attack]
	local.out_of_game.skills = [local_skill]
	local.out_of_game.others = [local_item]
	# 夹具要改的是"这个玩家自己的御主实例"，不是全局共享的模板：
	# 直接写模板的 _other_things / _specials 会污染所有用同一御主的玩家与后续克隆体。
	local.master = CloneObject.new().exec(local.master)
	local.master._other_things = [local_item, retained]
	local.master._specials["ATTACKS"] = [local_attack]
	local.master_skills = [local_skill]
	var first_card = other_card("first_opponent_removed")
	var first_retained = other_card("first_opponent_retained")
	var second_card = other_card("second_opponent_removed")
	first.out_of_game.others = [first_card]
	# 同理：夹具只改该玩家自己的御主实例，不动共享模板
	first.master = CloneObject.new().exec(first.master)
	first.master._other_things = [first_card, first_retained]
	second.out_of_game.others = [second_card]
	ui.refresh_all_ui()
	await frames()
	var local_removed_button := removed_button(dock)
	check(local_removed_button != null and local_removed_button.text.contains("×3"),
		"local out-of-game entry shows its card count")
	check(local_removed_button != null and local_removed_button.size.x >= 110 and local_removed_button.size.y >= 32,
		"local out-of-game entry has a prominent click target")
	press_browser(local_removed_button, [local_attack, local_skill, local_item], "local removed only")
	var local_names := shown_cards(ui.skills_scroll_h)
	check(local_names.has(retained.get_shown_name()), "local info retains non-removed item")
	for removed in [local_attack, local_skill, local_item]:
		check(not local_names.has(removed.get_shown_name()), "local info excludes " + removed.get_shown_name())
	check(local.master._other_things.has(local_item), "view filtering does not mutate master template ownership")

	open_drawer(first_id)
	await frames()
	var first_button := removed_button(ui.opponent_drawer)
	press_browser(first_button, [first_card], "first opponent removed only")
	var row: Node = ui.opponent_drawer.get_node_or_null("VBox/CardsContentRow/Col_Skills/CardsH")
	var opponent_names := shown_cards(row)
	check(opponent_names.has(first_retained.get_shown_name()), "opponent info retains non-removed item")
	check(not opponent_names.has(first_card.get_shown_name()), "opponent info excludes removed item")

	# 远坂凛抽屉已打开后使用宝石：轻量刷新必须现场显示游戏外入口与数量。
	var rin_template = null
	for master_template in GameData.loaded_masters:
		if master_template != null and master_template._name == "tohsaka_rin":
			rin_template = master_template
			break
	check(rin_template != null, "tohsaka rin master is loadable for removed jewel fixture")
	if rin_template != null:
		var original_first_master = first.master
		var rin = CloneObject.new().exec(rin_template)
		first.master = rin
		clear_removed(first)
		open_drawer(first_id)
		await frames()
		var jewel = null
		for thing in rin._other_things:
			if thing != null and thing._name == "jewel_card":
				jewel = thing
				break
		check(jewel != null, "rin owns a real jewel card")
		if jewel != null:
			DrawCardByCard.new().exec(jewel, rin._other_things, first.out_of_game.others)
			ui._refresh_open_opponent_drawer()
			await frames()
			var rin_button := removed_button(ui.opponent_drawer)
			check(rin_button != null and rin_button.is_visible_in_tree(),
				"open rin drawer reveals out-of-game entry after a jewel is used")
			check(rin_button != null and rin_button.text.contains("×1"),
				"rin out-of-game entry shows the used jewel count")
		first.master = original_first_master
		first.out_of_game.others = [first_card]
	open_drawer(second_id)
	press_browser(removed_button(ui.opponent_drawer), [second_card], "reused drawer button follows second player")
	open_drawer(first_id)
	press_browser(removed_button(ui.opponent_drawer), [first_card], "switching back does not retain second player binding")

	# 最后一张牌返回后入口收起，正常信息区重新展示；令咒登记仍存在。
	first.out_of_game.others.clear()
	ui.refresh_all_ui()
	open_drawer(first_id)
	button = removed_button(ui.opponent_drawer)
	check(button == null or not button.is_visible_in_tree(), "opponent entry hides after last removed card returns")
	check(shown_cards(row).has(first_card.get_shown_name()), "returned card reappears in opponent info")
	ui.opponent_drawer.hide()
	clear_removed(local)
	ui.refresh_all_ui()
	button = removed_button(dock)
	check(button == null or not button.is_visible_in_tree(), "local entry hides after last removed card returns")
	check(shown_cards(ui.skills_scroll_h).has(local_item.get_shown_name()), "returned card reappears in local info")
