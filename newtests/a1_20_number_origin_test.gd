extends Node
var checks:int = 0
var failures:Array = []
func check(value:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", value)
	if not value: failures.append(label)
func _ready() -> void:
	print("ENV user_dir=", OS.get_user_data_dir(), " pid=", OS.get_process_id())
	var started:Dictionary = GameData.reset_game_session([0,1])
	check(started.ok, "PRE real session starts")
	GameLog.reset()
	var resource:BaseNumber = GameData.player_data_library[1].command_spell_count
	var before = resource.number
	var result = EditDataNumber.new().exec("command_spell_count", null, BaseNumber.new(-1), 1)
	check(result == null, "no-frame keeps null return")
	check(resource.number == before, "no-frame refuses known same-ID target before resource write")
	check(GameData.player_data_library.keys() == [0,1], "no-frame never creates member")
	print("RESULT ", JSON.stringify({"suite":"a1_20_number_origin","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
