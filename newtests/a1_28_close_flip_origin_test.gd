extends Node

# 来源诊断夹具：仅在明确的新建对象处绑定，不替生产者补票。
const Router = preload("res://scripts/system/operation_router.gd")
var checks:int = 0
var failures:Array = []
var context:SessionContext
var id:int
var before_hits:int = 0

class ResetAttack extends BaseAttack:
	var reset_on_flip:bool = false
	func set_concealed(value:bool):
		super.set_concealed(value)
		if reset_on_flip:
			GameProgress.reset_progress()

func _ready():
	call_deferred("run")

func check(ok:bool, label:String):
	checks += 1
	print("CHECK ", label, " ", ok)
	if not ok: failures.append(label)

func fresh():
	var lifecycle:Dictionary = GameData.reset_game_session([])
	id = AddPlayer.new().exec(-1, [], {"player_name":"A1-28"}, lifecycle.context)
	GameData.player_id = id
	var token = SessionGeneration.current_token()
	context = SessionGeneration.derive_context(token.token, &"A1-28.new_action").context
	GameLog.reset()

func bind(card:BaseCard):
	check(SessionGeneration.bind_origin(card, context.token(), &"A1-28.new_card").ok, "trusted fixture new card bind")

func attack(hidden:bool = false, exception:String = "") -> BaseAttack:
	var card = BaseAttack.new("target", "", [], BaseNumber.new(0), BaseNumber.new(4))
	card.set_concealed(hidden)
	if exception != "": card._effects = [BaseEffect.new(exception, [], 0, true, false)]
	bind(card)
	check(AddAttack.new().exec(card, id), "real attack enters")
	return card

func skill() -> BaseSkill:
	var card = BaseSkill.new("skill", "", [], BaseNumber.new(0), BaseNumber.new(4))
	bind(card)
	check(AddSkill.new().exec(card, id, true), "real skill enters")
	return card

# 旧实现没有context尾参时仍跑同一业务oracle，不用参数错误当RED。
func direct(op, args:Array, source:SessionContext):
	for method in op.get_method_list():
		if method.name == "exec" and method.args.size() > args.size():
			args = args.duplicate()
			args.append(source)
			break
	return op.callv("exec", args)

func flip(card:BaseCard, hidden:bool, source:SessionContext):
	return direct(SetCardConcealed.new(), [card, hidden, id], source)

func close(card:BaseHandCard, source:SessionContext):
	return direct(CloseCard.new(), [card, id], source)

func facts() -> Array:
	return GameLog.query({"type":"power_source", "actor":id}, null)

func power():
	return GameDataManager.find_player_data(id).power.number

func legal_cases():
	fresh()
	var card = attack(true)
	GameLog.reset()
	flip(card, false, context)
	check(not card._is_concealed and power() == 4, "same-session reveal actual +4")
	check(facts().size() == 1 and facts()[0].data.delta == 4, "reveal delta recorded exactly once")
	flip(card, false, context)
	check(facts().size() == 1 and power() == 4, "same-state reveal no second delta")
	flip(card, true, context)
	flip(card, false, context)
	check(power() == 4 and facts().size() == 3 and facts()[1].data.delta == -4 and facts()[2].data.delta == 4, "legal repeated transitions retain all independent deltas")
	close(card, context)
	check(card._is_closed and card._is_concealed and power() == 0, "attack close delegates flip actual -4")
	check(facts().size() == 4 and facts()[3].data.delta == -4, "CloseCard adds no duplicate flip record")
	close(card, context)
	check(facts().size() == 4 and power() == 0, "repeat close no-op")

	fresh()
	card = attack(false, CountsPowerWhileConcealedEffect.EFFECT_NAME)
	GameLog.reset()
	flip(card, true, context)
	check(card._is_concealed and power() == 4 and facts().is_empty(), "declared concealed counting exception retains power no delta")
	close(card, context)
	check(card._is_closed and power() == 4 and facts().is_empty(), "attack concealed-counting close exception unchanged")

	fresh()
	card = attack(false, NeverCountsPowerEffect.EFFECT_NAME)
	GameLog.reset()
	flip(card, true, context)
	flip(card, false, context)
	check(power() == 0 and facts().is_empty(), "declared never-counting both directions no delta")

	fresh()
	var s = skill()
	GameLog.reset()
	close(s, context)
	check(s._is_closed and not s._is_activating and not s._is_concealed, "skill closed stopped active returned visible")
	check(not GameDataManager.find_player_data(id).played_cards.has(s) and GameDataManager.find_player_data(id).side.skills.has(s), "skill really returns to skill zone")
	check(power() == 0 and facts().size() == 1 and facts()[0].data.delta == -4, "non-flip skill exception single registered EditPower delta")
	close(s, context)
	check(facts().size() == 1, "skill repeated close no second EditPower")

	fresh()
	var event = BaseEvent.new("event", "")
	bind(event)
	flip(event, true, context)
	check(event._is_concealed and power() == 0 and facts().is_empty(), "non-handcard only flips no power record")

func stale_cases():
	for kind in ["flip", "close_attack", "close_skill", "event"]:
		fresh()
		var old:BaseCard
		if kind == "close_skill": old = skill()
		elif kind == "event":
			old = BaseEvent.new("old", "")
			bind(old)
		else: old = attack()
		var previous = context
		var previous_id:int = id
		fresh()
		check(id == previous_id, kind + " actual new session same player ID")
		var current = attack()
		GameLog.reset()
		var before = power()
		if kind.begins_with("close"): close(old, context)
		else: flip(old, true, context)
		check(not old._is_concealed and (not old is BaseHandCard or not old._is_closed), kind + " old card new context refuses before target write")
		check(power() == before and not current._is_concealed and facts().is_empty(), kind + " old card cannot change new ID power or sources")
		check(GameLog.query({}, null).is_empty(), kind + " old card no close/reveal facts")
		flip(current, true, previous)
		check(not current._is_concealed and power() == before and facts().is_empty(), kind + " old context new target refuses")
		if current is BaseHandCard:
			close(current, previous)
			check(not current._is_closed and power() == before and facts().is_empty(), kind + " old close context refuses")

	fresh()
	var old_card = attack()
	var old_context = context
	var before = power()
	GameProgress.reset_progress()
	var new_token = SessionGeneration.current_token()
	context = SessionGeneration.derive_context(new_token.token, &"A1-28.new_action").context
	GameLog.reset()
	flip(old_card, true, context)
	close(old_card, context)
	check(not old_card._is_concealed and not old_card._is_closed and power() == before and facts().is_empty(), "reset-progress-only reused same card/dictionary rejects old object")
	check(not SessionGeneration.validate_context(old_context).ok, "public progress reset invalidated actual old context")

	fresh()
	var unbound = BaseAttack.new("unbound", "", [], BaseNumber.new(0), BaseNumber.new(4))
	GameDataManager.find_player_data(id).played_cards.append(unbound)
	GameLog.reset()
	flip(unbound, true, context)
	close(unbound, context)
	check(not unbound._is_closed and not unbound._is_concealed and facts().is_empty(), "unbound target consumer cannot mint source")
	check(not SessionGeneration.origin_of(unbound).ok, "rejected consumer did not bind target")

func reentrant_cases():
	fresh()
	var card = attack()
	# 正式加载/登记的BEFORE_CARD_CLOSE监听：回调同步公开换代。
	var resetter = LoadGame.load_buffs([{"buff_name":"reset listener", "buff_img":"", "is_active":true, "buff_level":{"number":1, "can_change":true, "is_pure_number":true}, "effects":[]}], "", null)[0]
	resetter._effects = LoadHelper.load_effects([{"effect_name":"reset close", "time_points":[TimePoints.BEFORE_CARD_CLOSE], "priority":0, "is_pure_passive":true, "is_residue":false, "need_activate":false, "effect_numbers":[], "funcs":[{"func_name":"do_nothing", "parameters":[]}]}], resetter, context)
	var effect:BaseEffect = resetter._effects[0]
	# 故障注入监听body，不改生产；真实pending action负责派发它。
	var f:BaseFunc = effect._funcs[0]
	f._func = func(): GameProgress.reset_progress()
	EffectManager.register_effects(resetter._effects, id)
	GameLog.reset()
	close(card, context)
	check(not card._is_closed and not card._is_concealed and power() == 4 and facts().is_empty(), "BEFORE close reset callback prevents old tail writes")

	fresh()
	var hooked = ResetAttack.new("hooked", "", [], BaseNumber.new(0), BaseNumber.new(4))
	bind(hooked)
	check(AddAttack.new().exec(hooked, id), "real hooked attack enters")
	hooked.reset_on_flip = true
	GameLog.reset()
	flip(hooked, true, context)
	check(power() == 4 and facts().is_empty(), "flip setter reset stops old power and source tail")

func frame_case():
	fresh()
	var card = attack(true)
	var owner = BaseBuff.new("frame owner", "")
	var descriptors = [{"effect_name":"legal flip", "time_points":[], "priority":0, "is_pure_passive":true, "is_residue":false, "need_activate":false, "effect_numbers":[], "funcs":[{"func_name":"set_card_concealed", "parameters":[{"self_var":0}, false, id]}]}]
	var effects = LoadHelper.load_effects(descriptors, owner, context)
	check(effects.size() == 1, "trusted LoadHelper runtime effect")
	var effect:BaseEffect = effects[0]
	effect._self_vars = [card]
	GameLog.reset()
	var executed = EffectManager.run_base_func(effect._funcs[0], effect, context)
	check(executed[0] and power() == 4 and not card._is_concealed and facts().size() == 1, "formal BaseFunc inherits validated frame no explicit operation context")

func entry_cases():
	fresh()
	var card = attack()
	GameLog.reset()
	# 无帧、无显式context的旧直调不可从activating_eff/current补票。
	SetCardConcealed.new().exec(card, true, id)
	CloseCard.new().exec(card, id)
	check(not card._is_concealed and not card._is_closed and power() == 4 and facts().is_empty(), "no frame no explicit context fails closed")
	var known_id:int = id
	id = 9999
	var keys:Array = GameData.player_data_library.keys()
	flip(card, true, context)
	close(card, context)
	check(not card._is_concealed and not card._is_closed and GameData.player_data_library.keys() == keys, "unknown member rejected before card write no implicit player creation")
	id = known_id

	fresh()
	var old = attack()
	fresh()
	var owner = BaseBuff.new("before observer", "")
	owner._effects = LoadHelper.load_effects([{"effect_name":"before observed", "time_points":[TimePoints.BEFORE_CARD_CLOSE], "priority":0, "is_pure_passive":true, "is_residue":false, "need_activate":false, "effect_numbers":[], "funcs":[{"func_name":"do_nothing", "parameters":[]}]}], owner, context)
	before_hits = 0
	owner._effects[0]._funcs[0]._func = func(): before_hits += 1
	EffectManager.register_effects(owner._effects, id)
	close(old, context)
	check(before_hits == 0 and not old._is_closed, "CloseCard entry source gate blocks new-session BEFORE listener")

func run():
	print("ENV ", JSON.stringify({"user":OS.get_user_data_dir(), "res":ProjectSettings.globalize_path("res://"), "pid":OS.get_process_id()}))
	legal_cases()
	stale_cases()
	reentrant_cases()
	frame_case()
	entry_cases()
	print("RESULT ", JSON.stringify({"suite":"A1-28-close-flip-origin", "checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
