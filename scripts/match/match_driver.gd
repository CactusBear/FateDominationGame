class_name MatchDriver
extends RefCounted

## 无界面的单局推进器。界面节奏闸门由调用者维护，不把窗口状态带入规则。
const Seats = preload("res://scripts/match/seat_controller.gd")
const LocationQuery = preload("res://scripts/game_scene/tactical_board_ui.gd")

signal state_changed
signal ai_turn_started(player_id: int)
signal ai_played_card(player_id: int, card: BaseCard)

var seats = Seats.new()
var step_interval: float = 0.7
var _cooldown: float = 0.0
var _acting: bool = false

func _init(seat_table = null) -> void:
	if seat_table != null:
		seats = seat_table

func step(delta: float) -> bool:
	var action:String = prepare_step(delta)
	if action == "end_current_player_action":
		return GameProgress.end_current_player_action()
	if action == "ai_turn":
		run_bot_turn(GameProgress.current_player_id)
		return true
	return false

## 只判断推进时机及更新表现节奏；返回动作名，由调用方执行或录制。
func prepare_step(delta: float) -> String:
	if _acting or GameProgress.is_game_over or EffectManager.is_waiting_for_choice():
		return ""
	var id: int = GameProgress.current_player_id
	if id < 0 or (not seats.is_ai(id) and not seats.is_local(id)):
		return ""
	var phase_name: String = str(GameProgress.get_current_phase().get("name", ""))
	var acts_here: bool = GameProgress.is_phase_for(id, "outpost") or GameProgress.is_phase_for(id, "action")
	if (phase_name == "battle" or phase_name == "prepare") and not acts_here:
		if not EffectManager.has_manual_activation(id):
			return "end_current_player_action"
		if seats.is_local(id):
			return ""
	elif seats.is_local(id):
		_cooldown = 0.0
		return ""
	_cooldown -= delta
	if _cooldown > 0.0:
		return ""
	_cooldown = step_interval
	return "ai_turn"

## 保留手动 AI 单步入口；正常自动推进必须先通过座位类型判断。
func run_bot_turn(player_id: int) -> void:
	if _acting:
		return
	_acting = true
	ai_turn_started.emit(player_id)
	DummyBot.new().step(self, player_id)
	_acting = false

func answer_effect(pending: BaseEffect) -> bool:
	if pending == null or not seats.is_ai(pending._trigger_player_id):
		return false
	DummyBot.new().resolve_active_effect(pending, pending._trigger_player_id)
	return true

func answer_card(pending: Dictionary) -> bool:
	if not _bot_owns_request(pending):
		return false
	DummyBot.new().resolve_card_selection(pending)
	return true

func answer_player(pending: Dictionary) -> bool:
	if not _bot_owns_request(pending):
		return false
	DummyBot.new().resolve_player_selection(pending)
	return true

func answer_location(pending: Dictionary) -> bool:
	if not _bot_owns_request(pending):
		return false
	DummyBot.new().resolve_location_selection(pending, self)
	return true

func _bot_owns_request(pending: Dictionary) -> bool:
	var effect: BaseEffect = pending.get("effect")
	return effect != null and seats.is_ai(effect._trigger_player_id)

func answer_pending_for_bots() -> bool:
	# 每次提交后重新读下一个等待项，不能提前快照四份请求。
	var changed := answer_effect(EffectManager.get_pending_active_effect())
	changed = answer_card(EffectManager.get_pending_card_selection()) or changed
	changed = answer_player(EffectManager.get_pending_player_selection()) or changed
	changed = answer_location(EffectManager.get_pending_location_selection()) or changed
	return changed

# DummyBot 宿主契约：复用已有查询和操作，表现通过信号交给界面。
func ai_deploy_areas() -> Array:
	var areas: Array = []
	for area: BaseMapArea in MapData.areas:
		if not DeployRules.open_locations(area).is_empty():
			areas.append(area)
	return areas

func ai_pick_deploy_location(area: BaseMapArea) -> BaseLocation:
	return DeployRules.pick_location(area)

func ai_apply_deploy_benefit(loc: BaseLocation, player_id: int) -> void:
	DeployRules.apply_benefit(loc, player_id)

func ai_pick_effect_location(spec: Dictionary) -> BaseLocation:
	var forbidden: Array = spec.get("forbidden_target_areas", []) as Array
	for area: BaseMapArea in MapData.areas:
		if forbidden.has(str(area._area_name)):
			continue
		var target: BaseLocation = LocationQuery._first_effect_location_target(area, spec)
		if target != null:
			return target
	return null

func ai_record_played_card(player_id: int, card: BaseCard) -> void:
	ai_played_card.emit(player_id, card)

func refresh_all_ui() -> void:
	state_changed.emit()
