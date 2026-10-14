extends Node
## 原168 headless检查完整保留；-- window独立执行真实GUI与RSA回环ENet。
var host
var guest
var identity = preload("res://tests/net_window_identity_fixture.gd").new()
var port_fixture = preload("res://tests/network_test_port_fixture.gd").new()
var window_boards: Array = []
var serial := 0
var window_mode := false
var window_deadline := 0
var ending := false

func _process(delta: float) -> void:
	if not window_mode or ending: return
	if host != null: host.poll(delta)
	if guest != null: guest.poll(delta)
	if Time.get_ticks_msec() > window_deadline:
		check(false, "窗口120秒墙钟看门狗")
		window_finish()

func window_wait(predicate: Callable) -> bool:
	var until: int = Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < until and not ending:
		if predicate.call(): return true
		await get_tree().process_frame
	return false

func window_settle() -> void:
	check(await window_wait(func(): return not board._is_progress_blocked() and (board._scroll_tween == null or not board._scroll_tween.is_running())), "已有真实过场与卷轴tween完成 %d" % checks)
	board.refresh_all_ui()
	await get_tree().process_frame
	await get_tree().process_frame

func window_motion(point: Vector2, label: String) -> int:
	serial += 1
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = Vector2(1, 0)
	get_viewport().push_input(event, true)
	var immediate: int = board._main_area_index
	print("WINDOW_MOTION ", JSON.stringify({"serial":serial,"label":label,"point":str(point),"immediate":immediate}))
	await get_tree().process_frame
	return immediate

func window_button(point: Vector2, button: MouseButton, label: String) -> void:
	for down in [true, false]:
		serial += 1
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = button
		event.pressed = down
		get_viewport().push_input(event, true)
		print("WINDOW_BUTTON ", JSON.stringify({"serial":serial,"label":label,"down":down,"active":board._main_area_index,"handled":get_viewport().is_input_handled()}))

func window_click(path: String, label: String) -> bool:
	var control: Control = board.get_node(path)
	var receipt := {"down":0,"up":0,"pressed":0}
	var observe := func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed: receipt.down += 1
			else: receipt.up += 1
	var press := func(): receipt.pressed += 1
	control.gui_input.connect(observe)
	if control is Button: control.pressed.connect(press)
	var point: Vector2 = control.get_global_rect().get_center()
	await window_motion(point, label)
	var hovered := get_viewport().gui_get_hovered_control()
	var hit: bool = hovered == control or (hovered != null and control.is_ancestor_of(hovered))
	if hit: window_button(point, MOUSE_BUTTON_LEFT, label)
	control.gui_input.disconnect(observe)
	if control is Button: control.pressed.disconnect(press)
	print("WINDOW_CLICK ", JSON.stringify({"label":label,"path":path,"hit":hit,"receipt":receipt,"rect":str(control.get_global_rect())}))
	await get_tree().process_frame
	await get_tree().process_frame
	return hit and receipt.down == 1 and (not control is Button or receipt.pressed == 1)

func window_strip(index: int) -> Vector2:
	var rect: Rect2 = board.get_node("Strips").get_child(index).get_global_rect()
	return rect.position + Vector2(rect.size.x * 0.5, 48)

func window_shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var root: String = "res://tests/runtime_reports/round73-" + label
	check(image.save_png(root + "-full.png") == OK, "原生全图 " + label)
	var panel: Control = board.get_node("CardBrowser/Panel")
	var rect: Rect2 = panel.get_global_rect().intersection(Rect2(Vector2.ZERO, image.get_size()))
	check(image.get_region(Rect2i(rect)).save_png(root + "-browser.png") == OK, "原生浏览裁片 " + label)

func window_cards(view: Dictionary, personal: bool) -> Array:
	if not personal: return view.get("situation_discard", [])
	for player in view.get("players", []):
		if player.id == view.get("observer", -1): return player.get("discard", [])
	return []

func window_close(label: String, target: int) -> void:
	check(await window_click("CardBrowser/Panel/Close", label), label + " motion/down/up/pressed")
	check(not board.get_node("CardBrowser").visible and not board._hover_desc.visible and not board._hover_zoom.visible, label + " 关闭清理浮层")
	check(board._main_area_index == target, label + " 关闭同步及下一帧保持原目标")
	var next: int = (target + 1) % board.get_node("Strips").get_child_count()
	var immediate: int = await window_motion(window_strip(next), label + "-first-new-motion")
	check(immediate == next and board._main_area_index == next, label + " firstnewmotion立即切换")
	await window_settle()

func window_browse(personal: bool, label: String, screenshot := true) -> void:
	var view: Dictionary = board._source.read_view()
	var cards: Array = window_cards(view, personal)
	var before := state(true)
	var sequences: Array = [host._seq, guest._seq]
	var path: String = "Ops/Discard" if personal else "Piles/SituationPile"
	check(await window_click(path, label + "-open"), label + " 正式牌堆motion/down/up命中")
	expect(cards, "我方弃牌" if personal else "公共局势弃牌", label)
	if not board.get_node("CardBrowser").visible: return
	var target: int = board._main_area_index
	var next: int = (target + 1) % board.get_node("Strips").get_child_count()
	var immediate: int = await window_motion(window_strip(next), label + "-modal-motion")
	check(immediate == target and board._main_area_index == target, label + " 浏览模态motion保持原目标")
	var slots: Array = board.get_node("CardBrowser/Panel/CardScroll/Row").get_children()
	for slot in slots:
		var card: Dictionary = slot.get_meta("card")
		if not card.get("visible", false) or card.get("concealed", true):
			check(bool(slot.get_meta("zoom_disabled", false)) and not slot.has_meta("zoom_img") and not slot.has_meta("zoom_desc"), label + " 隐藏牌无正面/说明metadata")
			await window_motion(slot.get_global_rect().get_center(), label + "-hidden")
			window_button(slot.get_global_rect().get_center(), MOUSE_BUTTON_RIGHT, label + "-hidden-right")
			check(not board._hover_zoom.visible and not board._hover_desc.visible, label + " 隐藏牌真实右键不泄露")
			break
	if screenshot: await window_shot(label)
	var scroll: ScrollContainer = board.get_node("CardBrowser/Panel/CardScroll")
	if cards.size() > 12:
		var old: int = scroll.scroll_horizontal
		await window_motion(scroll.get_global_rect().get_center(), label + "-wheel")
		window_button(scroll.get_global_rect().get_center(), MOUSE_BUTTON_WHEEL_DOWN, label + "-wheel")
		await get_tree().process_frame
		check(scroll.scroll_horizontal > old, label + " 实际滚轮横向滚动")
	await window_close(label + "-close", target)
	check(state(true) == before and [host._seq, guest._seq] == sequences, label + " 无规则命令/牌区/阶段/资源变化")

func window_publish(label: String) -> void:
	var old: int = int(guest.read_match().get("seq", -1))
	host._publish_match()
	print("WINDOW_SOURCE ", JSON.stringify({"label":label,"host_error":host.error,"guest_error":guest.error,"host_seq":host.read_match().get("seq", -1),"guest_seq":guest.read_match().get("seq", -1)}))
	check(await window_wait(func(): return int(guest.read_match().get("seq", -1)) > old), label + " 正式权威新投影经ENet到达")

func run_window() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "window必须原生窗口")
		await finish()
		return
	window_mode = true
	window_deadline = Time.get_ticks_msec() + 120000
	GameStart.reset()
	board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	add_child(board)
	for pid in GameData.player_data_library: board._seat_controller.set_kind(int(pid), SeatController.REMOTE)
	await window_settle()
	for path in ["Ops/Discard", "Piles/SituationPile"]:
		check(board.get_node(path).gui_input.get_connections().is_empty(), "本地正式入口无接线 " + path)
		await window_motion(board.get_node(path).get_global_rect().get_center(), "local-absent-" + path)
		window_button(board.get_node(path).get_global_rect().get_center(), MOUSE_BUTTON_LEFT, "local-absent-" + path)
		await get_tree().process_frame
		check(not board.get_node("CardBrowser").visible, "本地真实点击不伪造新增浏览能力 " + path)
	board.queue_free()
	await get_tree().process_frame
	board = null
	fixture = load("res://tests/card_selection_owner_test.gd").new()
	fixture.setup()
	GameProgress.current_phase_player_index = GameProgress.get_ordered_player_ids().find(GameProgress.current_player_id) + 1
	MapData.active_situation = null
	MapData.event_discard.clear()
	MapData.situation_discard.clear()
	var models: Array = [LoadAttack.resolve("strength:2")]
	for card in GameData.objects:
		if card is BaseSkill and models.size() < 4: models.append(card)
	models.append(LoadCommandSpell.command_spells.values()[0])
	models.append(LoadEvent.events[0])
	models.append(LoadSituation.situations[0])
	models.append(LoadSituation.climax_situations.values()[0])
	var cards: Array = []
	for model in models:
		var card: BaseCard = CloneObject.new().exec(model)
		card._is_concealed = false
		cards.append(card)
	# 未觉醒技能本人的正面保护由真实builder负责；不自行添加可见字段。
	for card in cards:
		if card is BaseSkill and not card._is_awakened: card._is_concealed = true
	for pid in [0, 1]:
		GameData.player_data_library[pid].discard.clear()
		for i in cards.size() + 14:
			GameData.player_data_library[pid].discard.append(CloneObject.new().exec(cards[i % cards.size()]))
	MapData.situation_discard.assign([CloneObject.new().exec(cards[-1]), cards[-2], cards[-1]])
	MapData.situation_discard[0]._is_concealed = true
	host = preload("res://scripts/net/session/lobby_session.gd").new()
	guest = preload("res://scripts/net/session/lobby_session.gd").new()
	host.blobs.cache.root = OS.get_environment("FATE_TEST_SCRATCH_ROOT").path_join("host-cache")
	guest.blobs.cache.root = OS.get_environment("FATE_TEST_SCRATCH_ROOT").path_join("guest-cache")
	check(port_fixture.reserve_udp() == OK, "OS独占回环UDP端口")
	check(port_fixture.handoff(func(port): return host.host(port, "Round73", {"capacity":2,"minimum":1,"ai_count":0,"selection_mode":"test"}, "127.0.0.1")) == OK, "正式ENet房主监听")
	check(identity.install(host, guest), "既有内存RSA挑战夹具")
	check(guest.join("127.0.0.1", port_fixture.port, "Round73Guest") == OK, "正式客机连接")
	check(await window_wait(func(): return guest.identity_authenticated and guest.view.get("members", []).size() == 2), "RSA认证与两成员绑定")
	if not guest.identity_authenticated:
		await window_finish()
		return
	host.match_authority.started = true
	host.match_authority.controllers = {0:guest.peer_id(), 1:1}
	host.match_authority.driver.seats.default_kind = SeatController.REMOTE
	for pid in GameData.player_data_library: host.match_authority.driver.seats.set_kind(int(pid), SeatController.REMOTE)
	host.room.phase = "playing"
	host.room.revision += 1
	host._publish()
	host._bind_match()
	await window_publish("首次")
	if guest.read_match().is_empty():
		await window_finish()
		return
	for entry in [{"session":host,"label":"host","observer":1},{"session":guest,"label":"guest","observer":0}]:
		if is_instance_valid(board):
			board.hide()
			board.set_process_input(false)
		board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
		board.network_session = entry.session
		add_child(board)
		window_boards.append(board)
		await window_settle()
		check(board._source.read_view().get("observer", -1) == entry.observer, entry.label + " source当前本人正确")
		await window_browse(true, entry.label + "-personal")
		await window_browse(false, entry.label + "-situation")
		GameData.player_data_library[entry.observer].discard = [cards[0], CloneObject.new().exec(cards[0]), cards[-2]]
		cards[0]._shown_name = "当前source同ID刷新"
		MapData.situation_discard.assign([cards[-2], cards[-1]])
		await window_publish(entry.label + "字段及顺序更新")
		await window_browse(true, entry.label + "-personal-reopen")
		await window_browse(false, entry.label + "-situation-reopen")
		GameData.player_data_library[entry.observer].discard.clear()
		MapData.situation_discard.clear()
		await window_publish(entry.label + "empty更新")
		await window_browse(true, entry.label + "-personal-empty")
		await window_browse(false, entry.label + "-situation-empty")
		MapData.situation_discard.assign([CloneObject.new().exec(cards[-1]), cards[-2], cards[-1]])
		await window_publish(entry.label + "公共恢复")
	await window_finish()

func window_finish() -> void:
	if ending: return
	ending = true
	for item in window_boards:
		if is_instance_valid(item): item.queue_free()
	window_boards.clear()
	if is_instance_valid(board): board.queue_free()
	await get_tree().process_frame
	board = null
	if guest != null: guest.close()
	if host != null: host.close()
	identity.release()
	port_fixture.close()
	guest = null
	host = null
	await finish()
var checks := 0
var failures: Array[String] = []
var board
var fixture

class ReadTrap extends RefCounted:
	var calls := 0
	func actions(_seat: int) -> Dictionary:
		calls += 1
		return {}
	func pending(_seat: int) -> Dictionary:
		calls += 1
		return {}
	func preview(_seat: int, _cards: Array, _hidden: Array) -> Dictionary:
		calls += 1
		return {}

## 仅模拟投递；牌面来自真实builder，不模拟规则结果。
class SourceSession extends RefCounted:
	signal changed
	var view: Dictionary = {}
	var reads := 0
	var rule_calls := 0
	func read_match() -> Dictionary:
		reads += 1
		return view.duplicate(true)
	func publish(value: Dictionary) -> void:
		view = value.duplicate(true)
		changed.emit()
	func read_actions() -> Dictionary:
		rule_calls += 1
		return {}
	func read_pending() -> Dictionary:
		rule_calls += 1
		return {}
	func request(_kind: String, _payload: Dictionary) -> void:
		rule_calls += 1

func check(ok: bool, label: String) -> void:
	checks += 1
	print("CHECK ", label, " ", ok)
	if not ok: failures.append(label)

func _ready() -> void:
	call_deferred("run_window" if OS.get_cmdline_user_args().has("window") else "run")

func rendered() -> Array:
	return board.get_node("CardBrowser/Panel/CardScroll/Row").get_children().map(func(slot): return slot.get_meta("card"))

func textures_match(cards: Array) -> bool:
	var slots: Array = board.get_node("CardBrowser/Panel/CardScroll/Row").get_children()
	if slots.size() != cards.size(): return false
	for i in cards.size():
		var card: Dictionary = cards[i]
		var image: String = str(card.get("image", "")) if card.get("visible", false) and not card.get("concealed", true) else str(card.get("back_image", ""))
		var expected = LoadHelper.load_texture(image) if image != "" and LoadHelper.texture_exists(image) else null
		if slots[i].get_node("Img").texture != expected: return false
	return true

func expect(cards: Array, title: String, label: String) -> void:
	check(board.get_node("CardBrowser").visible, label + " 浏览器打开")
	check(rendered() == cards, label + " 完整投影顺序及重复ID保留")
	check(textures_match(cards), label + " 贴图只消费source显式声明")
	check(board.get_node("CardBrowser/Panel/Title").text == "%s · %d" % [title, cards.size()], label + " 原标题数量")
	check(board.get_node("CardBrowser/Panel/Empty").visible == cards.is_empty(), label + " empty状态")
	check(not board.get_node("EventDiscardMenu").visible, label + " 菜单关闭")

func state(generic_cards := false) -> Array:
	var out: Array = [GameProgress.current_round, GameProgress.current_player_id, GameProgress.current_phase_index,
		GameProgress.is_game_over, GameLog.query({}, null, -1).duplicate(true),
		MapData.event_discard.duplicate(), MapData.situation_discard.duplicate(), MapData.active_situation,
		EffectManager.is_waiting_for_choice(), EffectManager.is_waiting_for_card_selection()]
	for pid in GameData.player_data_library:
		var data: Dictionary = GameData.player_data_library[pid]
		out.append([pid, data.magic.number, data.score.number, data.command_spell_count.number,
			data.order.number, data.hand_cards.duplicate(), data.deck.duplicate(), data.discard.duplicate(),
			data.played_cards.duplicate(), data.buffs.duplicate(), data.out_of_game.duplicate(true)])
		for card in data.discard:
			var closed = card._is_closed if not generic_cards else (card.get("_is_closed") if card.get_property_list().any(func(p): return p.name == "_is_closed") else "not-declared")
			out.append([card, card._is_concealed, closed, card._card_img, card._card_back_img])
	return out

func left(pressed := true, button := MOUSE_BUTTON_LEFT) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	return event

func open_personal() -> void:
	board.get_node("Ops/Discard").gui_input.emit(left())

func open_situation() -> void:
	board.get_node("Piles/SituationPile").gui_input.emit(left())

func close() -> void:
	board.get_node("CardBrowser/Panel/Close").pressed.emit()
	check(not board.get_node("CardBrowser").visible and not board._hover_zoom.visible and not board._hover_desc.visible, "关闭清理浏览浮层 %d" % checks)

func run() -> void:
	GameStart.reset()
	board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	add_child(board)
	board.set_process(false)
	board.set_process_input(false)
	GameProgress.reset_progress()
	check(board.has_method("_open_discard_browser"), "共享弃牌浏览入口存在")
	if not board.has_method("_open_discard_browser"):
		await finish()
		return
	check(board.get_node("Ops/Discard").gui_input.get_connections().is_empty(), "本地个人弃牌保持无入口")
	check(board.get_node("Piles/SituationPile").gui_input.get_connections().is_empty(), "本地局势弃牌保持无入口")
	var menu: Control = board.get_node("EventDiscardMenu")
	var event_open: Button = board.get_node("Piles/EventPile/Open")
	event_open.pressed.emit()
	check(menu.visible, "本地事件按钮首次打开")
	event_open.pressed.emit()
	check(not menu.visible, "本地事件按钮再次切换关闭")
	fixture = load("res://tests/card_selection_owner_test.gd").new()
	fixture.setup()
	MapData.active_situation = null
	MapData.event_discard.clear()
	MapData.situation_discard.clear()
	var a: BaseCard = fixture.make_card()
	var b: BaseCard = fixture.make_card()
	a._is_concealed = false
	b._is_concealed = false
	a._zoom_kind = "card"
	b._zoom_kind = "card"
	a._shown_name = "同ID刷新前"
	b._shown_name = "第二张"
	GameData.player_data_library[0].discard = [a, b, a]
	GameData.player_data_library[1].discard = [b]
	MapData.situation_discard.assign([b, a, b])
	var builder = preload("res://scripts/match/view_builder.gd").new()
	var query := ReadTrap.new()
	board._source = preload("res://scripts/game_scene/battle_io/local_battle_source.gd").new(0, builder, query)
	board._source_is_local = true
	var before := state()
	board._open_discard_browser("我方弃牌", true)
	expect(builder.cards([a, b, a], true), "我方弃牌", "本地source首次个人")
	check(state() == before and query.calls == 0, "本地正例无规则查询或副作用")
	close()
	GameData.player_data_library[0].discard = [a]
	a._shown_name = "同ID刷新后"
	before = state()
	board._open_discard_browser("我方弃牌", true)
	expect(builder.cards([a], true), "我方弃牌", "本地同ID字段刷新")
	check(state() == before, "本地刷新不修改规则")
	board._open_discard_browser("公共局势弃牌", false)
	expect(builder.cards([b, a, b], false), "公共局势弃牌", "本地公共source顺序")
	MapData.situation_discard.clear()
	board._open_discard_browser("公共局势弃牌", false)
	expect([], "公共局势弃牌", "本地公共source刷新empty")
	board._source.set_seat(1)
	board._open_discard_browser("我方弃牌", true)
	expect(builder.cards([b], true), "我方弃牌", "本地observer切换")
	board._source.set_seat(-1)
	board._open_discard_browser("我方弃牌", true)
	expect([], "我方弃牌", "本地旁观者无个人弃牌")
	check(query.calls == 0, "本地不读取actions pending preview")
	board.queue_free()
	await get_tree().process_frame

	# 正式网络组合根绑定信号；投递与传输验收分层。
	var lobby = preload("res://scripts/net/session/lobby_session.gd").new()
	board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	board.network_session = lobby
	add_child(board)
	board.set_process(false)
	board.set_process_input(false)
	check(board.get_node("Ops/Discard").gui_input.get_connections().size() == 1, "网络个人牌堆唯一共享接线")
	check(board.get_node("Piles/SituationPile").gui_input.get_connections().size() == 1, "网络局势牌堆唯一共享接线")
	for path in ["Ops/Discard", "Piles/SituationPile"]:
		var pile: Control = board.get_node(path)
		check(pile.mouse_filter == Control.MOUSE_FILTER_STOP and pile.find_children("*", "Control", true, false).all(func(child): return child.mouse_filter == Control.MOUSE_FILTER_IGNORE), "网络牌堆过滤保持 " + path)
	menu = board.get_node("EventDiscardMenu")
	event_open = board.get_node("Piles/EventPile/Open")
	event_open.pressed.emit()
	event_open.pressed.emit()
	check(menu.visible, "网络事件按钮再次仍只打开")
	board._source.close()
	var session := SourceSession.new()
	board._source = preload("res://scripts/game_scene/battle_io/network_battle_source.gd").new(session)
	GameData.player_data_library[0].discard = [a, b, a]
	MapData.situation_discard.assign([b, a, b])
	var view: Dictionary = builder.build(0)
	session.publish(view)
	board._network_presenter._mine = {"discard": []}
	before = state()
	open_personal()
	expect(builder.cards([a, b, a], true), "我方弃牌", "网络source不读旧mine")
	check(state() == before, "网络正例无规则副作用")
	close()
	board.get_node("EventDiscardMenu").show()
	open_situation()
	expect(view.situation_discard, "公共局势弃牌", "网络公共局势")
	close()
	var replacement: Dictionary = view.duplicate(true)
	replacement.players[0].discard = [builder.card_view(b, true)]
	replacement.players[0].discard[0].name = "投递的同ID新字段"
	session.publish(replacement)
	open_personal()
	expect(replacement.players[0].discard, "我方弃牌", "网络同seq同ID字段刷新")
	close()
	var switched: Dictionary = builder.build(1)
	switched.seq = view.seq
	session.publish(switched)
	open_personal()
	expect(builder.cards([b], true), "我方弃牌", "网络同seq observer切换")
	close()
	a._is_concealed = true
	var hidden: Dictionary = builder.card_view(a, false)
	check(not hidden.has("name") and not hidden.has("image") and not hidden.has("effects") and not hidden.has("description"), "真实隐藏投影无敏感字段")
	var private_view: Dictionary = view.duplicate(true)
	private_view.players[0].discard = [hidden]
	session.publish(private_view)
	before = state()
	open_personal()
	expect([hidden], "我方弃牌", "网络隐藏字段原样消费")
	var slot: Control = board.get_node("CardBrowser/Panel/CardScroll/Row").get_child(0)
	check(bool(slot.get_meta("zoom_disabled", false)) and not slot.has_meta("zoom_title") and not slot.has_meta("zoom_desc") and not slot.has_meta("zoom_obj") and not slot.has_meta("zoom_img"), "隐藏字段不从本机规则补齐放大")
	check(state() == before, "隐藏反例无规则副作用")
	close()
	for bad in [{}, {"observer": -1, "players": [{"id": -1, "own": true, "discard": [hidden]}]}, {"observer": 92, "players": view.players}, {"players": view.players}, {"observer": 0, "players": [{"id": 0}]}]:
		session.publish(bad)
		open_personal()
		expect([], "我方弃牌", "网络缺席或缺字段 %d" % checks)
		close()
		session.publish(bad)
		open_situation()
		expect([], "公共局势弃牌", "网络公共缺字段 %d" % checks)
		close()
	session.publish(view)
	board.get_node("EventDiscardMenu").show()
	var reads: int = session.reads
	before = state()
	for event in [left(false), left(true, MOUSE_BUTTON_RIGHT), left(true, MOUSE_BUTTON_WHEEL_DOWN), InputEventMouseMotion.new(), InputEventKey.new()]:
		board.get_node("Ops/Discard").gui_input.emit(event)
		board.get_node("Piles/SituationPile").gui_input.emit(event)
	check(session.reads == reads and not board.get_node("CardBrowser").visible and board.get_node("EventDiscardMenu").visible, "非左键按下无读取且菜单不变")
	check(state() == before and session.rule_calls == 0, "网络所有正负浏览不发命令不查规则")
	board._source.close()
	open_personal()
	expect([], "我方弃牌", "网络source关闭清空")
	close()
	board.queue_free()
	await get_tree().process_frame
	lobby.close()
	await finish()

func finish() -> void:
	if is_instance_valid(board): board.queue_free()
	if is_instance_valid(fixture): fixture.free()
	GameStart.reset()
	await get_tree().process_frame
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
