extends Node

var checks:int = 0
var failures:Array = []
var mutation_mode:String = ""
var callback_count:int = 0
var callback_saw_payment:bool = false
var callback_trigger:bool = false:
	set(value):
		callback_trigger = value
		if value:
			callback_count += 1
			callback_saw_payment = GameLog.query({"type":"magic_decrease"}).size() == 1 and GameData.player_data_library[0].magic.number == 3
var mutation_trigger:bool = false:
	set(value):
		mutation_trigger = value
		if not value: return
		if mutation_mode == "magic": GameData.player_data_library[0].magic = BaseNumber.new(9)
		elif mutation_mode == "member": GameData.player_data_library[0] = GameData.new_player_data()
		elif mutation_mode == "reset":
			var reset:Dictionary = GameProgress.reset_progress()
			check(reset.ok, "PRE real BEFORE reset_progress")
var frame_trigger:bool = false:
	set(value):
		frame_trigger = value
		if value: in_frame_checks()

func check(value:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", value)
	if not value: failures.append(label)

func new_session() -> SessionContext:
	var setup:Dictionary = GameData.reset_game_session([0, 1])
	check(setup.ok, "PRE real session")
	GameLog.reset()
	callback_count = 0
	callback_saw_payment = false
	return setup.context

# 捕获由测试动作创建处承担，不从消费者领取当前票。
func intent(context:Variant, id:int = 0) -> Dictionary:
	var member:Dictionary = GameData.player_data_library[id]
	return {"context":context, "id":id, "member":member, "magic":member.magic}

# 按原/新实现真实 arity 裁掉未支持的尾参，保同一业务 oracle，不冒参数错误红。
func invoke(method:String, args:Array) -> bool:
	var operation:PayMagic = PayMagic.new()
	for entry:Dictionary in operation.get_script().get_script_method_list():
		if entry.name == method:
			return bool(operation.callv(method, args.slice(0, entry.args.size())))
	check(false, "PRE public PayMagic method exists " + method)
	return false

func quote(saved:Dictionary, amount:BaseNumber, available:Variant = null, overdraft:bool = false) -> bool:
	return invoke("can_pay", [amount, saved.id, available, overdraft, saved.context, saved.member, saved.magic])

func pay(saved:Dictionary, amount:BaseNumber, dispatch:bool = false, overdraft:bool = false) -> bool:
	return invoke("exec", [amount, saved.id, "a1_35", self, dispatch, overdraft, saved.context, saved.member, saved.magic])

func snapshot() -> String:
	var members:Array = []
	for id in GameData.player_data_library:
		var d:Dictionary = GameData.player_data_library[id]
		members.append([id, d.magic.number, d.score.number, d.power.number, d.played_cards.size(), d.hand_cards.size(), d.current_time_points.duplicate(), d.dynamic_time_points.duplicate()])
	return JSON.stringify([members, GameLog.query({}), GameData.objects.size(), GameData.effects.size()])

func rejected(saved:Dictionary, label:String, amount:BaseNumber = null) -> void:
	if amount == null: amount = BaseNumber.new(1)
	var before:String = snapshot()
	var old_balance:float = saved.magic.number
	check(not quote(saved, amount, 999), label + "_quote_rejected")
	check(snapshot() == before, label + "_quote_no_fact_or_half_commit")
	check(not pay(saved, amount, true), label + "_payment_rejected")
	check(snapshot() == before, label + "_payment_no_fact_or_half_commit")
	check(saved.magic.number == old_balance, label + "_captured_magic_not_debited")

func effect(context:SessionContext, name:String, funcs:Array, points:Array = []) -> BaseEffect:
	var loaded:Array = LoadHelper.load_effects([{"effect_name":name,"time_points":points,"priority":0,"is_pure_passive":true,"is_residue":false,"effect_numbers":[],"funcs":funcs}], null, context)
	check(loaded.size() == 1, "PRE trusted factory " + name)
	if loaded.is_empty(): return null
	var result:BaseEffect = loaded[0]
	check(EffectManager.register_effect(result, 0), "PRE registered " + name)
	return result

func missing_and_malformed() -> void:
	var context:SessionContext = new_session()
	var saved:Dictionary = intent(context)
	check(not PayMagic.can_pay(BaseNumber.new(1), 0), "no_frame_quote_rejected")
	check(not PayMagic.new().exec(BaseNumber.new(1), 0, "a1_35"), "no_frame_payment_rejected")
	check(saved.magic.number == 4, "no_frame_no_debit")
	check(GameLog.query({}).is_empty(), "no_frame_no_log_or_timepoint")
	for bad in [null, 17, {}, SessionToken.new(), SessionContext.new(context.token(), context.origin())]:
		var malformed:Dictionary = saved.duplicate()
		malformed.context = bad
		rejected(malformed, "invalid_source_" + str(typeof(bad)))
	var missing:Dictionary = saved.duplicate()
	missing.member = null
	check(not quote(missing, BaseNumber.new(1)) and not pay(missing, BaseNumber.new(1)), "token_only_missing_member_rejected")
	missing = saved.duplicate()
	missing.magic = null
	check(not quote(missing, BaseNumber.new(1)) and not pay(missing, BaseNumber.new(1)), "token_only_missing_magic_rejected")
	var unknown:Dictionary = saved.duplicate()
	unknown.id = 99
	rejected(unknown, "unknown_member")
	check(not GameData.player_data_library.has(99), "unknown_member_not_created")

func legal_balance_and_pure_quote() -> void:
	var context:SessionContext = new_session()
	var saved:Dictionary = intent(context)
	var before:String = snapshot()
	for unused in range(3): check(quote(saved, BaseNumber.new(3)), "legal_quote")
	check(snapshot() == before, "quote_is_pure")
	check(not SessionGeneration.origin_of(saved.magic).ok, "quote_does_not_bind_magic")
	check(quote(saved, BaseNumber.new(8), 9), "simulated_quote_balance")
	check(not pay(saved, BaseNumber.new(8)), "actual_payment_ignores_simulated_balance")
	check(snapshot() == before, "insufficient_payment_atomic")
	saved.magic.set_num(BaseNumber.new(2))
	check(not pay(saved, BaseNumber.new(3)), "current_balance_rechecked_after_quote")
	check(saved.magic.number == 2, "current_balance_refusal_no_debit")
	saved.magic.set_num(BaseNumber.new(4))
	check(pay(saved, BaseNumber.new(1)), "legal_payment_completed")
	check(saved.magic.number == 3, "legal_payment_debit")
	var facts:Array = GameLog.query({"type":"magic_decrease"})
	check(facts.size() == 1, "one_real_payment_log")
	if facts.size() == 1:
		check(facts[0].data.purpose == "a1_35" and facts[0].data.spent == 1, "payment_log_purpose_and_amount")
	check(GameLog.query({"type":"time_point"}).is_empty(), "dispatch_false_no_timepoint")
	check(pay(saved, BaseNumber.new(5), false, true), "explicit_overdraft_completed")
	check(saved.magic.number == -2, "explicit_overdraft_balance")
	check(not pay(saved, BaseNumber.new(1)), "missing_overdraft_rejected")

func legal_free_and_immune() -> void:
	var context:SessionContext = new_session()
	var saved:Dictionary = intent(context)
	var before:String = snapshot()
	check(quote(saved, BaseNumber.new(0)) and pay(saved, BaseNumber.new(0), true), "legal_zero_bool_true")
	check(snapshot() == before, "legal_zero_no_fact")
	saved.member.is_magic_immune = true
	check(quote(saved, BaseNumber.new(99)) and pay(saved, BaseNumber.new(99), true), "legal_immune_bool_true")
	check(snapshot() == before, "legal_immune_no_fact")
	for amount in [null, BaseNumber.new(-1), BaseNumber.new(INF), BaseNumber.new(NAN)]:
		check(not quote(saved, amount) and not pay(saved, amount), "invalid_amount_rejected_before_immune")
	saved.member.is_magic_immune = false
	check(not quote(saved, BaseNumber.new(1), "garbage"), "malformed_available_rejected")
	check(not quote(saved, BaseNumber.new(1), INF), "infinite_available_rejected")

func stale_same_dictionary() -> void:
	var context:SessionContext = new_session()
	var saved:Dictionary = intent(context)
	var deferred:Callable = pay.bind(saved, BaseNumber.new(1), false, false)
	var reset:Dictionary = GameProgress.reset_progress()
	check(reset.ok, "PRE reset_progress only")
	check(is_same(saved.member, GameData.player_data_library[0]) and is_same(saved.magic, GameData.player_data_library[0].magic), "PRE reset preserves member_and_magic_identity")
	check(not SessionGeneration.validate_context(context).ok, "PRE original_context_stale")
	rejected(saved, "old_direct_same_dictionary")
	var before:String = snapshot()
	check(not deferred.call(), "old_saved_callable_rejected")
	check(snapshot() == before, "old_saved_callable_no_debit_or_commit")
	rejected(saved, "old_zero_same_dictionary", BaseNumber.new(0))
	saved.member.is_magic_immune = true
	rejected(saved, "old_immune_same_dictionary", BaseNumber.new(99))
	saved.member.is_magic_immune = false
	var fresh:Dictionary = intent(reset.context)
	check(quote(fresh, BaseNumber.new(1)) and pay(fresh, BaseNumber.new(1)), "new_context_same_id_legal")
	check(fresh.magic.number == 3, "new_context_same_id_one_debit")

func before_callback_replacement(mode:String) -> void:
	var context:SessionContext = new_session()
	var saved:Dictionary = intent(context)
	mutation_mode = mode
	var listener:BaseEffect = effect(context, "a1_35_before_" + mode, [{"func_name":"set_property","parameters":[self,"mutation_trigger",true]}], [TimePoints.SELF_BEFORE_MAGIC_ADD])
	TimePointChecker.dynamic_time_point([TimePoints.BEFORE_MAGIC_ADD], 0, null, context)
	check(listener != null and mutation_trigger, "PRE real BEFORE listener executed " + mode)
	if mode == "magic": check(not is_same(saved.magic, GameData.player_data_library[0].magic), "PRE same_member_new_magic")
	if mode == "member": check(not is_same(saved.member, GameData.player_data_library[0]), "PRE same_id_new_member")
	rejected(saved, "after_real_before_" + mode)
	if mode in ["magic", "member"]:
		rejected(saved, "replaced_identity_zero_" + mode, BaseNumber.new(0))
		GameData.player_data_library[0].is_magic_immune = true
		saved.member.is_magic_immune = true
		rejected(saved, "replaced_identity_immune_" + mode, BaseNumber.new(99))
		GameData.player_data_library[0].is_magic_immune = false
		saved.member.is_magic_immune = false
	mutation_mode = ""
	mutation_trigger = false

func in_frame_checks() -> void:
	var frame:Dictionary = EffectManager.execution_context()
	check(frame.ok, "PRE real_verified_function_frame")
	if not frame.ok: return
	var saved:Dictionary = intent(null)
	check(quote(saved, BaseNumber.new(1)), "frame_inherited_context_legal_quote")
	check(pay(saved, BaseNumber.new(1)), "frame_inherited_context_legal_payment")
	check(saved.magic.number == 3, "frame_one_payment")
	var foreign:Dictionary = SessionGeneration.derive_context(frame.context, &"a1_35.other_caller")
	var wrong:Dictionary = intent(foreign.context)
	rejected(wrong, "different_context_in_same_frame")
	var loss:Variant = EditMagic.new().exec(null, BaseNumber.new(-9), 0)
	check(loss == null and saved.magic.number == 0, "ordinary_forced_loss_still_clamps_not_payment")

func legal_frame_and_timepoint() -> void:
	var context:SessionContext = new_session()
	var root:BaseEffect = effect(context, "a1_35_frame", [{"func_name":"set_property","parameters":[self,"frame_trigger",true]}])
	EffectManager.activate_effect(root)
	check(frame_trigger, "PRE real_frame_callback")
	context = new_session()
	var saved:Dictionary = intent(context)
	var listener:BaseEffect = effect(context, "a1_35_payment_listener", [{"func_name":"set_property","parameters":[self,"callback_trigger",true]}], [TimePoints.SELF_MAGIC_DECREASE])
	check(pay(saved, BaseNumber.new(1), true), "legal_direct_dispatch_payment")
	check(listener != null and callback_count == 1, "payment_timepoint_listener_exactly_once")
	check(callback_saw_payment, "payment_log_before_timepoint_callback")
	check(GameLog.query({"type":"time_point", "tags":[TimePoints.MAGIC_DECREASE]}).size() == 1, "one_real_payment_timepoint")

func deferred_identity() -> void:
	var context:SessionContext = new_session()
	var saved:Dictionary = intent(context)
	var deferred:Callable = pay.bind(saved, BaseNumber.new(1), false, false)
	await get_tree().process_frame
	GameData.player_data_library[0].magic = BaseNumber.new(8)
	var before:String = snapshot()
	check(not deferred.call(), "deferred_original_magic_rejected")
	check(snapshot() == before and saved.magic.number == 4, "deferred_no_old_or_new_debit")

func _ready() -> void:
	print("ENV executable=", OS.get_executable_path(), " user_dir=", OS.get_user_data_dir(), " pid=", OS.get_process_id())
	for key in ["TMPDIR","TEMP","TMP","APPDATA","LOCALAPPDATA"]: print("ENV ", key, "=", OS.get_environment(key))
	missing_and_malformed()
	legal_balance_and_pure_quote()
	legal_free_and_immune()
	stale_same_dictionary()
	for mode in ["magic", "member", "reset"]: before_callback_replacement(mode)
	legal_frame_and_timepoint()
	await deferred_identity()
	GameData.release_game_objects()
	print("RESULT ", JSON.stringify({"suite":"a1_35_paymagic_contract","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
