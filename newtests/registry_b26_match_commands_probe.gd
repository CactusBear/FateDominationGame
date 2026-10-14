extends "res://tests/match_driver_headless_test.gd"

## B26 行为级前置探针：只经公开查询/投影观察 MatchCommands 的真实结果。
const MATCH_COMMANDS_PATH := "res://scripts/match/match_commands.gd"
const VIEW_BUILDER_PATH := "res://scripts/match/view_builder.gd"
const MATCH_DRIVER_PATH := "res://scripts/match/match_driver.gd"

const SEAT := 0
var commands
var view_builder

func check(ok: bool, label: String) -> void:
	super.check(ok, label)

func check_bool(ok: bool, label: String) -> bool:
	check(ok, label)
	return ok

func player_view(snapshot: Dictionary) -> Dictionary:
	for player in snapshot.get("players", []):
		if int(player.get("id", -1)) == SEAT:
			return player
	return {}

func log_count(kind: String) -> int:
	return GameLog.query({"type": kind, "actor": SEAT}, null).size()

func start_formal_match() -> bool:
	driver = load(MATCH_DRIVER_PATH).new()
	commands = load(MATCH_COMMANDS_PATH).new()
	view_builder = load(VIEW_BUILDER_PATH).new()
	driver.step_interval = 0.0
	if not check_bool(GameStart.game_start([0, 1, 2, 3, 4, 5, 6]), "B26 formal GameStart"):
		return false
	driver.seats.set_single_local(SEAT)
	for attempt in range(2000):
		driver.answer_pending_for_bots()
		if GameProgress.current_player_id == SEAT and GameProgress.is_phase_for(SEAT, "outpost"):
			return true
		driver.step(1.0)
	check(false, "B26 reached outpost within guard")
	return false

func reach_action() -> bool:
	driver.seats.set_single_local(-1)
	for attempt in range(2000):
		driver.answer_pending_for_bots()
		if GameProgress.current_player_id == SEAT and GameProgress.is_phase_for(SEAT, "action"):
			driver.seats.set_single_local(SEAT)
			return true
		driver.step(1.0)
	check(false, "B26 reached action within guard")
	return false

func probe_flip() -> void:
	var data: Dictionary = GameDataManager.find_player_data(SEAT)
	var card: BaseAttack
	for candidate in RegularPlay.candidates(SEAT):
		if candidate is BaseAttack and RegularPlay.in_play_zone(data, candidate):
			var projection: Dictionary = view_builder.card_view(candidate, true)
			if not bool(projection.get("concealed", true)):
				card = candidate
				break
	if not check_bool(card != null, "B26 flip fixture has public face-up attack"):
		return
	var before: Dictionary = view_builder.card_view(card, true)
	commands.set_card_concealed(card, true, SEAT)
	var after: Dictionary = view_builder.card_view(card, true)
	check(not bool(before.get("concealed", true)) and bool(after.get("concealed", false)) and after != before, "B26 flip changes public card projection")
	commands.set_card_concealed(card, true, SEAT)
	var control: Dictionary = view_builder.card_view(card, true)
	check(control == after and bool(control.get("concealed", false)), "B26 flip same-state control is a distinct no-op")

func probe_deploy(target: BaseLocation) -> bool:
	var before: Dictionary = player_view(view_builder.build(SEAT))
	var before_logs := log_count("deploy")
	var accepted: bool = commands.deploy(target, SEAT)
	var after: Dictionary = player_view(view_builder.build(SEAT))
	var expected_id: int = view_builder.ids.id_for(target)
	check(accepted and int(after.get("location", 0)) == expected_id and log_count("deploy") == before_logs + 1, "B26 deploy facade reaches target station and records success")
	var repeat: bool = commands.deploy(target, SEAT)
	var control: Dictionary = player_view(view_builder.build(SEAT))
	check(not repeat and control.get("location", 0) == after.get("location", 0) and log_count("deploy") == before_logs + 1, "B26 deploy same-station control rejects without benefit")
	return accepted

func probe_move() -> void:
	if not check_bool(reach_action(), "B26 move action phase"):
		return
	var data: Dictionary = GameDataManager.find_player_data(SEAT)
	var origin: BaseLocation = data.get("location")
	var origin_area: BaseMapArea = origin.get_from() as BaseMapArea if origin != null else null
	var origin_index := MapData.areas.find(origin_area)
	var target: BaseLocation
	var steps := 0
	for candidate in MapData.areas:
		var candidate_index := MapData.areas.find(candidate)
		if candidate == origin_area or candidate_index == origin_index or not AreaActionRules.block_reason(SEAT, candidate_index).is_empty():
			continue
		var candidate_target: BaseLocation = GetMoveTargetLocation.new().exec(candidate)
		if candidate_target != null and candidate_index - origin_index != 0:
			target = candidate_target
			steps = candidate_index - origin_index
			break
	if not check_bool(target != null, "B26 move fixture has legal target station"):
		return
	var before: Dictionary = player_view(view_builder.build(SEAT))
	var before_location = before.get("location", 0)
	var before_magic = before.get("magic", 0)
	var before_logs := log_count("move")
	commands.move(999, SEAT)
	var rejected: Dictionary = player_view(view_builder.build(SEAT))
	check(rejected.get("location", 0) == before_location and rejected.get("magic", 0) == before_magic and log_count("move") == before_logs, "B26 move real no-target control stays put without payment")
	commands.move(steps, SEAT)
	var moved: Dictionary = player_view(view_builder.build(SEAT))
	var expected_id: int = view_builder.ids.id_for(target)
	var last_move: Dictionary = GameLog.last({"type": "move", "actor": SEAT}, null)
	var normal_move_fact := not last_move.is_empty() and bool(last_move.get("data", {}).get("is_move", false))
	check(int(moved.get("location", 0)) == expected_id and log_count("move") == before_logs + 1 and normal_move_fact, "B26 move facade truly enters target station via normal-move fact")
	print("B26_MOVE_PATH target_station_id=", expected_id, " steps=", steps, " location_projection=", moved.get("location"), " is_move_fact=", normal_move_fact)

func run() -> void:
	if not start_formal_match():
		GameStart.end_session()
		print("RESULT checks=", checks, " failures=", failures)
		get_tree().quit(1)
		return
	var target: BaseLocation = DeployRules.pick_location(MapData.magic_workshop)
	if check_bool(target != null, "B26 deploy fixture has target station"):
		if probe_deploy(target):
			probe_move()
			# 翻面需要正式行动阶段，并且只从公开候选查询取牌对象。
			probe_flip()
	GameStart.end_session()
	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
