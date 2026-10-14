extends Node
# 本局原来源取自 reset_runtime 回执；夹具对 operation 显式传入，不从全局补票。
var ctx: SessionContext = null
func _reset_ctx() -> SessionContext:
	var reset: Dictionary = EffectManager.reset_runtime()
	return reset.get("context") if reset.get("ok", false) else null

const BoardScene = preload("res://assets/scenes/game_scene/battle_board_v2.tscn")
const Builder = preload("res://scripts/match/view_builder.gd")

# 只停用自动启动/推进；绑定、候选查询、动画注册、输入门均继承生产实现。
class BoardProbe extends "res://scripts/game_scene/battle_board_v2.gd":
	func _ready() -> void: set_process(false)
	func _exit_tree() -> void: pass

# 权威查询生成的授权快照接收边界，不声称覆盖网络传输或会话生命周期。
class SnapshotSession extends RefCounted:
	signal changed
	var view: Dictionary = {}
	var actions: Dictionary = {}
	func read_match() -> Dictionary: return view
	func read_actions() -> Dictionary: return actions
	func read_pending() -> Dictionary: return {}
	func match_commands_available() -> bool: return true

class PresenterProbe extends "res://scripts/net/ui/v2_view_presenter.gd":
	func _init(target: Control, source) -> void:
		board = target
		session = source

var checks := 0
var failures: Array[String] = []
var rows: Array = []
var builder
var query
var source
var board
var session
var presenter
var selection
var data: Dictionary
var card: BaseHandCard
var support: BaseAttack
var effect: BaseEffect

func check(ok: bool, label: String) -> void:
	checks += 1
	print("CHECK ", label, " ", ok)
	if not ok: failures.append(label)

func _ready() -> void:
	call_deferred("run")

func setup(playable: bool, manual: bool, mixed: bool = false) -> void:
	ctx = _reset_ctx()
	GameProgress.reset_progress()
	GameLog.reset()
	GameLog.set_context(1, "action")
	GameData.player_data_library.clear()
	data = GameData.new_player_data()
	GameData.player_data_library[0] = data
	data.is_out = false
	data.magic.number = 8
	data.play_limit.number = 2 if mixed else 1
	data.regular_play_min.number = 2 if mixed else 1
	GameProgress.current_round = 1
	GameProgress.current_phase_index = 2
	GameProgress.current_player_id = 0
	MapData.active_situation = null
	for area in MapData.areas:
		area._events.clear()
		area._buffs.clear()
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.ACTION_PHASE, TimePoints.NON_CLIMAX])
	card = BaseSkill.new("approved affordance", "", [], BaseNumber.new(2), BaseNumber.new(1))
	card._is_concealed = false
	card._need_extra_play = not playable
	data.hand_cards.append(card)
	support = BaseAttack.new("support", "", [], BaseNumber.new(1), BaseNumber.new(1))
	support._is_concealed = false
	if mixed: data.hand_cards.append(support)
	effect = null
	if manual:
		effect = BaseEffect.new("approved manual", [TimePoints.SELF_PREFIX + TimePoints.ACTION_PHASE], 0, false, false)
		effect._is_manual = true
		effect._need_activate = false
		effect._cost = BaseNumber.new(1)
		effect.from = weakref(card)
		card._effects = [effect]
		check(EffectManager.register_effect(effect, 0), "fixture manual registration")
		TimePointChecker.dynamic_time_point([TimePoints.ACTION_PHASE], 0, null, ctx)
	builder = Builder.new()
	query = MatchSeatQuery.new(builder)
	source = LocalBattleSource.new(0, builder, query)
	board = BoardScene.instantiate()
	board.set_script(BoardProbe)
	add_child(board)
	board._local_player_id = 0
	board._source = source
	board._held_action_ids = builder.ids
	board._source_is_local = true
	board.get_node("Hand").show()

func dispose() -> void:
	if board.network_session != null:
		board._source.close()
		presenter.board = null
		presenter.session = null
	board.free()
	board = null
	presenter = null
	session = null
	selection = null
	ctx = _reset_ctx()

func slot_for(value, template: String = "HandCard") -> Control:
	var slot: Control = board._held_slot(value, template)
	slot.set_meta("held_group", "zone")
	slot.set_meta("rest_position", Vector2(500, 500))
	slot.set_meta("rest_rotation", 0.0)
	return slot

func network_snapshot() -> void:
	var group: Dictionary = source.read_group_preview(board._selected_cards, board._selected_cards_hidden())
	if session == null:
		session = SnapshotSession.new()
		presenter = PresenterProbe.new(board, session)
		selection = NetworkGroupSelection.new()
		presenter.selection = selection
		board.network_session = session
		board._network_presenter = presenter
		board._source = NetworkBattleSource.new(session)
		board._source.bind_group_selection(selection)
	source.invalidate()
	session.view = source.read_view()
	session.view.seq = 7
	session.view.observer = 0
	session.view.game_over = false
	session.actions = source.read_actions()
	selection._cards = group.cards.duplicate()
	selection._hidden = group.hidden.duplicate()
	selection._preview = group.preview.duplicate(true)
	selection._preview.view_seq = 7
	selection._waiting = false
	selection._submitted = false
	presenter._mine = session.view.players[0]

func frames(slot: Control, gold: bool, purple: bool, selected: bool, label: String) -> void:
	# 用户最新口径：选牌白框替代金框；发动紫框是另一意图。
	check(slot.get_node("Breath").visible == (gold and not selected), label + " gold unselected group-only")
	var active := slot.get_node_or_null("EffectBreath") as Control
	check(active != null and active.visible == purple, label + " purple manual-only")
	check(slot.get_node("Selected").visible == selected, label + " independent selected")
	rows.append({"case": label, "gold": slot.get_node("Breath").visible, "purple": active.visible if active != null else null, "selected": slot.get_node("Selected").visible})

func exercise_state(playable: bool, manual: bool, network: bool) -> void:
	setup(playable, manual)
	var modes: Array = RegularPlay.pending_modes(0, [], [], card)
	check(not modes.is_empty() == playable, "authority exact expected play state")
	check(EffectManager.can_manual_activate(effect, 0) == manual, "authority exact expected manual state")
	var original_magic: float = data.magic.number
	var original_history: int = GameLog.query({}, null, -1).size()
	var value = card
	if network:
		network_snapshot()
		value = builder.card_view(card, true)
	var slot := slot_for(value)
	var label := ("network" if network else "local") + " " + str(playable) + "/" + str(manual)
	board._bind_hand_card(slot, value, "手牌", 1, true, false)
	frames(slot, playable, manual, false, label + " bind")
	board._update_held_cards(0.0)
	frames(slot, playable, manual, false, label + " refresh")
	board._update_held_effect_button(slot, true, 1.0)
	var button := slot.get_node("EffectButton") as Button
	check(button.visible == manual and button.disabled == not manual, label + " original effect button availability")
	check(slot.get_node("Frame").modulate == (Color.WHITE if playable or manual else Color(0.55, 0.55, 0.55)), label + " existing dim policy")
	var identity: int = slot.get_instance_id()
	var count: int = slot.get_child_count()
	for i in range(12):
		board._bind_hand_card(slot, value, "手牌", 1, true, false)
		board._update_held_cards(0.0)
	check(slot.get_instance_id() == identity and slot.get_child_count() == count, label + " persistent nodes no duplication")
	for panel_name in ["Breath", "EffectBreath", "Selected"]:
		check(board._breathing.count(slot.get_node(panel_name)) <= 1, label + " rebind registration unique " + panel_name)
	check(data.magic.number == original_magic and not card._is_concealed and data.played_cards.is_empty() and GameLog.query({}, null, -1).size() == original_history, label + " hints read-only")
	if playable:
		check(RegularPlay.can_submit_group(0, [card], [false]), label + " authority complete group witness")
		check(RegularPlay.submit_group(0, [card], [false], false, ctx) and data.played_cards.has(card) and data.magic.number == original_magic - 2, label + " real play enters and pays")
	dispose()

func mixed_resource(network: bool) -> void:
	setup(true, true, true)
	board._selected_cards = [support]
	check(RegularPlay.pending_modes(0, [support], [false], card) == [false], "mixed group authority modes")
	var value = card
	if network:
		network_snapshot()
		value = builder.card_view(card, true)
	var slot := slot_for(value, "ZoneCard")
	board._bind_hand_card(slot, value, "技能", 1, true, false)
	board._update_held_cards(0.0)
	frames(slot, true, true, false, "mixed before resource " + str(network))
	data.magic.number = 1
	if network: network_snapshot()
	else: source.invalidate()
	board._update_held_cards(0.0)
	frames(slot, false, true, false, "mixed after cost short " + str(network))
	data.magic.number = 0
	if network: network_snapshot()
	else: source.invalidate()
	board._update_held_cards(0.0)
	frames(slot, false, false, false, "mixed all unavailable " + str(network))
	data.magic.number = 8
	board._selected_cards = [support, card]
	if network: network_snapshot()
	else: source.invalidate()
	board._update_held_cards(0.0)
	frames(slot, true, true, true, "selected white replaces gold " + str(network))
	board._bind_hand_card(slot, value, "技能", 1, true, false)
	frames(slot, true, true, true, "selected rebind white replaces gold " + str(network))
	board._end_command_attempt = {"test_input_lock": true}
	board._update_held_cards(0.0)
	frames(slot, false, false, true, "input lock hides both actionable frames " + str(network))
	board._update_held_effect_button(slot, true, 1.0)
	check(slot.get_node("EffectButton").disabled and not slot.get_node("EffectButton").visible, "input lock preserves effect button gate " + str(network))
	board._end_command_attempt = {}
	if network:
		selection._waiting = true
		board._update_held_cards(0.0)
		frames(slot, false, true, true, "waiting group independent manual")
		selection._waiting = false
		selection._submitted = true
		board._update_held_cards(0.0)
		frames(slot, false, true, true, "submitted group independent manual")
		selection._submitted = false
		session.view.seq = 8
		board._update_held_cards(0.0)
		frames(slot, false, true, true, "stale preview independent manual")
	dispose()

func geometry() -> void:
	setup(true, true)
	for template in ["HandCard", "ZoneCard"]:
		var slot := slot_for(card, template)
		board._bind_hand_card(slot, card, "手牌", 1, true, false)
		var gold := slot.get_node("Breath") as Panel
		var purple := slot.get_node_or_null("EffectBreath") as Panel
		var white := slot.get_node("Selected") as Panel
		check(purple != null, template + " predeclared purple frame")
		if purple == null: continue
		for scale_value in [1.0, board.HELD_HOVER_SCALE, 0.65, 1.7]:
			slot.scale = Vector2.ONE * scale_value
			slot.rotation = 0.16
			check(white.get_rect().is_equal_approx(gold.get_rect()), template + " selected white replaces gold at identical position " + str(scale_value))
			var inner: Array = [gold, white]
			var outer: Array = [purple, purple]
			for i in range(2):
				var a: Panel = outer[i]
				var b: Panel = inner[i]
				var style := a.get_theme_stylebox("panel") as StyleBoxFlat
				var thickness: float = maxf(maxf(style.border_width_left, style.border_width_right), maxf(style.border_width_top, style.border_width_bottom))
				var safe: Rect2 = a.get_rect().grow(-thickness)
				check(safe.encloses(b.get_rect()) and safe.position.x < b.position.x and safe.position.y < b.position.y and safe.end.x > b.get_rect().end.x and safe.end.y > b.get_rect().end.y, template + " stroke bands separated scale " + str(scale_value) + " pair " + str(i))
				var gap: float = (b.get_global_transform() * Vector2.ZERO).distance_to(a.get_global_transform() * Vector2(thickness, thickness))
				check(gap > 0.0, template + " transformed gap positive " + str(i))
		for panel: Panel in [gold, purple, white]:
			var style := panel.get_theme_stylebox("panel") as StyleBoxFlat
			check(panel.mouse_filter == Control.MOUSE_FILTER_IGNORE and not style.draw_center and style.shadow_size == 0, template + " outline has no input/fill/shadow " + panel.name)
			check(board._breathing.count(panel) <= 1, template + " animation registration unique " + panel.name)
		check(gold.get_theme_stylebox("panel").border_color != purple.get_theme_stylebox("panel").border_color, template + " distinct action colors")
		check(slot.has_node("EffectBreath") and slot.get_node("EffectBreath").get_parent() == slot, template + " own declared outline")
		board._hand.remove_child(slot)
		slot.queue_free()
	dispose()

func alternate_mode() -> void:
	setup(true, false)
	data.hand_cards.clear()
	card = BaseAttack.new("alternate", "", [], BaseNumber.new(20), BaseNumber.new(1))
	card._is_concealed = false
	data.hand_cards.append(card)
	data.magic.number = 0
	source.invalidate()
	check(RegularPlay.pending_modes(0, [], [], card) == [true], "only concealed declaration legal")
	var slot := slot_for(card)
	board._bind_hand_card(slot, card, "手牌", 1, true, false)
	board._update_held_cards(0.0)
	frames(slot, true, false, false, "any declared mode gold")
	check(not card._is_concealed and not board._can_confirm_held_cards(), "hint does not flip or confirm")
	dispose()

func backend_boundary_observation() -> void:
	setup(true, false, true)
	data.regular_play_min.number = 3
	data.play_limit.number = 3
	support._need_extra_play = true
	var third := BaseAttack.new("completion", "", [], BaseNumber.new(0), BaseNumber.new(1))
	data.hand_cards.append(third)
	board._selected_cards = [support]
	var group: Dictionary = source.read_group_preview([support], [false])
	var modes: Array = RegularPlay.pending_modes(0, [support], [false], card)
	var completion_exists := false
	for flag in [false, true]:
		completion_exists = completion_exists or RegularPlay.can_submit_group(0, [support, card, third], [false, false, flag])
	var hint: bool = board._held_card_playable(card, {}, group)
	check(hint == not modes.is_empty(), "backend boundary UI does not replace authority rules")
	print("BACKEND_BOUNDARY ", JSON.stringify({"selected_companion_need_extra_play": true, "minimum": 3, "selected_count": 1, "candidate_modes": modes, "complete_group_exists": completion_exists, "ui_gold_predicate": hint, "query_gap_observed": not modes.is_empty() and not completion_exists}))
	dispose()

func run() -> void:
	for network in [false, true]:
		for state in [[false, false], [true, false], [false, true], [true, true]]:
			exercise_state(state[0], state[1], network)
		mixed_resource(network)
	geometry()
	alternate_mode()
	backend_boundary_observation()
	print("OBSERVATIONS ", JSON.stringify(rows))
	print("RESULT approved_gold_affordance checks=", checks, " failures=", JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
