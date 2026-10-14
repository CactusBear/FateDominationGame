class_name DummyBot
extends RefCounted

const Search = preload("res://scripts/system/ai/group_search.gd")
const Planner = preload("res://scripts/system/ai/effect_planner.gd")
const SeatsQuery = preload("res://scripts/match/match_seat_query.gd")
const Builder = preload("res://scripts/match/view_builder.gd")

const operation_router = preload("res://scripts/system/operation_router.gd")

const RuleRandom = preload("res://scripts/match/rule_random.gd")

# 正式规则 AI 编排；类名 DummyBot 沿用旧名，免去全部调用方改名。
var source_context:SessionContext
var last_search:Dictionary = {}
# 搜索节点预算由调用方决定（正式对局用默认值；测试/无界面驱动可传小值缩短耗时），不影响合法性与威力口径。
var search_budget:int = Search.NODE_BUDGET

func _init(source:SessionContext = null) -> void:
	source_context = source if source != null else GameStart.startup_context()

#AI 策略参数（不是游戏规则，改这里不影响规则层）：
#魔力不高于此值时，优先用令咒换魔力
const CS_CHARGE_MAGIC_AT_OR_BELOW := 2

#同一玩家的同一阶段里，每条无印刷次数限制的主动能力由 AI 尝试一次。
#只存实例 id，不持有效果对象引用；回合/阶段/玩家任一变化即换作用域并清空。
static var _phase_attempt_scope:String = ""
static var _phase_attempted_effect_ids:Dictionary = {}


## 同进程状态令牌：递归复制容器，不克隆 Object；正式集合只存实例 ID 与布尔值。
static func capture_attempts() -> Dictionary:
	return {"scope": _phase_attempt_scope,
		"attempted_effect_ids": _phase_attempted_effect_ids.duplicate(true)}


## 恢复时再次复制，避免实时状态与输入令牌共享容器；空令牌恢复为空状态。
static func restore_attempts(state:Dictionary) -> void:
	_phase_attempt_scope = state.get("scope", "")
	var attempts:Dictionary = state.get("attempted_effect_ids", {})
	_phase_attempted_effect_ids = attempts.duplicate(true)


## 仅清理 AI 的尝试记忆，不推进阶段、不执行效果、不改变决策节奏。
static func clear_attempts() -> void:
	_phase_attempt_scope = ""
	_phase_attempted_effect_ids.clear()


## 只负责从模式提供的合法候选中决策，不在 AI 中重复选人规则。
func pick_master(selection_mode, player_id: int):
	var candidates: Array = selection_mode.available_masters(player_id)
	return RuleRandom.pick(candidates)


#走完该 AI 玩家在当前阶段能做的动作。调用方负责节流与"该不该轮到它"
func step(host, bot_id: int) -> void:
	if not SessionGeneration.validate_context(source_context).ok: return
	var pl_data: Dictionary = GameDataManager.find_player_data(bot_id)
	if pl_data.is_empty(): return
	var phase_name: String = str(GameProgress.get_current_phase().get("name", ""))
	#按"视为处于的阶段"做事：被 phase_as 映射到同一阶段里的前哨与行动依次完成
	var acted: bool = false
	if GameProgress.is_phase_for(bot_id, "outpost") and pl_data.get("location") == null:
		_deploy(host, bot_id)
		acted = true
	if GameProgress.is_phase_for(bot_id, "action"):
		use_command_spell_if_needed(bot_id, pl_data)
		fulfill_action_requirements(bot_id)
		activate_phase_abilities(bot_id)
		if EffectManager.is_waiting_for_choice(): return
		_play_regular_cards(host, bot_id)
		acted = true
	if not acted and (phase_name == "battle" or phase_name == "prepare"):
		#战斗阶段/准备好阶段的主动能力（"战斗阶段：你的总威力+2"这类）必须由使用者发动。
		#AI 不发动就等于永远拿不到自己卡面上的能力，与本地玩家的判定口径不一致。
		activate_phase_abilities(bot_id)
	GameProgress.end_current_player_action(source_context)
	host.refresh_all_ui()


#把此刻能发动的阶段能力逐个发动掉（判据与界面停驻、点击入口同一份 manual_activations）。
#每个能力发动后都重新查一次：选项与费用由既有链路处理，这里只决定"用不用"
func _next_phase_ability(bot_id:int) -> BaseEffect:
	var phase_name:String = str(GameProgress.get_current_phase().get("name", ""))
	var scope:String = "%d:%s:%d" % [GameProgress.current_round,phase_name,bot_id]
	if scope != _phase_attempt_scope:
		_phase_attempt_scope = scope
		_phase_attempted_effect_ids.clear()
	for effect:BaseEffect in EffectManager.manual_activations(bot_id):
		if not _phase_attempted_effect_ids.has(effect.get_instance_id()):
			_phase_attempted_effect_ids[effect.get_instance_id()] = true
			return effect
	return null

func activate_phase_abilities(bot_id:int) -> void:
	for _attempt in range(16):
		var effect:BaseEffect = _next_phase_ability(bot_id)
		if effect == null: return
		if EffectManager.request_manual_activation(effect,bot_id): resolve_active_effect(effect,bot_id)
		if EffectManager.is_waiting_for_choice(): return

func activate_phase_abilities_async(bot_id:int,tree:SceneTree) -> void:
	for _attempt in range(16):
		if not SessionGeneration.validate_context(source_context).ok or GameProgress.current_player_id != bot_id: return
		var effect:BaseEffect = _next_phase_ability(bot_id)
		if effect == null: return
		if EffectManager.request_manual_activation(effect,bot_id): await resolve_active_effect_async(effect,bot_id,tree)
		if EffectManager.is_waiting_for_choice(): return

#行动阶段：把数据声明的"结束行动前必须满足"的条件履行掉。
#条件本身由数据与 ActionRules 判定，这里只提供"用什么动作去满足它"的决策——
#不履行的话引擎会一直拒绝推进，AI 就会永远卡在自己的行动阶段
func fulfill_action_requirements(bot_id: int) -> void:
	for requirement in ActionRules.requirements(bot_id):
		if !ActionRules.unmet(str(requirement), bot_id):
			continue
		match str(requirement):
			ActionRules.COMMAND_SPELL_USED:
				_use_one_command_spell(bot_id,true)
			_:
				#不认识的条件下不猜解法：留在判定层，卡住说明规则数据与 AI 策略不同步
				pass


#用掉一枚此刻可发动的令咒（选项由 resolve_active_effect 选）。没有可发动的返回 false
func _use_one_command_spell(bot_id:int,force:bool = false) -> bool:
	for card in GetPlCommandSpellOutGame.new().exec(bot_id):
		var effects: Array = card.get("_effects") if card != null else []
		for eff in effects:
			if EffectManager.request_manual_activation(eff, bot_id):
				var plan:Dictionary = Planner.plan(eff,bot_id,force)
				apply_effect_plan(eff,plan)
				if plan.activate: return true
	return false


func _use_one_command_spell_async(bot_id:int,tree:SceneTree,force:bool = false) -> bool:
	for card in GetPlCommandSpellOutGame.new().exec(bot_id):
		var effects: Array = card.get("_effects") if card != null else []
		for eff in effects:
			if EffectManager.request_manual_activation(eff, bot_id):
				var plan:Dictionary = await Planner.plan_async(eff,bot_id,tree,force)
				if plan.get("cancelled",false): return false
				apply_effect_plan(eff,plan)
				if plan.activate: return true
	return false


#前哨阶段：在可部署的战区里挑一个、再在该战区挑该占的席位。
#席位不随机：由宿主按"先占满高收益档、同档从左到右"给出，AI 只决定去哪个战区
func _deploy(host, bot_id: int) -> void:
	var areas: Array = host.ai_deploy_areas()
	if areas.is_empty():
		return
	RuleRandom.shuffle(areas)
	var target: BaseLocation = host.ai_pick_deploy_location(areas[0])
	if target == null:
		return
	if operation_router.exec_registered("deploy", [target, bot_id, false, source_context], source_context):
		DeployRules.apply_benefit(target, bot_id, source_context)


#行动阶段：魔力不足或正处于交战时用一枚令咒（选项由 resolve_active_effect 自动选）。
#公开入口：这一条策略可以单独驱动（测试与将来更聪明的 AI 都用得上）
func use_command_spell_if_needed_async(bot_id:int,pl_data:Dictionary,tree:SceneTree) -> void:
	if _command_spell_needed(pl_data): await _use_one_command_spell_async(bot_id,tree)

func fulfill_action_requirements_async(bot_id:int,tree:SceneTree) -> void:
	for requirement in ActionRules.requirements(bot_id):
		if ActionRules.unmet(str(requirement),bot_id) and str(requirement) == ActionRules.COMMAND_SPELL_USED:
			await _use_one_command_spell_async(bot_id,tree,true)

func use_command_spell_if_needed(bot_id: int, pl_data: Dictionary) -> void:
	if _command_spell_needed(pl_data): _use_one_command_spell(bot_id)

func _command_spell_needed(pl_data:Dictionary) -> bool:
	var cs_num: int = int((pl_data.get("command_spell_count", BaseNumber.new(0)) as BaseNumber).number)
	if cs_num <= 0:
		return false
	var magic_num: int = int((pl_data.get("magic", BaseNumber.new(0)) as BaseNumber).number)
	var should_use: bool = magic_num <= CS_CHARGE_MAGIC_AT_OR_BELOW or bool(pl_data.get("is_battle", false))
	return should_use


# 行动阶段先无副作用挑出完整一组，再一次提交；不能逐张结算后按变化的上限继续选。
func _play_regular_cards(host, bot_id: int) -> void:
	if RegularPlay.completed(bot_id):
		return
	last_search = make_search(bot_id).run_sync()
	_submit_search(host,bot_id,last_search)

func _submit_search(host, bot_id:int, result:Dictionary) -> void:
	if result.cancelled or not SessionGeneration.validate_context(source_context).ok: return
	var group:Dictionary = result.group
	if not group.is_empty():
		RegularPlay.submit_group(bot_id,group.cards,group.hidden,false,source_context)
	elif RegularPlay.can_end(bot_id):
		RegularPlay.finalize(bot_id,true,source_context)
	if RegularPlay.completed(bot_id):
		var logs := GameLog.query({"type": "play", "actor": bot_id, "data": {"extra": false}}, 0, 1)
		if !logs.is_empty():
			host.ai_record_played_card(bot_id, logs[0].object)


## B 档估计规划；真实费用、次数与选择合法性最终由规则提交入口复核。
func resolve_active_effect_async(effect:BaseEffect,bot_id:int,tree:SceneTree) -> void:
	var plan:Dictionary = await Planner.plan_async(effect,bot_id,tree,not EffectManager.choice_allows_cancel(effect))
	apply_effect_plan(effect,plan)

func resolve_active_effect(effect: BaseEffect, bot_id: int) -> void:
	if effect == null:
		return
	var plan:Dictionary = Planner.plan(effect,bot_id,not EffectManager.choice_allows_cancel(effect))
	apply_effect_plan(effect,plan)

func apply_effect_plan(effect:BaseEffect,plan:Dictionary) -> void:
	if plan.get("cancelled",false): return
	print("AI_EFFECT_ESTIMATE tier=B estimate=",plan.estimate," activate=",plan.activate)
	if plan.activate and effect.has_options():
		for index in plan.quantities: effect.set_option_quantity(index,plan.quantities[index])
		EffectManager.submit_option_choice(effect,plan.selection)
	else:
		EffectManager.submit_active_choice(effect,plan.activate)



## 等玩家挑牌：枚举声明范围内的组合，以印刷威力作 B 档启发价值。
func resolve_card_selection(pending: Dictionary) -> void:
	var eff: BaseEffect = pending.get("effect")
	if eff == null:
		return
	var live: Dictionary = EffectManager.get_pending_card_selection()
	if live.get("effect") != eff:
		return
	pending = live
	var picks:Array = Planner.choose(pending.get("cards",[]),int(pending.get("min",1)),int(pending.get("max",1)),pending.get("required_cards",[]),func(card): return card._power.number if card is BaseHandCard else 0)
	EffectManager.submit_card_selection(eff,picks)



## 等玩家选位置：候选计算复用宿主的地图落点规则；没有合法位置时显式取消。
## 每战区只使用 UI 的一个合法落点，以地利数字作 B 档启发价值。
func resolve_location_selection(pending: Dictionary, host) -> void:
	var eff: BaseEffect = pending.get("effect")
	if eff == null:
		return
	var query = SeatsQuery.new(Builder.new(),source_context)
	var targets:Array = query.location_candidates(pending).values()
	var picks:Array = Planner.choose(targets,1,1,[],func(location): return location._benefit.number)
	print("AI_EFFECT_ESTIMATE tier=B location_candidates=",targets.size())
	EffectManager.submit_location_selection(eff,picks[0] if not picks.is_empty() else null)



## 等玩家选目标：枚举声明人数范围，以当前总威力作 B 档启发价值。
func resolve_player_selection(pending: Dictionary) -> void:
	var eff: BaseEffect = pending.get("effect")
	if eff == null:
		return
	var spec: Dictionary = pending.get("spec", {})
	var candidates: Array = pending.get("candidates", [])
	var picks:Array = Planner.choose(candidates,int(spec.get("min",1)),int(spec.get("max",spec.get("min",1))),[],func(id): return GetPlayerTotalPower.breakdown(id).total)
	EffectManager.submit_player_selection(eff,picks)

func resolve_selection_async(kind:String,pending:Dictionary,tree:SceneTree) -> void:
	var effect:BaseEffect = pending.get("effect")
	if effect == null or not effect.runtime_source_status().ok: return
	var candidates:Array = []
	var required:Array = []
	var low:int = 1
	var high:int = 1
	var value:Callable
	match kind:
		"cards":
			pending = EffectManager.get_pending_card_selection()
			candidates = pending.get("cards",[])
			required = pending.get("required_cards",[])
			low = int(pending.get("min",1)); high = int(pending.get("max",1))
			value = func(card): return card._power.number if card is BaseHandCard else 0
		"players":
			pending = EffectManager.get_pending_player_selection()
			candidates = pending.get("candidates",[])
			low = int(pending.get("spec",{}).get("min",1)); high = int(pending.get("spec",{}).get("max",low))
			value = func(id): return GetPlayerTotalPower.breakdown(id).total
		"location":
			pending = EffectManager.get_pending_location_selection()
			candidates = SeatsQuery.new(Builder.new(),source_context).location_candidates(pending).values()
			value = func(location): return location._benefit.number
		_: return
	if pending.get("effect") != effect: return
	var result:Dictionary = await Planner.choose_async(candidates,low,high,required,value,tree)
	if result.cancelled or not effect.runtime_source_status().ok: return
	var picks:Array = result.group.get("cards",[])
	print("AI_EFFECT_ESTIMATE tier=B selection=",kind," nodes=",result.nodes)
	match kind:
		"cards": EffectManager.submit_card_selection(effect,picks)
		"players": EffectManager.submit_player_selection(effect,picks)
		"location": EffectManager.submit_location_selection(effect,picks[0] if not picks.is_empty() else null)

func make_search(bot_id:int):
	var query = SeatsQuery.new(Builder.new(),source_context)
	var payment:Dictionary = query.payment_quote(bot_id)
	var candidates:Array = RegularPlay.candidates(bot_id)
	var round_id:int = GameProgress.current_round
	var phase:int = GameProgress.current_phase_index
	var data:Dictionary = GameDataManager.find_player_data(bot_id)
	var baseline:int = int(query.preview(bot_id,[],[],payment).get("power_breakdown",{}).get("total",0))
	var dynamic:bool = false
	var board:Array = [MapData.active_situation] if MapData.active_situation != null else []
	for area in MapData.areas: board.append_array(area._events)
	for card in board:
		for effect in card._effects:
			if not effect._power_query.is_empty(): dynamic = true
	var score_query:Callable = func(cards:Array,flags:Array) -> float:
		return float(query.preview(bot_id,cards,flags,payment).get("power_breakdown",{}).get("total",-INF))
	var modes_query:Callable = func(cards:Array,flags:Array,card) -> Array:
		return RegularPlay.pending_modes(bot_id,cards,flags,card,payment)
	var legal_query:Callable = func(cards:Array,flags:Array) -> bool:
		return RegularPlay.can_submit_group(bot_id,cards,flags,false,payment)
	var upper_query:Callable = func(cards:Array,flags:Array,start:int) -> float:
		if dynamic: return INF
		var value:float = baseline
		for i in cards.size():
			if CardCountsPower.new().counts_when_played(cards[i],flags[i],bot_id): value += int(cards[i]._power.number)
		for i in range(start,candidates.size()): value += maxi(0,int(candidates[i]._power.number))
		return value
	var equivalent_query:Callable = func(card) -> Variant:
		if dynamic or not card._effects.is_empty() or not card._play_requirements.is_empty() or card._need_extra_play or not card._keywords.is_empty() or not card._faces.is_empty() or not card._attached_cards.is_empty(): return null
		return str([card.get_script().resource_path,card._name,card._cost.number,card._cost_discount.number,card._power.number,card._attributes,card.get("_category"),card._is_concealed,card.get("_is_awakened"),card.get("_ignore_limit"),RegularPlay.in_play_zone(data,card)])
	var current_query:Callable = func() -> bool:
		return RegularPlay.payment_quote_is_current(bot_id,payment) and GameProgress.current_player_id == bot_id and GameProgress.current_round == round_id and GameProgress.current_phase_index == phase and not GameProgress.is_game_over and not data.get("is_out",false) and not EffectManager.is_waiting_for_choice()
	return Search.new(candidates,modes_query,legal_query,score_query,upper_query,equivalent_query,current_query,search_budget)

func step_async(host,bot_id:int,tree:SceneTree) -> void:
	if not SessionGeneration.validate_context(source_context).ok: return
	var data:Dictionary = GameDataManager.find_player_data(bot_id)
	if data.is_empty(): return
	if GameProgress.is_phase_for(bot_id,"outpost") and data.get("location") == null: _deploy(host,bot_id)
	if GameProgress.is_phase_for(bot_id,"action"):
		await use_command_spell_if_needed_async(bot_id,data,tree)
		await fulfill_action_requirements_async(bot_id,tree)
		await activate_phase_abilities_async(bot_id,tree)
		if EffectManager.is_waiting_for_choice(): return
		if not RegularPlay.completed(bot_id):
			var search = make_search(bot_id)
			last_search = await Planner.run_sliced(search,tree,true)
			_submit_search(host,bot_id,last_search)
			if last_search.cancelled: return
	elif str(GameProgress.get_current_phase().get("name","")) in ["battle","prepare"]:
		await activate_phase_abilities_async(bot_id,tree)
	if SessionGeneration.validate_context(source_context).ok and GameProgress.current_player_id == bot_id:
		GameProgress.end_current_player_action(source_context)
		host.refresh_all_ui()
