class_name MatchSeatQuery
extends RefCounted

## 与连接无关的座位只读投影；builder 与视图共享稳定对象 ID。
var builder
var _payments: Dictionary = {}

# 可信查询创建边界：本地缺省只交接成功开局保存的原值；其它创建者显式注入。
# 构造时捕获成员/magic 身份，延期不重新取当前票或重新报价。
func _init(view_builder, original_context: Variant = null) -> void:
	builder = view_builder
	var source: Variant = original_context if original_context != null else GameStart.startup_context()
	if not SessionGeneration.validate_context(source).ok:
		return
	for seat in GameData.player_data_library:
		var payment: Dictionary = RegularPlay.payment_quote(seat, source)
		if not payment.is_empty():
			payment.make_read_only()
			_payments[seat] = payment

func payment_quote(seat: int) -> Dictionary:
	var payment: Dictionary = _payments.get(seat, {})
	return payment if RegularPlay.payment_quote_is_current(seat, payment) else {}

func _card_choice_secret(pending: Dictionary) -> bool:
	var effect: BaseEffect = pending.get("effect")
	var index: int = int(pending.get("option_index",-1))
	return effect != null and index >= 0 and index < effect._options.size() and effect._options[index].get("tags",[]).has("secret_choice")

func _card_choice_confirm_text(pending: Dictionary) -> String:
	var effect: BaseEffect = pending.get("effect")
	var index: int = int(pending.get("option_index",0))
	var option_label: String = ""
	if effect != null and index >= 0 and index < effect._options.size(): option_label = str(effect._options[index].get("shown_option_name",""))
	return ChoiceText.card_confirm(str(pending.get("verb","")),option_label)

func pending(seat: int) -> Dictionary:
	if seat < 0:
		return {}
	var location_pending: Dictionary = EffectManager.get_pending_location_selection()
	if not location_pending.is_empty() and location_pending.effect._trigger_player_id == seat:
		return {"kind": "location_choice", "effect": builder.ids.id_for(location_pending.effect), "label": location_pending.effect.get_shown_name(), "areas": location_candidates(location_pending).keys(), "allow_cancel": location_pending.allow_cancel}
	var player_pending: Dictionary = EffectManager.get_pending_player_selection()
	if not player_pending.is_empty() and player_pending.effect._trigger_player_id == seat:
		var low: int = int(player_pending.spec.get("min", 1))
		return {"kind": "player_choice", "effect": builder.ids.id_for(player_pending.effect), "label": player_pending.effect.get_shown_name(), "players": player_pending.candidates.duplicate(), "min": low, "max": int(player_pending.spec.get("max", low)), "allow_cancel": player_pending.allow_cancel}
	var card_pending: Dictionary = EffectManager.get_pending_card_selection()
	if not card_pending.is_empty() and card_pending.effect._trigger_player_id == seat:
		var cards: Array = []
		var required: Array = []
		for card in card_pending.cards:
			cards.append(builder.ids.id_for(card))
		for card in card_pending.required_cards:
			required.append(builder.ids.id_for(card))
		return {"kind": "card_choice", "effect": builder.ids.id_for(card_pending.effect), "label": str(card_pending.shown_name), "cards": cards, "required": required, "min": card_pending.min, "max": card_pending.max, "allow_cancel": card_pending.allow_cancel, "card_views": builder.choice_cards(card_pending.cards, seat), "verb": str(card_pending.get("verb", "选择")), "secret": _card_choice_secret(card_pending), "confirm_text": _card_choice_confirm_text(card_pending)}
	var effect: BaseEffect = EffectManager.get_pending_active_effect()
	if effect == null or effect._trigger_player_id != seat:
		return {}
	var options: Array = []
	for index in range(effect._options.size()):
		var option: Dictionary = effect._options[index]
		var item := {"index": index, "label": str(option.get("shown_option_name", "")), "available": EffectManager.is_option_available(effect, index), "max_uses": int(option.get("max_uses", -1))}
		if option.has("quantity_range"):
			item["quantity_range"] = option.quantity_range.duplicate()
		options.append(item)
	return {"kind": "active_choice", "effect": builder.ids.id_for(effect), "label": effect.get_shown_name(), "allow_cancel": EffectManager.choice_allows_cancel(effect), "options": options, "multi": effect.allows_multi_choice(), "cost_text": CostText.attach_line("", CostText.effect_cost_items(effect)).strip_edges()}

## 本地直接传规则对象；网络适配器负责解析 ID 和附加视图序号。
func preview(seat: int, cards: Array, flags: Array, payment: Dictionary = {}) -> Dictionary:
	if payment.is_empty():
		payment = payment_quote(seat)
	if not RegularPlay.payment_quote_is_current(seat, payment):
		return {"ok": false}
	if seat < 0 or GameProgress.current_player_id != seat:
		return {"ok": false}
	if EffectManager.is_waiting_for_choice() or not GameProgress.is_phase_for(seat, "action") or cards.size() != flags.size():
		return {"ok": false}
	var data: Dictionary = GameDataManager.find_player_data(seat)
	if data.is_empty():
		return {}
	var available: Array = RegularPlay.candidates(seat)
	var selected: Array = []
	for index in range(cards.size()):
		if not cards[index] is BaseHandCard or not flags[index] is bool:
			return {"ok": false}
		if not available.has(cards[index]) or selected.has(cards[index]):
			return {"ok": false}
		selected.append(cards[index])
	var candidates: Array = []
	for card in available:
		if cards.has(card):
			continue
		var modes: Array = RegularPlay.pending_modes(seat, cards, flags, card, payment)
		if not modes.is_empty():
			candidates.append({"id": builder.ids.id_for(card), "modes": modes})
	# 私有、只读预览：复用单人规则查询，客户端不按牌面费用重算。
	var cost: float = 0.0
	var preview_power: int = 0
	var counts := CardCountsPower.new()
	for index in cards.size():
		var card: BaseHandCard = cards[index]
		if not bool(data.get("is_magic_immune", false)) and not flags[index]:
			cost += RegularPlay.cost(card, data)
		if counts.counts_when_played(card, flags[index], seat):
			preview_power += int(card._power.number)
	var breakdown: Dictionary = GetPlayerTotalPower.breakdown(seat, preview_power, cards, flags)
	return {"ok": true, "candidates": candidates, "can_submit": RegularPlay.can_submit_group(seat, cards, flags, false, payment), "mana_cost": cost, "remaining_magic": data.magic.number - cost, "power_breakdown": breakdown}

func actions(seat: int) -> Dictionary:
	if seat < 0 or GameProgress.is_game_over:
		return {}
	var data: Dictionary = GameDataManager.find_player_data(seat)
	if data.is_empty():
		return {}
	var result := {"deploy_areas": [], "move_areas": [], "move_costs": {}, "cards": [], "effects": [], "flip_cards": [], "can_end": false}
	if EffectManager.is_waiting_for_choice():
		return result
	for effect in EffectManager.manual_activations(seat):
		result.effects.append({"id": builder.ids.id_for(effect), "label": effect.get_shown_name()})
	for card in RegularPlay.candidates(seat):
		var modes: Array = flip_modes(seat, card)
		if not modes.is_empty():
			result.flip_cards.append({"id": builder.ids.id_for(card), "modes": modes})
	if GameProgress.current_player_id != seat:
		return result
	result.can_end = GameProgress.can_end_current_player_action()
	if GameProgress.is_phase_for(seat, "outpost") and data.get("location") == null:
		for area in DeployRules.deployable_areas():
			result.deploy_areas.append(builder.ids.id_for(area))
	if GameProgress.is_phase_for(seat, "action"):
		for area in MapData.areas:
			if AreaActionRules.block_reason(seat, MapData.areas.find(area)).is_empty():
				result.move_areas.append(builder.ids.id_for(area))
				var origin: BaseLocation = data.get("location")
				var steps: int = MapData.areas.find(area) - MapData.areas.find(origin.get_from())
				result.move_costs[str(builder.ids.id_for(area))] = AreaActionRules.estimate_move_cost(data, steps)
		for card in RegularPlay.candidates(seat):
			var modes: Array = RegularPlay.modes(seat, card)
			if not modes.is_empty():
				result.cards.append({"id": builder.ids.id_for(card), "modes": modes})
	return result

func flip_modes(seat: int, card) -> Array:
	var data: Dictionary = GameDataManager.find_player_data(seat)
	if data.is_empty():
		return []
	if GameProgress.is_game_over or EffectManager.is_waiting_for_choice() or not RegularPlay.candidates(seat).has(card):
		return []
	if card is BaseAttack and RegularPlay.in_play_zone(data, card):
		return [false, true]
	if card is BaseSkill and card._is_concealed and card._is_awakened:
		return [false]
	return []

func location_candidates(pending: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	if not EffectManager.location_option_origin_allowed(pending.effect, pending.spec):
		return result
	var source:Dictionary = SessionGeneration.origin_of(pending.get("effect"))
	if not source.ok:
		return result
	var forbidden: Array = pending.spec.get("forbidden_target_areas", [])
	for area in MapData.areas:
		if forbidden.has(str(area._area_name)):
			continue
		var location = AreaActionRules.first_effect_location_target(area, pending.spec, source.context)
		if location != null:
			result[builder.ids.id_for(area)] = location
	return result