extends Node

const Scene = preload("res://assets/scenes/game_scene/battle_board_v2.tscn")
class BoardProbe extends "res://scripts/game_scene/battle_board_v2.gd":
	func _ready() -> void: set_process(false)
	func _exit_tree() -> void: pass

var checks := 0
var failures: Array = []
func check(ok: bool, label: String) -> void:
	checks += 1
	print("CHECK ", label, " ", ok)
	if not ok: failures.append(label)
func _ready() -> void: call_deferred("run")
func run() -> void:
	var fixture := preload("res://newtests/ui_final_fixture.gd").setup()
	check(fixture.spell_ok, "real declared normal spell runtime factory registered")
	var board = Scene.instantiate()
	board.set_script(BoardProbe)
	add_child(board)
	var builder = preload("res://scripts/match/view_builder.gd").new()
	board._source_is_local = true
	board._local_player_id = 0
	board._source = LocalBattleSource.new(0,builder,MatchSeatQuery.new(builder))
	board._held_action_ids = builder.ids
	board._rebuild_battle_commands()
	board._bind_rivals()
	var own: Control = board._rival_card(0)
	check(not own.has_node("Spells"), "own top slot has no command spell display")
	board._bind_spell_box(board.get_node("Self/Spells"), board._source.read_view().players[0])
	var local_spell: Control = board.get_node("Self/Spells/SpellCard")
	check(local_spell.mouse_filter == Control.MOUSE_FILTER_STOP, "own resource spell card receives input")
	check(local_spell.gui_input.get_connections().size() >= 1, "own resource spell retains production callback")
	var rival: Control = board._rival_card(1)
	for summary in rival.get_node("Stats/Spells").get_children():
		check(summary.gui_input.get_connections().is_empty() and summary.mouse_filter == Control.MOUSE_FILTER_IGNORE, "rival remains information only")
	board._stop_battle_commands()
	board.free()
	print("RESULT ",JSON.stringify({"suite":"ui_final_spells","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
