extends Node

var failures: Array = []
var checks := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
	print("CHECK ", label, " ", value)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	get_tree().root.add_child(board)
	await get_tree().process_frame
	var button: Button = board.get_node("Ops/PlayButton")
	check(not button.pressed.get_connections().is_empty(), "right play button connected to existing submission flow")
	check(button.disabled, "no selection disables confirm")
	var hand: Control = board.get_node("Hand")
	var first: Control = hand.get_child(0)
	check(first.has_meta("card"), "held slot binds an actual card object")
	check(first.mouse_filter == Control.MOUSE_FILTER_STOP, "held slot receives mouse input")
	check(first.get_node("Breath").get_theme_stylebox("panel").shadow_size == 0, "held gold outline has no broad shadow")
	board.refresh_all_ui()
	check(hand.get_child(0) == first, "refresh preserves held card node identity")
	check(first.has_meta("rest_position"), "held slot declares collapsed rest position")
	check(not board.has_node("HeldFrames"), "red blue group frames removed")
	var pl_at_start: Dictionary = GameDataManager.get_player_data(GameData.player_id)
	for entry in board._zone_hand_entries(pl_at_start):
		if entry.card.get_from() == pl_at_start.master:
			check(entry.kind != "从者技能", "master-owned skill in shared side zone is not servant skill")
	var master_rect: Rect2 = board.get_node("Master").get_rect()
	var left_limit: float = board.get_node("Self").get_rect().end.x
	var right_limit: float = board.get_node("Ops/PlayButton").get_global_rect().position.x
	var left_slots: Array = []
	var right_slots: Array = []
	var hand_slots: Array = []
	for slot: Control in hand.get_children():
		# 牌上的类别文字已移除：改用槽位自身记录的分组与牌的来源判定左右/手牌
		if str(slot.get_meta("held_group", "")) == "hand":
			hand_slots.append(slot)
			continue
		var slot_card = slot.get_meta("card", null)
		if slot_card != null and slot_card.get_from() == pl_at_start.get("servant"):
			left_slots.append(slot)
		else:
			right_slots.append(slot)
	for slot: Control in left_slots:
		check(slot.get_meta("rest_position").x >= left_limit and slot.get_meta("rest_position").x + slot.size.x <= master_rect.position.x, "servant card between stats and master")
	for slot: Control in right_slots:
		check(slot.get_meta("rest_position").x >= master_rect.end.x and slot.get_meta("rest_position").x + slot.size.x <= right_limit, "master card between portrait and play button")
	hand_slots.sort_custom(func(a, b): return (a.get_meta("rest_position") as Vector2).x < (b.get_meta("rest_position") as Vector2).x)
	for slot: Control in hand_slots:
		check(slot.get_meta("rest_position").y >= board.size.y - board.HELD_VISIBLE_HEIGHT and slot.get_meta("rest_position").y < board.size.y, "fan cards remain in collapsed drawer band")
	if hand_slots.size() > 1:
		check(hand_slots.front().get_index() > hand_slots.back().get_index(), "left overlapping card draws above right")
		check(hand_slots.front().get_meta("rest_rotation", 0.0) < 0.0 and hand_slots.back().get_meta("rest_rotation", 0.0) > 0.0, "hand is fan shaped")
		var left: float = hand_slots.front().get_meta("rest_position").x
		var right: float = hand_slots.back().get_meta("rest_position").x + hand_slots.back().size.x
		check(is_equal_approx((left + right) * 0.5, master_rect.get_center().x), "hand centered below master")
	check(first.get_node("Selected") is Panel, "selection uses full white panel")
	if not hand_slots.is_empty():
		var rest: Vector2 = hand_slots.front().get_meta("rest_position")
		check(rest.y > board.size.y - hand_slots.front().size.y, "hand drawer partially collapsed below screen")
	board.set_process(false)
	var id: int = GameData.player_id
	var pl: Dictionary = GameDataManager.get_player_data(id)
	GameProgress.current_player_id = id
	GameProgress.current_phase_index = 0
	var original_hand: Array = pl.hand_cards.duplicate()
	var model = original_hand.front()
	if model is BaseHandCard:
		var duplicates: Array = []
		for i in range(3):
			var copy = CloneObject.new().exec(model)
			pl.hand_cards.append(copy)
			duplicates.append(copy)
		board.refresh_all_ui()
		var original_slot: Control = board._held_slot(model, "HandCard")
		check(original_slot.get_node("StackCount").visible and int(original_slot.get_node("StackCount").text.trim_prefix("x")) >= 4, "identical cards compact stack with count")
		var last_copy: Control = board._held_slot(duplicates.back(), "HandCard")
		# 同组（同名同图同状态）只做轻微错位：相邻错位要小于一整张卡（说明是叠着的），
		# 但也不能小到几乎重合、看不出是两张
		var span: float = last_copy.get_meta("rest_position").x - original_slot.get_meta("rest_position").x
		var per_gap: float = span / maxf(1.0, float(duplicates.size()))
		var ratio: float = per_gap / maxf(1.0, original_slot.size.x)
		check(ratio > 0.4 and ratio < 1.0, "duplicate spacing shows both cards without heavy overlap (%f)" % ratio)
		for copy in duplicates:
			pl.hand_cards.erase(copy)
		var extras: Array = []
		for i in range(30):
			var copy = CloneObject.new().exec(model)
			copy._name = "overflow_%d" % i
			pl.hand_cards.append(copy)
			extras.append(copy)
		board.refresh_all_ui()
		var positions: Array = []
		for card in pl.hand_cards:
			positions.append(board._held_slot(card, "HandCard").get_meta("rest_position").x)
		positions.sort()
		check(positions.front() >= board.get_node("Self").get_rect().end.x and positions.back() + original_slot.size.x <= board.get_node("Ops").position.x, "overflow fan keeps both edge cards within available width")
		for copy in extras:
			pl.hand_cards.erase(copy)
		board.refresh_all_ui()
	GameProgress.current_phase_index = 2
	GameLog.reset()
	MapData.active_situation = null
	pl.location = null
	pl.magic.set_num(BaseNumber.new(12))
	var group: Dictionary = RegularPlay.find_group(id)
	check(not group.is_empty(), "real engine finds legal group")
	if not group.is_empty():
		var card = group.cards[0]
		card._is_concealed = bool(group.hidden[0])
		board.refresh_all_ui()
		var slot: Control = board._held_slot(card, "HandCard")
		var click := InputEventMouseButton.new()
		click.pressed = true
		click.button_index = MOUSE_BUTTON_LEFT
		slot.gui_input.emit(click)
		check(board._selected_cards.has(card), "left click selects actual object")
		slot.gui_input.emit(click)
		check(not board._selected_cards.has(card), "second left click cancels selection")
		var original: bool = card._is_concealed
		click.button_index = MOUSE_BUTTON_RIGHT
		slot.gui_input.emit(click)
		check(card._is_concealed != original, "right click changes actual conceal state")
		if card._is_concealed:
			check(not slot.has_node("Frame/Name"), "concealed held card has no added face labels")
		slot.gui_input.emit(click)
		check(card._is_concealed == original, "second right click restores conceal state")
		for i in range(group.cards.size()):
			var chosen = group.cards[i]
			chosen._is_concealed = bool(group.hidden[i])
			board.refresh_all_ui()
			click.button_index = MOUSE_BUTTON_LEFT
			board._held_slot(chosen, "HandCard").gui_input.emit(click)
		check(not button.disabled, "legal selected group enables confirm")
		for chosen in group.cards:
			check(board._held_slot(chosen, "HandCard").get_node("Selected").visible, "selected card has white frame")
		var previous_magic: float = pl.magic.number
		pl.magic.set_num(BaseNumber.new(0))
		board._update_held_cards(0.0)
		check(button.disabled == not RegularPlay.can_submit_group(id, group.cards, board._held_hidden(group.cards)), "resource change confirm matches engine immediately")
		for chosen in group.cards:
			check(board._held_slot(chosen, "HandCard").get_node("Selected").visible and not board._held_slot(chosen, "HandCard").get_node("Breath").visible, "selection stays white on resource change")
		pl.magic.set_num(BaseNumber.new(previous_magic))
		GameProgress.current_phase_index = 0
		board._update_held_cards(0.0)
		check(button.disabled, "phase change disables confirm immediately")
		for chosen in group.cards:
			check(not board._held_slot(chosen, "HandCard").get_node("Breath").visible, "phase change removes gold immediately")
		GameProgress.current_phase_index = 2
		board._update_held_cards(0.0)
		if group.cards.size() > 1:
			var invalid = group.cards[0]
			var original_extra: bool = invalid._need_extra_play
			invalid._need_extra_play = true
			invalid._is_concealed = false
			board._update_held_cards(0.0)
			check(button.disabled, "changed selected card blocks confirm immediately")
			check(not board._held_card_playable(group.cards[1]), "invalid selected peer removes playable hint")
			invalid._need_extra_play = original_extra
			invalid._is_concealed = bool(group.hidden[0])
			board._update_held_cards(0.0)
		button.pressed.emit()
		check(RegularPlay.completed(id), "confirm submits through regular play")
		check(board._selected_cards.is_empty(), "successful submit clears selection")
		var remaining: Array = pl.hand_cards.filter(func(item): return item is BaseHandCard)
		for item in remaining:
			var held: Control = board._held_slot(item, "HandCard")
			check(held.position.distance_to(held.get_meta("rest_position")) < 0.01, "remaining hand immediately moves to recalculated position")
		if not remaining.is_empty():
			var left_edge := INF
			var right_edge := -INF
			for item in remaining:
				var held: Control = board._held_slot(item, "HandCard")
				left_edge = minf(left_edge, held.position.x)
				right_edge = maxf(right_edge, held.position.x + held.size.x)
			check(absf((left_edge + right_edge) * 0.5 - board.get_node("Master").get_rect().get_center().x) < 0.01, "remaining hand re-centers after submission")
		var count: int = pl.played_cards.size()
		button.pressed.emit()
		check(pl.played_cards.size() == count, "repeat confirm cannot submit twice")
		var played_face: bool = card._is_concealed
		click.button_index = MOUSE_BUTTON_RIGHT
		slot.gui_input.emit(click)
		check(card._is_concealed == played_face, "stale held slot cannot flip submitted card")
	# 抽屉抬起整副牌之后，鼠标落在牌上仍必须能判为悬浮（否则上移后就不能跟随）
	check(board.held_hover_allowed(true, true, 1.0), "hover allowed once the drawer is open")
	check(board.held_hover_allowed(true, true, 0.4), "hover works while the drawer is still rising")
	check(not board.held_hover_allowed(true, true, 0.0), "hover blocked before the drawer starts")
	check(not board.held_hover_allowed(false, true, 1.0), "no hover when the pointer is off the card")
	check(board.held_hover_allowed(true, false, 0.0), "side zone cards hover without the drawer")
	# 悬浮放大：横向绝不动（否则会盖住邻牌、挡住点击）；纵向只向上且限幅
	var sideways: Vector2 = board.held_hover_shift(Vector2(9999.0, 300.0), Vector2(0.0, 300.0))
	check(sideways.x == 0.0, "hover follow never shifts horizontally")
	var downward: Vector2 = board.held_hover_shift(Vector2(0.0, 9999.0), Vector2.ZERO)
	check(downward == Vector2.ZERO, "hover follow never moves downward")
	var rising: Vector2 = board.held_hover_shift(Vector2(0.0, 0.0), Vector2(0.0, 500.0))
	check(rising.x == 0.0 and rising.y < 0.0 and absf(rising.y) <= 46.0, "hover follow rises only, within cap")
	var still: Vector2 = board.held_hover_shift(Vector2(500.0, 300.0), Vector2(500.0, 300.0))
	check(still == Vector2.ZERO, "hover follow is zero when mouse sits on card centre")

	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
