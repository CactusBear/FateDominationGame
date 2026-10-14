extends Node
const Plan = preload("res://scripts/system/atomic_action_plan.gd")
const Domain = preload("res://scripts/system/atomic_execution_domain.gd")
var checks:int = 0
var failures:Array = []

class ResetReceiver:
	extends Node
	var calls:int = 0
	var mode:String
	var original_context:SessionContext
	var receipt:Dictionary = {}
	var trigger:int:
		set(_value):
			calls += 1
			receipt = GameProgress.reset_progress(true, original_context if mode == "same_context_reset" else null, &"invalidate" if mode == "invalidate" else &"begin")

class Participant:
	extends RefCounted
	var host:Node
	var mode:String
	var context:SessionContext
	var service:Variant
	var gp:Dictionary
	var gd:Dictionary
	var map:Dictionary
	var targets:Array
	var reset_result:Dictionary = {}
	var observations:Dictionary = {}
	var continuation:RefCounted = RefCounted.new()
	var receiver:Node
	func _init(owner:Node, selected:String, source:SessionContext):
		host = owner; mode = selected; context = source
		if selected in ["reset","invalidate","same_context_reset"]:
			receiver = ResetReceiver.new()
			receiver.mode = mode
			receiver.original_context = source
	func validate_original_context(candidate:Variant) -> Dictionary:
		if not is_same(candidate, context) or not SessionGeneration.validate_original_context(candidate).ok:
			return {"status":"REJECTED", "reason":"invalid_original"}
		return {"status":"COMPLETED", "reason":""}
	func open_domain(domain, source:Variant, _closure:Variant, _support:Dictionary) -> Dictionary:
		var opened:Dictionary = SessionGeneration.open_private_lifecycle(domain, source)
		if opened.status != "COMPLETED": return opened
		service = opened.service
		targets = [GameProgress.publication_backing(), GameData.publication_backing(), MapData.publication_backing()]
		gp = host.copy_plain(targets[0])
		gd = host.copy_plain(targets[1])
		# 这些是专项的受信最小成员数据，不声称本夹具证明全仓可执行图。
		gd.player_data_library = {17:GameData.new_player_data(), 18:GameData.new_player_data()}
		gd.player_data_library[17].is_out = false
		gd.player_data_library[18].is_out = false
		gd.player_data_library[17].order.number = 2
		gd.player_data_library[18].order.number = 1
		# MapArea 构造的自动登记必须同样落 D；先绑定分配帧，构造后关闭。
		var allocation = Domain.new()
		allocation.bind_dependency(targets[2], {"areas":[]})
		var entered:Dictionary = allocation.enter_frame(RefCounted.new(), source)
		map = host.copy_plain(targets[2])
		Domain.leave_frame(entered.frame_marker)
		allocation.discard()
		for pair in [[GameProgress,gp], [GameData,gd], [MapData,map]]:
			var bound:Dictionary = pair[0].bind_domain_model(domain, pair[1])
			if bound.status != "COMPLETED": return bound
		return {"status":"COMPLETED", "reason":""}
	func prepare(domain, _closure:Variant, source:Variant) -> Dictionary:
		var authenticated:Dictionary = SessionGeneration.validate_context(source)
		if not authenticated.ok: return {"status":"REJECTED", "reason":str(authenticated.reason)}
		if mode == "reset" or mode == "same_context_reset" or mode == "invalidate":
			host.seed_progress(gp)
			receiver.trigger = 1
			reset_result = receiver.receipt
			observations.original_valid = SessionGeneration.validate_original_context(source).ok
			observations.original_same = is_same(service.original_context, source)
			observations.status = service.diagnostic_status()
			if mode != "same_context_reset": observations.second_reset = GameProgress.reset_progress()
			# finish_reset 之后 P0 已 ABORTED，返回 COMPLETED 也不能把旧 P 复活。
			return {"status":"COMPLETED", "reason":""}
		if mode == "pending": return {"status":"PENDING", "reason":"", "continuation":continuation}
		if mode == "bypass":
			observations.startup = GameProgress.start_game(source)
			observations.runtime = GameData.reset_game_session([17], source)
			observations.factory = MapData.reset_event_deck(source)
			observations.bind = SessionGeneration.bind_origin(RefCounted.new(), source.token(), &"forbidden")
			observations.derive = SessionGeneration.derive_context(source, &"forbidden")
			return {"status":"UNSUPPORTED", "reason":"missing_service_closure"}
		GameProgress.current_round = 43
		GameData.player_num = 2
		GameDataManager.get_player_data(17).player_name = "private"
		MapData.event_deck.append("private-deck")
		MapData.event_discard.append("private-discard")
		MapData.areas[0]._locations[0]._players.append(17)
		observations.ids = GameDataManager.get_active_player_ids()
		observations.unknown = GameDataManager.get_player_data(999)
		observations.member_count = GameData.player_data_library.size()
		observations.phase = GameProgress.current_round
		if mode == "early_commit":
			observations.child = Plan.begin(source, {}, RefCounted.new())
			observations.commit = Plan.commit(Domain.current_frame().plan_identity)
		return {"status":"COMPLETED", "reason":""}
	func resume(_domain, _continuation:Variant, _input:Variant, _source:Variant) -> Dictionary:
		return {"status":"COMPLETED", "reason":""}
	func seal(domain, source:Variant) -> Dictionary:
		var current:Dictionary = validate_original_context(source)
		if current.status != "COMPLETED": return current
		if mode != "write": return {"status":"UNSUPPORTED", "reason":"unproven_publication"}
		# 仅此标量写集已证 reverse M；其它模型图写集保持 unsupported。
		var staged:Dictionary = domain.stage_slot(targets[0], "current_round", gp.current_round, &"rule")
		return staged

func check(label:String, value:bool) -> void:
	checks += 1
	print("CHECK ", label, " ", value)
	if not value: failures.append(label)

func source() -> SessionContext:
	var begun:Dictionary = SessionGeneration.begin_generation(&"a4-p1l3.fixture")
	return SessionGeneration.derive_context(begun.token, &"a4-p1l3.original").context

func begin(p:Participant) -> Dictionary:
	var registered:Dictionary = Plan.register_participant_manifest({"adapter":p, "support_manifest":{
		"abi_version":1, "status":"supported", "proof":"owner_registered_closed_domain",
		"source_validation":{"abi_version":1, "read_only":true, "validator_script":p.get_script()},
		"required_roots":["fixture-models"], "required_adapters":["fixture-only"], "state_domains":["fixture"], "participants":["fixture"]}})
	return Plan.begin(p.context, {}, registered.participant_manifest)

# 夹具显式复制本专项模型 schema；无执行代码/Callable 授权，不代替 P1-G。
func copy_plain(value:Variant, memo:Array = []) -> Variant:
	if value is Array or value is Dictionary or value is Object:
		for pair in memo:
			if is_same(pair[0], value): return pair[1]
	else: return value
	var cloned:Variant
	if value is BaseNumber:
		cloned = BaseNumber.new(value.number, value.can_change, value.is_pure_number)
		cloned.is_float = value.is_float
		memo.append([value,cloned]); return cloned
	if value is Array:
		cloned = []; memo.append([value,cloned])
		for item in value: cloned.append(copy_plain(item,memo))
		return cloned
	if value is Dictionary:
		cloned = {}; memo.append([value,cloned])
		for key in value: cloned[key] = copy_plain(value[key],memo)
		return cloned
	if value is BaseMapArea: cloned = BaseMapArea.new(value._area_name)
	elif value is BaseLocation: cloned = BaseLocation.new()
	else:
		# 未使用的对象表属于夹具边界；不把 opaque 对象洗成执行许可。
		cloned = RefCounted.new(); memo.append([value,cloned]); return cloned
	memo.append([value,cloned])
	for prop in value.get_property_list():
		if int(prop.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE and prop.name != "from" and not str(prop.name).begins_with("_from_"):
			cloned.set(prop.name, copy_plain(value.get(prop.name),memo))
	var parent:Variant = value.from
	if parent != null: cloned.from = copy_plain(parent,memo)
	return cloned

func seed_progress(state:Dictionary) -> void:
	for key in ["is_game_over","has_battle_resolved","_phase_end_pending","_phase_end_dispatched","_phase_player_end_dispatched","_phase_end_running","_round_end_running","_battle_broadcast_pending"]: state[key] = true
	for key in ["current_round","current_phase_index","current_phase_player_index","current_player_id","_battle_result_state"]: state[key] = 9
	state._round_start_state = {"pending":true}
	state._battle_broadcast_confirmed = [17]
	state._deploy_time_points_dispatched = {"old":true}
	state.last_battle_result = {"old":true}
	state._session_serial = 71

func verify_clear(p:Participant) -> void:
	check("real original Node setter once",p.receiver.calls == 1)
	check("real reset returned ok", p.reset_result.get("ok",false))
	check("reset returns original context", is_same(p.reset_result.get("context"),p.context))
	for key in ["is_game_over","has_battle_resolved","_phase_end_pending","_phase_end_dispatched","_phase_player_end_dispatched","_phase_end_running","_round_end_running","_battle_broadcast_pending"]:
		check("real clear "+key, p.gp[key] == false)
	for pair in [["current_round",0],["current_phase_index",-1],["current_phase_player_index",0],["current_player_id",-1],["_battle_result_state",-1],["_session_serial",72]]:
		check("real clear "+pair[0], p.gp[pair[0]] == pair[1])
	for key in ["_round_start_state","_battle_broadcast_confirmed","_deploy_time_points_dispatched","last_battle_result"]:
		check("real clear "+key, p.gp[key].is_empty())
	check("real clear requires confirm", p.gp.battle_broadcast_requires_confirm)
	check("real clear consumer", p.gp._battle_broadcast_consumer == null)
	check("original provenance valid after private reset", p.observations.original_valid and p.observations.original_same)

func _ready() -> void:
	print("USER_DATA_DIR ",OS.get_user_data_dir())
	check("user data physically configured on E",OS.get_user_data_dir().replace("\\", "/").begins_with("E:/"))
	if not GameProgress.has_method("publication_backing") or not SessionGeneration.new().has_method("open_private_lifecycle"):
		check("P1-L domain lifecycle and backing implemented",false)
		finish(); return
	var ctx:SessionContext = source()
	var forged := SessionContext.new(ctx.token(),ctx.origin())
	check("forged same shape context rejected", not SessionGeneration.validate_original_context(forged).ok)
	check("dictionary context rejected", not SessionGeneration.validate_original_context({"token":ctx.token(),"origin":ctx.origin()}).ok)
	check("original registry identity accepted", SessionGeneration.validate_original_context(ctx).ok)
	var original_metadata:Dictionary = SessionGeneration.lifecycle_diagnostics()
	var originals:Array = [GameProgress.publication_backing(),GameData.publication_backing(),MapData.publication_backing()]
	var live_deck:Array = MapData.event_deck.duplicate()
	var live_discard:Array = MapData.event_discard.duplicate()
	var live_seats:Array = []
	for area in MapData.areas:
		for loc in area._locations: live_seats.append([loc,loc._players.duplicate(),loc._players])
	var baseline:Array = []
	for item in originals: baseline.append(item.duplicate())
	for mode in ["reset","invalidate","same_context_reset"]:
		var p := Participant.new(self,mode,ctx)
		var planned:Dictionary = begin(p)
		var result:Dictionary = Plan.prepare(planned.plan_identity)
		verify_clear(p)
		if mode != "same_context_reset":
			check(mode+" old P ABORTED",result.state == "ABORTED")
			check(mode+" no commit possible",Plan.commit(planned.plan_identity).state == "ABORTED")
			check(mode+" sticky receipt",is_same(result.receipt,Plan.prepare(planned.plan_identity).receipt))
			check(mode+" revoked one epoch",p.observations.status.revoked_epochs == 1)
			check(mode+" real execution sequence",p.observations.status.steps == [&"authenticate_original",&"revoke_private_epoch",&"allocate_private_epoch" if mode == "reset" else &"invalidate_private_epoch",&"clear_progress_values",&"abort_old_plan"])
			check(mode+" revoked source cannot revive",not p.service.source_status(ctx).ok)
			check(mode+" second reset cannot revive",not p.observations.second_reset.ok)
			check(mode+" forged private context rejected",not p.service.source_status(forged).ok)
		else:
			check("explicit original context no second generation",result.state == "PREPARED" and p.observations.status.revoked_epochs == 0)
			Plan.abort(planned.plan_identity,"fixture_cleanup")
		check("context still live after "+mode,SessionGeneration.validate_original_context(ctx).ok)
		var metadata:Dictionary = SessionGeneration.lifecycle_diagnostics()
		check(mode+" live token identity unchanged",is_same(metadata.token,original_metadata.token))
		for key in ["bindings","contexts","issued_tokens"]: check(mode+" no L registration "+key,metadata[key] == original_metadata[key])
		for i in range(3):
			check(mode+" L root identity "+str(i),is_same(originals[i],[GameProgress.publication_backing(),GameData.publication_backing(),MapData.publication_backing()][i]))
			check(mode+" L scalar/container unchanged "+str(i),originals[i] == baseline[i])
		p.receiver.free()
	var writer := Participant.new(self,"write",ctx)
	var opened:Dictionary = begin(writer)
	var prepared:Dictionary = Plan.prepare(opened.plan_identity)
	check("write PREPARED not committed",prepared.state == "PREPARED" and prepared.receipt == null)
	check("D GameData write observed",writer.gd.player_num == 2 and writer.gd.player_data_library[17].player_name == "private")
	check("D GameDataManager reads D order",writer.observations.ids == [18,17])
	check("D unknown getter does not create",writer.observations.unknown.is_empty() and writer.observations.member_count == 2)
	check("D MapData write observed",writer.map.event_deck.has("private-deck") and writer.map.event_discard.has("private-discard"))
	check("D nested map seat write observed",writer.map.areas[0]._locations[0]._players.has(17))
	for i in range(3): check("D writes zero L leak "+str(i),originals[i] == baseline[i])
	check("D member never appears in L",not GameData.player_data_library.has(17))
	check("D deck append leaves L contents",MapData.event_deck == live_deck and MapData.event_discard == live_discard)
	for i in range(live_seats.size()):
		check("D nested seat leaves L contents "+str(i),live_seats[i][0]._players == live_seats[i][1] and is_same(live_seats[i][0]._players,live_seats[i][2]))
	var committed:Dictionary = Plan.commit(opened.plan_identity)
	check("only core commit produces receipt",committed.state == "COMMITTED" and committed.receipt.state == "COMMITTED")
	check("backing install visible through original facade",GameProgress.current_round == 43)
	check("unique receipt on replay",is_same(committed.receipt,Plan.commit(opened.plan_identity).receipt))
	check("publication window released after receipt",not Domain.publication_is_open())
	for mode in ["bypass","early_commit"]:
		var negative := Participant.new(self,mode,ctx)
		var plan:Dictionary = begin(negative)
		var rejected:Dictionary = Plan.prepare(plan.plan_identity)
		check(mode+" cannot bypass core receipt",rejected.state == "ABORTED" and rejected.receipt.state == "ABORTED")
		if mode == "bypass":
			for key in ["startup","runtime","factory","bind","derive"]:
				check("missing D service rejects "+key,not negative.observations[key].ok)
		else:
			check("child independent plan unsupported",negative.observations.child.status == "UNSUPPORTED")
			check("prepare early commit aborts",negative.observations.commit.state == "ABORTED")
	var root_wait := Participant.new(self,"pending",ctx)
	var rp:Dictionary = begin(root_wait)
	check("pending before protected root replacement",Plan.prepare(rp.plan_identity).state == "PENDING")
	var original_members:Dictionary = GameData.player_data_library
	GameData.player_data_library = original_members.duplicate()
	check("root replacement immediately aborts P",Plan.inspect(rp.plan_identity).state == "ABORTED")
	GameData.player_data_library = original_members
	check("root changed back does not revive P",is_same(GameData.player_data_library,original_members) and Plan.inspect(rp.plan_identity).state == "ABORTED")
	check("root barrier preserves original live context",SessionGeneration.validate_original_context(ctx).ok)
	var pending := Participant.new(self,"pending",ctx)
	var pp:Dictionary = begin(pending)
	check("real pending before L barrier",Plan.prepare(pp.plan_identity).state == "PENDING")
	var newer:SessionContext = source()
	check("live barrier immediately aborts pending",Plan.inspect(pp.plan_identity).state == "ABORTED")
	check("live source revoked one way",not SessionGeneration.validate_original_context(ctx).ok and SessionGeneration.validate_original_context(newer).ok)
	check("old pending cannot borrow newer context",Plan.resume(pp.plan_identity,{},newer).state == "ABORTED")
	var missing = Domain.new()
	var frame:Dictionary = missing.enter_frame(RefCounted.new(),newer)
	check("unbound model is unsupported no L fallback",GameData.domain_model_status().status == "UNSUPPORTED")
	check("unbound reset fails before live mutation",not GameProgress.reset_progress().ok)
	check("raw L backing not exposed in D",GameData.publication_backing().is_empty())
	Domain.leave_frame(frame.frame_marker)
	missing.discard()
	finish()

func finish() -> void:
	print("RESULT ",JSON.stringify({"suite":"A4-P1-L3","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
