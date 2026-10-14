class_name MatchCommandDispatcher
extends RefCounted

## 与连接无关的参数校验与单次分派；尚未接入生产。
## 规则检查显式注入，由调用方绑定公开规则方法。
var error: String = ""
var revision_delta: int = 0
var _ids
var _run: Callable
var _card_validator: Callable
var _location_origin_validator: Callable
var _context: SessionContext = null

func _init(card_validator: Callable, location_origin_validator: Callable) -> void:
	_card_validator = card_validator
	_location_origin_validator = location_origin_validator

## 调用方已完成 peer/seq/guard/audit 检查；此处不获取或修改权威状态。
## ok=false 不意味着规则未运行，调用方必须仍消费 revision_delta。
func dispatch(seat: int, kind: String, args: Dictionary, ids, run: Callable, context: Variant = null) -> Dictionary:
	_ids = ids
	_run = run
	_context = context as SessionContext
	var outcome: Variant = null
	if SessionGeneration.validate_context(_context).get("ok", false):
		outcome = _dispatch(seat, kind, args)
	else:
		error = "对局请求来源无效"
	var accepted: bool = _accepted(outcome)
	var result: Dictionary = {"ok": accepted, "result": outcome, "reason": error, "revision_delta": revision_delta}
	# 不跨调用持有绑定权威实例的 Callable，避免未来接线产生引用环。
	_ids = null
	_run = Callable()
	_context = null
	return result

func _dispatch(seat: int, kind: String, args: Dictionary):
	error = ""
	revision_delta = 0
	if kind == "confirm_broadcast":
		# 席位只取可信调用参数；先校验再同步执行，不跨 deferred/await。
		if args.size() != 1 or not args.get("batch_id") is int:
			return _reject("播报确认参数无效")
		if not GameProgress.can_confirm_battle_broadcast(seat, args.batch_id):
			return _reject("播报批次已失效或该席位无需确认")
		# 既有命令返回 void；不能把 null 当失败。审计故障由权威执行闸处理。
		var outcome = _invoke("confirm_battle_broadcast", [seat])
		if outcome == null and error.is_empty():
			outcome = true
		revision_delta += 1
		return outcome
	if kind == "cancel_choice":
		if args.size() != 1 or not args.get("effect") is int:
			return _reject("取消参数无效")
		var effect = _ids.object_for(args.effect)
		var source: SessionContext = _effect_context(effect)
		if not effect is BaseEffect or source == null or effect._trigger_player_id != seat:
			return _reject("不能取消其他玩家的选择")
		var outcome = _invoke("cancel_pending_choice", [effect], source)
		if not _accepted(outcome):
			return _reject("该选择当前不允许取消")
		revision_delta += 1
		return true
	if kind == "location_choice":
		if args.size() != 2 or not args.get("effect") is int or not args.get("area") is int:
			return _reject("位置选择格式无效")
		var pending: Dictionary = EffectManager.get_pending_location_selection()
		var effect = _ids.object_for(args.effect)
		var source: SessionContext = _effect_context(effect)
		if not effect is BaseEffect or source == null or pending.get("effect") != effect or effect._trigger_player_id != seat:
			return _reject("当前位置选择不属于该座位")
		var locations: Dictionary = _location_candidates(pending)
		if not locations.has(args.area):
			return _reject("目标战区不满足位置选择规则")
		var outcome = _invoke("submit_location_selection", [effect, locations[args.area]], source)
		revision_delta += 1
		return outcome
	if kind == "activate":
		if args.size() != 1 or not args.get("effect") is int:
			return _reject("发动参数无效")
		var effect = _ids.object_for(args.effect)
		var source: SessionContext = _effect_context(effect)
		if not effect is BaseEffect or source == null or not EffectManager.can_manual_activate(effect, seat):
			return _reject("该能力当前不可发动")
		var outcome = _invoke("request_manual_activation", [effect, seat], source)
		revision_delta += 1
		return outcome
	if kind == "player_choice":
		if args.size() != 2 or not args.get("effect") is int or not args.get("players") is Array:
			return _reject("目标选择格式无效")
		var pending: Dictionary = EffectManager.get_pending_player_selection()
		var effect = _ids.object_for(args.effect)
		var source: SessionContext = _effect_context(effect)
		if not effect is BaseEffect or source == null or pending.get("effect") != effect or effect._trigger_player_id != seat:
			return _reject("当前目标选择不属于该座位")
		var low: int = int(pending.spec.get("min", 1))
		var high: int = int(pending.spec.get("max", low))
		if args.players.size() < low or (high != -1 and args.players.size() > high):
			return _reject("目标数量不符合声明")
		var picked: Array = []
		for id in args.players:
			if not id is int or not pending.candidates.has(id) or picked.has(id):
				return _reject("目标不在候选集或重复")
			picked.append(id)
		var outcome = _invoke("submit_player_selection", [effect, picked], source)
		revision_delta += 1
		return outcome
	if kind == "card_choice":
		if args.size() != 2 or not args.get("effect") is int or not args.get("cards") is Array:
			return _reject("选牌答复格式无效")
		var pending: Dictionary = EffectManager.get_pending_card_selection()
		var effect = _ids.object_for(args.effect)
		var source: SessionContext = _effect_context(effect)
		if not effect is BaseEffect or source == null or pending.get("effect") != effect or effect._trigger_player_id != seat:
			return _reject("当前选牌不属于该座位")
		var cards: Array = []
		for id in args.cards:
			if not id is int:
				return _reject("候选 ID 类型无效")
			var card = _ids.object_for(id)
			if not card is BaseCard:
				return _reject("候选卡牌不存在")
			cards.append(card)
		if not _card_validator.call(pending, pending.cards, cards, pending.required_cards):
			return _reject("选牌不满足当前候选或数量要求")
		var outcome = _invoke("submit_card_selection", [effect, cards], source)
		revision_delta += 1
		return outcome
	if kind == "option_choice":
		if args.size() != 2 or not args.get("effect") is int or not args.get("choices") is Array:
			return _reject("选项答复格式无效")
		var effect = _ids.object_for(args.effect)
		var source: SessionContext = _effect_context(effect)
		if not effect is BaseEffect or source == null or effect != EffectManager.get_pending_active_effect() or effect._trigger_player_id != seat:
			return _reject("当前效果不等待该座位答复")
		var selection: Dictionary = {}
		var quantities: Dictionary = {}
		for choice in args.choices:
			if not choice is Dictionary or not choice.get("index") is int or not choice.get("count") is int:
				return _reject("选项次数格式无效")
			var index: int = choice.index
			if index < 0 or index >= effect._options.size() or selection.has(index) or choice.count <= 0:
				return _reject("选项下标或次数无效")
			var option: Dictionary = effect._options[index]
			if option.has("quantity_range"):
				var bounds = option.quantity_range
				if not bounds is Array or bounds.size() != 2 or not choice.get("quantity") is int:
					return _reject("缺少声明要求的数量")
				if choice.quantity < bounds[0] or choice.quantity > bounds[1]:
					return _reject("数量超出声明范围")
				quantities[index] = choice.quantity
			elif choice.has("quantity"):
				return _reject("选项未声明数量")
			selection[index] = choice.count
		if selection.is_empty():
			return _reject("取消应通过放弃入口提交")
		if not EffectManager.validate_selection(effect, selection):
			return _reject("选项次数不满足现有规则")
		var outcome = _invoke("submit_option_choice", [effect, selection, quantities], source)
		revision_delta += 1
		return outcome
	if kind == "active_choice":
		if args.size() != 2 or not args.get("effect") is int or not args.get("activate") is bool:
			return _reject("效果答复格式无效")
		var effect = _ids.object_for(args.effect)
		var source: SessionContext = _effect_context(effect)
		if not effect is BaseEffect or source == null or effect != EffectManager.get_pending_active_effect() or effect._trigger_player_id != seat:
			return _reject("当前效果不等待该座位答复")
		# 选项类发动必须另走明确的选项提交，不用布尔确认绕过选项。
		if args.activate and effect.has_options():
			return _reject("必须提交具体选项")
		var outcome = _invoke("submit_active_choice", [effect, args.activate], source)
		revision_delta += 1
		return outcome
	if kind == "set_concealed":
		if args.size() != 2 or not args.get("card") is int or not args.get("concealed") is bool:
			return _reject("翻面参数无效")
		var card = _ids.object_for(args.card)
		var source: SessionContext = _subject_context(card)
		if source == null or not _flip_modes(seat, card).has(args.concealed):
			return _reject("该牌当前不允许翻面")
		var outcome = _invoke("set_card_concealed", [card, args.concealed, seat], source)
		revision_delta += 1
		return outcome
	if GameProgress.current_player_id != seat:
		return _reject("尚未轮到该座位")
	match kind:
		"move":
			if args.size() != 1 or not args.get("area") is int or EffectManager.is_waiting_for_choice() or not GameProgress.is_phase_for(seat, "action"):
				return _reject("当前不能常规移动")
			var target = _ids.object_for(args.area)
			if not target is BaseMapArea or not MapData.areas.has(target):
				return _reject("移动目标不存在")
			var target_index: int = MapData.areas.find(target)
			var data: Dictionary = GameDataManager.find_player_data(seat)
			if data.is_empty():
				return _reject("座位无玩家数据")
			var reason: String = AreaActionRules.block_reason(seat, target_index)
			if not reason.is_empty():
				return _reject(reason)
			var origin: BaseLocation = data.get("location")
			var steps: int = target_index - MapData.areas.find(origin.get_from())
			var outcome = _invoke("move", [steps, seat])
			revision_delta += 1
			return outcome
		"play_group":
			if args.size() != 2 or not args.get("cards") is Array or not args.get("hidden") is Array or EffectManager.is_waiting_for_choice():
				return _reject("出牌参数无效或正在等待效果")
			if args.cards.is_empty() or args.cards.size() != args.hidden.size():
				return _reject("牌组与明暗数量不匹配")
			var cards: Array = []
			for index in range(args.cards.size()):
				if not args.cards[index] is int or not args.hidden[index] is bool:
					return _reject("牌组字段类型无效")
				var card = _ids.object_for(args.cards[index])
				if not card is BaseHandCard or cards.has(card):
					return _reject("牌对象无效或重复")
				cards.append(card)
			if not _accepted(_invoke("submit_group", [seat, cards, args.hidden])):
				return _reject("牌组不满足现有出牌规则")
		"end_action":
			if not args.is_empty() or not _accepted(_invoke("end_current_player_action", [])):
				return _reject("当前不能结束行动")
		"deploy":
			if args.size() != 1 or not args.get("area") is int or EffectManager.is_waiting_for_choice():
				return _reject("部署参数无效或正在等待效果")
			var data: Dictionary = GameDataManager.find_player_data(seat)
			if data.is_empty():
				return _reject("座位无玩家数据")
			if not GameProgress.is_phase_for(seat, "outpost") or data.get("location") != null:
				return _reject("当前不能部署")
			var area = _ids.object_for(args.area)
			if not area is BaseMapArea or not DeployRules.deployable_areas().has(area):
				return _reject("目标战区不可部署")
			if not _accepted(_invoke("deploy_to_area", [area, seat])):
				return _reject("部署失败")
		_:
			return _reject("不支持该对局指令")
	revision_delta += 1
	return true

func _invoke(kind: String, args: Array, context: SessionContext = null):
	var source: SessionContext = context if context != null else _context
	if not SessionGeneration.validate_context(source).get("ok", false):
		return null
	return _run.call(kind, args, source)

func _effect_context(effect: BaseEffect) -> SessionContext:
	if effect == null:
		return null
	var origin: Dictionary = SessionGeneration.origin_of(effect)
	if not origin.get("ok", false):
		return null
	var source: SessionContext = origin.get("context")
	if not SessionGeneration.validate_context(source).get("ok", false) or not is_same(source.token(), _context.token()):
		return null
	return source

func _subject_context(subject: Object) -> SessionContext:
	if subject == null:
		return null
	var origin: Dictionary = SessionGeneration.origin_of(subject)
	if not origin.get("ok", false):
		return null
	var source: SessionContext = origin.get("context")
	if not SessionGeneration.validate_context(source).get("ok", false) or not is_same(source.token(), _context.token()):
		return null
	return source

func _accepted(value: Variant) -> bool:
	return value == true

func _reject(reason: String) -> bool:
	error = reason
	return false

func _flip_modes(seat: int, card) -> Array:
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

func _location_candidates(pending: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var source: SessionContext = _effect_context(pending.get("effect"))
	if source == null or not _location_origin_validator.call(pending.effect, pending.spec):
		return result
	var forbidden: Array = pending.spec.get("forbidden_target_areas", [])
	for area in MapData.areas:
		if forbidden.has(str(area._area_name)):
			continue
		var location = AreaActionRules.first_effect_location_target(area, pending.spec, source)
		if location != null:
			result[_ids.id_for(area)] = location
	return result
