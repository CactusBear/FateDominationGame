class_name DummyBot
extends RefCounted

#临时测试用 AI：替人类玩家行动的占位决策。放在 system/ai/temp 下表示它是过渡实现，
#将来换成真 AI 时只替换这个目录里的文件，规则层与界面层都不用改。
#
#职责边界：
#  · 决策全部在这里（部署取舍、常规出牌、令咒、以及各种"等待玩家输入"的自动答复）；
#  · 规则数字走引擎既有入口（RegularPlay.modes/find_add、EffectManager 的可用性判据），
#    本文件不自己判断"能不能打出"；
#  · 与界面只有三件展示/查询往来，通过 host 注入（宿主实现同名的公开方法）：
#      ai_deploy_areas()                     可以部署的战区列表
#      ai_pick_deploy_location(area)         该战区里该占的席位
#      ai_apply_deploy_benefit(loc, bot_id)  部署落位后的席位收益
#      ai_record_played_card(bot_id, card)   把"它刚打出的牌"记给界面做提示
#      refresh_all_ui()                      动作做完后整屏刷新
#    这样 AI 不直接摸界面的私有状态，界面也不必知道 AI 的策略。

#AI 策略参数（不是游戏规则，改这里不影响规则层）：
#魔力不高于此值时，优先用令咒换魔力
const CS_CHARGE_MAGIC_AT_OR_BELOW := 2

#同一玩家的同一阶段里，每条无印刷次数限制的主动能力只由临时 AI 尝试一次。
#只存实例 id，不持有效果对象引用；回合/阶段/玩家任一变化即换作用域并清空。
static var _phase_attempt_scope:String = ""
static var _phase_attempted_effect_ids:Dictionary = {}


#走完该 AI 玩家在当前阶段能做的动作。调用方负责节流与"该不该轮到它"
func step(host, bot_id: int) -> void:
	var pl_data: Dictionary = GameDataManager.get_player_data(bot_id)
	var phase_name: String = str(GameProgress.get_current_phase().get("name", ""))
	if phase_name == "outpost":
		_deploy(host, bot_id)
	elif phase_name == "action":
		use_command_spell_if_needed(bot_id, pl_data)
		fulfill_action_requirements(bot_id)
		_play_regular_cards(host, bot_id)
	elif phase_name == "battle" or phase_name == "prepare":
		#战斗阶段/准备好阶段的主动能力（"战斗阶段：你的总威力+2"这类）必须由使用者发动。
		#AI 不发动就等于永远拿不到自己卡面上的能力，与本地玩家的判定口径不一致。
		activate_phase_abilities(bot_id)
	GameProgress.end_current_player_action()
	host.refresh_all_ui()


#把此刻能发动的阶段能力逐个发动掉（判据与界面停驻、点击入口同一份 manual_activations）。
#每个能力发动后都重新查一次：选项与费用由既有链路处理，这里只决定"用不用"
func activate_phase_abilities(bot_id: int) -> void:
	var phase_name:String = str(GameProgress.get_current_phase().get("name", ""))
	var scope:String = "%d:%s:%d" % [GameProgress.current_round, phase_name, bot_id]
	if scope != _phase_attempt_scope:
		_phase_attempt_scope = scope
		_phase_attempted_effect_ids.clear()
	var guard:int=0
	while guard < 16:
		guard+=1
		var usable:Array=EffectManager.manual_activations(bot_id)
		var effect:BaseEffect=null
		for candidate:BaseEffect in usable:
			if !_phase_attempted_effect_ids.has(candidate.get_instance_id()):
				effect=candidate
				break
		if effect == null:
			return
		#卡面没写次数限制时不能替规则补限制；这里只约束临时 AI 的阶段决策，
		#跨帧再次 step 也不会反复选择同一条能力。
		_phase_attempted_effect_ids[effect.get_instance_id()] = true
		if not EffectManager.request_manual_activation(effect, bot_id):
			continue
		resolve_active_effect(effect, bot_id)


#行动阶段：把数据声明的"结束行动前必须满足"的条件履行掉。
#条件本身由数据与 ActionRules 判定，这里只提供"用什么动作去满足它"的决策——
#不履行的话引擎会一直拒绝推进，AI 就会永远卡在自己的行动阶段
func fulfill_action_requirements(bot_id: int) -> void:
	for requirement in ActionRules.requirements(bot_id):
		if !ActionRules.unmet(str(requirement), bot_id):
			continue
		match str(requirement):
			ActionRules.COMMAND_SPELL_USED:
				_use_one_command_spell(bot_id)
			_:
				#不认识的条件下不猜解法：留在判定层，卡住说明规则数据与 AI 策略不同步
				pass


#用掉一枚此刻可发动的令咒（选项由 resolve_active_effect 选）。没有可发动的返回 false
func _use_one_command_spell(bot_id: int) -> bool:
	for card in GetPlCommandSpellOutGame.new().exec(bot_id):
		var effects: Array = card.get("_effects") if card != null else []
		for eff in effects:
			if EffectManager.request_manual_activation(eff, bot_id):
				resolve_active_effect(eff, bot_id)
				return true
	return false


#前哨阶段：在可部署的战区里挑一个、再在该战区挑该占的席位。
#席位不随机：由宿主按"先占满高收益档、同档从左到右"给出，AI 只决定去哪个战区
func _deploy(host, bot_id: int) -> void:
	var areas: Array = host.ai_deploy_areas()
	if areas.is_empty():
		return
	areas.shuffle()
	var target: BaseLocation = host.ai_pick_deploy_location(areas[0])
	if target == null:
		return
	Deploy.new().exec(target, bot_id)
	host.ai_apply_deploy_benefit(target, bot_id)


#行动阶段：魔力不足或正处于交战时用一枚令咒（选项由 resolve_active_effect 自动选）。
#公开入口：这一条策略可以单独驱动（测试与将来更聪明的 AI 都用得上）
func use_command_spell_if_needed(bot_id: int, pl_data: Dictionary) -> void:
	var cs_num: int = int((pl_data.get("command_spell_count", BaseNumber.new(0)) as BaseNumber).number)
	if cs_num <= 0:
		return
	var magic_num: int = int((pl_data.get("magic", BaseNumber.new(0)) as BaseNumber).number)
	var should_use: bool = magic_num <= CS_CHARGE_MAGIC_AT_OR_BELOW or bool(pl_data.get("is_battle", false))
	if !should_use:
		return
	_use_one_command_spell(bot_id)


# 行动阶段先无副作用挑出完整一组，再一次提交；不能逐张结算后按变化的上限继续选。
func _play_regular_cards(host, bot_id: int) -> void:
	if RegularPlay.completed(bot_id):
		return
	var preferred: Array = []
	for card in RegularPlay.candidates(bot_id):
		if card is BaseSkill:
			preferred.append(card)
	var group: Dictionary = RegularPlay.find_group(bot_id, preferred)
	if not group.is_empty():
		RegularPlay.submit_group(bot_id, group["cards"], group["hidden"])
	elif RegularPlay.can_end(bot_id):
		RegularPlay.finalize(bot_id, true)
	if RegularPlay.completed(bot_id):
		var logs := GameLog.query({"type": "play", "actor": bot_id, "data": {"extra": false}}, 0, 1)
		if !logs.is_empty():
			host.ai_record_played_card(bot_id, logs[0].object)


## 等玩家答复的效果：由 AI 代答。采纳判据只看"付不付得起"（成本门槛交给引擎），
## 选项类效果单选取第一个仍可用的选项、多选取足 max_choices 个
func resolve_active_effect(effect: BaseEffect, bot_id: int) -> void:
	if effect == null:
		return
	var should_act: bool = EffectManager.can_pay_effect_cost(effect)
	if effect.has_options():
		if !should_act or !EffectManager.has_available_options(effect):
			EffectManager.submit_active_choice(effect, false)
		elif effect.allows_multi_choice():
			var max_c: int = effect._max_choices
			var available_indices: Array = []
			for i in range(effect._options.size()):
				if EffectManager.is_option_available(effect, i, 1):
					available_indices.append(i)
			var pick_count: int = available_indices.size() if max_c == -1 else mini(max_c, available_indices.size())
			EffectManager.submit_option_choice(effect, available_indices.slice(0, pick_count))
		else:
			var first_available := -1
			for i in range(effect._options.size()):
				if EffectManager.is_option_available(effect, i, 1):
					first_available = i
					break
			if first_available == -1:
				EffectManager.submit_active_choice(effect, false)
			else:
				EffectManager.submit_option_choice(effect, [first_available])
	else:
		EffectManager.submit_active_choice(effect, should_act)


## 等玩家挑牌：按声明的最小张数从候选里取前几张；取不够就按放弃提交
func resolve_card_selection(pending: Dictionary) -> void:
	var eff: BaseEffect = pending.get("effect")
	if eff == null:
		return
	var cards: Array = pending.get("cards", [])
	var low: int = int(pending.get("min", 1))
	var picks: Array = []
	for card in cards:
		if picks.size() >= low:
			break
		picks.append(card)
	if picks.size() < low:
		picks = []
	EffectManager.submit_card_selection(eff, picks)


## 等玩家选位置：候选计算复用宿主的地图落点规则；没有合法位置时显式取消。
## AI 不认识战区名称、容量或特殊席位，只决定采用宿主给出的第一个合法目标。
func resolve_location_selection(pending: Dictionary, host) -> void:
	var eff: BaseEffect = pending.get("effect")
	if eff == null:
		return
	var spec: Dictionary = pending.get("spec", {})
	var target: BaseLocation = null
	if host != null and host.has_method("ai_pick_effect_location"):
		target = host.ai_pick_effect_location(spec)
	EffectManager.submit_location_selection(eff, target)


## 等玩家选目标：按候选集取足声明的最小人数（候选顺序由数据决定）
func resolve_player_selection(pending: Dictionary) -> void:
	var eff: BaseEffect = pending.get("effect")
	if eff == null:
		return
	var spec: Dictionary = pending.get("spec", {})
	var candidates: Array = pending.get("candidates", [])
	var need: int = maxi(1, int(spec.get("min", 1)))
	EffectManager.submit_player_selection(eff, candidates.slice(0, need))
