extends Node

const Authority = preload("res://scripts/net/authority/match_authority.gd")
const Selection = preload("res://scripts/net/authority/selection_authority.gd")
const Mode = preload("res://scripts/selection/class_pool_selection.gd")
const RR = preload("res://scripts/match/rule_random.gd")
var checks:int = 0
var failures:Array = []
var context:SessionContext
var authority

func check(ok:bool, label:String) -> void:
	checks += 1
	if not ok: failures.append(label)
	print("CHECK ",label," ",ok)

func _ready() -> void:
	call_deferred("run")

func number(value:int) -> Dictionary:
	return {"number":value,"can_change":true,"is_pure_number":true}

func start() -> bool:
	RR.start_seed(775041)
	var selection = Selection.new()
	check(selection.setup(Mode.new(),{0:101,1:202},GameStart.get_masters_can_use(),GameStart.get_servants_can_use(),
		{"regular_classes":["saber","assassin"],"per_class_count":1,"special_count":0,"randomize_initial_order":false}),"PRE public selection")
	check(selection.choose(101,0,"emiya_shirou"),"PRE first master choice")
	check(selection.choose(202,1,"kuzuki_souichirou"),"PRE second master choice")
	# 声明无动作的真实模板，开局仍经 MapData runtime 工厂、正式放置与激活。
	LoadEvent.events = [LoadEvent.build_event({"card_name":"receipt witness event","card_img":"","score":number(1),"effects":[]},"")]
	LoadSituation.situations = [LoadSituation.build_situation({"card_name":"receipt witness situation","card_img":"","magic":number(0),"effects":[]},"")]
	LoadSituation.climax_situations = {}
	authority = Authority.new()
	check(authority.declare_broadcast_confirmation(false),"PRE no broadcast wait declaration")
	check(authority.start(selection),"PRE actual GameStart authority start: " + authority.error)
	context = GameStart.startup_context()
	check(context != null and SessionGeneration.validate_context(context).ok,"PRE saved original successful GameStart context")
	for unused in 60:
		if not EffectManager.is_running and not EffectManager.is_waiting_for_choice() and not GameProgress.get_current_phase().is_empty(): break
		await get_tree().process_frame
	check(GameProgress.current_round == 1 and GameProgress.get_current_phase().get("name") == "prepare","PRE real first round ready")
	return failures.is_empty()

func gone(buff:DefeatBuff, owner:Dictionary) -> bool:
	if owner.buffs.has(buff) or GameData.objects.has(buff): return false
	for effect in buff._effects:
		if GameData.objects.has(effect) or GameData.effects.has(effect) or EffectManager.effect_pool.has(effect) or owner.self_effects.has(effect): return false
	return true

func intact(buff:DefeatBuff, owner:Dictionary) -> bool:
	if not owner.buffs.has(buff) or not GameData.objects.has(buff): return false
	for effect in buff._effects:
		if not GameData.objects.has(effect) or not GameData.effects.has(effect) or not EffectManager.effect_pool.has(effect) or not owner.self_effects.has(effect): return false
	return true

func facts(point:String) -> int:
	return GameLog.query({"type":"time_point","actor":-1,"tags":[point]},null).size()

func probe(refusal:bool) -> void:
	var owners:Array = [GameDataManager.find_player_data(0),GameDataManager.find_player_data(1)]
	var layers:Array = []
	# 新动作可信创建边界，仅从保存的成功开局 token 签一次不同 origin。
	# 不给旧对象重签；回合与清理消费端从不 derive/current/bind。
	var second:Dictionary = SessionGeneration.derive_context(context.token(),&"round-defeat-receipt.distinct-new-action")
	check(second.ok and second.context.origin() != context.origin() and not is_same(second.context,context),"PRE distinct legitimate action origin in same generation")
	for entry in [{"id":0,"ctx":context},{"id":1,"ctx":second.context},{"id":1,"ctx":context}]:
		var op:Dictionary = GameProgress.start_progress_operation("defeat",[entry.id],entry.ctx)
		var receipt:Dictionary = await GameProgress.wait_progress_operation(op,false)
		check(receipt.get("ok",false) and receipt.get("value") == true,"PRE formal Defeat installed target %d" % entry.id)
		var owner:Dictionary = owners[entry.id]
		if not owner.buffs.is_empty(): layers.append({"buff":owner.buffs.back(),"owner":owner})
	check(layers.size() == 3 and DefeatBuff.get_defeat_count(0) == 1 and DefeatBuff.get_defeat_count(1) == 2,"PRE real multi-target multi-layer defeat")
	for entry in layers:
		check(intact(entry.buff,entry.owner) and RegisterObjectEffects.can_register_object(entry.buff,0 if is_same(entry.owner,owners[0]) else 1,context),"PRE different origins accept saved round context without same-handle requirement")
	var events:Array = MapData.miyama._events.duplicate() + MapData.shinto._events.duplicate()
	var situation:BaseSituation = MapData.active_situation
	var order:Array = GameProgress.get_ordered_player_ids().duplicate()
	check(events.size() == 2 and situation != null and order == [0,1],"PRE nonempty real event situation and ordered-player witnesses")
	var loc:BaseLocation = MapData.miyama0
	var printed:int = GetLocationBenefit.new().exec(loc).number
	EditLocationBenefit.new().exec(loc,BaseNumber.new(printed * 2 + 1))
	var benefit:BaseNumber = GetLocationBenefit.new().exec(loc)
	var modified:int = benefit.number
	check(modified != printed,"PRE actual modified location benefit witness")
	var old_round:int = GameProgress.current_round
	var day_end:int = facts(TimePoints.DAY_END)
	var day_start:int = facts(TimePoints.DAY_START)
	var event_discard:Array = MapData.event_discard.duplicate()
	var situation_discard:Array = MapData.situation_discard.duplicate()
	if refusal:
		# 真对象负例：同 ID 换 Dictionary，保留真实已安装图。既有登记 owner 门必须拒绝。
		var replacement:Dictionary = owners[1].duplicate()
		GameData.player_data_library[1] = replacement
		check(not is_same(replacement,owners[1]) and replacement.buffs == owners[1].buffs,"PRE same-ID replacement retains actual installed graph")
		check(not RegisterObjectEffects.can_register_object(layers[1].buff,1,context),"PRE actual original-owner registration refusal")
	else:
		await get_tree().process_frame
		check(GameProgress.current_round == old_round and benefit.number == modified and MapData.active_situation == situation,"CONTROL no end_round preserves witnesses")
	await GameProgress.end_round(context)
	for unused in 4: await get_tree().process_frame
	check(facts(TimePoints.DAY_END) == day_end + 1,"upstream DAY_END actually occurred once; no rollback claimed")
	if refusal:
		check(GameProgress.current_round == old_round and GameProgress.get_current_phase().is_empty(),"REFUSAL does not start next round")
		check(facts(TimePoints.DAY_START) == day_start,"REFUSAL no next DAY_START")
		check(is_same(MapData.active_situation,situation) and MapData.situation_discard == situation_discard,"REFUSAL preserves nonempty original situation and discard")
		check(MapData.miyama._events.duplicate() + MapData.shinto._events.duplicate() == events and MapData.event_discard == event_discard,"REFUSAL preserves nonempty original events and discard")
		check(is_same(GetLocationBenefit.new().exec(loc),benefit) and benefit.number == modified,"REFUSAL does not restore location benefit")
		check(GameProgress.get_ordered_player_ids() == order,"REFUSAL does not rotate player order")
		for entry in layers: check(intact(entry.buff,entry.owner),"REFUSAL all original defeat graphs remain intact")
		await GameProgress.end_round(context)
		check(facts(TimePoints.DAY_END) == day_end + 1 and GameProgress.current_round == old_round,"REFUSAL existing round-end lock blocks redispatch on repeated call")
		# 不自行解除锁/续行/整轮重跑；恢复原 Dictionary 只用于结束场景的合法资源释放。
		GameData.player_data_library[1] = owners[1]
	else:
		check(GameProgress.current_round == old_round + 1 and GameProgress.get_current_phase().get("name") == "prepare","NORMAL advances exactly one round to prepare")
		check(facts(TimePoints.DAY_START) == day_start + 1,"NORMAL starts next round once")
		for entry in layers: check(gone(entry.buff,entry.owner),"NORMAL removes original defeat graph")
		check(DefeatBuff.get_defeat_count(0) == 0 and DefeatBuff.get_defeat_count(1) == 0,"NORMAL clears all target layers")
		check(MapData.situation_discard.has(situation) and not is_same(MapData.active_situation,situation),"NORMAL discards original nonempty situation")
		var all_discarded:bool = true
		for event in events:
			if not MapData.event_discard.has(event): all_discarded = false
		check(all_discarded,"NORMAL discards each original event identity")
		check(is_same(GetLocationBenefit.new().exec(loc),benefit) and benefit.number == printed,"NORMAL restores location benefit with identity")
		check(GameProgress.get_ordered_player_ids() == [order[1],order[0]],"NORMAL rotates original real order once")

func run() -> void:
	var refusal:bool = OS.get_cmdline_user_args().has("refusal")
	print("USER_DIR ",OS.get_user_data_dir())
	if await start(): await probe(refusal)
	GameStart.end_session()
	print("RESULT ",JSON.stringify({"suite":"round_defeat_cleanup_receipt_refusal" if refusal else "round_defeat_cleanup_receipt_normal","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
