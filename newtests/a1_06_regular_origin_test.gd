extends Node

# Public API guard; production callbacks observed only via the public runtime snapshot.
const Sessions = preload("res://scripts/system/session_generation.gd")
const Rules = preload("res://scripts/match/rule_checkpoint.gd")
const Effects = preload("res://scripts/match/effect_checkpoint.gd")
var checks:int = 0
var failures:Array = []
var held:Array = []

class RuleProbe extends RefCounted:
	var writes:int = 0
	var value:int = 0:
		set(next):
			writes += 1
			value = next

func check(label:String, ok:bool) -> void:
	checks += 1
	print("CHECK ", label, " ", ok)
	if not ok: failures.append(label)

func _ready() -> void:
	call_deferred("run")

# Trusted fixture creation: lifecycle returns the original context, no current fallback.
func setup() -> SessionContext:
	var started:Dictionary = GameProgress.reset_progress()
	check("public reset creates original context", started.get("ok", false))
	if not started.get("ok", false): return null
	var context:SessionContext = started.context
	check("same-domain cleanup preserves startup source", EffectManager.clear_runtime_in_context(context).ok)
	GameLog.reset()
	check("public audit lifecycle reset", MatchJournal.reset_audit_memory())
	GameData.player_data_library.clear()
	var data:Dictionary = GameData.new_player_data()
	GameData.player_data_library[0] = data
	GameData.player_id = 0
	data.is_out = false
	data.magic.number = 8
	data.regular_play_min.number = 1
	data.play_limit.number = 1
	GameProgress.current_round = 1
	GameProgress.current_phase_index = 2
	GameProgress.current_player_id = 0
	GameLog.set_context(1, "action")
	var action:Dictionary = Sessions.derive_context(context, &"regular-prep.new-action")
	check("new fixture action inherits original startup source", action.ok)
	return action.context if action.ok else null

func snapshot() -> Dictionary:
	var data:Dictionary = GameData.player_data_library[0]
	return {"keys":GameData.player_data_library.keys(), "hand":data.hand_cards.duplicate(),
		"played":data.played_cards.duplicate(), "magic":data.magic.number, "power":data.power.number,
		"logs":GameLog.query({}, null, -1).duplicate(true), "transaction":EffectManager.capture_transaction_state(),
		"messages":EffectManager.messages.duplicate(true), "random":preload("res://scripts/match/rule_random.gd").snapshot(),
		"progress":[GameProgress.current_round,GameProgress.current_phase_index,GameProgress.current_player_id],
		"token":Sessions.current_token().token}

func primitives() -> void:
	var source:SessionContext = setup()
	if source == null: return
	var data:Dictionary = GameData.player_data_library[0]
	var probe:RuleProbe = RuleProbe.new()
	var missing = Rules.new()
	check("omitted capture source fails closed", not missing.capture([probe]) and not missing.ready)
	var graph = Rules.new()
	check("explicit original graph capture", graph.capture([probe], {}, source))
	probe.value = 7
	check("same-session graph restore", graph.restore() and probe.value == 0 and Sessions.validate_context(source).ok)
	var null_root = Effects.new(null, false, source)
	check("explicit null-effect origin permits audit without pretending ready", null_root.transaction_id > 0 and not null_root.ready and null_root.audit("resume"))
	var absent = Effects.new(null, false)
	check("null root omitted context cannot allocate audit identity", absent.transaction_id == 0 and absent.members.is_empty() and not absent.audit("regular-prep.missing"))
	# Only reset_progress: do not clear EM, facts, players, or map to mask a source failure.
	var next:Dictionary = GameProgress.reset_progress()
	check("reset-progress-only preserves actual player dictionary", next.ok and is_same(data,GameData.player_data_library[0]))
	check("reset-progress-only permanently revokes original source", not Sessions.validate_context(source).ok)
	probe.value = 11
	var before_writes:int = probe.writes
	var before:Dictionary = snapshot()
	check("old graph refuses before setter", not graph.restore() and probe.value == 11 and probe.writes == before_writes)
	check("old null root refuses audit", not null_root.audit("regular-prep.stale"))
	check("old checkpoint consumer changes no public baseline", snapshot() == before)

func entries() -> void:
	var source:SessionContext = setup()
	if source == null: return
	var data:Dictionary = GameData.player_data_library[0]
	var card = new_attack(source, "regular-prep-card", "", [], BaseNumber.new(0), BaseNumber.new(1))
	data.hand_cards.append(card)
	var before:Dictionary = snapshot()
	check("unbound submit rejects before any rule side effect", not regular_call("submit_group", [0,[card],[true],false,null]) and snapshot() == before)
	check("unbound add rejects before any rule side effect", not regular_call("add", [0,card,true,null]) and snapshot() == before)
	check("unbound forced finalize does not write completion", not regular_call("finalize", [0,true,null]) and snapshot() == before)
	# U061 oracle preserved, not reimplemented as a source API.
	check("unknown literal limit retains -1", RegularPlay.limit(907061) == -1 and GameData.player_data_library.keys() == [0])
	data.play_limit.number = 4
	check("dynamic limit increase remains live", RegularPlay.limit(0) == 4)
	data.play_limit = 1
	check("bare-number dynamic decrease remains live", RegularPlay.limit(0) == 1)
	data.erase("play_limit")
	check("legal missing field original default stays 2", RegularPlay.limit(0) == 2)
	data.play_limit = BaseNumber.new(1)
	var old_finalize:Callable = public_callable("finalize", [0,true,source])
	var next:Dictionary = GameProgress.reset_progress()
	check("stale-entry reset-only same-member prerequisite", next.ok and is_same(data,GameData.player_data_library[0]))
	before = snapshot()
	check("original public finalize Callable rejects reused dictionary", not old_finalize.call() and snapshot() == before)
	check("stale explicit submit rejects reused dictionary", not regular_call("submit_group", [0,[card],[true],false,source]) and snapshot() == before)
	check("stale explicit add rejects reused dictionary", not regular_call("add", [0,card,true,source]) and snapshot() == before)
	# No old origin refresh: legitimate new action is explicitly created from the new lifecycle result.
	var fresh:SessionContext = Sessions.derive_context(next.context,&"regular-prep.fresh-action").context
	GameProgress.current_round = 1
	GameProgress.current_phase_index = 2
	GameProgress.current_player_id = 0
	check("fresh action candidate positive", RegularPlay.can_submit_group(0,[card],[true]))
	check("fresh null-effect group executes with original context", regular_call("submit_group", [0,[card],[true],false,fresh]))
	check("fresh group enters and completes exactly once", data.played_cards == [card] and RegularPlay.completed(0) and GameLog.query({"type":"regular_play","actor":0},0).size() == 1)
	check("same-source completed finalize idempotent", regular_call("finalize", [0,true,fresh]) and GameLog.query({"type":"regular_play","actor":0},0).size() == 1)

func pending() -> void:
	var source:SessionContext = setup()
	if source == null: return
	# Runtime production factory; never activating_eff/current/fake frame for qualification.
	TimePointChecker.set_phase_time_points([TimePoints.ACTION_PHASE], source)
	var produced:Array = LoadHelper.load_effects([{"effect_name":"regular-prep-choice","time_points":[TimePoints.SELF_PREFIX + TimePoints.ACTION_PHASE],
		"priority":0,"is_pure_passive":false,"is_residue":false,"is_manual":true,"need_activate":false,"effect_numbers":[],"funcs":[],
		"options":[{"name":"continue","funcs":[]}]}],null,source)
	check("declared runtime choice factory", produced.size() == 1)
	if produced.is_empty(): return
	var effect:BaseEffect = produced[0]
	held.append(effect)
	check("real choice origin registration", EffectManager.register_effect(effect,0))
	var accepted:bool = EffectManager.request_manual_activation(effect,0)
	var waiting:bool = accepted and EffectManager.is_waiting_for_choice() and EffectManager.get_pending_active_effect() == effect
	check("actual public choice wait (not fake paused flag)", waiting)
	if not waiting:
		print("BLOCKED A1-14 real pending prerequisite not reached; no pending business claim")
		return
	var before:Dictionary = snapshot()
	check("pending finalize is refusal not completed success", not regular_call("finalize", [0,true,source]) and not RegularPlay.completed(0) and snapshot() == before)
	# Deliberately does not claim that a choice or payment tail can already resume.

# Same oracle on before/after signatures. Dropping only the unavailable tail parameter
# lets the original implementation fail business assertions, not call-arity parsing.
func regular_arguments(method:String, arguments:Array) -> Array:
	var script:Script = RegularPlay.new().get_script()
	for entry in script.get_script_method_list():
		if entry.name == method:
			return arguments.slice(0, entry.args.size())
	return arguments

func regular_call(method:String, arguments:Array):
	return Callable(RegularPlay,method).callv(regular_arguments(method,arguments))

func public_callable(method:String, arguments:Array) -> Callable:
	return Callable(RegularPlay,method).bindv(regular_arguments(method,arguments))

func pause_add(source:SessionContext) -> Dictionary:
	var data:Dictionary = GameData.player_data_library[0]
	var funcs:Array = []
	for i in range(5): funcs.append({"func_name":"do_nothing","parameters":[]})
	var effect:BaseEffect = LoadHelper.load_effects([{"effect_name":"a1-06-guard","priority":0,"is_pure_passive":true,
		"need_activate":false,"is_residue":false,"effect_numbers":[],"time_points":[TimePoints.CARD_COST_CALCULATED],"funcs":funcs}],null,source)[0]
	held.append(effect)
	check("real cost listener registered", EffectManager.register_effect(effect,0))
	EffectManager.configure_runtime_guard({"enabled":true,"steps":2,"seconds":0.0})
	var card = new_attack(source, "a1-06-tail","",[],BaseNumber.new(1),BaseNumber.new(2))
	data.hand_cards.append(card)
	check("real public add accepted and cost listener paused", regular_call("add",[0,card,false,source]) and EffectManager.runtime_guard_status().paused)
	var queue:Array = EffectManager.execution_runtime_snapshot().guard_continuations
	check("original production tail visible through public snapshot", not queue.is_empty())
	if queue.is_empty(): return {}
	var tail:Callable = queue.back().continuation
	var state:Dictionary = tail.get_bound_arguments()[0]
	return {"tail":tail,"finish":state.finish,"state":state,"card":card,"effect":effect}

func complete_guard() -> bool:
	for i in range(32):
		if not EffectManager.runtime_guard_status().paused: return true
		if not EffectManager.resume_runtime_guard(): return false
	return false

func tails(stale:bool) -> void:
	var source:SessionContext = setup()
	preload("res://scripts/match/rule_random.gd").start_seed(6106061)
	var data:Dictionary = GameData.player_data_library[0]
	var saved:Dictionary = pause_add(source)
	if saved.is_empty(): return
	check("pause before payment entry and completion", data.magic.number == 8 and data.played_cards.is_empty() and not RegularPlay.completed(0))
	if not stale:
		check("same-session real guard resume", complete_guard())
		check("same-session payment entry and completion exactly once", data.magic.number == 7 and data.played_cards == [saved.card] and RegularPlay.completed(0) and GameLog.query({"type":"regular_play","actor":0},0).size() == 1 and saved.state.phase == "done")
		var before:Dictionary = snapshot()
		saved.tail.call(); saved.finish.call()
		check("duplicate exact production tail finish make no changes", snapshot() == before)
		return
	var areas:Array = MapData.areas
	var next:Dictionary = GameProgress.reset_progress()
	check("reset-only preserves same dictionary and map", next.ok and is_same(data,GameData.player_data_library[0]) and is_same(areas,MapData.areas))
	var before:Dictionary = snapshot()
	var reply = saved.finish.call()
	check("exact production old finish explicitly refuses", typeof(reply) == TYPE_BOOL and not reply)
	check("old finish does not change new-session baseline", snapshot() == before)
	saved.tail.call()
	check("exact production old tail rejected with no new-session write", saved.state.phase == "rejected" and snapshot() == before)
	check("old group checkpoint cannot cover new session", not saved.state.checkpoint.restore() and snapshot() == before)
	var limit_query:Callable = public_callable("limit", [0,source])
	check("saved source-bound limit Callable refuses same dictionary", limit_query.call() == -1 and snapshot() == before)
	check("old guard public consumer refuses", not EffectManager.resume_runtime_guard() and snapshot() == before)
	# Fresh action after stale chain: no old origin refresh, same rule objects retained.
	check("fresh-domain cleanup explicit", EffectManager.clear_runtime_in_context(next.context).ok)
	GameLog.reset(); GameLog.set_context(1,"action")
	GameProgress.current_round=1;GameProgress.current_phase_index=2;GameProgress.current_player_id=0
	var fresh:SessionContext=Sessions.derive_context(next.context,&"a1-06.new-action").context
	check("new action same dictionary legal", regular_call("submit_group",[0,[saved.card],[true],false,fresh]) and RegularPlay.completed(0))

func delayed_refusal() -> void:
	var source:SessionContext = setup()
	preload("res://scripts/match/rule_random.gd").start_seed(6106062)
	var data:Dictionary = GameData.player_data_library[0]
	var saved:Dictionary = pause_add(source)
	if saved.is_empty(): return
	# Change an explicit live rule declaration, not the production finish Callable.
	# At completion count reaches limit but minimum now requires another card.
	data.regular_play_min.number=2
	check("refused finalize is not treated as completed", complete_guard() and not RegularPlay.completed(0) and saved.state.phase == "rejected")
	check("refused finish restores owned payment and entry", data.magic.number == 8 and data.played_cards.is_empty() and data.hand_cards.has(saved.card) and GameLog.query({"type":"play","actor":0},0).is_empty())

func pure_queries() -> void:
	var source:SessionContext=setup()
	var data:Dictionary=GameData.player_data_library[0]
	var card=new_attack(source, "pure","",[],BaseNumber.new(0),BaseNumber.new(1))
	data.hand_cards=[card]
	var before:Dictionary=snapshot()
	check("legal candidates prefix modes and group predicates", RegularPlay.candidates(0)==[card] and RegularPlay.can_play_group_prefix(0,[],[]) and RegularPlay.pending_modes(0,[],[],card).has(true) and RegularPlay.can_submit_group(0,[card],[true]))
	check("candidate queries are pure",snapshot()==before)
	for id in [907061,-1,-77]:
		check("unknown member guards retain no-create "+str(id),RegularPlay.limit(id)==-1 and RegularPlay.minimum(id)==-1 and RegularPlay.candidates(id).is_empty() and not regular_call("finalize",[id,true,source]) and snapshot()==before)

func dynamic_limits(value:int) -> void:
	var source:SessionContext=setup()
	var data:Dictionary=GameData.player_data_library[0]
	data.play_limit.number=2
	var effect:BaseEffect=LoadHelper.load_effects([{"effect_name":"a1-06-dynamic","priority":0,"is_pure_passive":true,"is_residue":false,
		"effect_numbers":[{"number":value,"can_change":true,"is_pure_number":true},{"number":0,"can_change":true,"is_pure_number":true}],
		"time_points":[TimePoints.PLAYED_CARD],"funcs":[{"func_name":"edit_data_number","parameters":["play_limit",{"number_index":0},{"number_index":1},0]}]}],null,source)[0]
	held.append(effect)
	check("dynamic declaration real listener registered",EffectManager.register_effect(effect,0))
	for i in range(value): data.hand_cards.append(new_attack(source, "dynamic-%s"%i,"",[],BaseNumber.new(1),BaseNumber.new(2)))
	var cards:Array=data.hand_cards.duplicate()
	var query:Callable=public_callable("limit",[0,source])
	for i in range(value):
		check("dynamic public add "+str(value)+"/"+str(i),regular_call("add",[0,cards[i],false,source]))
		check("dynamic real event changes live limit",query.call()==value)
		check("dynamic pay entry once",data.magic.number==8-i-1 and data.played_cards.size()==i+1)
		check("dynamic completion only at declared limit",RegularPlay.completed(0)==(i==value-1))
	check("dynamic completion single fact",GameLog.query({"type":"regular_play","actor":0},0).size()==1)

func replaced_member() -> void:
	var source:SessionContext=setup()
	var saved:Dictionary=pause_add(source)
	if saved.is_empty():return
	GameData.player_data_library[0]=GameData.new_player_data()
	var before:Dictionary=snapshot()
	check("same-session replaced member finish refusal",not saved.finish.call() and snapshot()==before and Sessions.validate_context(source).ok)
	saved.tail.call()
	check("same-session replaced member tail refusal",saved.state.phase=="rejected" and snapshot()==before)

func requeued_finish() -> void:
	var source:SessionContext=setup()
	var saved:Dictionary=pause_add(source)
	if saved.is_empty():return
	var data:Dictionary=GameData.player_data_library[0]
	var areas:Array=MapData.areas
	var next:Dictionary=GameProgress.reset_progress()
	check("requeue reset-only keeps dictionary and map",next.ok and is_same(data,GameData.player_data_library[0]) and is_same(areas,MapData.areas))
	# A separate new root can consume registrations, but cannot confer its source on an old finish.
	check("requeue fresh-domain cleanup",EffectManager.clear_runtime_in_context(next.context).ok)
	GameProgress.current_round=1;GameProgress.current_phase_index=2;GameProgress.current_player_id=0
	GameLog.set_context(1,"action")
	var fresh:SessionContext=Sessions.derive_context(next.context,&"a1-06.new-listener").context
	var funcs:Array=[]
	for i in range(5):funcs.append({"func_name":"do_nothing","parameters":[]})
	var effect:BaseEffect=LoadHelper.load_effects([{"effect_name":"new-guard","priority":0,"is_pure_passive":true,"is_residue":false,"effect_numbers":[],"time_points":[],"funcs":funcs}],null,fresh)[0]
	held.append(effect)
	check("new guard has real registered member",EffectManager.register_effect(effect,0))
	EffectManager.configure_runtime_guard({"enabled":true,"steps":2,"seconds":0.0})
	EffectManager.activate_effect(effect)
	check("new genuine guard paused",EffectManager.runtime_guard_status().paused)
	check("old exact finish requeued through public API",EffectManager.defer_until_runtime_guard_complete(saved.finish,fresh))
	var before:Dictionary=snapshot()
	check("new root public resume drains old saved finish",complete_guard())
	# Only this independently created root may publish its own effect/end facts.
	var after:Array=GameLog.query({},null,-1)
	var own_tail:bool=after.size()==before.logs.size()+2 and after.slice(0,before.logs.size())==before.logs
	if own_tail:
		own_tail=after[-2].type=="effect" and after[-2].object==effect and after[-1].type=="time_point" and after[-1].object==effect and after[-1].data.time_points==[TimePoints.EFFECT_END]
	check("old requeued finish cannot finish or pay in new root",data.magic.number==before.magic and data.played_cards==before.played and own_tail and not RegularPlay.completed(0))

func router_top_source() -> void:
	var source:SessionContext=setup()
	var data:Dictionary=GameData.player_data_library[0]
	var card=new_attack(source, "declared-true-name","",[],BaseNumber.new(0),BaseNumber.new(1))
	card._keywords=[ApplyCardKeywords.TRUE_NAME_RELEASE]
	data.hand_cards=[card]
	check("explicit original source permits registered batch keyword route",regular_call("submit_group",[0,[card],[false],false,source]))
	check("batch keyword router publishes actual true-name release once",GameLog.query({"type":"true_name_release","actor":0},null,-1).size()==1)

func run() -> void:
	print("PATH_PROOF ",JSON.stringify({"pid":OS.get_process_id(),"user":OS.get_user_data_dir()}))
	var mode:String=OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "all"
	if mode == "all":
		entries();primitives();pure_queries();tails(false);tails(true);delayed_refusal();pending();dynamic_limits(4);dynamic_limits(1);replaced_member();requeued_finish();router_top_source()
	elif mode == "tails": tails(true)
	elif mode == "refusal": delayed_refusal()
	else: check("known mode",false)
	print("RESULT ",JSON.stringify({"suite":"a1_06_regular_origin","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)

# Trusted fixture runtime creation: retain the lifecycle source and publish only after binding.
func new_attack(source:SessionContext, card_name:String, card_img:String, attributes:Array, cost:BaseNumber, power:BaseNumber) -> BaseAttack:
	if source == null or not Sessions.validate_context(source).ok:
		return null
	var created:BaseAttack = BaseAttack.new(card_name, card_img, attributes, cost, power, [], false)
	return created if LoadHelper.finalize_loaded_card(created, source) else null
