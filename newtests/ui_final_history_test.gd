extends Node

const Scene = preload("res://assets/scenes/game_scene/battle_board_v2.tscn")
class BoardProbe extends "res://scripts/game_scene/battle_board_v2.gd":
	func _ready() -> void:
		set_process(false)
		$CardModificationHistory/Panel/Close.pressed.connect(_close_card_modification_history)
		_bind_card_view_controls()
	func _exit_tree() -> void: pass

var board
var session
var builder
var data: Dictionary
var card
var view: Dictionary
var checks := 0
var failures: Array = []

func check(ok: bool, label: String) -> void:
	checks += 1
	print("CHECK ", label, " ", ok)
	if not ok: failures.append(label)

func _ready() -> void: call_deferred("run")

func deliver(snapshot: Dictionary) -> void:
	session.transport.message_received.emit(1, {"kind":"match_view", "state":snapshot, "pending":{}, "actions":{}})
	check(session.read_match() == snapshot, "formal session mirror accepted seq " + str(snapshot.seq))

func erase_history(value) -> void:
	if value is Dictionary:
		value.erase("modification_history")
		for child in value.values(): erase_history(child)
	elif value is Array:
		for child in value: erase_history(child)

func run() -> void:
	GameStart.reset()
	EffectManager.reset_runtime()
	GameProgress.reset_progress()
	GameData.player_data_library.clear()
	data = GameData.new_player_data()
	GameData.player_data_library[0] = data
	GameData.player_data_library[1] = GameData.new_player_data()
	LoadAttack.load_all()
	card = LoadAttack.resolve("strength:2")
	card._is_concealed = false
	data.hand_cards.append(card)
	preload("res://scripts/system/operations/EditCardCost.gd").new().exec(BaseNumber.new(2), null, card)
	builder = preload("res://scripts/match/view_builder.gd").new()
	view = builder.build(0)
	view.seq = 101
	session = preload("res://scripts/net/session/lobby_session.gd").new()
	session.transport.message_received.emit(1, {"kind":"match_bind", "observer":0})
	deliver(view)
	board = Scene.instantiate()
	board.set_script(BoardProbe)
	board.network_session = session
	add_child(board)
	board._source_is_local = false
	board._source = NetworkBattleSource.new(session)
	board._local_player_id = 0
	board.get_node("Hand").show()
	var slot: Control = board._spawn("HandCard", board.get_node("Hand"))
	var projected: Dictionary = session.read_match().players[0].hand_cards[0]
	check(projected.has("modification_history"), "actual operation builder mirror history exists")
	board._sync_card_modification_badge(slot, projected, true)
	var badge: Button = slot.get_node("CardModificationBadge")
	check(badge.visible, "network authorized real history badge visible")
	badge.pressed.emit()
	check(board.get_node("CardModificationHistory").visible, "network production badge opens same modal")
	check(board.get_node("CardModificationHistory/Panel/Entries").text.contains(card.get_modification_details()[0].detail), "network renders exact operation record")
	check(not board.get_node("CardModificationHistory/Panel/Entries").bbcode_enabled, "literal BBCode disabled")
	# 新seq同id实时更新，不缓存旧历史。
	preload("res://scripts/system/operations/EditCardPower.gd").new().exec(card, BaseNumber.new(3), null, 0)
	view = builder.build(0)
	view.seq = 102
	deliver(view)
	board._refresh_card_modification_history()
	check(board.get_node("CardModificationHistory").visible and board.get_node("CardModificationHistory/Panel/Entries").text.contains(card.get_modification_details().back().detail), "same id new seq refreshes open history")
	check(badge.get_meta("mod_seq") == 102, "badge sequence refreshed")
	var fresh: Dictionary = session.read_match().players[0].hand_cards[0]
	# UI自己也严格拒绝畸形，不依赖调用方已做Mirror校验。
	for bad in [null, 3, "records", {}, ["record"], [{"type":"cost"}], [{"type":"cost","detail":"x","extra":"x"}], [{"type":1,"detail":"x"}], [{"type":"x","detail":[]}]]:
		var malformed: Dictionary = fresh.duplicate(true)
		malformed.modification_history = bad
		board._sync_card_modification_badge(slot, malformed, true)
		check(not badge.visible and not badge.has_meta("mod_target_card"), "UI rejects exact malformed history " + str(bad))
	for field in ["visible", "concealed"]:
		var malformed: Dictionary = fresh.duplicate(true)
		malformed[field] = 1
		board._sync_card_modification_badge(slot, malformed, true)
		check(not badge.visible, "strict bool gate " + field)
	board._sync_card_modification_badge(slot, fresh, false)
	check(not badge.visible, "explicit unauthorized cannot grant history")
	board._sync_card_modification_badge(slot, card, true)
	check(not badge.visible, "network rejects local rule object fallback")
	board._sync_card_modification_badge(slot, fresh, true)
	badge.pressed.emit()
	var absent: Dictionary = view.duplicate(true)
	absent.seq = 103
	erase_history(absent)
	deliver(absent)
	board._refresh_card_modification_history()
	check(not badge.visible and not badge.has_meta("mod_target_card") and not board.get_node("CardModificationHistory").visible and board.get_node("CardModificationHistory/Panel/Entries").text.is_empty(), "missing field revokes closed badge target and open modal without bind")
	view.seq = 104
	deliver(view)
	board._sync_card_modification_badge(slot, fresh, true)
	badge.pressed.emit()
	card._is_concealed = true
	view = builder.build(0)
	view.seq = 105
	deliver(view)
	board._refresh_card_modification_history()
	check(not badge.visible and not board.get_node("CardModificationHistory").visible, "concealment revokes before next periodic rebind")
	card._is_concealed = false
	data.hand_cards.erase(card)
	data.played_cards.append(card)
	view = builder.build(0)
	view.seq = 106
	deliver(view)
	board._refresh_card_modification_history()
	check(not badge.visible, "leaving held collection clears old held badge")
	var row := Control.new()
	board.add_child(row)
	board._bind_played_cards_row(row, view.players[0].played_cards, 0)
	var played: Control = row.get_child(0)
	var played_badge: Button = played.get_node("CardModificationBadge")
	check(played_badge.visible, "network formal played binder shares badge")
	played_badge.pressed.emit()
	check(board.get_node("CardModificationHistory").visible, "network formal played reader opens")
	data.played_cards.erase(card)
	GameData.player_data_library[1].played_cards.append(card)
	view = builder.build(0)
	view.seq = 107
	deliver(view)
	board._refresh_card_modification_history()
	check(not played_badge.visible and not played_badge.has_meta("mod_target_card") and not board.get_node("CardModificationHistory").visible, "current owner transfer revokes former owner's badge and reader")
	board._bind_played_cards_row(row, view.players[1].played_cards, 1)
	check(not row.get_child(0).get_node("CardModificationBadge").visible, "opponent public played card grants no control or history")
	GameData.player_data_library[1].played_cards.erase(card)
	data.hand_cards.append(card)
	view = builder.build(0)
	view.seq = 108
	deliver(view)
	board._sync_card_modification_badge(slot, view.players[0].hand_cards[0], true)
	badge.pressed.emit()
	session.transport.message_received.emit(1, {"kind":"match_reset"})
	session.transport.message_received.emit(1, {"kind":"match_bind", "observer":-1})
	board._refresh_card_modification_history()
	check(not badge.visible and not board.get_node("CardModificationHistory").visible, "observer reset clears previous identity immediately")
	var spectate: Dictionary = builder.build(-1)
	spectate.seq = 109
	deliver(spectate)
	board._local_player_id = -1
	board._sync_card_modification_badge(slot, fresh, true)
	check(not badge.visible, "spectator cannot use former owner's dictionary")
	board.free()
	session.close()
	print("RESULT ", JSON.stringify({"suite":"ui_final_history", "checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
