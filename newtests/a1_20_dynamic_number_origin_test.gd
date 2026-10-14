extends Node
const Generation = preload("res://scripts/system/session_generation.gd")
var checks:int = 0
var failures:Array = []
var kept:Array = []
var watched:BaseEffect
var reset_hits:int = 0
var reset_snapshot:Dictionary = {}
var reset_target:Dictionary = {}
var old_target:Dictionary = {}
var old_known:Dictionary = {}
var new_context:SessionContext
var raw_callback:bool = false
var reset_marker:bool = false:
	set(value):
		reset_marker = value
		if value: reset_inside_operation()
func check(value:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", value)
	if not value: failures.append(label)
func start(ids:Array = [0,1]) -> SessionContext:
	var started:Dictionary = GameData.reset_game_session(ids)
	check(started.ok, "PRE real session starts")
	GameLog.reset()
	for area in MapData.areas:
		for loc in area._locations: loc._players.clear()
	for index in range(ids.size()):
		var id:int = ids[index]
		GameData.player_data_library[id].is_out = false
		GameData.player_data_library[id].location = MapData.miyama._locations[index]
		MapData.miyama._locations[index]._players.append(id)
	return started.context
func make_effect(context:SessionContext, funcs:Array = [], options:Array = [], descriptor:Dictionary = {}) -> BaseEffect:
	var desc:Dictionary = descriptor if not descriptor.is_empty() else {"effect_name":"a1-20-probe","priority":0,"time_points":[],"is_pure_passive":false,"is_residue":false,"effect_numbers":[],"funcs":funcs}
	if not options.is_empty(): desc["options"] = options
	var loaded:Array = LoadHelper.load_effects([desc], null, context)
	check(loaded.size() == 1, "PRE runtime factory")
	if loaded.is_empty(): return null
	var effect:BaseEffect = loaded[0]
	kept.append(effect)
	check(EffectManager.register_effect(effect, 0), "PRE runtime registers")
	return effect
func descriptor(key:String, set_num, vary_num, id = 1, low = null, high = null) -> Dictionary:
	return {"func_name":"edit_data_number","parameters":[key,set_num,vary_num,id,low,high]}
func call_descriptor(desc:Dictionary, effect:BaseEffect, context:SessionContext) -> Array:
	EffectManager.activating_eff = effect
	var result:Array = EffectManager.run_func_descriptor(desc, effect, context)
	EffectManager.activating_eff = null
	return result
func graph() -> Dictionary:
	var members:Array = []
	for id in GameData.player_data_library:
		var data:Dictionary = GameData.player_data_library[id]
		var nums:Dictionary = {}
		for key in data:
			if data[key] is BaseNumber: nums[key] = {"ref":data[key],"value":data[key].number}
		members.append({"id":id,"ref":data,"numbers":nums,"known":data.get("known_info"),"known_text":JSON.stringify(data.get("known_info"))})
	var seats:Array = []
	for area in MapData.areas:
		for loc in area._locations: seats.append({"loc":loc,"ref":loc._players,"values":loc._players.duplicate()})
	return {"library":GameData.player_data_library,"members":members,"map":MapData.areas,"seats":seats,"logs":GameLog.query({}).size(),"calls":GameLog.all_func_calls().size()}
func same_graph(saved:Dictionary) -> bool:
	if not is_same(saved.library, GameData.player_data_library) or not is_same(saved.map, MapData.areas): return false
	if saved.members.size() != GameData.player_data_library.size(): return false
	for member in saved.members:
		var current:Dictionary = GameDataManager.find_player_data(member.id)
		if not is_same(member.ref,current) or not is_same(member.known,current.get("known_info")) or member.known_text != JSON.stringify(current.get("known_info")): return false
		for key in member.numbers:
			var number:Dictionary = member.numbers[key]
			if not is_same(number.ref,current.get(key)) or number.ref.number != number.value: return false
	for seat in saved.seats:
		if not is_same(seat.ref,seat.loc._players) or seat.values != seat.loc._players: return false
	return saved.logs == GameLog.query({}).size() and saved.calls == GameLog.all_func_calls().size()
func no_frame_and_old_callable() -> void:
	var context:SessionContext = start()
	var current:BaseEffect = make_effect(context)
	EffectManager.activating_eff = current
	var saved:Dictionary = graph()
	var result = EditDataNumber.new().exec("command_spell_count", null, BaseNumber.new(-1), 1)
	check(result == null, "no-frame keeps null return")
	check(same_graph(saved), "no-frame refuses known same-ID target before resource write")
	check(not EffectManager.execution_context().ok, "fresh activating_eff never grants no-frame source")
	var operation:EditDataNumber = EditDataNumber.new()
	var retained:Callable = Callable(operation,"exec").bind("total_power_bonus",null,BaseNumber.new(7),1)
	var prior:Dictionary = GameData.player_data_library[1]
	start()
	saved = graph()
	EffectManager.activating_eff = current
	check(not current.runtime_source_status().ok, "PRE retained source genuinely stale")
	retained.call()
	check(same_graph(saved), "old raw Callable never writes new same-ID resource graph")
	check(prior.total_power_bonus.number == 0, "old raw Callable never writes old target either")
	var stale:Array = call_descriptor(descriptor("command_spell_count",null,BaseNumber.new(-1)),current,context)
	check(not stale[0] and stale[1] == null, "old descriptor refused before invocation")
	check(same_graph(saved), "old descriptor leaves graph and facts unchanged")
	EffectManager.activating_eff = null
func legal_fields() -> void:
	var context:SessionContext = start()
	var effect:BaseEffect = make_effect(context)
	var player:Dictionary = GameData.player_data_library[1]
	var count:int = 0
	# Iterate actual existing numeric fields, not a new API whitelist.
	for key in player:
		if not player[key] is BaseNumber: continue
		count += 1
		var number:BaseNumber = player[key]
		var before = number.number
		var invoked:Array = call_descriptor(descriptor(key,BaseNumber.new(5),BaseNumber.new(2)),effect,context)
		check(invoked[0] and invoked[1] == null and is_same(number,player[key]) and number.number == 7, "legal all numeric field "+key)
		invoked = call_descriptor(descriptor(key,null,BaseNumber.new(5),1,BaseNumber.new(0),BaseNumber.new(9)),effect,context)
		check(invoked[0] and number.number == 9, "legal explicit maximum "+key)
		invoked = call_descriptor(descriptor(key,null,BaseNumber.new(-20),1,0,9),effect,context)
		check(invoked[0] and number.number == 0, "legal explicit minimum "+key)
		number.number = before
	check(count > 0, "PRE existing numeric field set nonempty")
	var sources:int = GameLog.query({"type":"power_source"}).size()
	var result:Array = call_descriptor(descriptor("total_power_bonus",null,BaseNumber.new(2)),effect,context)
	var logs:Array = GameLog.query({"type":"power_source"})
	check(result[0] and logs.size() == sources+1 and logs.back().data.delta == 2, "legal total_power_bonus exact source delta")
	result = call_descriptor(descriptor("power",null,BaseNumber.new(2)),effect,context)
	check(result[0] and GameLog.query({"type":"power_source"}).size() == logs.size(), "other numeric fields preserve no extra source accounting")
	for bad in ["missing_numeric_field","is_out","known_info"]:
		result = call_descriptor(descriptor(bad,BaseNumber.new(50),BaseNumber.new(3)),effect,context)
		check(result[0] and result[1] == null, "undeclared or nonnumeric field keeps no-op "+bad)
		check(not player.has("missing_numeric_field") and player.is_out is bool and player.get("known_info",{}) is Dictionary, "undeclared field feature remains closed "+bad)
	var keys:Array = GameData.player_data_library.keys()
	result = call_descriptor(descriptor("total_power_bonus",null,BaseNumber.new(3),777),effect,context)
	check(result[0] and result[1] == null and keys == GameData.player_data_library.keys(), "unknown dynamic member does not create resources")
	result = call_descriptor(descriptor("play_limit",BaseNumber.new(6),BaseNumber.new(1),-1),effect,context)
	check(result[0] and GameData.player_data_library[0].play_limit.number == 7, "valid frame preserves declared owner fallback")
func wait_choice(context:SessionContext, funcs:Array) -> BaseEffect:
	var option:Dictionary = {"shown_option_name":"a1-20 pick target","select_players":{"candidates":[{"func_name":"get_all_players_id","parameters":[]}],"min":1,"max":1},"funcs":funcs}
	var effect:BaseEffect = make_effect(context,[],[option])
	EffectManager.decision_queue.append(effect)
	EffectManager.run_pipeline()
	check(EffectManager.get_pending_active_effect() == effect, "PRE real choice waiting")
	check(EffectManager.submit_option_choice(effect,[0]), "PRE real option accepts")
	check(EffectManager.get_pending_player_selection().get("candidates",[]) == [0,1], "PRE real declared candidates")
	return effect
func choice_functions(reset:bool) -> Array:
	var funcs:Array = [{"func_name":"get_activating_eff","parameters":[],"var_index":0},{"func_name":"get_property","parameters":[{"self_var":0},"_selected_player"],"var_index":1},{"func_name":"get_player_data_value","parameters":["known_info",{"self_var":1}],"var_index":2}]
	if reset: funcs.append({"func_name":"set_property","parameters":[self,"reset_marker",true]})
	funcs.append(descriptor("command_spell_count",null,BaseNumber.new(-1),{"self_var":1},0))
	return funcs
func reset_inside_operation() -> void:
	reset_hits += 1
	check(watched._selected_player == 1 and watched._self_vars.size() >= 3 and watched._self_vars[1] == 1, "PRE accepted dynamic target captured before callback reset")
	check(is_same(watched._self_vars[2],old_known), "PRE original target knowledge captured without copying")
	var previous:SessionContext = watched.runtime_context()
	var frame:Dictionary = EffectManager.execution_runtime_snapshot().functions.back()
	check(frame.stage == "call" and is_same(frame.context,previous), "PRE reset callback is inside real registered operation frame")
	new_context = start()
	reset_target = GameData.player_data_library[1]
	reset_snapshot = graph()
	check(not Generation.validate_context(previous).ok, "PRE synchronous reset invalidates original context")
	check(not EffectManager.execution_context().ok, "old frame rejects immediately during callback")
	if raw_callback:
		var result = EditDataNumber.new().exec("command_spell_count",null,BaseNumber.new(-1),watched._self_vars[1],0)
		check(result == null, "stale frame direct consumer retains null return")
		check(same_graph(reset_snapshot), "accepted-then-reset direct consumer never writes new graph")
	check(old_target.command_spell_count.number == 3, "accepted-then-reset never modifies original target")
func accepted_choice(reset:bool, raw:bool) -> void:
	var context:SessionContext = start()
	old_target = GameData.player_data_library[1]
	old_known = {"servant_class":{"original":true}}
	old_target.known_info = old_known
	reset_hits = 0
	raw_callback = raw
	watched = wait_choice(context,choice_functions(reset))
	check(EffectManager.configure_runtime_guard({"enabled":true,"steps":1,"seconds":0.0}), "PRE configure real budget before accepted submit")
	var accepted:bool = EffectManager.submit_player_selection(watched,[1])
	check(accepted and watched._selected_player == 1, "PRE public submit really accepts selected target before reset")
	check(EffectManager.runtime_guard_status().paused and reset_hits == 0, "PRE accepted choice pauses before reset callback")
	var resumes:int = 0
	while EffectManager.runtime_guard_status().paused and resumes < 10:
		var resumed:bool = EffectManager.resume_runtime_guard()
		check(resumed == not (reset and reset_hits > 0), "PRE actual resume return follows original source invalidation")
		resumes += 1
	if reset:
		check(reset_hits == 1, "PRE other operation callback synchronously reset exactly once")
		check(same_graph(reset_snapshot), "accepted-then-reset following descriptor writes no resources known-info map or facts")
		check(reset_target.command_spell_count.number == 3 and not is_same(reset_target,old_target), "new same-ID target remains independent and unchanged")
		check(not is_same(reset_target.get("known_info"),old_known), "new knowledge never receives old reference")
		check(not EffectManager.runtime_guard_status().paused, "source rejection is not resumable budget pause")
		var fresh:BaseEffect = make_effect(new_context)
		var result:Array = call_descriptor(descriptor("command_spell_count",null,BaseNumber.new(-1),1,0),fresh,new_context)
		check(result[0] and reset_target.command_spell_count.number == 2, "new legal same-ID effect still edits after old rejection")
	else:
		check(not EffectManager.runtime_guard_status().paused and reset_hits == 0, "same-session dynamic choice completes")
		check(old_target.command_spell_count.number == 2 and is_same(old_target.known_info,old_known), "same-session self_var target edits and preserves original knowledge")
		check(GameData.player_data_library[0].command_spell_count.number == 3, "same-session dynamic target never edits owner")
	check(EffectManager.configure_runtime_guard({"enabled":false,"steps":0,"seconds":0.0}), "PRE guard disabled")
func formal_medea_descriptor() -> void:
	var context:SessionContext = start()
	GameProgress.current_phase_index = 2
	GameProgress.current_player_id = 0
	GameProgress.current_round = 1
	GameData.player_data_library[0].current_time_points = ["self_"+TimePoints.ACTION_PHASE]
	var parsed:Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/servants/00005_medea/00005_medea.json"))
	var desc:Dictionary = {}
	for skill in parsed.specials.SKILLS:
		if skill.skill_name == "rule_breaker": desc = skill.effects[0]
	check(not desc.is_empty(), "PRE formal Medea descriptor loaded unchanged")
	var effect:BaseEffect = make_effect(context,[],[],desc)
	print("OBS formal can_manual=",EffectManager.can_manual_activate(effect,0)," points=",EffectManager.get_matched_time_points(effect)," runtime=",effect.runtime_source_status()," options=",EffectManager.has_available_options(effect)," running=",EffectManager.is_running)
	check(EffectManager.request_manual_activation(effect,0), "PRE formal manual request accepted")
	print("OBS formal wait=",EffectManager.get_pending_active_effect()," source=",EffectManager.execution_source_status())
	check(EffectManager.get_pending_active_effect() == effect, "PRE formal descriptor decision enters real pipeline")
	check(EffectManager.submit_option_choice(effect,[0]), "PRE formal descriptor option accepts")
	check(EffectManager.get_pending_player_selection().get("candidates",[]) == [1], "formal candidate descriptor retains same-area exclusion")
	check(EffectManager.submit_player_selection(effect,[1]), "formal declared dynamic target accepted")
	check(GameData.player_data_library[1].command_spell_count.number == 2 and GameData.player_data_library[0].total_power_bonus.number == 0, "formal unchanged function chain keeps original three-seal result")
func _ready() -> void:
	print("ENV user_dir=",OS.get_user_data_dir()," pid=",OS.get_process_id())
	no_frame_and_old_callable()
	legal_fields()
	accepted_choice(false,false)
	accepted_choice(true,false)
	accepted_choice(true,true)
	formal_medea_descriptor()
	print("RESULT ",JSON.stringify({"suite":"a1_20_dynamic_number_origin","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
