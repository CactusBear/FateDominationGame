extends Node
# is_victory 唯一写入点：VictoryResolver 只判定、EndGame 与自然终局都经 GameProgress.end_game 写标记。

var checks:int = 0
var failures:Array = []

func check(ok:bool, label:String) -> void:
	checks += 1
	if !ok:
		failures.append(label)
	print("CHECK ", label, " ", ok)

func _ready() -> void:
	call_deferred("run")

func setup() -> void:
	var reset:Dictionary = GameData.reset_game_session([0, 1, 2])
	check(bool(reset.get("ok", false)), "fixture_session_ready")
	for id in [0, 1, 2]:
		var data:Dictionary = GameData.player_data_library[id]
		data.is_out = false
		data.is_victory = false
	GameProgress.is_game_over = false

func run() -> void:
	setup()
	GameData.player_data_library[0].score.number = 5
	GameData.player_data_library[1].score.number = 9
	GameData.player_data_library[2].score.number = 3
	var winners:Array = VictoryResolver.new().exec({})
	check(winners == [1], "resolver_picks_highest_score")
	check(GameData.player_data_library.values().all(func(d): return not d.is_victory), "resolver_writes_no_flags")
	GameProgress.end_game(winners)
	check(GameData.player_data_library[1].is_victory and not GameData.player_data_library[0].is_victory and not GameData.player_data_library[2].is_victory, "end_game_writes_flags")

	setup()
	GameData.player_data_library[2].victory_override = true
	check(VictoryResolver.new().exec({}) == [2], "override_winner_returned")
	check(not GameData.player_data_library[2].is_victory, "override_resolver_writes_no_flags")
	GameData.player_data_library[2].victory_override = false

	setup()
	check(EndGame.new().exec([0, 2]), "end_game_operation_ends")
	check(GameData.player_data_library[0].is_victory and GameData.player_data_library[2].is_victory and not GameData.player_data_library[1].is_victory, "end_game_operation_flags_via_end_game")
	check(GameLog.query({"type": "game_end"}, null).size() >= 1, "game_end_fact_recorded")

	# 空胜者（圣杯溢出）：所有标记清零。
	setup()
	GameData.player_data_library[0].is_victory = true
	GameProgress.end_game([])
	check(GameData.player_data_library.values().all(func(d): return not d.is_victory), "empty_winners_clear_all_flags")
	GameProgress.is_game_over = false
	print("RESULT checks=", checks, " failures=", JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
