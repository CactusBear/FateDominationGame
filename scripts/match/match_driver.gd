class_name MatchDriver
extends RefCounted

## 无界面的单局推进器。界面节奏闸门由调用者维护，不把窗口状态带入规则。
const Seats = preload("res://scripts/match/seat_controller.gd")

signal state_changed
signal ai_turn_started(player_id: int)
signal ai_played_card(player_id: int, card: BaseCard)

var seats = Seats.new()
var step_interval: float = 0.7
var _cooldown: float = 0.0
var _acting: bool = false
var _answering_effect:bool = false
var _answering_selection:bool = false
var _location_query_source: Dictionary = {}
var _location_query_spec: Dictionary = {}
var source_context: SessionContext = null
# AI 每次出牌搜索的节点预算；默认与正式 AI 相同，调用方可调小（测试墙钟）。
var ai_search_budget: int = preload("res://scripts/system/ai/group_search.gd").NODE_BUDGET

func _init(seat_table = null, captured_context: SessionContext = null) -> void:
	if seat_table != null:
		seats = seat_table
	# 创建边界保存成功开局的原来源；延期消费不重新领票。
	source_context = captured_context if captured_context != null else GameStart.startup_context()

static func capture_runtime_context() -> SessionContext:
	var seen: Array = []
	var guard_effect = EffectManager.runtime_guard_effect()
	var from_guard: SessionContext = _context_from_value(guard_effect, seen, 0)
	if from_guard != null:
		return from_guard
	for player_id in GameData.player_data_library:
		var context: SessionContext = _context_from_value(GameData.player_data_library[player_id], seen, 0)
		if context != null:
			return context
	return null

static func _context_from_value(value, seen: Array, depth: int) -> SessionContext:
	if value == null or depth > 4:
		return null
	if value is SessionContext:
		return value if SessionGeneration.validate_context(value).get("ok", false) else null
	if value is Object:
		if seen.has(value):
			return null
		seen.append(value)
		var origin: Dictionary = SessionGeneration.origin_of(value)
		return origin.context if origin.get("ok", false) else null
	if value is Dictionary:
		for nested in value.values():
			var nested_context: SessionContext = _context_from_value(nested, seen, depth + 1)
			if nested_context != null:
				return nested_context
	elif value is Array:
		for nested in value:
			var nested_context: SessionContext = _context_from_value(nested, seen, depth + 1)
			if nested_context != null:
				return nested_context
	return null

func _source_is_current() -> bool:
	return SessionGeneration.validate_context(source_context).get("ok", false)

func step(delta: float) -> bool:
	if not _source_is_current():
		return false
	var action:String = prepare_step(delta)
	if action == "end_current_player_action":
		return GameProgress.end_current_player_action(source_context)
	if action == "ai_turn":
		run_bot_turn(GameProgress.current_player_id)
		return true
	return false

## 只判断推进时机及更新表现节奏；返回动作名，由调用方执行或录制。
func prepare_step(delta: float) -> String:
	if not _source_is_current() or _acting or GameProgress.is_game_over or EffectManager.is_waiting_for_choice():
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
	if not _source_is_current() or _acting:
		return
	_acting = true
	ai_turn_started.emit(player_id)
	_bot().step(self, player_id)
	_acting = false

## v2 分帧入口；回放及旧调用仍使用同步 run_bot_turn。
func run_bot_turn_async(player_id:int, tree:SceneTree) -> void:
	if not _source_is_current() or _acting: return
	_acting = true
	ai_turn_started.emit(player_id)
	await _bot().step_async(self,player_id,tree)
	_acting = false

func answer_effect_async(pending:BaseEffect,tree:SceneTree) -> bool:
	if _acting or _answering_effect or not _source_is_current() or pending == null or not seats.is_ai(pending._trigger_player_id): return false
	if not _pending_source_is_current({"effect":pending}): return false
	_answering_effect = true
	await _bot().resolve_active_effect_async(pending,pending._trigger_player_id,tree)
	_answering_effect = false
	return true

func answer_effect(pending: BaseEffect) -> bool:
	if not _source_is_current() or pending == null or not seats.is_ai(pending._trigger_player_id):
		return false
	var origin: Dictionary = SessionGeneration.origin_of(pending)
	if not origin.get("ok", false) or not SessionGeneration.validate_context(origin.get("context")).get("ok", false):
		return false
	_bot().resolve_active_effect(pending, pending._trigger_player_id)
	return true

func answer_selection_async(kind:String,pending:Dictionary,tree:SceneTree) -> bool:
	if _acting or _answering_selection or not _source_is_current() or not _bot_owns_request(pending) or not _pending_source_is_current(pending): return false
	_answering_selection = true
	await _bot().resolve_selection_async(kind,pending,tree)
	_answering_selection = false
	return true

func answer_card(pending: Dictionary) -> bool:
	if not _source_is_current() or not _bot_owns_request(pending):
		return false
	if not _pending_source_is_current(pending):
		return false
	_bot().resolve_card_selection(pending)
	return true

func answer_player(pending: Dictionary) -> bool:
	if not _source_is_current() or not _bot_owns_request(pending):
		return false
	if not _pending_source_is_current(pending):
		return false
	_bot().resolve_player_selection(pending)
	return true

func answer_location(pending: Dictionary) -> bool:
	if not _source_is_current() or not _bot_owns_request(pending):
		return false
	var original:Dictionary = AreaActionRules.get_pending_location_selection()
	if original.is_empty() or original.effect != pending.get("effect") or not is_same(original.spec, pending.get("spec")):
		return false
	var source:Dictionary = SessionGeneration.origin_of(pending.effect)
	if not source.ok or not SessionGeneration.validate_context(source.context).ok or not is_same(source.context.token(), source_context.token()):
		return false
	# 同步 AI 选点只消费这份原请求；嵌套答复结束后恢复外层来源。
	var previous_source:Dictionary = _location_query_source
	var previous_spec:Dictionary = _location_query_spec
	_location_query_source = source
	_location_query_spec = pending.spec
	_bot().resolve_location_selection(pending, self)
	_location_query_source = previous_source
	_location_query_spec = previous_spec
	return true

func _pending_source_is_current(pending: Dictionary) -> bool:
	var effect: BaseEffect = pending.get("effect")
	if effect == null:
		return false
	var source: Dictionary = SessionGeneration.origin_of(effect)
	return source.get("ok", false) and SessionGeneration.validate_context(source.get("context")).get("ok", false) and is_same(source.context.token(), source_context.token())

func _bot_owns_request(pending: Dictionary) -> bool:
	var effect: BaseEffect = pending.get("effect")
	return effect != null and seats.is_ai(effect._trigger_player_id)

func answer_pending_for_bots() -> bool:
	if not _source_is_current():
		return false
	# 每次提交后重新读下一个等待项，不能提前快照四份请求。
	var changed := answer_effect(EffectManager.get_pending_active_effect())
	changed = answer_card(EffectManager.get_pending_card_selection()) or changed
	changed = answer_player(EffectManager.get_pending_player_selection()) or changed
	changed = answer_location(EffectManager.get_pending_location_selection()) or changed
	changed = confirm_broadcast_for_bots() or changed
	return changed

## 战斗播报屏障：AI 席位与真人一样需要确认；资格与批次由 GameProgress 判定，这里只代 AI 席位提交。
## 真人席位不代确认。与 match_authority / local_battle_commands 走同一个批次确认入口。
func confirm_broadcast_for_bots() -> bool:
	if not _source_is_current() or not GameProgress.is_battle_broadcast_pending():
		return false
	var batch:int = GameProgress.battle_broadcast_batch_id()
	var changed := false
	for seat in GameProgress.battle_broadcast_confirmers():
		if seat is int and seats.is_ai(seat) and GameProgress.can_confirm_battle_broadcast(seat, batch):
			changed = GameProgress.confirm_battle_broadcast_batch(seat, batch) or changed
			if not GameProgress.is_battle_broadcast_pending():
				break
	return changed

func _bot():
	var bot = DummyBot.new(source_context)
	bot.search_budget = ai_search_budget
	return bot

# DummyBot 宿主契约：复用已有查询和操作，表现通过信号交给界面。
func ai_deploy_areas() -> Array:
	if not _source_is_current():
		return []
	var areas: Array = []
	for area: BaseMapArea in MapData.areas:
		if not DeployRules.open_locations(area).is_empty():
			areas.append(area)
	return areas

func ai_pick_deploy_location(area: BaseMapArea) -> BaseLocation:
	return DeployRules.pick_location(area) if _source_is_current() else null

func ai_apply_deploy_benefit(loc: BaseLocation, player_id: int) -> void:
	if not _source_is_current():
		return
	DeployRules.apply_benefit(loc, player_id)

func ai_pick_effect_location(spec: Dictionary) -> BaseLocation:
	if not _source_is_current():
		return null
	var source:Dictionary = _location_query_source
	if not source.get("ok", false) or not SessionGeneration.validate_context(source.get("context")).get("ok", false) or not is_same(source.context.token(), source_context.token()) or not is_same(spec, _location_query_spec):
		return null
	var forbidden: Array = spec.get("forbidden_target_areas", []) as Array
	for area: BaseMapArea in MapData.areas:
		if forbidden.has(str(area._area_name)):
			continue
		var target: BaseLocation = AreaActionRules.first_effect_location_target(area, spec, source.context)
		if target != null:
			return target
	return null

func ai_record_played_card(player_id: int, card: BaseCard) -> void:
	ai_played_card.emit(player_id, card)

func refresh_all_ui() -> void:
	state_changed.emit()
