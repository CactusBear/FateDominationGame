class_name RegularPlay
extends RefCounted

# 常规出牌逐张提交；play 日志是已提交事实，regular_play 是流程完成事实。
static func candidates(id: int) -> Array:
	var d: Dictionary = GameDataManager.get_player_data(id)
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

#打出时从来源区移除：出牌区与技能区都查，不假设牌来自手牌
static func _take_from_source(d: Dictionary, card) -> void:
	for zone in play_zone_arrays(d):
		zone.erase(card)
	d.hand_cards.erase(card); d.servant_skills.erase(card); d.master_skills.erase(card); d.side.skills.erase(card)

static func completed(id: int) -> bool:
	return not GameLog.query({"type": "regular_play", "actor": id}, 0).is_empty()

static func played_count(id: int) -> int:
	return GameLog.query({"type":"play", "actor":id, "data":{"extra":false}}, 0).size()

static func minimum(id: int) -> int:
	var n = GameDataManager.get_player_data(id).get("regular_play_min", BaseNumber.new(2))
	return maxi(0, int(n.number if n is BaseNumber else n))

static func limit(id: int) -> int:
	var n = GameDataManager.get_player_data(id).get("play_limit", BaseNumber.new(2))
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

static func faceup_allowed(card: BaseHandCard, id: int, start_magic = null) -> bool:
	var d: Dictionary = GameDataManager.get_player_data(id)
	if not PlayRules.can_play(card, d): return false
	if card is BaseSkill and not card._is_awakened: return false
	#明置与暗置共用 PlayRules 的场面禁令。
	var threshold: float = d.magic.number if start_magic == null else float(start_magic)
	if not in_play_zone(d, card) and not d.is_magic_immune and not d.ignore_skill_zone_magic_limit:
		if not (card is BaseSkill and card._ignore_limit) and threshold < GameData.skill_zone_magic_limit.number: return false
	return d.is_magic_immune or cost(card, d) <= minf(d.magic.number, GameData.player_magic_limit(id).number)

static func _mode_basic(id: int, card, hidden: bool, magic: float, start_magic: float) -> bool:
	var d: Dictionary = GameDataManager.get_player_data(id)
	if not candidates(id).has(card) or not PlayRules.board_allows(card, d): return false
	if hidden:
		return in_play_zone(d, card) and card is BaseAttack and not card._need_extra_play
	return faceup_allowed(card, id, start_magic) and (d.is_magic_immune or cost(card, d) <= magic)

static func _path_exists(id: int, cards: Array, magic: float, count: int, faceup: bool, start_magic: float) -> bool:
	var d: Dictionary = GameDataManager.get_player_data(id)
	if count >= minimum(id) and (not battlefield(d) or faceup): return true
	if count >= limit(id): return false
	for card in cards:
		for hidden in [false, true]:
			if not _mode_basic(id, card, hidden, magic, start_magic): continue
			var left := cards.duplicate(); left.erase(card)
			var next_magic := magic if hidden or d.is_magic_immune else magic - cost(card, d)
			if _path_exists(id, left, next_magic, count + 1, faceup or not hidden, start_magic): return true
	return false

static func can_add(id: int, card, hidden: bool) -> bool:
	if not GameData.player_data_library.has(id) or completed(id): return false
	var d: Dictionary = GameDataManager.get_player_data(id)
	if d.is_out or GameProgress.current_player_id != id or not GameProgress.is_phase_for(id, "action"): return false
	if PlayerBuffsHaveEffect.new().exec(CannotPlayCardsEffect.EFFECT_NAME, id): return false
	var count := played_count(id)
	if count >= limit(id): return false
	var start_magic := _start_magic(id)
	if not _mode_basic(id, card, hidden, d.magic.number, start_magic): return false
	var left := candidates(id); left.erase(card)
	var next_magic: float = d.magic.number if hidden or d.is_magic_immune else d.magic.number - cost(card, d)
	return _path_exists(id, left, next_magic, count + 1, _has_faceup(id) or not hidden, start_magic)

static func modes(id: int, card) -> Array:
	var result := []
	for hidden in [false, true]:
		if can_add(id, card, hidden): result.append(hidden)
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
static func pending_modes(id:int, pending_cards:Array, pending_hidden:Array, card) -> Array:
	var result:Array = []
	if !GameData.player_data_library.has(id) or completed(id):
		return result
	var d:Dictionary = GameDataManager.get_player_data(id)
	if d.is_out or GameProgress.current_player_id != id or not GameProgress.is_phase_for(id, "action"):
		return result
	if PlayerBuffsHaveEffect.new().exec(CannotPlayCardsEffect.EFFECT_NAME, id):
		return result
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
		if not _mode_basic(id, card, hidden, remaining, start_magic):
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
		if not _path_exists(id, left, next_magic, next_count, has_faceup, start_magic):
			continue
		result.append(hidden)
	return result


static func pending_has_legal_add(id:int, pending_cards:Array, pending_hidden:Array) -> bool:
	for card in candidates(id):
		if not pending_modes(id, pending_cards, pending_hidden, card).is_empty():
			return true
	return false


static func has_legal_add(id: int) -> bool:
	for card in candidates(id):
		if not modes(id, card).is_empty(): return true
	return false

static func can_submit_group(id:int, cards:Array, hidden_flags:Array) -> bool:
	if !GameData.player_data_library.has(id) or completed(id):
		return false
	if cards.size() != hidden_flags.size() or cards.is_empty():
		return false
	var d:Dictionary = GameDataManager.get_player_data(id)
	if d.is_out or GameProgress.current_player_id != id or not GameProgress.is_phase_for(id, "action"):
		return false
	if PlayerBuffsHaveEffect.new().exec(CannotPlayCardsEffect.EFFECT_NAME, id):
		return false
	var seen:Array = []
	var magic:float = d.magic.number
	var start_magic:float = _start_magic(id)
	var faceup:bool = _has_faceup(id)
	for i in range(cards.size()):
		var card = cards[i]
		var hidden:bool = bool(hidden_flags[i])
		if seen.has(card) or not candidates(id).has(card):
			return false
		if not _mode_basic(id, card, hidden, magic, start_magic):
			return false
		seen.append(card)
		faceup = faceup or not hidden
		if not hidden and not d.is_magic_immune:
			magic -= cost(card, d)
	var total_count:int = played_count(id) + cards.size() - batch_extra_cards(id, cards, hidden_flags).size()
	if total_count < minimum(id) or total_count > limit(id):
		return false
	return not battlefield(d) or faceup


# 为 AI 查找当前可提交的整组牌。搜索只读，不扣费、不触发效果；
# 选择策略优先尽量多出牌，规则限制仍全部由 pending_modes / can_submit_group 判断。
static func find_group(id:int, candidate_order:Array = []) -> Dictionary:
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
	return _find_pending_group(id, [], [], ordered)

static func _find_pending_group(id:int, cards:Array, hidden_flags:Array, ordered:Array) -> Dictionary:
	if cards.size() < ordered.size():
		for card in ordered:
			if cards.has(card):
				continue
			for hidden in pending_modes(id, cards, hidden_flags, card):
				var next_cards := cards.duplicate()
				var next_hidden := hidden_flags.duplicate()
				next_cards.append(card)
				next_hidden.append(hidden)
				var found := _find_pending_group(id, next_cards, next_hidden, ordered)
				if not found.is_empty():
					return found
	if can_submit_group(id, cards, hidden_flags):
		return {"cards":cards, "hidden":hidden_flags}
	return {}

#一次性提交已经确认的整组常规出牌。先完整校验，校验通过才开始产生副作用；
#玩家在确认前的选择只存在 UI 暂存里，因此撤销不需要反向补魔力/回滚效果。
static func submit_group(id:int, cards:Array, hidden_flags:Array) -> bool:
	if !can_submit_group(id, cards, hidden_flags):
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
			ApplyCardKeywords.new().apply(ApplyCardKeywords.TRUE_NAME_RELEASE, id)
			break
	var extra_cards:Array = batch_extra_cards(id, cards, hidden_flags)
	for i in range(cards.size()):
		var card:BaseHandCard = cards[i]
		var hidden:bool = bool(hidden_flags[i])
		TimePointChecker.dynamic_time_point([TimePoints.CARD_COST_CALCULATED], id, card)
		var paid:float = 0.0 if hidden else cost(card, d)
		if not d.is_magic_immune and paid > 0:
			var before = d.magic.number
			d.magic.minus(BaseNumber.new(paid))
			GameLog.record_resource_payment("magic", id, before, d.magic.number, "regular_play", card)
		card._is_concealed = hidden
		card._is_activating = not hidden
		_take_from_source(d, card)
		d.played_cards.append(card)
		if CardCountsPower.new().exec(card, id): d.power.add(card._power)
		GameLog.record("play", id, -1, "", card, ["play"], {"card_name":card._name, "card_type":"attack" if card is BaseAttack else "skill", "extra":extra_cards.has(card), "concealed":hidden})
		if not hidden:
			ApplyCardKeywords.new().exec(card, id)
			#明置卡牌在进入打出区后亮出；暗置卡牌等之后真正翻开时再派发
			TimePointChecker.card_revealed(card)
	#打出时点在整批入场、整批 play 日志都写完之后才逐张派发：
	#卡面「若此牌与一张基础攻击一同打出」这类条件要看得到同批的其他牌，
	#放在入场循环里会让排在前面的牌漏判排在后面的同批牌（顺序不该影响同时打出的判定）
	for card in cards:
		TimePointChecker.dynamic_time_point([TimePoints.PLAYED_CARD], id, card)
	GameLog.record("regular_play", id, -1, "", null, [], {"count":played_count(id), "forced":false})
	return true


static func can_finalize(id: int) -> bool:
	if completed(id): return true
	var d: Dictionary = GameDataManager.get_player_data(id)
	return played_count(id) >= minimum(id) and (not battlefield(d) or _has_faceup(id))

static func finalize(id: int, forced: bool = false) -> bool:
	if completed(id): return true
	if not can_finalize(id) and not (forced and not has_legal_add(id)): return false
	GameLog.record("regular_play", id, -1, "", null, [], {"count":played_count(id), "forced":forced})
	return true

static func can_end(id: int) -> bool:
	if completed(id): return true
	if can_finalize(id): return true
	return not has_legal_add(id)

static func add(id: int, card, hidden: bool) -> bool:
	if not can_add(id, card, hidden): return false
	var d: Dictionary = GameDataManager.get_player_data(id)
	if GameLog.query({"type":"regular_play_start", "actor":id}, 0).is_empty():
		GameLog.record("regular_play_start", id, -1, "", null, [], {"magic":d.magic.number})
	var paid: float = 0.0 if hidden else cost(card, d)
	#费用修正必须在扣费和入场前结算，才能影响本次实际支付。
	#此时卡尚未入场，但其已登记效果仍可响应费用计算时点。
	TimePointChecker.dynamic_time_point([TimePoints.CARD_COST_CALCULATED], id, card)
	paid = 0.0 if hidden else cost(card, d)
	if not d.is_magic_immune and paid > 0:
		var before = d.magic.number
		d.magic.minus(BaseNumber.new(paid))
		GameLog.record_resource_payment("magic", id, before, d.magic.number, "regular_play", card)
	card._is_concealed = hidden
	card._is_activating = not hidden
	_take_from_source(d, card)
	d.played_cards.append(card)
	if CardCountsPower.new().exec(card, id): d.power.add(card._power)
	GameLog.record("play", id, -1, "", card, ["play"], {"card_name":card._name, "card_type":"attack" if card is BaseAttack else "skill", "extra":false, "concealed":hidden})
	if not hidden:
		ApplyCardKeywords.new().exec(card, id)
		#明置卡牌进入打出区后亮出；暗置卡牌不在这里泄露牌面
		TimePointChecker.card_revealed(card)
	TimePointChecker.dynamic_time_point([TimePoints.PLAYED_CARD], id, card)
	if played_count(id) >= limit(id): finalize(id)
	elif not has_legal_add(id): finalize(id, true)
	return true

# AI：每次只返回当前可立即提交的一张。
static func find_add(id: int) -> Dictionary:
	for card in candidates(id):
		for hidden in [false, true]:
			if can_add(id, card, hidden): return {"card":card, "hidden":hidden}
	return {}
