extends Node

const Op = preload("res://scripts/system/operations/ActivateEffect.gd")
var checks:int = 0
var failures:Array = []
var samples:Array = []
var bodies:int = 0
var raise_amount:bool = false
var sources:Array = []

func _ready() -> void:
	call_deferred("run")

func check(ok:bool, label:String) -> void:
	checks += 1
	print("CHECK ", ok, " ", label)
	if !ok: failures.append(label)

func setup() -> void:
	EffectManager.reset_runtime()
	if EffectManager.has_meta(&"activate_effect_registration_attempts"):
		EffectManager.remove_meta(&"activate_effect_registration_attempts")
	GameLog.reset()
	GameLog.set_context(1, "action")
	GameData.player_data_library.clear()
	GameData.player_id = 0
	GameProgress.current_player_id = 0
	for id in range(2):
		var data:Dictionary = GameData.new_player_data()
		data.is_out = false
		data.magic.number = 20
		data.command_spell_count.number = 3
		GameData.player_data_library[id] = data
	bodies = 0
	samples.clear()
	sources.clear()
	raise_amount = false

func body() -> void:
	bodies += 1

func payment_listener() -> void:
	var pending:Dictionary = EffectManager.current_pending_action()
	var target:BaseEffect = pending.source
	var pool:Array = []
	for candidate in EffectManager.effect_pool:
		pool.append([candidate._name, candidate._trigger_player_id])
	samples.append({"registered":EffectManager.effect_pool.has(target),
		"self_registered":GameDataManager.get_player_data(0).self_effects.has(target),
		"owner":target._trigger_player_id, "pool":pool,
		"matched":EffectManager.matched_time_points.get(target, []).duplicate(),
		"trigger":target._trigger_time_points.duplicate(),
		"selected":target._chosen_selection.duplicate(),
		"usage":target._option_use_counts.duplicate(),
		"waiting":EffectManager.waiting_effect == target,
		"queued":EffectManager.decision_queue.has(target),
		"spells":GameDataManager.get_player_data(0).command_spell_count.number})
	if raise_amount: pending.values.amount.number = 99

func fixture(mode:int, passive:bool = true, options:bool = false) -> BaseEffect:
	var listener := BaseEffect.new("payment_listener", [TimePoints.BEFORE_COMMAND_SPELL_SPEND], 0, true)
	listener._funcs = [BaseFunc.new(payment_listener, [])]
	EffectManager.register_effect(listener, 0)
	var effect := BaseEffect.new("d1_target", ["d1_probe"], 0, passive)
	var source := BaseMaster.new("d1_source", "登记来源", "", "", "")
	sources.append(source)
	effect.from = source
	source._effects = [effect]
	effect._is_manual = !passive or options
	effect._cost = {"type":"command_spell", "amount":1}
	effect._funcs = [BaseFunc.new(body, [])]
	if options: effect._options = [{"funcs":[BaseFunc.new(body, [])], "max_uses":-1}]
	if mode == 1: EffectManager.register_effect(effect, 0)
	if mode == 2: EffectManager.register_effect(effect, 1)
	return effect

func negative(mode:int, after_listener:bool, reason:String = "cost") -> void:
	setup()
	var effect:BaseEffect = fixture(mode)
	if reason == "disabled": effect._disabled = true
	if reason == "options": effect._options = [{"funcs":[], "max_uses":0}]
	var prior_matched:Array = ["prior_match"]
	var prior_trigger:Array = ["prior_trigger"]
	EffectManager.matched_time_points[effect] = prior_matched
	EffectManager.resolved_effects[effect] = "prior_result"
	effect._trigger_time_points = prior_trigger
	var pool:Array = EffectManager.effect_pool.duplicate()
	var own0:Array = GameDataManager.get_player_data(0).self_effects.duplicate()
	var own1:Array = GameDataManager.get_player_data(1).self_effects.duplicate()
	var objects:Array = GameData.objects.duplicate()
	var effects:Array = GameData.effects.duplicate()
	var owner:int = effect._trigger_player_id
	if reason == "cost":
		if after_listener: raise_amount = true
		else: GameDataManager.get_player_data(0).command_spell_count.number = 0
	var result = Op.new().exec(effect, 0)
	var label:String = "negative_%s_%s_%s" % [mode, after_listener, reason]
	check(result == null, label + " rejects")
	check(EffectManager.effect_pool == pool, label + " pool ordered unchanged")
	check(GameDataManager.get_player_data(0).self_effects == own0 and GameDataManager.get_player_data(1).self_effects == own1, label + " self registrations unchanged")
	check(effect._trigger_player_id == owner, label + " original owner unchanged")
	check(effect.from == sources[0] and sources[0]._effects == [effect], label + " real source alias unchanged")
	check(is_same(EffectManager.matched_time_points.get(effect), prior_matched) and EffectManager.resolved_effects.get(effect) == "prior_result" and is_same(effect._trigger_time_points, prior_trigger), label + " context identity restored")
	check(EffectManager.decision_queue.is_empty() and EffectManager.activation_pool.is_empty() and !EffectManager.is_waiting_for_choice() and bodies == 0, label + " no execution or waiting residue")
	check(GameData.objects == objects and GameData.effects == effects, label + " no clone object-table residue")
	if EffectManager.has_meta(&"activate_effect_registration_attempts"):
		check((EffectManager.get_meta(&"activate_effect_registration_attempts") as Dictionary).is_empty(), label + " no registration attempt residue")
	if after_listener: check(samples.size() == 1, label + " actual payment listener ran")

func positive(mode:int, passive:bool, options:bool) -> void:
	setup()
	var effect:BaseEffect = fixture(mode, passive, options)
	var result = Op.new().exec(effect, 0)
	check(result is BaseEffect, "positive enqueued %s %s %s" % [mode, passive, options])
	if result == null: return
	if !passive or options:
		check(EffectManager.waiting_effect == result, "positive real waiting established")
		var accepted:bool = EffectManager.submit_option_choice(result, [0]) if options else EffectManager.submit_active_choice(result, true)
		check(accepted, "positive real choice accepted")
	check(samples.size() == 1 and bodies == 1, "positive single payment and body")
	check(GameDataManager.get_player_data(0).command_spell_count.number == 2, "positive spends exactly one")
	check(result.from == sources[0] and effect.from == sources[0], "positive real clone source alias preserved")
	if samples.size() == 1:
		check(samples[0].registered and samples[0].self_registered and samples[0].owner == 0, "payment sees prior registration and owner")
	var logs:Array = []
	for fact in GameLog.query({}, null):
		var object_name:String = ""
		if fact.object is BaseObject: object_name = fact.object._name
		logs.append({"type":fact.type, "actor":fact.actor, "target":fact.target,
			"object":object_name, "tags":fact.tags, "data":fact.data,
			"round":fact.round, "phase":fact.phase})
	print("SUCCESS_TRACE ", JSON.stringify({"mode":mode,"passive":passive,"options":options,
		"samples":samples,"logs":logs,"spells":GameDataManager.get_player_data(0).command_spell_count.number,
		"bodies":bodies,"clone":result != effect,"source_alias":result.from == effect.from}))

func run() -> void:
	print("USER_DIR ", OS.get_user_data_dir())
	for mode in range(3):
		negative(mode, false)
		negative(mode, true)
		negative(mode, false, "disabled")
		negative(mode, false, "options")
	for mode in range(3):
		positive(mode, true, false)
		positive(mode, false, false)
		positive(mode, false, true)
	print("RESULT checks=", checks, " failures=", JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
