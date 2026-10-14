extends Node

# 与原78项守卫分开：验证新增声明的生产者、克隆、消费及真实结算。
var checks:int = 0
var failures:Array = []

func check(value:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", value)
	if not value:
		failures.append(label)

func descriptor(flag:Variant, need:bool = true, passive:bool = true) -> Dictionary:
	var data:Dictionary = {
		"effect_name":"explicit-conceal-probe", "priority":0,
		"time_points":[TimePoints.SELF_PLAYED_CARD],
		"is_pure_passive":passive, "is_residue":false,
		"effect_numbers":[], "funcs":[], "need_activate":need
	}
	if flag != null:
		data["allow_while_concealed"] = flag
	return data

func declaration_matrix() -> void:
	var event := BaseEvent.new("matrix-event", "", BaseNumber.new(0), [], false)
	check(not BaseEffect.new("default", [])._allow_while_concealed, "direct constructor default false")
	for flag in [null, false, true]:
		for need in [false, true]:
			for passive in [false, true]:
				var loaded:Array = LoadHelper.load_effects([descriptor(flag, need, passive)], event)
				check(loaded.size() == 1, "PRE matrix loader")
				if loaded.size() != 1:
					continue
				var effect:BaseEffect = loaded[0]
				check(effect._allow_while_concealed == (flag == true), "top-level declaration default and explicit")
				check(effect.runtime_context() == null, "template declaration has no execution ticket")
				for concealed in [false, true]:
					event._is_concealed = concealed
					check(EffectManager.card_state_allows(effect) == (not concealed or flag == true), "event face and explicit allowance independent of activation")
					effect._disabled = true
					check(not EffectManager.card_state_allows(effect), "explicit allowance cannot bypass disabled")
					effect._disabled = false
					event._text_disabled = true
					check(not EffectManager.card_state_allows(effect), "explicit allowance cannot bypass lost text")
					event._text_disabled = false
	var nested:Dictionary = descriptor(null)
	nested["values"] = {"allow_while_concealed":true}
	var nested_effect:BaseEffect = LoadHelper.load_effects([nested], event)[0]
	check(not nested_effect._allow_while_concealed, "nested value does not declare top-level allowance")
	for need in [false, true]:
		var hand := BaseHandCard.new()
		var hand_effect:BaseEffect = LoadHelper.load_effects([descriptor(true, need)], hand)[0]
		for concealed in [false, true]:
			for active in [false, true]:
				hand._is_concealed = concealed
				hand._is_activating = active
				check(EffectManager.card_state_allows(hand_effect) == (not need or active), "allowance never changes hand activation")

func clone_declaration() -> void:
	var session:Dictionary = GameData.reset_game_session([0, 1])
	check(session.ok, "PRE clone session")
	for flag in [null, false, true]:
		var template := BaseEvent.new("template", "", BaseNumber.new(0), [], false)
		template._is_concealed = true
		template._effects = LoadHelper.load_effects([descriptor(flag)], template)
		var factory := CloneContext.new()
		check(factory.configure_template(session.context, [template]), "PRE explicit identity template factory")
		var first:Dictionary = factory.copy_result(template, session.context)
		check(first.ok, "template to runtime clone accepted")
		if not first.ok:
			continue
		var card:BaseEvent = first.object
		# BaseCard 的既有克隆合同重置为正面；本守卫显式设置被测暗置输入，不改克隆合同。
		card._is_concealed = true
		var effect:BaseEffect = card._effects[0]
		check(effect._allow_while_concealed == (flag == true), "template clone preserves allowance")
		check(effect.runtime_source_status().ok and is_same(effect.from, card), "clone retains legitimate source and owner")
		check(EffectManager.card_state_allows(effect) == (flag == true), "cloned concealed event consumes declaration")
		var second:Dictionary = CloneContext.new().copy_result(card, session.context)
		check(second.ok, "runtime clone accepted")
		if second.ok:
			var copied:BaseEffect = second.object._effects[0]
			check(copied._allow_while_concealed == (flag == true), "runtime clone preserves allowance")
			check(is_same(copied.runtime_context().token(), effect.runtime_context().token()) and copied.runtime_context().origin() == effect.runtime_context().origin(), "runtime clone inherits original source without resigning")
		check(template._effects[0].runtime_context() == null, "template remains unbound after clone")

func execution_case(flag:Variant, concealed:bool, disabled:bool = false, textless:bool = false, once:bool = false, stale:bool = false) -> void:
	var session:Dictionary = GameData.reset_game_session([0, 1])
	check(session.ok, "PRE execution session")
	GameLog.reset()
	var data:Dictionary = descriptor(flag)
	data["once_per_game"] = once
	data["effect_numbers"] = [{"number":1, "can_change":true, "is_pure_number":true}]
	data["funcs"] = [{"func_name":"edit_score", "parameters":[null, {"number_index":0}, 0]}]
	var card:BaseEvent = LoadEvent.build_event({
		"card_name":"execution-event", "card_img":"", "score":{"number":0, "can_change":true, "is_pure_number":true},
		"effects":[data]
	}, "res://", session.context)
	check(card != null and card._effects.size() == 1, "PRE trusted runtime event loader")
	if card == null or card._effects.size() != 1:
		return
	var effect:BaseEffect = card._effects[0]
	card._is_concealed = concealed
	card._text_disabled = textless
	effect._disabled = disabled
	check(EffectManager.register_effect(effect, 0), "PRE real effect registration")
	if stale:
		GameData.reset_game_session([0, 1])
		check(not EffectManager.can_register_effect(effect, 0), "allowance cannot register stale source")
	var player:Dictionary = GameDataManager.find_player_data(0)
	var before:float = player.score.number
	player.current_time_points = [TimePoints.SELF_PLAYED_CARD]
	EffectManager.run_time_point(card, 0)
	var allowed:bool = (not concealed or flag == true) and not disabled and not textless and not stale
	check(player.score.number == before + (1 if allowed else 0), "real declared operation obeys face and existing gates")
	var facts:int = GameLog.query({"type":"effect"}).size()
	check(facts == (1 if allowed else 0), "refusal emits no effect fact")
	if once:
		print("CONCEAL_PROBE once=", effect._once_per_game, " used=", EffectManager.is_effect_used_once(effect), " actor=", effect._trigger_player_id, " facts=", GameLog.query({"type":"effect"}))
		player.current_time_points = [TimePoints.SELF_PLAYED_CARD]
		EffectManager.run_time_point(card, 0)
		check(player.score.number == before + (1 if allowed else 0), "explicit allowance cannot bypass once-per-game")
		check(GameLog.query({"type":"effect"}).size() == facts, "once-per-game emits no second activation")
	if stale:
		var template_effect:BaseEffect = LoadHelper.load_effects([descriptor(true)], null)[0]
		check(not EffectManager.register_effect(template_effect, 0), "allowance cannot register missing source")
		check(template_effect.runtime_context() == null, "rejected consumption never supplies ticket")

func schema_fields(value:Variant) -> Array:
	var fields:Array = []
	if value is Dictionary:
		if value.get("key") == "allow_while_concealed":
			fields.append(value)
		for child in value.values():
			fields.append_array(schema_fields(child))
	elif value is Array:
		for child in value:
			fields.append_array(schema_fields(child))
	return fields

func option_counts() -> void:
	var session:Dictionary = GameData.reset_game_session([0, 1])
	check(session.ok, "PRE option count session")
	GameLog.reset()
	var data:Dictionary = descriptor(true, true, false)
	data["max_total_uses"] = 1
	data["effect_numbers"] = [{"number":1, "can_change":true, "is_pure_number":true}]
	data["options"] = [{"shown_option_name":"use once", "max_uses":1, "funcs":[{"func_name":"edit_score", "parameters":[null, {"number_index":0}, 0]}]}]
	var card:BaseEvent = LoadEvent.build_event({"card_name":"count-event", "card_img":"", "score":{"number":0, "can_change":true, "is_pure_number":true}, "effects":[data]}, "res://", session.context)
	check(card != null, "PRE limited runtime event")
	if card == null:
		return
	card._is_concealed = true
	var effect:BaseEffect = card._effects[0]
	check(EffectManager.register_effect(effect, 0), "PRE limited event registration")
	var player:Dictionary = GameDataManager.find_player_data(0)
	player.current_time_points = [TimePoints.SELF_PLAYED_CARD]
	EffectManager.run_time_point(card, 0)
	check(EffectManager.get_pending_active_effect() == effect, "concealed explicit event awaits declared option")
	check(EffectManager.submit_option_choice(effect, {0:1}), "first legal option executes")
	check(player.score.number == 1, "limited event real operation executes once")
	check(not EffectManager.has_available_options(effect), "explicit allowance does not bypass exhausted option")
	check(not EffectManager.validate_selection(effect, {0:1}), "explicit allowance does not bypass total use limit")
	var facts:int = GameLog.query({"type":"effect"}).size()
	player.current_time_points = [TimePoints.SELF_PLAYED_CARD]
	EffectManager.run_time_point(card, 0)
	check(EffectManager.get_pending_active_effect() == null, "exhausted event does not offer second choice")
	check(player.score.number == 1 and GameLog.query({"type":"effect"}).size() == facts, "exhausted event changes neither score nor facts")

func run() -> void:
	if OS.get_cmdline_user_args().has("once-diagnostic"):
		# 保留原诊断断言：事件事实 actor=-1 与旧每局限一次的 actor=trigger 查法不一致。
		# 这是与本字段无关的既有缺口；不删断言、不改生产门、不拿它冒充正常套件绿。
		execution_case(true, true, false, false, true)
		print("RESULT ", JSON.stringify({"suite":"conceal_event_once_diagnostic", "checks":checks, "failures":failures}))
		get_tree().quit(0 if failures.is_empty() else 1)
		return
	check(GameData.reset_game_session([0, 1]).ok, "PRE matrix session")
	declaration_matrix()
	clone_declaration()
	for flag in [null, false, true]:
		for concealed in [false, true]:
			execution_case(flag, concealed)
	execution_case(true, true, true)
	execution_case(true, true, false, true)
	option_counts()
	execution_case(true, true, false, false, false, true)
	var schema = JSON.parse_string(FileAccess.get_file_as_string("res://json_maker/types.json"))
	var fields:Array = schema_fields(schema)
	check(fields.size() == 1, "editor schema registers allowance exactly once")
	if fields.size() == 1:
		check(fields[0].control == "bool" and fields[0].get("default") == false and not fields[0].get("required", false), "editor field optional boolean default false")
	print("RESULT ", JSON.stringify({"suite":"conceal_allow_while_concealed", "checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)

func _ready() -> void:
	call_deferred("run")
