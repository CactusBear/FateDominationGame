extends "res://tests/fd39_operations_test.gd"

func descriptor() -> Dictionary:
	var data:Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/masters/00006_kotomine_kirei/00006_kotomine_kirei.json"))
	for buff in data.specials.BUFFS:
		for effect in buff.effects:
			if effect.effect_name == "overseer_neutral_move":
				return effect
	return {}

func probe(payment_first:bool) -> Dictionary:
	setup()
	SetLocation.new().exec(MapData.magic_workshop0, 0, false)
	pd(0).magic.set_num(BaseNumber.new(4))
	var original:bool = MapData.scout._can_move_to
	MapData.scout._can_move_to = false
	var origin:BaseLocation = pd(0).location
	var desc:Dictionary = descriptor()
	var effect := BaseEffect.new("overseer_neutral_move", [], 0, false, false)
	effect._trigger_player_id = 0
	effect._using_numbers = [BaseNumber.new(desc.effect_numbers[0].number)]
	var descriptors:Array = desc.options[0].funcs.duplicate(true)
	if payment_first:
		# 候选只在内存重排，正式 JSON 字节不变；保留费用 max 与原负数计算。
		var placement:Dictionary = descriptors[7]
		var maximum:Dictionary = descriptors[8]
		var negative:Dictionary = descriptors[9]
		var payment:Dictionary = {"func_name": "pay_magic", "parameters": [{"self_var": 9}, -1, "move", {"self_var": 2}], "var_index": 8, "condition": {"self_var": 5}}
		placement.condition = {"self_var": 8}
		descriptors[7] = maximum
		descriptors[8] = negative
		descriptors[9] = payment
		descriptors[10] = placement
	var funcs:Array = LoadHelper.load_funcs(descriptors, effect)
	EffectManager.activating_eff = effect
	GameLog.reset()
	for f in funcs:
		EffectManager.run_base_func(f, effect)
	EffectManager.activating_eff = null
	var result:Dictionary = {"magic": pd(0).magic.number, "same_location": pd(0).location == origin, "position_facts": GameLog.query({"type": "move"}).size(), "payment_facts": GameLog.query({"type": "magic_decrease"}).size()}
	MapData.scout._can_move_to = original
	return result

func run() -> void:
	var existing:Dictionary = probe(false)
	var candidate:Dictionary = probe(true)
	check(existing.magic == 4 and existing.same_location and existing.position_facts == 0 and existing.payment_facts == 0, "formal Kirei rejected target currently preserves all movement state")
	check(candidate.same_location and candidate.position_facts == 0, "payment-first candidate still refuses forbidden target")
	check(candidate.magic == 4, "REQUIRED Kirei rejected placement must preserve magic")
	check(candidate.payment_facts == 0, "REQUIRED Kirei rejected placement must retain no payment fact")
	print("KIREI_PREFLIGHT_CAUSE ", JSON.stringify({"existing": existing, "candidate": candidate}))
	print("RESULT checks=%d failures=%s" % [checks, str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
