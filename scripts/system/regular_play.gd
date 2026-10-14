class_name RegularPlay
extends RefCounted

# 常规出牌逐张提交；play 日志是已提交事实，regular_play 是流程完成事实。
static func candidates(id: int) -> Array:
	var d: Dictionary = GameDataManager.find_player_data(id)
	if d.is_empty(): return []
	#"视为手牌"的牌区由玩家数据 regular_play_zones 声明（缺省只有手牌）；技能区一直可以常规出牌
	var zone_cards: Array = play_zone_cards(d)
	var cards: Array = zone_cards.duplicate()
	cards.append_array(d.servant_skills)
	cards.append_array(d.master_skills)
	cards.append_array(d.side.skills)
	var master = d.get("master")
	if master != null:
		cards.append_array(master._specials.get("SKILLS", []))
		cards.append_array(master._specials.get("ATTACKS", []))
	#升华技不参与常规出牌：它只有觉醒后才算可用，而项目里没有觉醒入口，
	#放进来会让这些牌长出"现在能出"的金框
	var unique: Array = []
	for card in cards:
		if not (card is BaseHandCard) or card._is_activating or d.played_cards.has(card) or unique.has(card):
			continue
		#牌库、弃牌堆里的牌只有在它们被声明为出牌区时才算候选
		if (d.deck.has(card) or d.discard.has(card)) and not zone_cards.has(card):
			continue
		unique.append(card)
	return unique

#玩家"视为手牌"的各牌区里的全部牌（按 regular_play_zones 的顺序），路径格式同 CardZones 的区路径
static func play_zone_cards(d: Dictionary) -> Array:
	var result: Array = []
	for zone in play_zone_arrays(d):
		for card in zone:
			if not result.has(card):
				result.append(card)
	return result

#regular_play_zones 解析成真实数组；找不到的路径跳过。字段缺失时退回手牌，与原行为一致
static func play_zone_arrays(d: Dictionary) -> Array:
	var paths = d.get("regular_play_zones", ["hand_cards"])
	if not (paths is Array):
		paths = ["hand_cards"]
	var arrays: Array = []
	for path in paths:
		var node = d
		for part in str(path).split("/"):
			node = node.get(part) if node is Dictionary else null
		if node is Array and not arrays.has(node):
			arrays.append(node)
	return arrays

#这张牌是否在"视为手牌"的区里：暗置打出与技能区魔力门槛都以它代替原来的"在手牌中"
static func in_play_zone(d: Dictionary, card) -> bool:
	for zone in play_zone_arrays(d):
		if zone.has(card):
			return true
	return false

# 不经过效果执行器，避免新增预算、日志或事务边界。
static func _operation(func_name:String) -> RefCounted:
	return AllOperations.create_instance_of(func_name)

#打出时从来源区移除：出牌区与技能区都查，不假设牌来自手牌
static func _take_from_source(d: Dictionary, card) -> void:
	for zone in play_zone_arrays(d):
		_operation("remove_from_array").exec(card, zone)
	_operation("remove_from_array").exec(card, d.hand_cards); _operation("remove_from_array").exec(card, d.servant_skills); _operation("remove_from_array").exec(card, d.master_skills); _operation("remove_from_array").exec(card, d.side.skills)

static func completed(id: int) -> bool:
	return not GameLog.query({"type": "regular_play", "actor": id}, 0).is_empty()

static func played_count(id: int) -> int:
	return GameLog.query({"type":"play", "actor":id, "data":{"extra":false}}, 0).size()

# 未知主体返回 -1；合法成员缺字段仍按原规则回退到 2，消费者须先验成员。
static func minimum(id: int) -> int:
	var d: Dictionary = GameDataManager.find_player_data(id)
	if d.is_empty(): return -1
	var n = d.get("regular_play_min", BaseNumber.new(2))
	return maxi(0, int(n.number if n is BaseNumber else n))

# 未知主体返回 -1；查询不创建玩家，合法成员的动态上限与缺字段默认值保持不变。
static func limit(id: int, source:Variant = null) -> int:
	# 裸 ID 是即时只读查询；保存的查询 Callable 必须显式绑定原来源。
	if source != null and not SessionGeneration.validate_context(source).ok: return -1
	var d: Dictionary = GameDataManager.find_player_data(id)
	if d.is_empty(): return -1
	var n = d.get("play_limit", BaseNumber.new(2))
	return maxi(0, int(n.number if n is BaseNumber else n))

static func battlefield(d: Dictionary) -> bool:
	var loc = d.get("location")
	if loc == null or !(loc.get_from() is BaseMapArea):
		return false
	# 常规出牌看区域是否为战场；交战状态只用于移动等独立规则。
	return loc.get_from()._score_need_win

static func cost(card: BaseHandCard, d: Dictionary) -> float:
	var discount: float = card._cost_discount.number
	if card is BaseAttack:
		discount += d.attack_cost_discount.number
	return maxf(0, card._cost.number - discount)

static func _start_magic(id: int) -> float:
	var logs := GameLog.query({"type":"regular_play_start", "actor":id}, 0, 1)
	if logs.is_empty():
		return GameDataManager.get_player_data(id).magic.number
	return float(logs[0].data.get("magic", 0))

static func _has_faceup(id: int) -> bool:
	for e in GameLog.query({"type":"play", "actor":id, "data":{"extra":false}}, 0):
		if not bool(e.data.get("concealed", false)):
			return true
	return false

# 报价创建者捕获原来源/成员/magic；递归搜索及保存的报价复用同一快照。
# 无显式来源时只继承已验函数帧，不从 current 或卡牌消费口领票。
static func payment_quote(id:int, source:Variant = null) -> Dictionary:
	return _member_context(id, RegisterObjectEffects.captured_context(source))

# 查询创建者保存报价；消费时仅验原来源/成员/magic，不重新捕获或补票。
static func payment_quote_is_current(id:int, payment:Dictionary) -> bool:
	return _source_member_is_current(payment) and payment.id == id

static func faceup_allowed(card: BaseHandCard, id: int, start_magic = null, allow_magic_overdraft:bool = false, payment:Dictionary = {}) -> bool:
	if payment.is_empty(): payment = payment_quote(id)
	if payment.is_empty() or not _source_member_is_current(payment) or payment.id != id: return false
	var d: Dictionary = payment.data
	if not PlayRules.can_play(card, d): return false
	if card is BaseSkill and not card._is_awakened: return false
	#明置与暗置共用 PlayRules 的场面禁令。
	var threshold: float = d.magic.number if start_magic == null else float(start_magic)
	if not in_play_zone(d, card) and not d.is_magic_immune and not d.ignore_skill_zone_magic_limit:
		if not (card is BaseSkill and card._ignore_limit) and threshold < GameData.skill_zone_magic_limit.number: return false
	return PayMagic.can_pay(BaseNumber.new(cost(card, d)), id, minf(d.magic.number, GameData.player_magic_limit(id).number), allow_magic_overdraft, payment.source, payment.data, payment.magic)

static func _mode_basic(id: int, card, hidden: bool, magic: float, start_magic: float, allow_magic_overdraft:bool = false, payment:Dictionary = {}) -> bool:
	var d: Dictionary = GameDataManager.find_player_data(id)
	if d.is_empty(): return false
	if not candidates(id).has(card) or not PlayRules.board_allows(card, d): return false
	if hidden:
		return in_play_zone(d, card) and card is BaseAttack and not card._need_extra_play
	return faceup_allowed(card, id, start_magic, allow_magic_overdraft, payment) and PayMagic.can_pay(BaseNumber.new(cost(card, d)), id, magic, allow_magic_overdraft, payment.get("source"), payment.get("data"), payment.get("magic"))

static func _path_exists(id: int, cards: Array, magic: float, count: int, faceup: bool, start_magic: float, payment:Dictionary) -> bool:
	var d: Dictionary = GameDataManager.find_player_data(id)
	if d.is_empty(): return false
	if count >= minimum(id) and (not battlefield(d) or faceup): return true
	if count >= limit(id): return false
	for card in cards:
		for hidden in [false, true]:
			if not _mode_basic(id, card, hidden, magic, start_magic, false, payment): continue
			var left := cards.duplicate(); left.erase(card)
			var next_magic := magic if hidden or d.is_magic_immune else magic - cost(card, d)
			if _path_exists(id, left, next_magic, count + 1, faceup or not hidden, start_magic, payment): return true
	return false

static func can_add(id: int, card, hidden: bool, payment:Dictionary = {}) -> bool:
	if payment.is_empty(): payment = payment_quote(id)
	if not GameData.player_data_library.has(id) or completed(id): return false
	var d: Dictionary = GameDataManager.get_player_data(id)
	if d.is_out or GameProgress.current_player_id != id or not GameProgress.is_phase_for(id, "action"): return false
	if PlayerBuffsHaveEffect.new().exec(CannotPlayCardsEffect.EFFECT_NAME, id): return false
	var count := played_count(id)
	if count >= limit(id): return false
	var start_magic := _start_magic(id)
	if not _mode_basic(id, card, hidden, d.magic.number, start_magic, false, payment): return false
	var left := candidates(id); left.erase(card)
	var next_magic: float = d.magic.number if hidden or d.is_magic_immune else d.magic.number - cost(card, d)
	return _path_exists(id, left, next_magic, count + 1, _has_faceup(id) or not hidden, start_magic, payment)

static func modes(id: int, card, payment:Dictionary = {}) -> Array:
	if payment.is_empty(): payment = payment_quote(id)
	var result := []
	for hidden in [false, true]:
		if can_add(id, card, hidden, payment): result.append(hidden)
	return result

# 同批追加资格只由明置、非追加的攻击支撑，不能互相循环授权追加。
static func _batch_extra_qualifies(card, cards:Array, hidden_flags:Array, extra:Array) -> bool:
	for requirement in card._play_requirements:
		if not requirement is Dictionary or str(requirement.get("type", "")) != "extra_with_batch": continue
		var count:int = 0
		for j in range(cards.size()):
			var other = cards[j]
			if extra.has(other) or other == card or not (other is BaseAttack or other is BaseSkill) or bool(hidden_flags[j]): continue
			var matches:bool = true
			for attribute in requirement.get("attributes", []):
				if not other._attributes.has(attribute): matches = false
			if matches: count += 1
		if count >= int(requirement.get("count", 1)): return true
	return false

static func batch_extra_cards(id:int, cards:Array, hidden_flags:Array) -> Array:
	if GameDataManager.find_player_data(id).is_empty(): return []
	var extra:Array = []
	for i in range(cards.size()):
		var card = cards[i]
		if not card is BaseHandCard or bool(hidden_flags[i]): continue
		var proposed:Array = extra.duplicate()
		proposed.append(card)
		if played_count(id) + cards.size() - proposed.size() < minimum(id): continue
		var valid:bool = true
		for candidate in proposed:
			if not _batch_extra_qualifies(candidate, cards, hidden_flags, proposed): valid = false
		if valid: extra = proposed
	return extra
static func pending_modes(id:int, pending_cards:Array, pending_hidden:Array, card, payment:Dictionary = {}) -> Array:
	if payment.is_empty(): payment = payment_quote(id)
	var result:Array = []
	if not can_play_group_prefix(id, pending_cards, pending_hidden, false, payment):
		return result
	var d:Dictionary = GameDataManager.find_player_data(id)
	var committed_count:int = played_count(id)
	if pending_cards.has(card):
		return result
	var used_magic:float = 0.0
	for i in range(pending_cards.size()):
		if not bool(pending_hidden[i]) and not d.is_magic_immune:
			used_magic += cost(pending_cards[i], d)
	var remaining:float = d.magic.number - used_magic
	var start_magic:float = _start_magic(id)
	for hidden in [false, true]:
		if not _mode_basic(id, card, hidden, remaining, start_magic, false, payment):
			continue
		var proposed:Array = pending_cards.duplicate()
		var proposed_hidden:Array = pending_hidden.duplicate()
		proposed.append(card); proposed_hidden.append(hidden)
		var next_count:int = committed_count + proposed.size() - batch_extra_cards(id, proposed, proposed_hidden).size()
		if next_count > limit(id):
			continue
		var has_faceup:bool = _has_faceup(id) or not hidden
		for pending_flag in pending_hidden:
			if not bool(pending_flag):
				has_faceup = true
				break
		#交战战场的待确认组合一旦达到最低张数，必须已有至少一张明置。
		#不能只验证单张合法性，否则第二张暗置会在界面上错误出现。
		if battlefield(d) and next_count >= minimum(id) and not has_faceup:
			continue
		var left:Array = candidates(id)
		for pending_card in pending_cards:
			left.erase(pending_card)
		left.erase(card)
		var next_magic:float = remaining if hidden or d.is_magic_immune else remaining - cost(card, d)
		if not _path_exists(id, left, next_magic, next_count, has_faceup, start_magic, payment):
			continue
		result.append(hidden)
	return result


static func pending_has_legal_add(id:int, pending_cards:Array, pending_hidden:Array, payment:Dictionary = {}) -> bool:
	if payment.is_empty(): payment = payment_quote(id)
	if GameDataManager.find_player_data(id).is_empty(): return false
	for card in candidates(id):
		if not pending_modes(id, pending_cards, pending_hidden, card, payment).is_empty():
			return true
	return false


static func has_legal_add(id: int, payment:Dictionary = {}) -> bool:
	if payment.is_empty(): payment = payment_quote(id)
	if GameDataManager.find_player_data(id).is_empty(): return false
	for card in candidates(id):
		if not modes(id, card, payment).is_empty(): return true
	return false

# 只重验前缀已有牌的模式资格与顺序费用；空前缀可开始选择，不代表可提交。
# 不检查最低/上限或补齐路径：这些仍由 pending_modes / can_submit_group 判定。
static func can_play_group_prefix(id:int, cards:Array, hidden_flags:Array, allow_magic_overdraft:bool = false, payment:Dictionary = {}) -> bool:
	if payment.is_empty(): payment = payment_quote(id)
	if !GameData.player_data_library.has(id) or completed(id):
		return false
	if cards.size() != hidden_flags.size():
		return false
	var d:Dictionary = GameDataManager.find_player_data(id)
	if d.is_out or GameProgress.current_player_id != id or not GameProgress.is_phase_for(id, "action"):
		return false
	if PlayerBuffsHaveEffect.new().exec(CannotPlayCardsEffect.EFFECT_NAME, id):
		return false
	var seen:Array = []
	var magic:float = d.magic.number
	var start_magic:float = _start_magic(id)
	for i in range(cards.size()):
		var card = cards[i]
		var hidden:bool = bool(hidden_flags[i])
		if seen.has(card) or not candidates(id).has(card):
			return false
		if not _mode_basic(id, card, hidden, magic, start_magic, allow_magic_overdraft, payment):
			return false
		seen.append(card)
		if not hidden and not d.is_magic_immune:
			magic -= cost(card, d)
	return true

static func can_submit_group(id:int, cards:Array, hidden_flags:Array, allow_magic_overdraft:bool = false, payment:Dictionary = {}) -> bool:
	if payment.is_empty(): payment = payment_quote(id)
	if cards.is_empty() or not can_play_group_prefix(id, cards, hidden_flags, allow_magic_overdraft, payment):
		return false
	var d:Dictionary = GameDataManager.find_player_data(id)
	var total_count:int = played_count(id) + cards.size() - batch_extra_cards(id, cards, hidden_flags).size()
	if total_count < minimum(id) or total_count > limit(id):
		return false
	var faceup:bool = _has_faceup(id)
	for hidden in hidden_flags:
		faceup = faceup or not bool(hidden)
	return not battlefield(d) or faceup


# 为 AI 查找当前可提交的整组牌。搜索只读，不扣费、不触发效果；
# 选择策略优先尽量多出牌，规则限制仍全部由 pending_modes / can_submit_group 判断。
static func find_group(id:int, candidate_order:Array = [], payment:Dictionary = {}) -> Dictionary:
	if payment.is_empty(): payment = payment_quote(id)
	if not GameData.player_data_library.has(id):
		return {}
	var available: Array = candidates(id)
	var ordered: Array = []
	for card in candidate_order:
		if available.has(card) and not ordered.has(card):
			ordered.append(card)
	for card in available:
		if not ordered.has(card):
			ordered.append(card)
	return _find_pending_group(id, [], [], ordered, payment)

static func _find_pending_group(id:int, cards:Array, hidden_flags:Array, ordered:Array, payment:Dictionary) -> Dictionary:
	if cards.size() < ordered.size():
		for card in ordered:
			if cards.has(card):
				continue
			for hidden in pending_modes(id, cards, hidden_flags, card, payment):
				var next_cards := cards.duplicate()
				var next_hidden := hidden_flags.duplicate()
				next_cards.append(card)
				next_hidden.append(hidden)
				var found := _find_pending_group(id, next_cards, next_hidden, ordered, payment)
				if not found.is_empty():
					return found
	if can_submit_group(id, cards, hidden_flags, false, payment):
		return {"cards":cards, "hidden":hidden_flags}
	return {}

# 保存原会话来源、事务及成员身份；这三个维度不可互相替代。
static func _member_context(id:int, source:Variant) -> Dictionary:
	if not SessionGeneration.validate_context(source).ok: return {}
	var d:Dictionary = GameDataManager.find_player_data(id)
	if d.is_empty(): return {}
	if not d.get("magic") is BaseNumber: return {}
	return {"id":id, "data":d, "source":source, "magic":d.magic}

static func _source_member_is_current(context:Dictionary) -> bool:
	if typeof(context.get("id")) != TYPE_INT or not context.get("data") is Dictionary or not context.get("magic") is BaseNumber: return false
	if not SessionGeneration.validate_context(context.get("source")).ok: return false
	var d:Dictionary = GameDataManager.find_player_data(context.id)
	return not d.is_empty() and is_same(d, context.data) and is_same(d.get("magic"), context.magic)

static func _context_is_current(context:Dictionary) -> bool:
	if context.is_empty() or not _source_member_is_current(context): return false
	var ticket:Dictionary = GameLog.fact_transaction_status(context.transaction_id)
	if ticket.status != GameLog.FactTransactionStatus.PENDING or ticket.generation != context.generation: return false
	var d:Dictionary = GameDataManager.find_player_data(context.id)
	return not d.is_empty() and is_same(d, context.data) and is_same(d.get("magic"), context.magic)

static func _discard_group(state:Dictionary) -> void:
	state.phase = "rejected"
	# 失效来源只终止本地游标，不写事实事务，也不还原旧检查点。
	if not _source_member_is_current(state.context): return
	var ticket:Dictionary = GameLog.fact_transaction_status(state.transaction_id)
	if ticket.status == GameLog.FactTransactionStatus.PENDING and ticket.generation == state.context.generation:
		GameLog.abort_fact_transaction(state.transaction_id)

# 复用现有规则对象图检查点与事实事务，不用反向补魔力/逐项撤销。
static func _begin_group(id:int, cards:Array, hidden_flags:Array, finish:Callable, allow_magic_overdraft:bool, source:Variant) -> Dictionary:
	var context:Dictionary = _member_context(id, source)
	if context.is_empty(): return {}
	var checkpoint
	if preload("res://scripts/match/rule_random.gd").snapshot().get("known", false):
		checkpoint = preload("res://scripts/match/effect_checkpoint.gd").new(null, true, context.source)
	else:
		# 旧入口没有可恢复的随机流；沿用通用对象图检查点，不伪造随机状态。
		checkpoint = preload("res://scripts/match/rule_checkpoint.gd").new()
		checkpoint.capture([GameData, GameProgress, MapData, TimePointChecker, GameStart, EffectManager, cards,
			GameLog._journal, GameLog._trace, AbilityRestrictions.entries, Attributes.custom_attributes],
			{GameProgress:["_battle_broadcast_consumer", "battle_broadcast_requires_confirm", "_battle_broadcast_batch_serial"],
			EffectManager:["_message_serial", "_guard_continuations", "_guard_transactions", "_transaction_scope", "_continuation_transactions",
			"_batch_transactions", "_runtime_guard", "_guard_run", "_guard_frames", "_resume_frames"]}, context.source)
	if not checkpoint.ready:
		EffectManager.push_message("无法建立完整出牌检查点，未执行出牌", id)
		return {}
	if not _source_member_is_current(context): return {}
	var transaction_id:int = MatchJournal.next_audit_identity()
	GameLog.begin_fact_transaction(transaction_id)
	context["transaction_id"] = transaction_id
	context["generation"] = GameLog.fact_transaction_status(transaction_id).generation
	return {"id":id, "cards":cards.duplicate(), "hidden":hidden_flags.duplicate(), "phase":"extras", "index":0,
		"context":context, "finish":finish.bind(context), "allow_magic_overdraft":allow_magic_overdraft, "checkpoint":checkpoint, "transaction_id":transaction_id, "transactions":EffectManager.capture_transaction_state()}

static func _reject_group(state:Dictionary, message:String = "魔力不足，已取消本次出牌") -> void:
	if not _context_is_current(state.context):
		_discard_group(state)
		return
	# 先终止游标；迟到的同一续行即便被再次调用也不能扣费。
	state.phase = "rejected"
	GameLog.abort_fact_transaction(state.transaction_id)
	if not state.checkpoint.restore() or not EffectManager.restore_transaction_state(state.transactions):
		EffectManager.mark_guard_audit_failed(EffectManager.active_transaction_root())
		return
	EffectManager.push_message(message, state.id)

#一次性提交已经确认的整组常规出牌。先完整校验，校验通过才开始产生副作用；
#玩家在确认前的选择只存在 UI 暂存里，因此撤销不需要反向补魔力/回滚效果。
static func submit_group(id:int, cards:Array, hidden_flags:Array, allow_magic_overdraft:bool = false, source:Variant = null) -> bool:
	if not SessionGeneration.validate_context(source).ok: return false
	if !can_submit_group(id, cards, hidden_flags, allow_magic_overdraft, payment_quote(id, source)):
		return false
	var state:Dictionary = _begin_group(id, cards, hidden_flags, Callable(RegularPlay, "_finish_group"), allow_magic_overdraft, source)
	if state.is_empty():
		return false
	var d:Dictionary = GameDataManager.get_player_data(id)
	if GameLog.query({"type":"regular_play_start", "actor":id}, 0).is_empty():
		GameLog.record("regular_play_start", id, -1, "", null, [], {"magic":d.magic.number})
	#整组常规出牌是同时打出：只要本批次有明置的【真名解放】牌，
	#同批其他牌从费用计算开始就应读取到已解放状态，不受数组先后顺序影响。
	#这里只提前结算会改变整组条件上下文的词条；其他词条仍在各自进场时结算。
	for i in range(cards.size()):
		var batch_card = cards[i]
		if not bool(hidden_flags[i]) and batch_card is BaseCard \
			and batch_card.has_keyword(ApplyCardKeywords.TRUE_NAME_RELEASE):
			#已解放是原合法 no-op，不把 false 与来源拒绝混为一谈。
			if not ReleaseTrueName.is_released(id):
				var released = preload("res://scripts/system/operation_router.gd").exec_registered("release_true_name", [id, ReleaseTrueName.DEFAULT_SHOWN_AREAS, state.context.source], state.context.source)
				if typeof(released) != TYPE_BOOL or not released:
					_reject_group(state, "真名解放被拒绝，已取消本次出牌")
					return false
			break
	if not EffectManager.defer_until_runtime_guard_complete(Callable(RegularPlay, "_resume_group").bind(state), state.context.source):
		_resume_group(state)
	return state.phase != "rejected"

#阶段游标在派发前前移；恢复不重新派发已进入的时点，也不重复扣费入场。
static func _resume_group(state:Dictionary) -> void:
	if state.phase in ["rejected", "finishing", "done"]:
		return
	if not _context_is_current(state.context):
		_discard_group(state)
		return
	var id:int = state.id
	var d:Dictionary = GameDataManager.find_player_data(id)
	var cards:Array = state.cards
	var hidden_flags:Array = state.hidden
	while true:
		if not _context_is_current(state.context):
			_discard_group(state)
			return
		match state.phase:
			"extras":
				state["extra_cards"] = batch_extra_cards(id, cards, hidden_flags)
				state.phase = "cost"
			"cost":
				if state.index >= cards.size():
					state.index = 0
					state.phase = "played"
					continue
				state.phase = "enter"
				TimePointChecker.dynamic_time_point([TimePoints.CARD_COST_CALCULATED], id, cards[state.index], state.context.source)
			"enter":
				var card:BaseHandCard = cards[state.index]
				var hidden:bool = bool(hidden_flags[state.index])
				var paid:float = 0.0 if hidden else cost(card, d)
				if not PayMagic.new().exec(BaseNumber.new(paid), id, "regular_play", card, false, state.allow_magic_overdraft, state.context.source, state.context.data, state.context.magic):
					_reject_group(state)
					return
				if not _context_is_current(state.context):
					_discard_group(state)
					return
				_operation("set_property").exec(card, "_is_concealed", hidden)
				_operation("set_property").exec(card, "_is_activating", not hidden)
				_take_from_source(d, card)
				_operation("add_to_array").exec(card, d.played_cards, -1)
				if CardCountsPower.new().exec(card, id):
					var power:BaseNumber = d.power
					var increment:BaseNumber = card._power
					if power.can_change:
						_operation("set_property").exec(power, "number", power.number + increment.number)
				GameLog.record("play", id, -1, "", card, ["play"], {"card_name":card._name, "card_type":"attack" if card is BaseAttack else "skill", "extra":state.extra_cards.has(card), "concealed":hidden})
				if hidden:
					state.index += 1
					state.phase = "cost"
				else:
					state.phase = "keywords"
			"keywords":
				state.phase = "reveal"
				var applied = preload("res://scripts/system/operation_router.gd").exec_registered("apply_card_keywords", [cards[state.index], id, state.context.source], state.context.source)
				if typeof(applied) != TYPE_BOOL or not applied:
					_reject_group(state, "词条结算被拒绝，已取消本次出牌")
					return
			"reveal":
				var card = cards[state.index]
				state.index += 1
				state.phase = "cost"
				TimePointChecker.card_revealed(card, state.context.source)
			"played":
				#整批入场及 play 日志完成后才逐张派发，保持同时打出口径。
				if state.index >= cards.size():
					state.phase = "finishing"
					var reply = state.finish.call()
					if not _context_is_current(state.context):
						_discard_group(state)
						return
					if typeof(reply) != TYPE_BOOL or not reply:
						if EffectManager.is_waiting_for_choice():
							# 待续不是完成或最终拒绝；保留原游标/来源，不恢复正在等待的图。
							state.phase = "played"
							EffectManager.defer_until_runtime_guard_complete(Callable(RegularPlay, "_resume_group").bind(state), state.context.source)
							return
						_reject_group(state, "出牌完成被拒绝，已取消本次出牌")
						return
					GameLog.commit_fact_transaction(state.transaction_id)
					if not _source_member_is_current(state.context):
						_discard_group(state)
						return
					state.phase = "done"
					return
				var card = cards[state.index]
				state.index += 1
				TimePointChecker.dynamic_time_point([TimePoints.PLAYED_CARD], id, card, state.context.source)
		if EffectManager.defer_until_runtime_guard_complete(Callable(RegularPlay, "_resume_group").bind(state), state.context.source):
			return

static func _finish_group(context:Dictionary) -> bool:
	if not _context_is_current(context): return false
	var id:int = context.id
	if EffectManager.is_waiting_for_choice(): return false
	if completed(id): return true
	GameLog.record("regular_play", id, -1, "", null, [], {"count":played_count(id), "forced":false})
	return _context_is_current(context)

static func _finish_incremental(context:Dictionary) -> bool:
	if not _context_is_current(context): return false
	var id:int = context.id
	# 动态 limit 保持原查询契约，但只有原根来源通过才允许读取。
	if played_count(id) >= limit(id, context.source): return finalize(id, false, context.source)
	if not has_legal_add(id, context): return finalize(id, true, context.source)
	return _context_is_current(context)


static func can_finalize(id: int) -> bool:
	var d: Dictionary = GameDataManager.find_player_data(id)
	if d.is_empty(): return false
	if completed(id): return true
	return played_count(id) >= minimum(id) and (not battlefield(d) or _has_faceup(id))

static func finalize(id: int, forced: bool = false, source:Variant = null) -> bool:
	if not SessionGeneration.validate_context(source).ok: return false
	if GameDataManager.find_player_data(id).is_empty(): return false
	# 待答/guard 尚未完成不是完成成功；由原动作所有者保留来源后续重试。
	if EffectManager.is_waiting_for_choice(): return false
	if completed(id): return true
	var member:Dictionary = GameDataManager.find_player_data(id)
	if not can_finalize(id) and not (forced and not has_legal_add(id, payment_quote(id, source))): return false
	if not SessionGeneration.validate_context(source).ok or not is_same(member, GameDataManager.find_player_data(id)): return false
	GameLog.record("regular_play", id, -1, "", null, [], {"count":played_count(id), "forced":forced})
	return true

static func can_end(id: int, payment:Dictionary = {}) -> bool:
	if payment.is_empty(): payment = payment_quote(id)
	if GameDataManager.find_player_data(id).is_empty(): return false
	if completed(id): return true
	if can_finalize(id): return true
	return not has_legal_add(id, payment)

static func add(id: int, card, hidden: bool, source:Variant = null) -> bool:
	if not SessionGeneration.validate_context(source).ok: return false
	if not can_add(id, card, hidden, payment_quote(id, source)): return false
	var state:Dictionary = _begin_group(id, [card], [hidden], Callable(RegularPlay, "_finish_incremental"), false, source)
	if state.is_empty():
		return false
	state.phase = "cost"
	state["extra_cards"] = []
	var d: Dictionary = GameDataManager.get_player_data(id)
	if GameLog.query({"type":"regular_play_start", "actor":id}, 0).is_empty():
		GameLog.record("regular_play_start", id, -1, "", null, [], {"magic":d.magic.number})
	#增量入口不预结算整组真名解放，也不判定整组额外出牌；完成规则独立传入。
	_resume_group(state)
	return state.phase != "rejected"

# AI：每次只返回当前可立即提交的一张。
static func find_add(id: int, payment:Dictionary = {}) -> Dictionary:
	if payment.is_empty(): payment = payment_quote(id)
	if GameDataManager.find_player_data(id).is_empty(): return {}
	for card in candidates(id):
		for hidden in [false, true]:
			if can_add(id, card, hidden, payment): return {"card":card, "hidden":hidden}
	return {}
