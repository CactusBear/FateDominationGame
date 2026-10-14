extends "res://newtests/round71_shared_discard_browsing_test.gd"
const FixtureClone = preload("res://newtests/fixture_clone.gd")
## 仅复用输入/截图/事实比较夹具；不执行原168/221专项。
var builder
var a: BaseCard
var b: BaseCard
var hidden_skill: BaseSkill

func seed_fixture() -> void:
	fixture = load("res://tests/card_selection_owner_test.gd").new()
	fixture.setup()
	GameProgress.current_phase_player_index = GameProgress.get_ordered_player_ids().find(GameProgress.current_player_id) + 1
	MapData.active_situation = null
	MapData.event_discard.clear()
	MapData.situation_discard.clear()
	a = fixture.make_card()
	b = fixture.make_card()
	a._is_concealed = false
	b._is_concealed = true
	for item in GameData.objects:
		if item is BaseSkill:
			hidden_skill = FixtureClone.clone_template(item, GameStart.startup_context())
			break
	check(hidden_skill != null, "真实声明技能模板存在")
	if hidden_skill != null:
		hidden_skill._is_awakened = false
	for pid in [0, 1]:
		var data: Dictionary = GameData.player_data_library[pid]
		data.out_of_game.attacks.assign([FixtureClone.clone_template(a, GameStart.startup_context()), FixtureClone.clone_template(b, GameStart.startup_context())])
		data.out_of_game.attacks[1]._is_concealed = true
		if hidden_skill != null: data.out_of_game.skills.assign([FixtureClone.clone_template(hidden_skill, GameStart.startup_context())])
		data.out_of_game.others.clear()
	builder = preload("res://scripts/match/view_builder.gd").new()

func selected_cards(view: Dictionary, pid: int) -> Array:
	for player in view.get("players", []):
		if player.get("id", -1) == pid: return player.get("out_of_game_cards", [])
	return []

func title() -> String:
	var button: Button = board._opponent_drawer.get_node("VBox/BtnOutOfGame")
	return str(button.get_meta("base_text", button.text))

func open_selected(pid: int) -> void:
	board._selected_opponent_id = pid
	board._on_drawer_out_of_game_pressed()

func expect_removed(cards: Array, label: String) -> void:
	expect(cards, title(), label)
	var slots: Array = board.get_node("CardBrowser/Panel/CardScroll/Row").get_children()
	for i in cards.size():
		var card: Dictionary = cards[i]
		if not card.get("visible", false):
			check(bool(slots[i].get_meta("zoom_disabled", false)) and not slots[i].has_meta("zoom_img") and not slots[i].has_meta("zoom_desc"), label + " 不可见无正面/说明")
		elif card.get("concealed", true):
			check(str(slots[i].get_meta("zoom_img", "")) == str(card.get("back_image", "")) and str(slots[i].get_meta("zoom_desc", "")).is_empty() and str(slots[i].get_meta("zoom_title", "")).is_empty(), label + " 本人暗置仅声明牌背/无说明")
		if not card.get("visible", false) or card.get("concealed", true):
			if not str(card.get("back_image", "")).is_empty():
				check(slots[i].get_node("Img").texture != null, label + " 自身声明牌背纹理非空")

func run() -> void:
	GameStart.reset()
	board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	add_child(board)
	board.set_process(false)
	board.set_process_input(false)
	GameProgress.reset_progress()
	seed_fixture()
	check(not board.has_method("_refresh_drawer_out_of_game"), "无caller旧包装退休")
	var button: Button = board._opponent_drawer.get_node("VBox/BtnOutOfGame")
	check(button.pressed.get_connections().size() == 1 and button.pressed.is_connected(board._on_drawer_out_of_game_pressed), "本地正式按钮唯一共享绑定")
	var query := ReadTrap.new()
	board._source = preload("res://scripts/game_scene/battle_io/local_battle_source.gd").new(0, builder, query)
	board._source_is_local = true
	var before := state(true)
	for pid in [0, 1]:
		open_selected(pid)
		expect_removed(selected_cards(builder.build(0), pid), "本地玩家%d" % pid)
		close()
	check(state(true) == before and query.calls == 0, "本地无玩家创建/规则命令/动作查询")
	var mine: Array = selected_cards(builder.build(0), 0)
	var rival: Array = selected_cards(builder.build(0), 1)
	check(mine[1].visible and mine[1].concealed and not rival[1].visible and not rival[1].has("image"), "本人暗置仍遮面/对手过滤不泄私牌")
	check(not mine[2].visible and not mine[2].has("image") and not rival[2].has("effects"), "未觉醒技能双方无正面/对手无内部效果")
	GameData.player_data_library[1].out_of_game.attacks = [a]
	GameData.player_data_library[1].out_of_game.skills.clear()
	a._shown_name = "同ID字段刷新"
	open_selected(1)
	expect_removed(selected_cards(builder.build(0), 1), "本地失效缓存新字段")
	close()
	GameData.player_data_library[1].out_of_game.attacks.clear()
	open_selected(1)
	expect_removed([], "本地empty")
	close()
	before = state(true)
	for pid in [-1, 999]:
		open_selected(pid)
		check(not board.get_node("CardBrowser").visible, "本地invalidselected不打开%d" % pid)
	check(state(true) == before and not GameData.player_data_library.has(999), "无效selected不创建玩家")
	board.queue_free()
	await get_tree().process_frame

	var lobby = preload("res://scripts/net/session/lobby_session.gd").new()
	board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	board.network_session = lobby
	add_child(board)
	board.set_process(false)
	board.set_process_input(false)
	button = board._opponent_drawer.get_node("VBox/BtnOutOfGame")
	check(button.pressed.get_connections().size() == 1 and button.pressed.is_connected(board._on_drawer_out_of_game_pressed), "网络正式按钮唯一共享绑定")
	check(not board._network_presenter.has_method("open_out_of_game"), "网络重复展示回调退休")
	board._source.close()
	var session := SourceSession.new()
	board._source = preload("res://scripts/game_scene/battle_io/network_battle_source.gd").new(session)
	var view: Dictionary = builder.build(0)
	session.publish(view)
	board._network_presenter._mine = {"out_of_game_cards": []}
	before = state(true)
	open_selected(0)
	expect_removed(selected_cards(view, 0), "跨source刷新不读mine")
	close()
	var replacement: Dictionary = view.duplicate(true)
	replacement.players[0].out_of_game_cards = [builder.card_view(a, true)]
	replacement.players[0].out_of_game_cards[0].name = "只在网络source的新字段"
	session.publish(replacement)
	open_selected(0)
	expect_removed(replacement.players[0].out_of_game_cards, "同seq同ID当前source")
	close()
	for bad in [{"players": [{"id": 0}]}, {"players": [{"id": 0, "out_of_game_cards": []}]}]:
		session.publish(bad)
		open_selected(0)
		expect_removed([], "缺声明不补查规则%d" % checks)
		close()
	for bad in [{}, {"players": [{"out_of_game_cards": mine}]}, {"players": [{"id": 77, "out_of_game_cards": mine}]}]:
		session.publish(bad)
		open_selected(0)
		check(not board.get_node("CardBrowser").visible, "缺玩家身份不替代selected%d" % checks)
	var no_back: Dictionary = {"id": 1234, "visible": false, "concealed": true}
	session.publish({"players": [{"id": 0, "out_of_game_cards": [no_back]}]})
	open_selected(0)
	expect_removed([no_back], "无牌背声明保持空")
	check(board.get_node("CardBrowser/Panel/CardScroll/Row").get_child(0).get_node("Img").texture == null, "不按类型或图片名猜背面")
	close()
	session.publish(view)
	board._source.close()
	open_selected(0)
	check(not board.get_node("CardBrowser").visible, "关闭source无旧字段")
	check(state(true) == before and session.rule_calls == 0 and query.calls == 0, "所有网络正负例无规则/玩家变更")
	board.queue_free()
	await get_tree().process_frame
	board = null
	lobby.close()
	await finish()

func drawer_target(pid: int) -> Control:
	for node in board.find_children("*", "Control", true, false):
		if node.get_meta("turn_order_player_id", -1) == pid and node.is_visible_in_tree() and node.gui_input.is_connected(board._on_opponent_gui_input.bind(node)):
			return node
	return null

func gui_removed(pid: int, label: String) -> void:
	var target := drawer_target(pid)
	check(target != null, label + " 正式玩家入口可见")
	if target == null: return
	check(await window_click(str(board.get_path_to(target)), label + "-drawer"), label + " 真实玩家入口命中")
	check(board._opponent_drawer.visible and board._selected_opponent_id == pid, label + " 正式抽屉打开")
	for cycle in ["open", "reopen"]:
		var current: Array = selected_cards(board._source.read_view(), pid)
		var before := state(true)
		var sequences: Array = [host._seq, guest._seq] if host != null else []
		check(await window_click("ModalLayer/OpponentDrawer/VBox/BtnOutOfGame", label + "-" + cycle), label + " 正式除外按钮真实mouse")
		expect_removed(current, label + "-" + cycle)
		if not board.get_node("CardBrowser").visible: return
		await RenderingServer.frame_post_draw
		var image: Image = get_viewport().get_texture().get_image()
		check(image.save_png("res://tests/runtime_reports/round74-" + label + "-" + cycle + ".png") == OK, label + " 原生截图" + cycle)
		var slots: Array = board.get_node("CardBrowser/Panel/CardScroll/Row").get_children()
		for slot in slots:
			var card: Dictionary = slot.get_meta("card")
			if card.get("concealed", true) or not card.get("visible", false):
				await window_motion(slot.get_global_rect().get_center(), label + "-hidden")
				window_button(slot.get_global_rect().get_center(), MOUSE_BUTTON_RIGHT, label + "-hidden-right")
				check(not board._hover_zoom.visible and not board._hover_desc.visible, label + " 暗置真实右键无正面/说明")
				break
		check(await window_click("CardBrowser/Panel/Close", label + "-close-" + cycle), label + " 真实关闭")
		check(not board.get_node("CardBrowser").visible and not board._hover_zoom.visible and not board._hover_desc.visible, label + " 关闭无浮层残留")
		check(state(true) == before and (host == null or [host._seq, guest._seq] == sequences), label + " 浏览无规则命令/状态变更")
	check(await window_click(str(board.get_path_to(target)), label + "-drawer-close"), label + " 正式玩家入口切换关闭抽屉")

func run_window() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "必须真实窗口")
		await finish()
		return
	window_mode = true
	window_deadline = Time.get_ticks_msec() + 120000
	GameStart.reset()
	board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	add_child(board)
	for pid in GameData.player_data_library: board._seat_controller.set_kind(int(pid), SeatController.REMOTE)
	var clone: BaseCard = FixtureClone.clone_template(LoadAttack.resolve("strength:2"), GameStart.startup_context())
	clone._is_concealed = false
	GameData.player_data_library[1].out_of_game.attacks.assign([clone, FixtureClone.clone_template(clone, GameStart.startup_context())])
	GameData.player_data_library[1].out_of_game.attacks[1]._is_concealed = true
	await window_settle()
	await gui_removed(1, "local-opponent")
	board.queue_free()
	await get_tree().process_frame
	board = null
	seed_fixture()
	host = preload("res://scripts/net/session/lobby_session.gd").new()
	guest = preload("res://scripts/net/session/lobby_session.gd").new()
	host.blobs.cache.root = OS.get_environment("FATE_TEST_SCRATCH_ROOT").path_join("host-cache")
	guest.blobs.cache.root = OS.get_environment("FATE_TEST_SCRATCH_ROOT").path_join("guest-cache")
	check(port_fixture.reserve_udp() == OK, "OS独占回环UDP端口")
	check(port_fixture.handoff(func(port): return host.host(port, "Round74", {"capacity":2,"minimum":1,"ai_count":0,"selection_mode":"test"}, "127.0.0.1")) == OK, "正式ENet监听")
	check(identity.install(host, guest), "内存RSA身份夹具")
	check(guest.join("127.0.0.1", port_fixture.port, "Round74Guest") == OK, "正式ENet连接")
	check(await window_wait(func(): return guest.identity_authenticated and guest.view.get("members", []).size() == 2), "RSA认证与两成员")
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
	await window_publish("Round74首次")
	if guest.read_match().is_empty():
		await window_finish()
		return
	board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	board.network_session = guest
	add_child(board)
	window_boards.append(board)
	await window_settle()
	check(board._source.read_view().get("observer", -1) == 0, "网络source observer=0")
	await gui_removed(1, "network-opponent")
	await window_finish()
