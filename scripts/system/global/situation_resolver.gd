class_name SituationResolver
extends RefCounted

const ROUTER = preload("res://scripts/system/operation_router.gd")

# 保存原卡、原牌堆、原 map 和原 context；工厂与消费职责分开。
func activate(context:SessionContext = null) -> Dictionary:
	var state:Dictionary = {"ok":true, "completed":false, "context":context, "areas":MapData.areas,
		"deck":MapData.situations, "players":GameDataManager.get_active_player_ids(), "index":0}
	if not _source(state): return state
	var drawn:Dictionary = _draw_current(context)
	if not drawn.ok:
		_refuse(state, drawn.reason)
		return state
	var situation:BaseSituation = drawn.object
	if situation == null:
		MapData.active_situation = null
		state.completed = true
		return state
	state["situation"] = situation
	var action:Dictionary = EffectManager.begin_pending_action(TimePoints.BEFORE_SITUATION_ACTIVATE, -1, {"situation":situation}, situation)
	if not _source(state): return state
	if action.get("invalidated", false):
		_refuse(state, &"operation_rejected")
		return state
	if action.get("cancelled", false):
		MapData.situation_discard.append(situation)
		MapData.active_situation = null
		state.completed = true
		return state
	MapData.active_situation = situation
	_resume_activation(state)
	return state

static func _refuse(state:Dictionary, reason:StringName) -> void:
	state["ok"] = false
	state["reason"] = reason
	state["completed"] = true

static func _source(state:Dictionary) -> bool:
	var status:Dictionary = SessionGeneration.validate_context(state.get("context"))
	if not status.ok:
		_refuse(state, status.reason)
		return false
	if not is_same(state.get("areas"), MapData.areas) or not is_same(state.get("deck"), MapData.situations):
		_refuse(state, &"unbound_origin")
		return false
	return state.get("ok", false)

static func _resume_activation(state:Dictionary) -> void:
	if not _source(state): return
	var situation:BaseSituation = state.situation
	if not SetCardConcealed.source_is_current(situation, state.context) or not is_same(MapData.active_situation, situation):
		_refuse(state, &"unbound_origin")
		return
	while state.index < state.players.size():
		if not _source(state): return
		var id:int = state.players[state.index]
		var operation:Dictionary = GameProgress.start_progress_operation("edit_magic", [null, situation._magic, id], state.context)
		var edited:Dictionary = await GameProgress.wait_progress_operation(operation, false)
		if not _source(state): return
		if not edited.ok or (edited.value is bool and edited.value == false):
			_refuse(state, &"operation_rejected")
			return
		state.index += 1
		while SessionGeneration.validate_context(state.context).ok and (EffectManager.is_running or EffectManager.is_waiting_for_choice()):
			await GameProgress.get_tree().process_frame
		if not _source(state): return
	var gain = situation._magic.number
	if gain != 0: EffectManager.push_message("局势牌【%s】：全员魔力 %+d" % [situation.get_shown_name(), gain])
	if not _register_situation_effects(situation, state.context):
		_refuse(state, &"unbound_origin")
		return
	TimePointChecker.card_revealed(situation, state.context)
	while SessionGeneration.validate_context(state.context).ok and (EffectManager.is_running or EffectManager.is_waiting_for_choice()):
		await GameProgress.get_tree().process_frame
	if not _source(state): return
	TimePointChecker.global_time_point([TimePoints.SITUATION_ACTIVATED], situation, state.context)
	if not _source(state): return
	state.completed = true

func _draw_current(context:SessionContext) -> Dictionary:
	var status:Dictionary = SessionGeneration.validate_context(context)
	if not status.ok: return {"ok":false, "object":null, "reason":status.reason}
	if LoadSituation.climax_situations.has(GameProgress.current_round):
		return MapData.copy_climax(GameProgress.current_round, context)
	if MapData.situations.is_empty(): return {"ok":true, "object":null}
	# 非高潮牌堆已经是 runtime；只能继承，不能 configure_template 重签。
	var copied:Dictionary = CloneContext.new().copy_result(MapData.situations[0], context)
	if copied.ok: MapData.situations.pop_front()
	return copied

static func _register_situation_effects(situation:BaseSituation, context:SessionContext) -> bool:
	if not SetCardConcealed.source_is_current(situation, context): return false
	var ids:Array = GameDataManager.get_active_player_ids()
	if ids.is_empty(): return true
	for effect in situation._effects:
		if not SessionGeneration.validate_context(context).ok: return false
		if effect._trigger_player_id == -1 and not EffectManager.register_effect(effect, int(ids[0])): return false
	return true

func clear_all(context:SessionContext = null) -> Dictionary:
	var state:Dictionary = {"ok":true, "context":context, "areas":MapData.areas, "deck":MapData.situations}
	if not _source(state): return state
	var situation = MapData.active_situation
	if situation == null: return state
	if not SetCardConcealed.source_is_current(situation, context):
		_refuse(state, &"unbound_origin")
		return state
	ROUTER.exec_registered("unregister_object_effects", [situation], context)
	if not _source(state): return state
	MapData.situation_discard.append(situation)
	MapData.active_situation = null
	ROUTER.exec_registered("restore_map_area_move_flags", [], context)
	if not _source(state): return state
	ROUTER.exec_registered("restore_location_pl_num_limits", [], context)
	_source(state)
	return state
