extends Node
func _ready() -> void:
	GameData.default_master = "tohsaka_rin"
	GameData.default_servant = "artoria_pendragon"
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		get_tree().quit(1)
		return
	get_tree().call_deferred("change_scene_to_file", "res://tests/" + args[0] + ".tscn")
