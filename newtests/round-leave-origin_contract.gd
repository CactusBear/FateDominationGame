extends "res://newtests/round-defeat-cleanup-receipt_contract.gd"

var callback_calls:int = 0
var callback_mode:String = ""
var replacement:Dictionary = {}
var new_context:SessionContext
var new_state:Dictionary = {}
var callback_marker:bool = false:
	set(value):
		callback_marker = value
		if not value: return
		callback_calls += 1
		if callback_mode == "member":
			replacement = GameDataManager.find_player_data(0).duplicate()
			GameData.player_data_library[0] = replacement
		elif callback_mode == "reset":
			var begun:Dictionary = GameData.reset_game_session([0,1])
			check(begun.ok,"CALLBACK real new generation and members")
			new_context = begun.context
			check(GameProgress.reset_progress(false,new_context).ok,"CALLBACK new generation progress reset")
			check(Deploy.new().exec(MapData.miyama0,1,false,new_context),"CALLBACK new member legally takes freed seat")
			new_state = {"player":GameDataManager.find_player_data(1),"round":GameProgress.current_round,"phase":GameProgress.current_phase_index,"facts":GameLog.query({}).size(),"order":GameProgress.get_ordered_player_ids().duplicate()}

func operation(key:String, parameters:Array) -> Variant:
	var state:Dictionary = await GameProgress.wait_progress_operation(GameProgress.start_progress_operation(key,parameters,context),false)
	check(state.get("ok",false) and state.get("completed",false) and is_same(state.get("context"),context),"PRE real progress receipt " + key)
	return state.get("value")

func listener(mode:String) -> void:
	callback_mode = mode
	var loaded:Array = LoadHelper.load_effects([{"effect_name":"round leave callback","time_points":["self_" + TimePoints.LEAVE_LOCATION],"priority":0,"is_pure_passive":true,"is_residue":false,"effect_numbers":[],"funcs":[{"func_name":"set_property","parameters":[self,"callback_marker",true]}]}],null,context)
	check(loaded.size() == 1 and EffectManager.register_effect(loaded[0],0),"PRE real factory registered synchronous LEAVE listener")

func leave_count() -> int:
	return GameLog.query({"type":"leave_board","actor":0},null).size()

func guard(mode:String) -> void:
	var owner:Dictionary = GameDataManager.find_player_data(0)
	var other:Dictionary = GameDataManager.find_player_data(1)
	var loc:BaseLocation = MapData.miyama0
	if mode != "noop": check(Deploy.new().exec(loc,0,false,context),"PRE actual explicit-source deployment without function frame")
	else: check(owner.location == null and other.location == null,"PRE legitimate members already have no position")
	check(not EffectManager.execution_context().get("ok",false),"PRE Node has no inherited function frame")
	await operation("edit_power",[null,BaseNumber.new(7),0])
	await operation("defeat",[0])
	var buff:DefeatBuff = owner.buffs.back()
	check(intact(buff,owner),"PRE real installed defeat downstream witness")
	var printed:int = loc._printed_benefit.number
	await operation("edit_location_benefit",[loc,BaseNumber.new(printed * 2 + 1)])
	var benefit:BaseNumber = loc._benefit
	var modified = benefit.number
	var power:BaseNumber = owner.power
	var prior_power = power.number
	var events:Array = MapData.miyama._events.duplicate() + MapData.shinto._events.duplicate()
	var situation:BaseSituation = MapData.active_situation
	var order:Array = GameProgress.get_ordered_player_ids().duplicate()
	check(events.size() == 2 and situation != null and modified != printed and prior_power != 0,"PRE nonempty downstream witnesses")
	var old_round:int = GameProgress.current_round
	var day_end:int = facts(TimePoints.DAY_END)
	var day_start:int = facts(TimePoints.DAY_START)
	var leaves:int = leave_count()
	if mode in ["member","reset"]: listener(mode)
	await get_tree().process_frame
	check(owner.location == (null if mode == "noop" else loc) and benefit.number == modified and GameProgress.current_round == old_round,"CONTROL no tail preserves original location and benefit")
	await GameProgress.end_round(context)
	for unused in 4: await get_tree().process_frame
	if mode == "reset":
		check(callback_calls == 1 and not SessionGeneration.validate_context(context).ok,"RESET real synchronous callback invalidates old source once")
		check(not is_same(owner,GameDataManager.find_player_data(0)) and is_same(new_state.player,GameDataManager.find_player_data(1)),"RESET actual new members, not same-ID old object")
		check(GameProgress.current_round == new_state.round and GameProgress.current_phase_index == new_state.phase and GameProgress.get_ordered_player_ids() == new_state.order,"RESET old tail does not advance new progress or order")
		check(GameDataManager.find_player_data(1).location == loc and loc._players == [1],"RESET old tail does not remove new deployment")
		check(GameLog.query({}).size() == new_state.facts,"RESET old tail emits no new facts after callback")
		check(benefit.number == modified and power.number == prior_power,"RESET old tail does not rebuild original power or benefit")
		return
	check(facts(TimePoints.DAY_END) == day_end + 1,"DAY_END occurred once; earlier writes are not rolled back")
	check(owner.last_turn_location == (null if mode == "noop" else loc) and not owner.is_battle,"Original last location and earlier battle flag write preserved")
	if mode in ["member","refusal"]:
		if mode == "member":
			check(callback_calls == 1 and not is_same(owner,GameDataManager.find_player_data(0)) and is_same(replacement,GameDataManager.find_player_data(0)),"MEMBER actual synchronous same-ID dictionary replacement")
			check(owner.location == null and not loc._players.has(0) and leave_count() == leaves + 1,"MEMBER already committed leave remains truthful, once")
		else:
			check(owner.location == loc and loc._players.has(0) and leave_count() == leaves,"REFUSAL required removal fails without a leave fact or location write")
		check(GameProgress.current_round == old_round and GameProgress.get_current_phase().is_empty(),"STOP no next round")
		check(facts(TimePoints.DAY_START) == day_start,"STOP no next DAY_START")
		check(is_same(owner.power,power) and power.number == prior_power,"STOP no downstream power rebuild")
		check(intact(buff,owner),"STOP no downstream defeat cleanup")
		check(is_same(MapData.active_situation,situation) and not MapData.situation_discard.has(situation),"STOP no nonempty situation discard")
		check(MapData.miyama._events.duplicate() + MapData.shinto._events.duplicate() == events,"STOP no nonempty event discard")
		check(is_same(loc._benefit,benefit) and benefit.number == modified,"STOP no benefit restoration")
		check(GameProgress.get_ordered_player_ids() == order,"STOP no order rotation")
		await GameProgress.end_round(context)
		check(facts(TimePoints.DAY_END) == day_end + 1 and GameProgress.current_round == old_round,"STOP original lock prevents redispatch, no retry")
	else:
		check(GameProgress.current_round == old_round + 1 and facts(TimePoints.DAY_START) == day_start + 1,"NORMAL occupied or no-position member advances once")
		check(owner.location == null and not loc._players.has(0),"NORMAL actual position null and original seat empty")
		check(leave_count() == leaves + (0 if mode == "noop" else 1),"NORMAL leave fact exactly once, none for no-op")
		check(gone(buff,owner) and benefit.number == printed,"NORMAL downstream cleanup and benefit restore")
		check(Deploy.new().exec(loc,1,false,context),"NORMAL next player really deploys into freed seat")
		check(other.location == loc and loc._players == [1],"NORMAL real next occupancy, no old occupant")

func run() -> void:
	var args:PackedStringArray = OS.get_cmdline_user_args()
	var mode:String = args[0] if not args.is_empty() else "normal"
	print("USER_DIR ",OS.get_user_data_dir())
	if await start(): await guard(mode)
	GameStart.end_session()
	print("RESULT ",JSON.stringify({"suite":"round_leave_origin_" + mode,"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
