extends Node
# 本局原来源取自 reset_runtime 回执；夹具对 operation 显式传入，不从全局补票。
var ctx: SessionContext = null
func _reset_ctx() -> SessionContext:
	var reset: Dictionary = EffectManager.reset_runtime()
	return reset.get("context") if reset.get("ok", false) else null
const FixtureClone = preload("res://newtests/fixture_clone.gd")

const Scene = preload("res://assets/scenes/game_scene/battle_board_v2.tscn")
const CostOperation = preload("res://scripts/system/operations/EditCardCost.gd")
const PowerOperation = preload("res://scripts/system/operations/EditCardPower.gd")
const AttributesOperation = preload("res://scripts/system/operations/EditCardAttributes.gd")

# 只停自动开局/推进；保留生产绑定、回调、历史刷新、模态与输入处理。
class BoardProbe extends "res://scripts/game_scene/battle_board_v2.gd":
	func _ready() -> void:
		set_process(false)
		$CardModificationHistory/Panel/Close.pressed.connect(_close_card_modification_history)
		_bind_card_view_controls()
	func _exit_tree() -> void: pass

var checks := 0
var failures: Array[String] = []
var board
var data: Dictionary
var builder
var card: BaseAttack
var other: BaseAttack
var skill: BaseSkill

func check(value: bool, label: String) -> void:
	checks += 1
	print("CHECK ", label, " ", value)
	if not value: failures.append(label)

func _ready() -> void:
	get_tree().create_timer(180.0).timeout.connect(func():
		print("RESULT ", JSON.stringify({"suite":"card_modification_history_v2", "checks":maxi(1, checks), "failures":failures + ["180s watchdog"]}))
		get_tree().quit(1))
	call_deferred("run")

func bind_hand(slot: Control, value, mine: bool = true) -> void:
	slot.set_meta("card", value)
	board._bind_hand_card(slot, value, "手牌", 1, mine, false)

func badge(slot: Control) -> Button:
	return slot.get_node("CardModificationBadge")

func reader() -> Control:
	return board.get_node("CardModificationHistory")

func text() -> String:
	return reader().get_node("Panel/Entries").text

func open(slot: Control) -> void:
	# headless只验证正式信号/回调，不冒称GUI命中通过。
	badge(slot).pressed.emit()

func state() -> String:
	var cards: Array = []
	for value in [card, other, skill]:
		cards.append([value.get_instance_id(), value._cost.number, value._power.number, value._is_concealed, value._is_activating, value._is_closed, value._attributes.duplicate(), value.get_modification_details().duplicate(true)])
	return JSON.stringify({"cards":cards,"magic":data.magic.number,"score":data.score.number,"spells":data.command_spell_count.number,"power":data.power.number,"hand":data.hand_cards.map(func(c):return c.get_instance_id()),"played":data.played_cards.map(func(c):return c.get_instance_id()),"selection":board._selected_cards.map(func(c):return c.get_instance_id()),"phase":GameProgress.current_phase_index,"round":GameProgress.current_round,"current":GameProgress.current_player_id,"log":GameLog.query({}, null, -1),"wait":EffectManager.is_waiting_for_choice()})

func run() -> void:
	ctx = _reset_ctx()
	GameProgress.reset_progress()
	GameLog.reset()
	GameData.player_data_library.clear()
	data = GameData.new_player_data()
	GameData.player_data_library[0] = data
	GameData.player_data_library[1] = GameData.new_player_data()
	GameProgress.current_phase_index = 2
	GameProgress.current_player_id = 0
	GameProgress.current_round = 1
	data.magic.number = 8
	LoadAttack.load_all()
	card = LoadAttack.resolve("strength:2")
	other = LoadAttack.resolve("strength:2")
	check(card != null and other != null and card != other, "real JSON loader creates independent instances")
	if card == null or other == null:
		finish()
		return
	skill = BaseSkill.new("未觉醒身份[b]", "", [], BaseNumber.new(1), BaseNumber.new(1))
	data.hand_cards.append_array([card, other])
	data.servant_skills.append(skill)
	builder = preload("res://scripts/match/view_builder.gd").new()
	board = Scene.instantiate()
	board.set_script(BoardProbe)
	add_child(board)
	board._local_player_id = 0
	board._source_is_local = true
	board._held_action_ids = builder.ids
	board._source = LocalBattleSource.new(0, builder, MatchSeatQuery.new(builder))
	board.get_node("Hand").show()
	for template in ["HandCard", "ZoneCard", "PlayedCard"]:
		check(board.get_node("Templates/" + template).has_node("CardModificationBadge"), template + " contains static badge")
	check(not reader().visible and text().is_empty(), "static read-only panel starts empty and closed")
	var panel_id := reader().get_instance_id()
	var slot: Control = board._held_slot(card, "HandCard")
	bind_hand(slot, card)
	check(not badge(slot).visible, "unchanged real template has no badge")
	var before_cost = card._cost.number
	CostOperation.new().exec(BaseNumber.new(2), null, card)
	PowerOperation.new().exec(card, BaseNumber.new(3), null, 0)
	AttributesOperation.new().exec(["history[b]"], [], [""], card)
	check(card.has_modifications() and card.get_modification_details().size() == 3, "real production operations wrote three records")
	check(card._cost.number == before_cost + 2, "production operation actually changed cost")
	check(not other.has_modifications(), "independent template instance untouched")
	bind_hand(slot, card)
	check(badge(slot).visible, "held binder consumes real history")
	check(badge(slot).mouse_filter == Control.MOUSE_FILTER_STOP, "badge owns mouse input")
	check(board._meta_or(badge(slot), "mod_target_card", null) == card, "badge metadata targets current real card")
	check(badge(slot).pressed.get_connections().size() == 1, "binding has one signal callback")
	var before := state()
	open(slot)
	check(reader().visible, "production badge signal opens panel")
	check(board._native_modal_visible(), "history uses shared modal blocker")
	check(not board._held_input_available(), "history modal disables held commands")
	check(not reader().get_node("Panel/Entries").bbcode_enabled, "history is literal text not BBCode")
	for record in card.get_modification_details():
		check(text().contains("• " + record.detail), "panel contains exact producer detail " + record.type)
	check(text().contains("history[b]"), "brackets in real attribute detail preserved")
	check(state() == before, "open/read do not select flip activate or mutate game")
	for i in 3:
		bind_hand(slot, card)
		board._refresh_card_modification_history()
	check(reader().visible and reader().get_instance_id() == panel_id, "refresh retains same panel and current history")
	check(badge(slot).pressed.get_connections().size() == 1, "refresh does not duplicate signal")
	CostOperation.new().exec(BaseNumber.new(1), null, card)
	board._refresh_card_modification_history()
	check(text().contains(card.get_modification_details().back().detail), "open reader refreshes newly produced real operation record")
	var cloned = FixtureClone.clone_template(card, ctx)
	check(cloned != card and cloned.get_modification_details() == card.get_modification_details(), "real clone preserves recorded history without reconstruction")
	before = state()
	reader().get_node("Panel/Close").pressed.emit()
	check(not reader().visible and text().is_empty(), "production close signal clears contents")
	check(state() == before, "close is read-only")
	open(slot)
	CostOperation.new().exec(BaseNumber.new(1), null, other)
	bind_hand(slot, other)
	check(not reader().visible and text().is_empty(), "same slot switching cards clears previous history")
	open(slot)
	check(reader().visible and text().contains(other.get_modification_details()[0].detail) and not text().contains("history[b]"), "reused slot opens only new card records")
	check(badge(slot).pressed.get_connections().size() == 1, "switch does not capture old object or duplicate callback")
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = KEY_ESCAPE
	board._input(event)
	check(not reader().visible and not board._is_paused(), "Escape closes history without opening pause menu")
	# 未记录的真实改值不能据模板差异猜历史。
	var unrecorded := LoadAttack.resolve("strength:2")
	data.hand_cards.append(unrecorded)
	unrecorded.edit_cost(BaseNumber.new(7))
	bind_hand(slot, unrecorded)
	check(not badge(slot).visible and not unrecorded.has_modifications(), "unrecorded value difference never fabricates badge")
	bind_hand(slot, card)
	open(slot)
	card._is_concealed = true
	board._refresh_card_modification_history()
	check(not reader().visible and text().is_empty(), "live concealed revocation clears open history")
	bind_hand(slot, card)
	check(not badge(slot).visible and not badge(slot).has_meta("mod_target_card"), "concealed card exposes neither badge nor target")
	card._is_concealed = false
	bind_hand(slot, card, false)
	check(not badge(slot).visible, "explicit unauthorized binding cannot expose history")
	var rival := LoadAttack.resolve("strength:2")
	GameData.player_data_library[1].hand_cards.append(rival)
	CostOperation.new().exec(BaseNumber.new(1), null, rival)
	bind_hand(slot, rival)
	check(not badge(slot).visible, "other owner face-up history stays private even with mine flag")
	CostOperation.new().exec(BaseNumber.new(1), null, skill)
	skill._is_awakened = false
	var zone: Control = board._held_slot(skill, "ZoneCard")
	bind_hand(zone, skill)
	check(not badge(zone).visible, "unawakened skill hides history identity hint")
	skill._is_awakened = true
	bind_hand(zone, skill)
	check(badge(zone).visible, "authorized owner held skill consumes shared binding")
	open(zone)
	check(reader().visible, "owner skill history opens without public true-name grant")
	board._close_card_modification_history()
	# 中央已出和残留共用正式binder，输入是当前view投影，不是另造历史字段。
	data.hand_cards.erase(card)
	data.played_cards.append(card)
	var rows: Array[Control] = [Control.new(), Control.new()]
	for row in rows:
		board.add_child(row)
		board._source.invalidate()
		var projected: Array = board._source.read_view().players[0].played_cards
		board._bind_played_cards_row(row, projected, 0)
		var played_slot: Control = row.get_child(0)
		check(badge(played_slot).visible and board._meta_or(badge(played_slot), "mod_target_card", null) == card, "played/residue projected binding resolves authorized real instance")
		open(played_slot)
		check(reader().visible and text().contains("history[b]"), "played/residue history opens same literal records")
		board._close_card_modification_history()
		board._bind_played_cards_row(row, [], 0)
		check(row.get_child_count() == 0, "empty played/residue refresh removes old slot")
	# 经真实残留声明与生产view分类，验证正式LocalResiduePile接线。
	var residue_effect := BaseEffect.new("residue history fixture", [], 0, false, false)
	residue_effect._is_residue = true
	card._effects.append(residue_effect)
	board._source.invalidate()
	check(board._source.read_view().players[0].residue_cards.size() == 1, "authority classifies explicit residue effect")
	board._bind_residue_piles()
	var pile: Control = board.get_node("LocalResiduePile")
	var residue_slot: Control = pile.get_node("Cards/Row").get_child(0)
	check(pile.visible and badge(residue_slot).visible, "formal LocalResiduePile consumes shared history binder")
	var residue_before := state()
	open(residue_slot)
	check(reader().visible and text().contains("history[b]"), "formal residue badge opens actual operation records")
	check(state() == residue_before, "residue browsing leaves power resources zones and history unchanged")
	board._close_card_modification_history()
	card._is_closed = true
	board._source.invalidate()
	board._bind_residue_piles()
	check(not pile.visible and pile.get_node("Cards/Row").get_child_count() == 0, "closed residue refresh removes badge and stale slot")
	card._is_closed = false
	# 对手明置已出牌仍不给旧历史。
	GameData.player_data_library[1].played_cards.append(rival)
	board._source.invalidate()
	board._bind_played_cards_row(rows[0], board._source.read_view().players[1].played_cards, 1)
	check(not badge(rows[0].get_child(0)).visible, "opponent played card cannot expose old private history")
	bind_hand(slot, other)
	open(slot)
	before = state()
	var outside := InputEventMouseButton.new()
	outside.pressed = true
	outside.button_index = MOUSE_BUTTON_LEFT
	outside.position = Vector2.ZERO
	board._input(outside)
	check(not reader().visible and state() == before, "outside close is consumed and read-only")
	open(slot)
	board._local_player_id = 1
	board._refresh_card_modification_history()
	check(not reader().visible and text().is_empty(), "observer switch revokes open owner history")
	board._local_player_id = 0
	open(slot)
	data.hand_cards.erase(other)
	board._refresh_card_modification_history()
	check(not reader().visible and text().is_empty(), "card leaving all authorized zones revokes reader")
	data.hand_cards.append(other)
	bind_hand(slot, other)
	open(slot)
	slot.get_parent().remove_child(slot)
	board._refresh_card_modification_history()
	check(not reader().visible and text().is_empty(), "removed source slot cannot keep stale history")
	slot.free()
	# 当前网络view没有历史；即使本机对象与同名模板存在也不补齐。
	board.network_session = RefCounted.new()
	board._refresh_card_modification_history()
	var network_slot: Control = board._spawn("HandCard", board.get_node("Hand"))
	board._sync_card_modification_badge(network_slot, builder.card_view(card, true), true)
	check(not badge(network_slot).visible and not badge(network_slot).has_meta("mod_target_card"), "network dictionary without declared history remains closed")
	board._sync_card_modification_badge(network_slot, card, true)
	check(not badge(network_slot).visible, "network cannot fall back to local rule object history")
	board.network_session = null
	check(reader().get_instance_id() == panel_id, "panel skeleton never rebuilt")
	print("HISTORY_RECORDS ", JSON.stringify(card.get_modification_details()))
	finish()

func finish() -> void:
	if is_instance_valid(board):
		board.free()
	ctx = _reset_ctx()
	print("RESULT ", JSON.stringify({"suite":"card_modification_history_v2","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
