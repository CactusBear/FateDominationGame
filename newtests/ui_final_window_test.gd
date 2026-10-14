extends Node

class WindowBoard extends "res://scripts/game_scene/battle_board_v2.gd":
	# 唯一测试差异：不自动推进AI。正式ready、process、输入、权威命令均保留。
	func _check_and_step_ai(_delta: float) -> void: pass

var board
var fixture: Dictionary
var session
var builder
var stage := "local"
var command_seen := ""
var checks := 0
var failures: Array = []
var downs := 0
var ups := 0
var mouse_events: Array = []
const ROOT = "E:/scratch/continuous-next-wave/ui-final/"

func check(ok: bool, label: String) -> void:
	checks += 1
	print("CHECK ", label, " ", ok)
	if not ok: failures.append(label)

func _ready() -> void:
	call_deferred("start")

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		mouse_events.append({"position":[event.position.x,event.position.y],"pressed":event.pressed})
		if event.pressed: downs += 1
		else: ups += 1

func start() -> void:
	DisplayServer.window_set_title("UI FINAL owned acceptance")
	check(DisplayServer.get_name() != "headless", "real non-headless window")
	fixture = preload("res://newtests/ui_final_fixture.gd").setup()
	check(fixture.spell_ok, "real normal command spell factory")
	var location = MapData.miyama2
	location._players = [0]
	fixture.data.location = location
	board = preload("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	board.set_script(WindowBoard)
	add_child(board)
	await get_tree().create_timer(3.0).timeout
	write_state()

func rect(node: Control) -> Array:
	var r := node.get_global_rect()
	return [r.position.x,r.position.y,r.size.x,r.size.y]

func slot_for(card) -> Control:
	for slot in board.get_node("Hand").get_children():
		if board._same_card(slot.get_meta("card", null), card): return slot
	return null

func write_state() -> void:
	if not is_instance_valid(board): return
	var targets: Dictionary = {}
	var frames: Array = []
	for slot in board.get_node("Hand").get_children():
		if not slot.is_visible_in_tree(): continue
		var card = slot.get_meta("card")
		var badge: Button = slot.get_node("CardModificationBadge")
		frames.append({"card":card.id if card is Dictionary else card._name,"slot":rect(slot),"gold":slot.get_node("Breath").visible,"purple":slot.get_node("EffectBreath").visible,"white":slot.get_node("Selected").visible,"effect_color":str(slot.get_node("EffectBreath").get_theme_stylebox("panel").border_color),"badge_visible":badge.is_visible_in_tree(),"badge":rect(badge)})
		if card is BaseHandCard:
			var kind: String = "gold" if card == fixture.cards[1] else ("both" if card == fixture.cards[3] else "other")
			targets["card-" + kind] = rect(slot)
			var effect_button: Control = slot.get_node("EffectButton")
			if effect_button.is_visible_in_tree(): targets["effect-" + kind] = rect(effect_button)
		if badge.is_visible_in_tree(): targets["history"] = rect(badge)
	var own: Control = board._rival_card(0)
	var self_spell: Control = board.get_node("Self/Spells/SpellCard")
	if self_spell.is_visible_in_tree(): targets["own_spell"] = rect(self_spell)
	var rival: Control = board._rival_card(1)
	if rival != null and rival.has_node("Stats/Spells") and rival.get_node("Stats/Spells").get_child_count()>0: targets["rival_spell"] = rect(rival.get_node("Stats/Spells").get_child(0))
	for path in ["ModalLayer/EffectChoice/Box/ButtonsRow/BtnCancel", "ModalLayer/EffectChoice/Box/ButtonsRow/BtnConfirm"]:
		var n := board.get_node_or_null(path) as Control
		if n != null and n.is_visible_in_tree(): targets[path] = rect(n)
	for n in board.get_node("ModalLayer/EffectChoice").find_children("*", "Button", true, false):
		if n.is_visible_in_tree(): targets[str(board.get_path_to(n)) + ":" + n.text] = rect(n)
	for group in board._play_group_nodes():
		for slot in group.get_node("Cards/Row").get_children():
			var b: Control = slot.get_node("CardModificationBadge")
			if b.is_visible_in_tree(): targets["played_history"] = rect(b)
	var result: Dictionary = {"stage":stage,"mouse_position":[board.get_global_mouse_position().x,board.get_global_mouse_position().y],"hovered":str(board.get_viewport().gui_get_hovered_control()),"drawer_open":board._hand_drawer_open,"mouse_events":mouse_events,"checks":checks,"failures":failures,"downs":downs,"ups":ups,"targets":targets,"frames":frames,"history_visible":board.get_node("CardModificationHistory").visible,"history_text":board.get_node("CardModificationHistory/Panel/Entries").text,"modal_visible":board._effect_modal.visible,"pending":board._source.read_pending(),"own_spell_count":fixture.data.command_spell_count.number,"own_magic":fixture.data.magic.number,"rival_spell_count":GameData.player_data_library[1].command_spell_count.number,"selected":board._selected_cards.size(),"attempt":board._end_command_attempt,"drawer":board._opponent_drawer.visible}
	var file := FileAccess.open(ROOT + "window-state.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))

func _process(_delta: float) -> void:
	if not is_instance_valid(board): return
	write_state()
	var command: String = FileAccess.get_file_as_string(ROOT + "window-command.txt").strip_edges() if FileAccess.file_exists(ROOT + "window-command.txt") else ""
	if command.is_empty() or command == command_seen: return
	command_seen = command
	process_command(command)

func process_command(command: String) -> void:
	if command.begins_with("shot-"):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(ROOT + command + ".png")
		return
	match command:
		"verify-initial":
			check(not board._rival_card(0).has_node("Spells"), "own top slot no spell display after latest user decision")
			for index in fixture.cards.size():
				var slot := slot_for(fixture.cards[index])
				check(slot != null and slot.get_node("Breath").visible == (index in [1,3]) and slot.get_node("EffectBreath").visible == (index in [2,3]), "real authority local four-state " + str(index))
		"verify-selected":
			var slot := slot_for(fixture.cards[1])
			check(board._selected_cards.has(fixture.cards[1]) and slot.get_node("Selected").visible and not slot.get_node("Breath").visible, "OS selected gold replaced by white in place")
		"verify-effect-selected":
			var slot := slot_for(fixture.cards[3])
			check(board._effect_modal.visible and slot.get_node("EffectBreath").visible and slot.get_node("EffectBreath").get_theme_stylebox("panel") == slot.get_node("EffectBreath").get_meta("selected_outline"), "OS effect selection turns original purple frame white")
		"verify-effect-cancel":
			var slot := slot_for(fixture.cards[3])
			check(not board._effect_modal.visible and slot.get_node("EffectBreath").get_theme_stylebox("panel") == slot.get_node("EffectBreath").get_meta("available_outline"), "OS effect cancel restores purple frame")
		"verify-spell-open":
			check(board._effect_modal.visible and not board._source.read_pending().is_empty(), "OS own resource spell opened authority pending modal")
			check(fixture.data.command_spell_count.number==3 and fixture.data.magic.number==8, "opening did not pay or grant resource")
		"verify-spell-cancel":
			check(not board._effect_modal.visible and board._source.read_pending().is_empty() and fixture.data.command_spell_count.number==3 and fixture.data.magic.number==8, "OS cancel restores no cost state")
		"verify-spell-confirm":
			check(fixture.data.command_spell_count.number==2 and fixture.data.magic.number==12 and GameData.player_data_library[1].command_spell_count.number==3, "OS confirm applied real declared gain and charged own spell once")
		"deny":
			fixture.data.command_spell_count.number = 0
			board.refresh_all_ui()
			stage = "deny"
		"verify-deny":
			check(not board._effect_modal.visible and board._source.read_pending().is_empty() and board._end_command_attempt.is_empty() and fixture.data.command_spell_count.number==0 and fixture.data.magic.number==12, "OS no authority candidate rejects without modal or state mutation")
		"verify-rival":
			check(board._opponent_drawer.visible and not board._effect_modal.visible and GameData.player_data_library[1].command_spell_count.number==3 and fixture.data.command_spell_count.number==0, "OS rival spell only browses information")
		"network":
			start_network()
		"verify-network-history":
			check(board.get_node("CardModificationHistory").visible and board.get_node("CardModificationHistory/Panel/Entries").text.contains(fixture.cards[1].get_modification_details()[0].detail), "OS network badge opens exact real operation history")
		"revoke-network":
			var snapshot: Dictionary = session.read_match()
			snapshot.seq += 1
			erase_history(snapshot)
			session.transport.message_received.emit(1,{"kind":"match_view","state":snapshot,"pending":{},"actions":{}})
			stage = "network-revoked"
		"verify-network-revoked":
			check(not board.get_node("CardModificationHistory").visible and board.get_node("CardModificationHistory/Panel/Entries").text.is_empty(), "normal network process immediately clears revoked open modal")
		"network-played":
			fixture.data.hand_cards.erase(fixture.cards[1])
			fixture.data.played_cards.append(fixture.cards[1])
			var snapshot: Dictionary = builder.build(0)
			snapshot.seq = session.read_match().seq + 1
			session.transport.message_received.emit(1,{"kind":"match_view","state":snapshot,"pending":{},"actions":{}})
			stage = "network-played"
		"verify-played-history":
			check(board.get_node("CardModificationHistory").visible, "OS first played card external badge opens history")
		"finish":
			check(downs>=8 and ups>=8, "real OS left down and up observed")
			print("RESULT ",JSON.stringify({"suite":"ui_final_os_window","checks":checks,"failures":failures,"os_down":downs,"os_up":ups}))
			board.queue_free()
			if session != null: session.close()
			get_tree().quit(0 if failures.is_empty() else 1)
	write_state()

func erase_history(value) -> void:
	if value is Dictionary:
		value.erase("modification_history")
		for v in value.values(): erase_history(v)
	elif value is Array:
		for v in value: erase_history(v)

func start_network() -> void:
	board.queue_free()
	await get_tree().process_frame
	session = preload("res://scripts/net/session/lobby_session.gd").new()
	session.transport.message_received.emit(1,{"kind":"match_bind","observer":0})
	builder = preload("res://scripts/match/view_builder.gd").new()
	var snapshot: Dictionary = builder.build(0)
	snapshot.seq = 501
	session.transport.message_received.emit(1,{"kind":"match_view","state":snapshot,"pending":{},"actions":{}})
	board = preload("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	board.network_session = session
	add_child(board)
	stage = "network-history"
