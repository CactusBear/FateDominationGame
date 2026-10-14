extends "res://newtests/conceal_allow_while_concealed_test.gd"

# 复用真实声明/加载与来源控制夹具；只验证现有 actor + effect_name 历史键。
func declaration(once:bool = true) -> Dictionary:
	var data:Dictionary = descriptor(true, false, true)
	data["effect_name"] = "once-history-scope"
	data["once_per_game"] = once
	data["effect_numbers"] = [{"number":1, "can_change":true, "is_pure_number":true}]
	data["funcs"] = [{"func_name":"edit_score", "parameters":[null, {"number_index":0}, 0]}]
	return data

func field_card(context:SessionContext, situation:bool, once:bool = true):
	var data:Dictionary = {"card_name":"history-source", "card_img":"", "effects":[declaration(once)]}
	var number:Dictionary = {"number":0, "can_change":true, "is_pure_number":true}
	if situation:
		data["magic"] = number
		return LoadSituation.build_situation(data, "res://", context)
	data["score"] = number
	return LoadEvent.build_event(data, "res://", context)

func trigger(card, id:int) -> void:
	GameDataManager.find_player_data(id).current_time_points = [TimePoints.SELF_PLAYED_CARD]
	EffectManager.run_time_point(card, id)

func field_case(situation:bool, weak:bool, once:bool) -> void:
	var session:Dictionary = GameData.reset_game_session([0, 1])
	check(session.ok, "PRE field session")
	GameLog.reset()
	var card = field_card(session.context, situation, once)
	check(card != null, "PRE field runtime factory")
	if card == null: return
	var effect:BaseEffect = card._effects[0]
	# BaseObject.from 的 setter 弱持 Object，必须保活此包装而不是传临时 WeakRef。
	var owner_ref:WeakRef = weakref(card)
	if weak: effect.from = owner_ref
	check((effect.from is WeakRef) == weak, "PRE owner representation is retained")
	check(effect.runtime_source_status().ok, "field retains original source")
	check(EffectManager.register_effect(effect, 0), "PRE field registration with legal ordering anchor")
	check(effect._trigger_player_id == 0 and EffectManager.effect_fact_actor_id(effect) == -1, "anchor is not fact actor")
	check(not EffectManager.is_effect_used_once(effect), "fresh field history empty")
	trigger(card, 0)
	check(GameDataManager.find_player_data(0).score.number == 1, "field first registered operation executes")
	var facts:Array = GameLog.query({"type":"effect"}, null)
	check(facts.size() == 1 and facts[0].actor == -1, "field first fact remains unowned")
	check(GameLog.query({"type":"effect", "actor":0}, null).is_empty(), "no anchor-owned effect fact")
	check(EffectManager.is_effect_used_once(effect), "field history query uses fact actor")
	check(EffectManager.card_state_allows(effect) == not once, "field once declaration controls second entry")
	var history:Array = GameLog.query({}, null)
	trigger(card, 0)
	check(GameDataManager.find_player_data(0).score.number == (1 if once else 2), "same field second execution obeys declared once")
	check(GameLog.query({"type":"effect"}, null).size() == (1 if once else 2), "same field writes no second activation when once")
	if once:
		check(GameLog.query({}, null) == history, "same field second trigger writes no rule log")
	else:
		check(GameLog.query({}, null).size() > history.size(), "without once declaration second execution still logs")

func cross_anchor_and_scope() -> void:
	var session:Dictionary = GameData.reset_game_session([0, 1])
	check(session.ok, "PRE scope session")
	GameLog.reset()
	var first = field_card(session.context, false)
	check(first != null, "PRE first anchor factory")
	if first == null: return
	check(EffectManager.register_effect(first._effects[0], 0), "PRE first anchor register")
	trigger(first, 0)
	var second = field_card(session.context, false)
	check(second != null, "PRE second anchor factory")
	if second == null: return
	var second_effect:BaseEffect = second._effects[0]
	check(EffectManager.register_effect(second_effect, 1), "PRE second legal anchor register")
	check(second_effect._trigger_player_id == 1 and EffectManager.effect_fact_actor_id(second_effect) == -1, "different anchor still same unowned scope")
	check(EffectManager.is_effect_used_once(second_effect), "existing declared key is independent of field anchor")
	var history:Array = GameLog.query({}, null)
	trigger(second, 1)
	check(GameDataManager.find_player_data(0).score.number == 1 and GameLog.query({}, null) == history, "different anchor does not create extra field quota or log")
	var template := BaseHandCard.new()
	template._effects = LoadHelper.load_effects([declaration()], template)
	var factory := CloneContext.new()
	check(factory.configure_template(session.context, [template]), "PRE trusted hand template identity")
	for id in [0, 1]:
		var copy:Dictionary = factory.copy_result(template, session.context)
		check(copy.ok, "PRE runtime hand clone")
		if not copy.ok: continue
		var card:BaseHandCard = copy.object
		var effect:BaseEffect = card._effects[0]
		check(EffectManager.register_effect(effect, id), "PRE runtime player effect register")
		check(EffectManager.effect_fact_actor_id(effect) == id, "player fact actor remains owner")
		check(not EffectManager.is_effect_used_once(effect), "other actor same declared key does not exhaust player")
		trigger(card, id)
		check(EffectManager.is_effect_used_once(effect), "player actor history remains effective")
		check(GameLog.query({"type":"effect", "actor":id}, null).size() == 1, "one real player-owned activation")
		var player_history:Array = GameLog.query({}, null)
		trigger(card, id)
		check(GameLog.query({}, null) == player_history, "player once still rejects without extra log")
	check(GameDataManager.find_player_data(0).score.number == 3, "one field and both separate player quotas executed")
	check(not EffectManager.is_effect_used_once(null), "null query retains false")
	var unregistered:BaseEffect = LoadHelper.load_effects([declaration()], first)[0]
	check(unregistered._trigger_player_id < 0 and not EffectManager.is_effect_used_once(unregistered), "negative unregistered anchor retains original false")
	var context:SessionContext = session.context
	GameData.reset_game_session([0, 1])
	check(not SessionGeneration.validate_context(context).ok, "new session invalidates original source")
	check(not EffectManager.can_register_effect(second_effect, 1), "old field source still rejected")
	var fresh_history:Array = GameLog.query({}, null)
	trigger(second, 1)
	check(GameDataManager.find_player_data(0).score.number == 0 and GameLog.query({}, null) == fresh_history, "stale field executes nothing and logs nothing")

func run() -> void:
	for situation in [false, true]:
		for weak in [false, true]:
			for once in [false, true]:
				field_case(situation, weak, once)
	cross_anchor_and_scope()
	execution_case(true, true, false, false, false, true)
	print("RESULT ", JSON.stringify({"suite":"once_per_game_actor", "checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
