extends Node

var checks:int = 0
var failures:Array = []

func check(value:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", value)
	if not value:
		failures.append(label)

func _ready() -> void:
	var setup:Dictionary = GameData.reset_game_session([0, 1])
	check(setup.ok, "PRE real session")
	GameLog.reset()
	var magic:BaseNumber = GameData.player_data_library[0].magic
	check(not PayMagic.can_pay(BaseNumber.new(1), 0), "no_frame_quote_rejected")
	check(not PayMagic.new().exec(BaseNumber.new(1), 0, "a1_35"), "no_frame_payment_rejected")
	check(magic.number == 4, "no_frame_no_debit")
	check(GameLog.query({}).is_empty(), "no_frame_no_payment_log")
	GameData.release_game_objects()
	print("RESULT ", JSON.stringify({"suite":"a1_35_paymagic_origin","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
