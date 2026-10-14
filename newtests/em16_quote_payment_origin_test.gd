extends Node
const Generation = preload("res://scripts/system/session_generation.gd")
var checks:int = 0
var failures:Array = []
func check(value:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", value)
	if not value: failures.append(label)
func start(ids:Array = [0,1]) -> SessionContext:
	var result:Dictionary = GameData.reset_game_session(ids)
	check(result.ok, "PRE session")
	GameLog.reset()
	for id in ids: GameData.player_data_library[id].location = MapData.magic_workshop0
	return result.context
func effect(context:SessionContext, cost = null, id:int = 0, options:Array = [], funcs:Array = [], points:Array = [], passive:bool = false) -> BaseEffect:
	var desc:Dictionary = {"effect_name":"em16-probe", "priority":0, "time_points":points, "is_pure_passive":passive, "is_residue":false, "effect_numbers":[], "funcs":funcs}
	if cost != null: desc["cost"] = {"number":cost.number,"can_change":true,"is_pure_number":false} if cost is BaseNumber else cost
	if not options.is_empty(): desc["options"] = options
	var loaded:Array = LoadHelper.load_effects([desc], null, context)
	check(loaded.size() == 1, "PRE runtime factory")
	var result:BaseEffect = loaded[0]
	check(EffectManager.register_effect(result, id), "PRE registration")
	return result
func reset_chain(kind:String) -> void:
	if kind == "progress": GameProgress.reset_progress()
	elif kind == "runtime": EffectManager.reset_runtime()
	elif kind == "release": GameData.release_game_objects()
	elif kind == "end_start":
		GameStart.end_session()
		GameData.reset_game_session([0,1])
	else: GameData.reset_game_session([0,1])
func quotes() -> void:
	for kind in ["progress", "game", "runtime", "release", "end_start"]:
		for cost in [null, BaseNumber.new(0), BaseNumber.new(1), {"type":"command_spell","amount":0}, {"type":"command_spell","amount":1}, {"type":"undeclared","amount":1}]:
			var context:SessionContext = start()
			var old:BaseEffect = effect(context, cost)
			GameData.player_data_library[0].is_magic_immune = true
			check(EffectManager.can_pay_effect_cost(old), "PRE lawful quote " + kind)
			reset_chain(kind)
			check(not EffectManager.can_pay_effect_cost(old), "stale quote before early return " + kind + "/" + str(cost))
		check(not EffectManager.can_pay_effect_cost(null), "null quote not authority " + kind)
	var context:SessionContext = start([-7,1])
	GameData.player_id = 1
	var negative:BaseEffect = effect(context, BaseNumber.new(1), -7)
	GameData.player_data_library[-7].magic.set_num(BaseNumber.new(0))
	check(not EffectManager.can_pay_effect_cost(negative), "literal negative quote does not borrow local")
	context = start()
	GameData.player_id = 0
	for cost in [BaseNumber.new(1), {"type":"command_spell","amount":1}]:
		var quote:BaseEffect = effect(context, cost, -1)
		var bindings:int = Generation._bindings.size()
		var facts:int = GameLog.query({}).size()
		var objects:int = GameData.objects.size()
		for i in range(3): check(EffectManager.can_pay_effect_cost(quote), "S01 local quote allowed")
		check(Generation._bindings.size() == bindings and GameLog.query({}).size() == facts and GameData.objects.size() == objects and not quote.has_meta(EffectManager.PAYMENT_SUBJECT_META), "quote pure no payment binding")
		quote._trigger_player_id = 990016
		check(not EffectManager.can_pay_effect_cost(quote), "unknown quote closed")
	context = start()
	var fresh:BaseEffect = effect(context, BaseNumber.new(1))
	GameData.player_data_library[0].is_magic_immune = true
	check(EffectManager.can_pay_effect_cost(fresh), "fresh magic immunity kept")
	fresh._cost = {"type":"command_spell","amount":999}
	check(not EffectManager.can_pay_effect_cost(fresh), "magic immunity not command exemption")
	check(not EffectManager.can_pay_effect_cost(BaseEffect.new("unbound", [])), "unbound free quote closed")
var callback_mode:String = ""
var callback_hits:int = 0
var callback_data:Dictionary = {}
var callback_magic:BaseNumber = null
var callback_marker:bool = false:
	set(value):
		callback_marker = value
		if value:
			callback_hits += 1
			if callback_mode == "progress": GameProgress.reset_progress()
			elif callback_mode == "game": GameData.reset_game_session([0,1])
			elif callback_mode == "magic": GameData.player_data_library[0].magic = BaseNumber.new(4)
			callback_data = GameData.player_data_library[0]
			callback_magic = callback_data.magic
func pay(root:BaseEffect, context:SessionContext):
	var methods:Array = EffectManager.get_method_list().filter(func(m): return m.name == "pay_effect_cost_result")
	if methods[0].args.size() == 1: return EffectManager.pay_effect_cost_result(root)
	return EffectManager.call("pay_effect_cost_result", root, context)
func active_wait(context:SessionContext, cost, options:Array = []) -> BaseEffect:
	var root:BaseEffect = effect(context, cost, 0, options)
	EffectManager.decision_queue.append(root)
	EffectManager.run_pipeline()
	check(EffectManager.get_pending_active_effect() == root, "PRE accepted active wait")
	return root
func payments() -> void:
	for kind in ["progress","game","runtime","release","end_start"]:
		var context:SessionContext = start()
		var root:BaseEffect = active_wait(context, {"type":"command_spell","amount":1})
		reset_chain(kind)
		var facts:int = GameLog.query({}).size()
		var graph:Dictionary = EffectManager.capture_transaction_state()
		check(pay(root, context).status == EffectManager.PAYMENT_REJECTED, "stale payment rejected " + kind)
		check(GameLog.query({}).size() == facts and EffectManager.capture_transaction_state().transaction_bindings == graph.transaction_bindings, "stale payment no facts or graph " + kind)
		check(not root.has_meta(EffectManager.PAYMENT_RECEIPT_META), "stale payment no receipt " + kind)
	for cost in [null,BaseNumber.new(0),BaseNumber.new(1),{"type":"command_spell","amount":1}]:
		var context:SessionContext = start()
		var root:BaseEffect = BaseEffect.new("unbound", [])
		root._cost = cost
		var facts:int = GameLog.query({}).size()
		check(EffectManager.pay_effect_cost_result(root).status == EffectManager.PAYMENT_REJECTED, "unbound payment rejected " + str(cost))
		check(GameLog.query({}).size() == facts and not root.has_meta(EffectManager.PAYMENT_SUBJECT_META), "unbound payment no registration " + str(cost))
	var context:SessionContext = start()
	var old:BaseEffect = active_wait(context, {"type":"command_spell","amount":1})
	GameProgress.reset_progress()
	check(pay(old, context).status == EffectManager.PAYMENT_REJECTED, "stale payment caller rejected")
	check(pay(null, context).status == EffectManager.PAYMENT_REJECTED, "null not payment completed")
	context = start()
	var fresh:BaseEffect = active_wait(context, {"type":"command_spell","amount":1})
	var fresh_data:Dictionary = GameData.player_data_library[0]
	var fresh_spells:float = fresh_data.command_spell_count.number
	check(EffectManager.submit_active_choice(fresh, true), "same-session real payment and activation")
	check(fresh_data.command_spell_count.number == fresh_spells - 1, "same-session payment once")
	check(GameLog.query({"type":"effect"}).size() == 1, "same-session one activation")
	context = start()
	var replaced:BaseEffect = active_wait(context, BaseNumber.new(1))
	var original:BaseNumber = GameData.player_data_library[0].magic
	GameData.player_data_library[0].magic = BaseNumber.new(original.number)
	var facts:int = GameLog.query({}).size()
	check(not EffectManager.submit_active_choice(replaced, true), "S06 equal magic replacement refuses")
	check(GameData.player_data_library[0].magic.number == original.number and GameLog.query({"type":"effect"}).is_empty() and GameLog.query({"type":"resource_payment"}).is_empty(), "S06 no payment or activation on replacement")
	for mode in ["progress", "game"]:
		context = start()
		callback_mode = mode
		var before:int = callback_hits
		effect(context, null, 1, [], [{"func_name":"set_property","parameters":[self,"callback_marker",true]}], [TimePoints.BEFORE_COMMAND_SPELL_SPEND], true)
		var root:BaseEffect = active_wait(context, {"type":"command_spell","amount":1})
		var spells:BaseNumber = GameData.player_data_library[0].command_spell_count
		var spell_before:float = spells.number
		check(not EffectManager.submit_active_choice(root, true), "BEFORE reset refuses tail " + mode)
		check(callback_hits == before + 1, "PRE real BEFORE listener " + mode)
		check(is_same(callback_data,GameData.player_data_library[0]) and callback_data.command_spell_count.number == spell_before, "old tail does not charge reused dictionary " + mode)
		check(root._option_use_counts.is_empty() and not root.has_meta(EffectManager.PAYMENT_RECEIPT_META), "old tail no usage or receipt " + mode)
func locations() -> void:
	for kind in ["full","foreign","target_slot"]:
		var context:SessionContext = start()
		var spec:Dictionary = {"target_slot":"unlimited"} if kind == "target_slot" else {}
		var root:BaseEffect = active_wait(context, {"type":"command_spell","amount":1}, [{"select_location":spec,"funcs":[]}])
		check(EffectManager.submit_option_choice(root, [0]), "PRE location choice")
		var target:BaseLocation = MapData.magic_workshop1
		if kind == "full": target._players.append(1)
		if kind == "foreign":
			target = BaseLocation.new()
			target.from = MapData.magic_workshop
		if kind == "target_slot": target = MapData.miyama._locations.filter(func(x): return x._pl_num_limit != -1)[0]
		var data:Dictionary = GameData.player_data_library[0]
		var before:float = data.command_spell_count.number
		var selected:BaseLocation = root._selected_location
		var facts:int = GameLog.query({}).size()
		check(not EffectManager.submit_location_selection(root,target), "ineligible location before payment " + kind)
		check(data.command_spell_count.number == before and root._option_use_counts.is_empty() and is_same(root._selected_location,selected), "ineligible location no partial commit " + kind)
		check(GameLog.query({}).size() == facts, "ineligible location no facts " + kind)
		if kind == "full": target._players.erase(1)
	var context:SessionContext = start()
	var legal:BaseEffect = active_wait(context, {"type":"command_spell","amount":1}, [{"select_location":{},"funcs":[]}])
	check(EffectManager.submit_option_choice(legal, [0]), "PRE legal location choice")
	var legal_spells:float = GameData.player_data_library[0].command_spell_count.number
	check(EffectManager.submit_location_selection(legal, MapData.miyama0), "legal location pays and activates")
	check(GameData.player_data_library[0].command_spell_count.number == legal_spells - 1, "legal location payment once")
	var context2:SessionContext = start()
	var root:BaseEffect = effect(context2)
	root._trigger_player_id = -1
	var keys:Array = GameData.player_data_library.keys()
	check(not EffectManager.location_option_origin_allowed(root,{}), "S03 location trigger sentinel closed before GetLocation")
	check(GameData.player_data_library.keys() == keys, "S03 location query pure")
func _ready() -> void:
	print("ENV ", JSON.stringify({"user":OS.get_user_data_dir(), "TMPDIR":OS.get_environment("TMPDIR"), "TEMP":OS.get_environment("TEMP"), "TMP":OS.get_environment("TMP"), "APPDATA":OS.get_environment("APPDATA"), "LOCALAPPDATA":OS.get_environment("LOCALAPPDATA")}))
	quotes()
	payments()
	locations()
	print("RESULT ", JSON.stringify({"suite":"em16_quote_payment_origin", "checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
