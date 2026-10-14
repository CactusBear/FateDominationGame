extends Node

# 显式来源透传与旧三参ABI；不重签来源，不修改原数值写入语义。
const Router = preload("res://scripts/system/operation_router.gd")
var checks:int = 0
var failures:Array = []
var context:SessionContext
var player_id:int

func _ready() -> void:
	call_deferred("run")

func check(ok:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", ok)
	if not ok:
		failures.append(label)

func fresh() -> void:
	var lifecycle:Dictionary = GameData.reset_game_session([])
	check(lifecycle.get("ok", false), "trusted lifecycle starts")
	context = lifecycle.get("context")
	player_id = AddPlayer.new().exec(-1, [], {"player_name":"EditPower context"}, context)
	check(player_id >= 0, "trusted lifecycle creates member")
	GameLog.reset()

func power() -> BaseNumber:
	return GameDataManager.find_player_data(player_id).power

func facts() -> Array:
	return GameLog.query({"type":"power_source", "actor":player_id}, null)

# 原三参实现也执行同一业务oracle；基线不以参数错误冒充RED。
func direct(set_num:BaseNumber, vary_num:BaseNumber, id:int, source:Variant):
	var operation = EditPower.new()
	var args:Array = [set_num, vary_num, id]
	for method in operation.get_method_list():
		if method.name == "exec" and method.args.size() > args.size():
			args.append(source)
			break
	return operation.callv("exec", args)

func frame(name:String, args:Array) -> Array:
	var owner = BaseBuff.new("trusted frame owner", "")
	var effects:Array = LoadHelper.load_effects([{
		"effect_name":"context ABI", "time_points":[], "priority":0,
		"is_pure_passive":true, "is_residue":false, "need_activate":false,
		"effect_numbers":[], "funcs":[{"func_name":name, "parameters":args}]
	}], owner, context)
	check(effects.size() == 1, name + " trusted effect factory")
	if effects.size() != 1:
		return [false, null]
	var effect:BaseEffect = effects[0]
	check(effect._funcs.size() == 1, name + " trusted function factory")
	if effect._funcs.size() != 1:
		return [false, null]
	return EffectManager.run_base_func(effect._funcs[0], effect, context)

func explicit_cases() -> void:
	fresh()
	var original:BaseNumber = power()
	original.set_num(BaseNumber.new(8))
	var assigned = BaseNumber.new(3)
	var varied = BaseNumber.new(2)
	var result = direct(assigned, varied, player_id, context)
	check(result == null, "EditPower original void return")
	check(power().number == 5, "explicit set then add original order")
	check(is_same(power(), original), "explicit write retains player number identity")
	check(assigned.number == 3 and varied.number == 2, "effect numeric arguments remain unchanged")
	check(facts().size() == 1 and facts()[0].data.delta == -3, "explicit original context records exact net delta once")
	direct(null, BaseNumber.new(2), player_id, context)
	check(power().number == 7 and facts().size() == 2 and facts()[1].data.delta == 2, "independent explicit addition keeps second fact")
	direct(null, BaseNumber.new(0), player_id, context)
	check(facts().size() == 2, "zero delta retains record no-op")
	var keys:Array = GameData.player_data_library.keys()
	direct(null, BaseNumber.new(9), 9525111, context)
	check(GameData.player_data_library.keys() == keys and GameLog.query({"type":"power_source", "actor":9525111}, null).is_empty(), "unknown member original refusal creates no member or fact")

	GameLog.reset()
	Router.exec_registered("edit_power", [null, BaseNumber.new(-2), player_id, context], context)
	check(power().number == 5 and facts().size() == 1 and facts()[0].data.delta == -2, "router business array explicitly forwards original context")
	GameLog.reset()
	Router.exec_registered("edit_power", [null, BaseNumber.new(1), player_id], context)
	check(facts().is_empty(), "router qualification alone never injects business context")
	EditPower.new().exec(null, BaseNumber.new(1), player_id)
	check(facts().is_empty(), "legacy no-frame three-arg call never mints record source")
	var old:SessionContext = context
	fresh()
	direct(null, BaseNumber.new(1), player_id, old)
	check(facts().is_empty(), "stale explicit context cannot record for reused player ID")
	direct(null, BaseNumber.new(1), player_id, {})
	check(facts().is_empty(), "foreign context cannot record source")

func frame_cases() -> void:
	fresh()
	var result:Array = frame("edit_power", [null, BaseNumber.new(6), player_id])
	check(result[0] and result[1] == null, "old three-arg descriptor retains execution and void return")
	check(power().number == 6 and facts().size() == 1 and facts()[0].data.delta == 6, "old three-arg EditPower inherits verified function frame")
	GameLog.reset()
	var attack = BaseAttack.new("trusted strength", "", ["strength"], BaseNumber.new(0), BaseNumber.new(4))
	check(SessionGeneration.bind_origin(attack, context.token(), &"editpower-context.new_card").get("ok", false), "trusted creation binds attack original origin")
	GameDataManager.find_player_data(player_id).played_cards.append(attack)
	result = frame("modify_attack_power_by_attribute", [["strength"], BaseNumber.new(3), player_id])
	check(result[0] and power().number == 9, "ModifyAttackPowerByAttribute original numeric behavior")
	check(facts().size() == 1 and facts()[0].data.delta == 3, "ModifyAttackPowerByAttribute three-arg inner router inherits frame")
	result = frame("zero_attribute_power", [player_id, ["strength"]])
	check(result[0] and result[1] == 4 and power().number == 5, "ZeroAttributePower original removed total and return")
	check(facts().size() == 2 and facts()[1].data.delta == -4, "ZeroAttributePower three-arg inner router inherits frame")
	check(attack._power.number == 4, "attribute aggregate operations preserve printed card power")

func run() -> void:
	print("ENV ", JSON.stringify({"pid":OS.get_process_id(), "user":OS.get_user_data_dir(), "res":ProjectSettings.globalize_path("res://")}))
	explicit_cases()
	frame_cases()
	print("RESULT ", JSON.stringify({"suite":"editpower-context", "checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
