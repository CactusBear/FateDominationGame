extends Node

var Rules:Script = preload("res://scripts/system/area_action_rules.gd")
const RR = preload("res://scripts/match/rule_random.gd")
const SPEC = {"target_slot":"move_target"}
var checks:int = 0
var failures:Array = []

func check(value:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", value)
	if not value: failures.append(label)

func point(location:BaseLocation) -> bool:
	# 改前版本没有新 ABI，明确记为不支持，而不是触发编译错误或猜默认语义。
	return Rules.call("is_move_target_location", location) if Rules.has_method("is_move_target_location") else false

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	RR.start_seed(81747)
	check(GameStart.game_start([0, 1]), "PRE real GameStart")
	var source:SessionContext = GameStart.startup_context()
	check(source != null and SessionGeneration.validate_context(source).ok, "PRE original startup source")
	for area:BaseMapArea in MapData.areas:
		for location:BaseLocation in area._locations: location._players.clear()
	check(Rules.first_effect_location_target(MapData.miyama, SPEC, source) == MapData.miyama2, "explicit move_target skips empty benefit seat")
	check(point(MapData.magic_workshop0), "public predicate accepts empty finite workshop")
	print("RESULT ", JSON.stringify({"suite":"command-move-target-query", "checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
