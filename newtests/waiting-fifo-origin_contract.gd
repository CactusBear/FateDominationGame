extends "res://tests/command_spell_test.gd"
# 真实工厂/登记/选择/事务；不伪造函数帧或补票。
var writer
var serial:int = 0

class LegacyScore extends BaseNumber:
	var accepted:Array = []
	var original:SessionContext
	func set_num(value:BaseNumber) -> BaseNumber:
		original = EffectManager.execution_context().get("context")
		accepted = [EffectManager.run_time_point(), EffectManager.run_time_point(null), EffectManager.run_time_point(null, 0)]
		return super.set_num(value)

func end_audit() -> void:
	if writer != null:
		MatchJournal.end_audit(writer)
		writer = null

func open_case(audit:bool = false, optional:bool = false) -> Dictionary:
	end_audit()
	_setup()
	check(_place(MapData.miyama, 0, 0), "guard original placement")
	if audit:
		serial += 1
		writer = MatchJournal.begin_audit(OS.get_user_data_dir().path_join("fifo-%d-%d.log" % [OS.get_process_id(), serial]))
		check(writer != null, "guard real audit writer")
	var sentinels:Array = LoadHelper.load_effects([
		{"effect_name":"fifo_guard_a", "time_points":[TimePoints.DAY_END], "priority":0, "is_pure_passive":not optional, "is_residue":false, "effect_numbers":[], "funcs":[{"func_name":"edit_score","parameters":[null,BaseNumber.new(1),0],"var_index":-1}]},
		{"effect_name":"fifo_guard_b", "time_points":[TimePoints.DAY_START], "priority":0, "is_pure_passive":true, "is_residue":false, "effect_numbers":[], "funcs":[{"func_name":"edit_score","parameters":[null,BaseNumber.new(10),0],"var_index":-1}]}], null, fixture_context)
	check(sentinels.size() == 2 and EffectManager.register_effects(sentinels, 0), "guard two legal sentinels")
	var root:BaseEffect = _command_effect()
	check(root != null and EffectManager.request_manual_activation(root, 0), "guard true original waiting")
	check(not EffectManager.execution_context().ok and EffectManager.execution_runtime_snapshot().functions.is_empty(), "guard no function frame")
	return {"root":root, "sentinels":sentinels, "source":root.from.get_ref() if root.from is WeakRef else root.from}

func stage(point:String) -> void:
	for id in EffectManager.get_all_players_id():
		var data:Dictionary = GameDataManager.find_player_data(id)
		data.dynamic_time_points = [point]
		data.current_time_points = [point]

func facts() -> Array:
	var names:Array = []
	for fact in GameLog.query({"type":"effect"}, null): names.append(fact.data.effect_name)
	return names

func enqueue(c:Dictionary) -> void:
	stage(TimePoints.DAY_END)
	check(EffectManager.run_time_point(c.source, 0, fixture_context, c.root), "guard explicit card source/original root accepted without frame")
	check(TimePointChecker.global_time_point([TimePoints.DAY_START], null, fixture_context), "guard null source second FIFO batch")
	check((EffectManager.waiting_effect == c.root or EffectManager.waiting_location == c.root) and GameDataManager.find_player_data(0).score.number == 0, "guard waiting held before execution")

func positive() -> void:
	var c:Dictionary = open_case(true)
	var original:SessionContext = fixture_context
	check(not is_same(original, c.root.runtime_context()) and is_same(original.token(), c.root.runtime_context().token()), "guard different legal origin context")
	var transaction = EffectManager.capture_transaction_state(original).transaction_bindings.get(c.root)
	check(transaction != null and transaction.root == c.root and not transaction.settled, "guard original root transaction")
	enqueue(c)
	var batches:Array = EffectManager.capture_transaction_state(original).batch_transactions
	check(batches.size() == 2, "guard two FIFO transaction bindings")
	if batches.size() == 2:
		check(is_same(batches[0].transaction, transaction) and is_same(batches[1].transaction, transaction), "guard both batches belong to original transaction")
		check(is_same(batches[0].batch.context, original) and is_same(batches[1].batch.context, original), "guard original context object preserved")
		check(is_same(batches[0].batch.root, c.root) and is_same(batches[1].batch.root, c.root) and is_same(batches[0].batch.source, c.source) and batches[1].batch.source == null, "guard source and root distinct saved identities")
	check(EffectManager.submit_option_choice(c.root, [0]), "guard real option accepted")
	check(GameDataManager.find_player_data(0).score.number == 11, "guard both sentinels truly execute")
	check(Observer.names("fifo_guard_a") == ["edit_score"] and Observer.names("fifo_guard_b") == ["edit_score"] and Observer.names(c.root._name) == ["edit_magic"], "guard three branches exactly once")
	check(facts() == ["fifo_guard_a", "fifo_guard_b", c.root._name], "guard FIFO facts before chosen branch")
	var child_ids:Array = []
	var commits:int = 0
	for record in MatchJournal.audit_records:
		if record.event == "child": child_ids.append(record.root_id)
		if record.event == "commit" and record.root_id == transaction.transaction_id: commits += 1
	check(child_ids == [transaction.transaction_id, transaction.transaction_id], "guard sentinel child audits in original transaction")
	check(commits == 1 and transaction.settled, "guard live root transaction commits once")
	var n:int = GameLog.all_func_calls().size()
	EffectManager.run_pipeline()
	check(GameLog.all_func_calls().size() == n and GameDataManager.find_player_data(0).score.number == 11, "guard idle cannot replay")
	print("FIFO_TRANSACTION ", JSON.stringify(MatchJournal.audit_records))
	end_audit()

func release(cancel:bool) -> void:
	var c:Dictionary = open_case()
	if cancel: check(EffectManager.submit_option_choice(c.root, [2]) and EffectManager.waiting_location == c.root, "guard real location choice opens")
	enqueue(c)
	var accepted:bool = EffectManager.cancel_pending_choice(c.root) if cancel else EffectManager.submit_active_choice(c.root, false)
	check(accepted, "guard cancellation/decline accepted")
	check(not EffectManager.is_waiting_for_choice() and GameDataManager.find_player_data(0).score.number == 11, "guard cancellation/decline advances FIFO")
	check(facts() == ["fifo_guard_a", "fifo_guard_b"], "guard cancelled root has no branch and two sentinel facts")
	var n:int = GameLog.all_func_calls().size()
	EffectManager.run_pipeline()
	check(GameLog.all_func_calls().size() == n, "guard cancelled idle no replay")

func negative() -> void:
	var c:Dictionary = open_case(true)
	stage(TimePoints.DAY_END)
	var audit_before:Array = MatchJournal.audit_records.duplicate(true)
	var transaction = EffectManager.capture_transaction_state(fixture_context).transaction_bindings.get(c.root)
	check(not EffectManager.run_time_point(c.source, 0), "guard missing context rejected")
	check(not EffectManager.run_time_point(c.source, 0, fixture_context, c.sentinels[0]), "guard wrong legal root rejected")
	check(EffectManager.waiting_effect == c.root and EffectManager.capture_transaction_state(fixture_context).batch_transactions.is_empty(), "guard rejects preserve true waiting and no batches")
	check(GameDataManager.find_player_data(0).dynamic_time_points == [TimePoints.DAY_END] and MatchJournal.audit_records == audit_before, "guard rejects consume no transient/audit/control")
	check(is_same(transaction, EffectManager.capture_transaction_state(fixture_context).transaction_bindings.get(c.root)), "guard rejects keep original transaction identity")
	EffectManager.waiting_effect = c.sentinels[0]
	check(not EffectManager.run_time_point(c.source, 0, fixture_context), "guard pseudo waiting rejected without record")
	check(EffectManager.waiting_effect == c.sentinels[0], "guard dispatch rejection never clears waiting")
	EffectManager.waiting_effect = c.root
	var member:Dictionary = GameDataManager.find_player_data(0)
	GameData.player_data_library[0] = GameData.new_player_data()
	check(not EffectManager.run_time_point(c.source, 0, fixture_context, c.root), "guard same ID member replacement rejected")
	check(EffectManager.waiting_effect == c.root, "guard member reject retains original waiting")
	GameData.player_data_library[0] = member
	c.root._selected_players = [1]
	check(not EffectManager.run_time_point(c.source, 0, fixture_context, c.root), "guard changed selection rejected")
	c.root._selected_players = []
	var location = member.location
	member.location = MapData.magic_workshop0
	check(not EffectManager.run_time_point(c.source, 0, fixture_context, c.root), "guard owner location replacement rejected")
	member.location = location
	var map:Array = MapData.areas
	MapData.areas = map.duplicate()
	check(not EffectManager.run_time_point(c.source, 0, fixture_context, c.root), "guard map container replacement rejected")
	MapData.areas = map
	check(EffectManager.waiting_effect == c.root and MatchJournal.audit_records == audit_before and EffectManager.capture_transaction_state(fixture_context).batch_transactions.is_empty(), "guard all rejects retain waiting/transaction/control")
	var count:int = GameLog.query({"type":"time_point"}, null).size()
	EffectManager.waiting_effect = c.sentinels[0]
	check(not TimePointChecker.global_time_point([TimePoints.DAY_START], null, fixture_context), "guard TPC propagates EM rejection")
	check(GameLog.query({"type":"time_point"}, null).size() == count + 1, "guard TPC prewrites visible: not A4 atomic certification")
	EffectManager.waiting_effect = c.root
	end_audit()
	var old:SessionContext = fixture_context
	var fresh:Dictionary = open_case()
	stage(TimePoints.DAY_END)
	check(not EffectManager.run_time_point(c.source, 0, old, c.root), "guard old generation rejected")
	check(EffectManager.waiting_effect == fresh.root and GameDataManager.find_player_data(0).dynamic_time_points == [TimePoints.DAY_END], "guard old generation cannot touch fresh waiting/transients")
	check(not EffectManager.run_time_point(c.source, 0, fixture_context, c.root), "guard new context cannot launder old source/root")

func legacy() -> void:
	end_audit()
	_setup()
	var score = LegacyScore.new(0)
	GameDataManager.find_player_data(0).score = score
	var effects:Array = LoadHelper.load_effects([{"effect_name":"fifo_legacy_frame", "time_points":[], "priority":0, "is_pure_passive":true, "is_residue":false, "effect_numbers":[], "funcs":[{"func_name":"edit_score", "parameters":[null,BaseNumber.new(1),0],"var_index":-1}]}], null, fixture_context)
	check(effects.size() == 1 and EffectManager.register_effect(effects[0], 0), "guard legacy real registered func factory")
	EffectManager.activate_effect(effects[0])
	check(score.accepted == [true,true,true] and SessionGeneration.validate_context(score.original).ok, "guard old 0/1/2 inherit actual validated function frame")
	check(score.number == 1 and not EffectManager.execution_context().ok, "guard legacy leaves no fake frame")
	check(not EffectManager.run_time_point() and not EffectManager.run_time_point(null) and not EffectManager.run_time_point(null, 0), "guard defaults fail closed without function frame")

func secondary_choice() -> void:
	var c:Dictionary = open_case(false, true)
	enqueue(c)
	check(EffectManager.submit_option_choice(c.root, [0]), "guard original choice accepted before nested batch choice")
	check(EffectManager.waiting_effect == c.sentinels[0] and Observer.names(c.root._name).is_empty(), "guard first batch creates real secondary choice and parks root")
	check(EffectManager.submit_active_choice(c.sentinels[0], true), "guard secondary choice accepted")
	check(GameDataManager.find_player_data(0).score.number == 11 and facts() == ["fifo_guard_a", "fifo_guard_b", c.root._name], "guard secondary choice preserves both batches and original root FIFO")
	check(Observer.names(c.root._name) == ["edit_magic"], "guard parked original branch survives batch pool reset exactly once")
	var n:int = GameLog.all_func_calls().size()
	EffectManager.run_pipeline()
	check(GameLog.all_func_calls().size() == n, "guard secondary choice idle cannot replay")

func tpc_sites() -> void:
	var c:Dictionary = open_case()
	check(TimePointChecker.dynamic_time_point([TimePoints.DAY_END], 0, c.source, fixture_context), "guard no-frame dynamic passes original context")
	stage(TimePoints.DAY_START)
	check(TimePointChecker.time_point_check(fixture_context), "guard no-frame check passes original context")
	check(EffectManager.submit_option_choice(c.root, [0]), "guard dynamic/check original choice resolves")
	check(GameDataManager.find_player_data(0).score.number == 11 and facts() == ["fifo_guard_a", "fifo_guard_b", c.root._name], "guard dynamic/check FIFO business executes")

func run() -> void:
	Observer.reset()
	_setup()
	_test_waiting_preserves_following_timepoint()
	positive()
	secondary_choice()
	tpc_sites()
	release(false)
	release(true)
	negative()
	legacy()
	end_audit()
	Observer.finish(get_tree())
