extends Node

const RR = preload("res://scripts/match/rule_random.gd")
var checks:int = 0
var failures:Array = []
var location:BaseLocation
var reported:int = -1
var requested:bool = false:
	set(value):
		requested = value
		if value: reported = DeployRules.apply_benefit(location, 0)

func check(ok:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", ok)
	if not ok: failures.append(label)

func _ready() -> void: call_deferred("run")

func run() -> void:
	GameStart.end_session()
	GameData.loaded_masters = []
	GameData.loaded_servants = []
	RR.start_seed(81748)
	check(GameStart.game_start([0, 1]), "PRE real GameStart")
	var source:SessionContext = GameStart.startup_context()
	location = DeployRules.pick_location(MapData.magic_workshop)
	check(SetLocation.new().exec(location, 0, false, false, false, source), "PRE real neutral placement with original source")
	var data:Dictionary = GameDataManager.find_player_data(0)
	var magic:BaseNumber = data.magic
	var before:float = magic.number
	# 现有明示资源免疫字段；不改数字、收益、规则或收益 oracle。
	data.is_magic_immune = true
	var loaded:Array = LoadHelper.load_effects([{"effect_name":"deploy-origin-handoff-receipt", "time_points":[], "priority":0,
		"is_pure_passive":true, "is_residue":false, "need_activate":false, "effect_numbers":[],
		"funcs":[{"func_name":"set_property", "parameters":[self, "requested", true], "var_index":-1}]}], null, source)
	check(loaded.size() == 1, "PRE trusted descriptor creation")
	var effect:BaseEffect = loaded[0]
	check(EffectManager.register_effect(effect, 0), "PRE descriptor registration")
	var result:Array = EffectManager.run_base_func(effect._funcs[0], effect, effect.runtime_context())
	check(result[0] == true and requested, "actual validated frame consumes independent benefit primitive")
	check(is_same(data, GameDataManager.find_player_data(0)) and is_same(magic, data.magic) and magic.number == before, "declared magic immunity preserves original resource")
	check(reported == 0, "benefit reports zero when EditMagic does not grant anything")
	print("RECEIPT_OBSERVATION ", JSON.stringify({"reported":reported, "actual_delta":magic.number-before, "printed":location._magic.number}))
	GameStart.end_session(); RR.stop_tracking()
	print("RESULT ", JSON.stringify({"suite":"deploy-origin-handoff-receipt", "checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
