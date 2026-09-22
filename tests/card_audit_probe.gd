extends Node
# Independent audit, not a regression suite. Never run beside the live editor/game.
# Run in a disposable project copy: LoadGame autoload writes caches before _ready.
# Only this probe's result is written here; no business/data files are edited.
# -- --audit-output=<absolute path> optionally changes the result destination.
# Exit 0: audit completed (including reproduced bugs); exit 2: harness/precondition error.
# Parent runner must ALSO inspect stdout/stderr for SCRIPT ERROR / Parse Error.
const CASES = ["A05", "A06_cost", "A06_origin", "A01", "A04", "A12", "A13"]
var rows:Array = []
var output_path:String = "res://card_audit_probe_result.json"
var current:int = -1
var keepalive:Array = []

func _ready():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-output="):
			output_path = arg.trim_prefix("--audit-output=")
	for id in CASES:
		rows.append({"id":id, "status":"error", "expected":{}, "actual":{}, "note":"not executed", "complete":false})
	_save(false)
	call_deferred("_next")

func _next():
	current += 1
	if current >= CASES.size():
		var errors:int = 0
		for row in rows:
			if row.status == "error": errors += 1
		_save(true)
		print("AUDIT_RESULT ", JSON.stringify({"cases":rows.size(), "errors":errors, "path":output_path}))
		get_tree().quit(2 if errors > 0 else 0)
		return
	rows[current].note = "entered; an incomplete row means runtime abort or timeout"
	_save(false)
	# Schedule continuation BEFORE invoking business code: GDScript has no try/catch.
	# Runtime aborts leave an error row, but do not silently omit subsequent cases.
	get_tree().create_timer(0.1).timeout.connect(_next, CONNECT_ONE_SHOT)
	_setup()
	match CASES[current]:
		"A05": _reward()
		"A06_cost": _movement(false)
		"A06_origin": _movement(true)
		"A01": _rank()
		"A04": _marble()
		"A12": _book()
		"A13": _excalibur()

func _save(finished:bool):
	var counts:Dictionary = {"reproduced":0, "not_reproduced":0, "error":0}
	for row in rows: counts[row.status] += 1
	var file = FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		push_error("AUDIT_OUTPUT_ERROR " + output_path)
		get_tree().quit(2)
		return
	file.store_string(JSON.stringify({"schema_version":1, "finished":finished, "kind":"read_only_business_audit", "counts":counts, "cases":rows, "not_covered":["A02", "A03", "A07", "A08", "A09", "A10", "A11", "A14"], "scope_note":"A06 tests charge/origin/automatic destination; does not simulate arbitrary-target UI. A12 tests master replacement only. Inspect engine error log separately."}, "\t"))
	file.close()

func _result(bug:bool, expected:Dictionary, actual:Dictionary, note:String = ""):
	rows[current] = {"id":CASES[current], "status":"reproduced" if bug else "not_reproduced", "expected":expected, "actual":actual, "note":note, "complete":true}
	print("OBSERVED_BUG " if bug else "AUDIT_NOT_REPRODUCED ", JSON.stringify(rows[current]))
	_save(false)

func _error(note:String, actual:Dictionary = {}):
	rows[current] = {"id":CASES[current], "status":"error", "expected":{}, "actual":actual, "note":note, "complete":true}
	print("AUDIT_ERROR ", JSON.stringify(rows[current]))
	_save(false)

func _setup():
	EffectManager.reset_runtime()
	GameLog.reset()
	GameLog.set_context(1, "action")
	GameData.player_data_library.clear()
	GameData.player_id = 0
	for id in range(4):
		var d = GameData.new_player_data()
		d.is_out = false
		d.order.number = id
		d.magic.number = 12
		GameData.player_data_library[id] = d
	GameProgress.is_game_over = false
	GameProgress.current_round = 1
	GameProgress.current_phase_index = 2
	GameProgress.current_player_id = 0
	MapData.active_situation = null
	for area in MapData.areas:
		area._events.clear()
		area._buffs.clear()
		for loc in area._locations: loc._players.clear()
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.ACTION_PHASE, TimePoints.NON_CLIMAX])
	TimePointChecker.dynamic_time_point([TimePoints.ACTION_PHASE, TimePoints.NON_CLIMAX], 0)

func _named(pool:Array, key:String):
	for object in pool:
		if object != null and object._name == key: return object
	return null

func _clone(object):
	if object == null: return null
	var copy = CloneObject.new().exec(object)
	keepalive.append(copy)
	return copy

func _place(area, id:int, slot:int = 0) -> bool:
	if area == null or area._locations.size() <= slot: return false
	return SetLocation.new().exec(area._locations[slot], id, false, true)

func _command():
	var template = _named(LoadCommandSpell.command_spells.values(), "normal_command_spell")
	var card = _clone(template)
	if card == null or card._effects.is_empty(): return null
	var eff = card._effects[0]
	EffectManager.register_effect(eff, 0)
	return eff

func _choose(eff, index:int) -> bool:
	if eff == null: return false
	if not EffectManager.request_manual_activation(eff, 0): return false
	return EffectManager.submit_option_choice(eff, [index])

func _reward():
	var d = GameDataManager.get_player_data(0)
	if not _place(MapData.miyama, 0) or not _place(MapData.miyama, 1, 1):
		_error("battle placement unavailable"); return
	d.power.number = 20
	var eff = _command()
	if not _choose(eff, 1): _error("command option request/submit failed"); return
	var before = d.score.number
	var bonus = d.total_power_bonus.number
	var result = BattleResolver.new().exec([0, 1])
	var detail:Dictionary = result.details_by_area.get(MapData.miyama._area_name, {})
	if detail.is_empty() or not detail.winners.has(0): _error("fixture did not win real battle"); return
	var ordinary = detail.score_gained.get(0, 0)
	var delta = d.score.number - before
	_result(delta != ordinary + 2, {"later_win_bonus":2}, {"score_before_battle":before, "battle_gain":delta, "ordinary_award":ordinary, "extra_award":delta - ordinary, "power_bonus":bonus, "command_remaining":d.command_spell_count.number, "wins":GetRoundBattleWins.new().exec(0)}, "Real manual option then BattleResolver; no fabricated battle log.")

func _movement(invalid_origin:bool):
	var area = MapData.magic_workshop if invalid_origin else MapData.miyama
	if not _place(area, 0): _error("movement origin unavailable"); return
	var d = GameDataManager.get_player_data(0)
	var origin = d.location
	var eff = _command()
	var magic_before = d.magic.number
	var spells_before = d.command_spell_count.number
	var accepted = _choose(eff, 2)
	var pending:Dictionary = EffectManager.get_pending_location_selection()
	var target:BaseLocation = null
	if not invalid_origin:
		for map_area in MapData.areas:
			if map_area == area: continue
			for loc in map_area._locations:
				if loc._players.is_empty():
					target = loc
					break
			if target != null: break
	var submitted:bool = target != null and EffectManager.submit_location_selection(eff, target)
	var moved:bool = d.location != origin
	var actual:Dictionary = {"accepted":accepted, "awaiting_location":not pending.is_empty(), "submitted":submitted, "moved":moved, "origin":str(area._area_name), "destination":str(d.location.get_from()._area_name), "magic_spent":magic_before - d.magic.number, "spells_spent":spells_before - d.command_spell_count.number, "pending_choice":EffectManager.get_pending_active_effect() != null}
	if invalid_origin:
		_result(moved or d.command_spell_count.number != spells_before or d.magic.number != magic_before, {"origin_workshop_allowed":false, "moved":false, "spells_spent":0}, actual)
	else:
		_result(!accepted or pending.is_empty() or !submitted or !moved or d.magic.number != magic_before, {"location_choice":true, "moves_to_selected_other_area":true, "magic_spent":0}, actual, "Uses the engine location-selection protocol rather than assuming an automatic destination.")

func _rank():
	var event = _clone(_named(LoadEvent.events, "desperate_measure"))
	if event == null: _error("desperate_measure not loaded"); return
	var scores:Array = [0, 10, 20, 30]
	var powers:Array = [40, 30, 20, 10]
	for id in range(4):
		var d = GameDataManager.get_player_data(id)
		d.score.number = scores[id]
		d.power.number = powers[id]
	# Only player 0 occupies the event: prevents earlier loop mutations altering ranks.
	if not _place(MapData.miyama, 0): _error("rank fixture placement failed"); return
	var before = GetPlayerTotalPower.new().exec(0)
	event.from = MapData.miyama
	MapData.miyama._events.append(event)
	var after = GetPlayerTotalPower.new().exec(0)
	_result(after - before != 12, {"score_bottom_rank":1, "power_gain":12}, {"initial_scores":scores, "initial_powers":powers, "power_before":before, "power_after":after, "power_gain":after - before}, "Real event clone and current total-power query; score rank and power rank deliberately opposite.")

func _marble():
	var card = LoadAttack.resolve("special:luck")
	keepalive.append(card)
	var event = _clone(_named(LoadEvent.events, "reality_marble"))
	if card == null or event == null: _error("required card/event not loaded"); return
	var d = GameDataManager.get_player_data(0)
	d.hand_cards = [card, BaseAttack.new("audit_filler", "", [], BaseNumber.new(0), BaseNumber.new(1))]
	if not _place(MapData.shinto, 0): _error("cross-area placement failed"); return
	var baseline:bool = RegularPlay.can_add(0, card, false)
	event.from = MapData.miyama
	MapData.miyama._events.append(event)
	var other_area:bool = RegularPlay.can_add(0, card, false)
	if not _place(MapData.miyama, 0): _error("local-area placement failed"); return
	var same_area:bool = RegularPlay.can_add(0, card, false)
	if not baseline: _error("special card not playable in control fixture"); return
	_result(not other_area, {"outside_event_area_playable":true, "inside_event_area_playable":false}, {"baseline":baseline, "outside_event_area_playable":other_area, "inside_event_area_playable":same_area, "card":card._name}, "Uses real loaded special attack and RegularPlay.can_add, not just BoardHasEffect.")

func _book():
	var control = _book_sequence(false)
	if control.is_empty(): return
	if control.second_master != "matou_sakura":
		_error("fresh eligible positive control did not replace master", control); return
	_setup()
	var sequence = _book_sequence(true)
	if sequence.is_empty(): return
	_result(sequence.second_master == "matou_shinji" and sequence.effect_logs_after_failed_check > 0, {"first_master":"matou_shinji", "second_master":"matou_sakura", "failed_check_consumes_once":false}, {"positive_control":control, "failed_then_eligible":sequence}, "Real DAY_END dispatches; history retained across the failed/eligible checks. Fresh eligible positive control must succeed first.")

func _book_sequence(failed_first:bool) -> Dictionary:
	var master = _clone(_named(GameData.loaded_masters, "matou_shinji"))
	if master == null or _named(GameData.loaded_masters, "matou_sakura") == null:
		_error("replacement master templates missing"); return {}
	var buff = _named(master._specials.get("BUFFS", []), "false_servant_book")
	if buff == null: _error("false_servant_book buff missing"); return {}
	var eff = _named(buff._effects, "false_servant_book_master_replace")
	if eff == null: _error("master replacement effect missing"); return {}
	var d = GameDataManager.get_player_data(0)
	d.master = master
	d.buffs = [buff]
	d.command_spell_count.number = 3
	# Register only this audited effect, preventing unrelated master abilities from masking it.
	EffectManager.register_effect(eff, 0)
	if failed_first:
		TimePointChecker.global_time_point([TimePoints.DAY_END])
	var first_master:String = str(d.master._name)
	var failed_logs:int = GameLog.query({"type":"effect", "actor":0, "data":{"effect_name":eff._name}}, null).size()
	GameProgress.current_round = 2
	GameLog.set_context(2, "battle")
	d.command_spell_count.number = 0
	TimePointChecker.global_time_point([TimePoints.DAY_END])
	var second_master:String = str(d.master._name)
	return {"first_master":first_master, "effect_logs_after_failed_check":failed_logs, "second_master":second_master, "command_remaining":d.command_spell_count.number}

func _excalibur():
	var servant = _named(GameData.loaded_servants, "artoria_pendragon")
	if servant == null: _error("artoria template missing"); return
	var card = _clone(_named(servant._specials.get("SKILLS", []), "excalibur"))
	if card == null: _error("excalibur missing"); return
	var d = GameDataManager.get_player_data(0)
	d.servant = _clone(servant)
	d.servant_skills = [card]
	d.hand_cards = [BaseAttack.new("audit_filler", "", [], BaseNumber.new(0), BaseNumber.new(1))]
	RegisterObjectEffects.new().exec(card, 0)
	var entered:bool = RegularPlay.add(0, card, false)
	if not entered: _error("excalibur did not enter via RegularPlay", {"keywords":card._keywords}); return
	var released:bool = ReleaseTrueName.is_released(0)
	_result(not released, {"faceup_regular_play_releases_true_name":true}, {"entered":entered, "keywords":card._keywords, "released":released, "release_log_count":GameLog.query({"type":"true_name_release", "actor":0}, null).size()})
