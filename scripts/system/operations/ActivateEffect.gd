class_name ActivateEffect
extends RefCounted

#让一项已经存在的效果作为某名玩家的一次使用进入结算（"再用一次某能力""组合使用""发动对手的能力"）。
#不看它的时点是否命中——发动时机由调用方决定；但仍遵守效果自己的规则：
#失去文字/被禁用/每局一次/需激活、选项次数与资源、费用，都照常经由同一条询问与结算链。
#效果已归属别的玩家时复制一份给这名玩家用，用完即移除，不改原效果的归属与用量。
#返回实际排进结算的那个效果，被规则拦下时返回 null
#登记尝试独立于选项字典，由管理器持有；同一 target 重入按尝试栈保存。
const REGISTRATION_ATTEMPTS := &"activate_effect_registration_attempts"

static func registration_attempts() -> Dictionary:
	if !EffectManager.has_meta(REGISTRATION_ATTEMPTS):
		EffectManager.set_meta(REGISTRATION_ATTEMPTS, {})
	return EffectManager.get_meta(REGISTRATION_ATTEMPTS)

#实际支付成功时只丢弃前态，不改规则/队列/日志。
static func accept_registration(effect:BaseEffect) -> void:
	if !EffectManager.has_meta(REGISTRATION_ATTEMPTS): return
	var attempts:Dictionary = EffectManager.get_meta(REGISTRATION_ATTEMPTS)
	if !attempts.has(effect) or (attempts[effect] as Array).is_empty(): return
	if !_attempt_is_current(effect, (attempts[effect] as Array).back()): return
	(attempts[effect] as Array).pop_back()
	if (attempts[effect] as Array).is_empty(): attempts.erase(effect)

#实际拒绝/取消的终态写入和续行之前调用；false 必须走完整恢复门。
static func reject_registration(effect:BaseEffect) -> bool:
	if !EffectManager.has_meta(REGISTRATION_ATTEMPTS): return true
	var attempts:Dictionary = EffectManager.get_meta(REGISTRATION_ATTEMPTS)
	if !attempts.has(effect) or (attempts[effect] as Array).is_empty(): return true
	if bool(EffectManager.runtime_guard_status().get("paused", false)): return false
	var state:Dictionary = (attempts[effect] as Array).back()
	if !_attempt_is_current(effect, state): return false
	if !is_same(EffectManager.effect_pool, state.pool): return false
	if state.context_written:
		if !is_same(EffectManager.matched_time_points, state.matched_store): return false
		if !is_same(EffectManager.resolved_effects, state.resolved_store): return false
		if !EffectManager.matched_time_points.has(effect): return false
		if !is_same(EffectManager.matched_time_points[effect], state.written_matched): return false
		if !is_same(effect._trigger_time_points, state.written_trigger): return false
		if effect._trigger_time_points != state.expected_points or state.written_matched != state.expected_points: return false
		if EffectManager.resolved_effects.has(effect): return false
	#只撤销此次追加的成员，不注销此前已登记对象或摘其既有队列/等待。
	if !state.pool_had: (state.pool as Array).erase(effect)
	if !state.self_had: (state.self_effects as Array).erase(effect)
	effect._trigger_player_id = state.owner
	if state.context_written:
		if state.matched_had: EffectManager.matched_time_points[effect] = state.matched
		else: EffectManager.matched_time_points.erase(effect)
		if state.resolved_had: EffectManager.resolved_effects[effect] = state.resolved
		else: EffectManager.resolved_effects.erase(effect)
		effect._trigger_time_points = state.trigger
	if state.created_clone:
		#CloneObject 构造时还加入两个对象表，只删除此次创建的确切 clone。
		GameData.effects.erase(effect)
		GameData.objects.erase(effect)
	#前置已经验过本栈顶；恢复 owner 后不能再按激活 owner 复验而遗留本条。
	(attempts[effect] as Array).pop_back()
	if (attempts[effect] as Array).is_empty(): attempts.erase(effect)
	return true

#reset/完整恢复的所有者在规则恢复后清记录，不能以此代替登记补偿。
static func clear_registration_attempts() -> void:
	if EffectManager.has_meta(REGISTRATION_ATTEMPTS):
		EffectManager.remove_meta(REGISTRATION_ATTEMPTS)

#同一调用固定原来源；只读验证，不给旧对象绑定或领取当前票。
static func _source_is_current(effect:BaseEffect, context:Variant, effect_context:SessionContext) -> bool:
	if !(context is SessionContext): return false
	if !SessionGeneration.validate_context(context).get("ok", false): return false
	if effect == null or !effect.runtime_source_status().get("ok", false): return false
	return is_same(effect.runtime_context(), effect_context) and is_same(context.token(), effect_context.token())

#补偿记录属于精确 target 和真实 owner，不用同 ID 或 activating_eff 猜归属。
static func _attempt_is_current(effect:BaseEffect, state:Dictionary) -> bool:
	if !is_same(state.get("target"), effect): return false
	if !_source_is_current(state.get("source_effect"), state.get("context"), state.get("source_context")): return false
	if !_source_is_current(effect, state.get("context"), state.get("target_context")): return false
	if !EffectManager.can_register_effect(state.source_effect, state.source_owner): return false
	if effect._trigger_player_id != state.player_id: return false
	if state.player_id != -1:
		var owner:Dictionary = GameDataManager.find_player_data(state.player_id)
		if !is_same(owner, state.owner_data) or !is_same(owner.get("self_effects"), state.self_effects): return false
	return EffectManager.can_register_effect(effect, state.player_id)

static func _activation_is_current(effect:BaseEffect, state:Dictionary, in_frame:bool) -> bool:
	if !_attempt_is_current(effect, state): return false
	if in_frame:
		var source:Dictionary = EffectManager.execution_context()
		if !source.get("ok", false) or !is_same(source.get("context"), state.context): return false
	return true

#帧内调用必须保留同一原帧；直接调用必须显式传入原调用来源。
#这里只读原句柄，缺来源即拒绝；不以目标效果/当前局/activating_eff 补票。
func exec(effect:BaseEffect, player_id:int = -1, context:Variant = null):
	if effect == null:
		return null
	var frame_source:Dictionary = EffectManager.execution_context()
	var in_frame:bool = !EffectManager.execution_runtime_snapshot().get("functions", []).is_empty()
	if in_frame and !frame_source.get("ok", false): return null
	if context == null and in_frame:
		context = frame_source.get("context")
	if in_frame and !is_same(frame_source.get("context"), context): return null
	var effect_context:SessionContext = effect.runtime_context()
	if !_source_is_current(effect, context, effect_context): return null
	var id:int = EffectManager.resolve_player_id(player_id)
	#克隆会进入对象总表且不复制登记 metadata；先验目标成员和原对象资格，
	#不能靠克隆把已被登记门拒绝的旧主体洗成新对象。
	if id != -1 and GameDataManager.find_player_data(id).is_empty():
		return null
	var needs_clone:bool = effect._trigger_player_id != -1 and effect._trigger_player_id != id
	if not EffectManager.can_register_effect(effect, effect._trigger_player_id if needs_clone else id):
		return null
	var target:BaseEffect = effect
	var created_clone:bool = false
	if needs_clone:
		target = CloneObject.new().exec(effect) as BaseEffect
		if target == null:
			return null
		created_clone = true
		target._remove_after_trigger = true
	var owner_data:Dictionary = GameDataManager.find_player_data(id) if id != -1 else {}
	var self_effects:Array = owner_data.get("self_effects", [])
	var state:Dictionary = {
		"target": target, "context": context, "source_effect": effect,
		"source_context": effect_context, "target_context": target.runtime_context(),
		"source_owner": effect._trigger_player_id, "owner_data": owner_data,
		"player_id": id, "owner": target._trigger_player_id,
		"pool": EffectManager.effect_pool, "pool_had": EffectManager.effect_pool.has(target),
		"self_effects": self_effects, "self_had": self_effects.has(target),
		"matched_store": EffectManager.matched_time_points,
		"resolved_store": EffectManager.resolved_effects,
		"matched_had": EffectManager.matched_time_points.has(target),
		"matched": EffectManager.matched_time_points.get(target),
		"resolved_had": EffectManager.resolved_effects.has(target),
		"resolved": EffectManager.resolved_effects.get(target),
		"trigger": target._trigger_time_points, "context_written": false,
		"created_clone": created_clone,
	}
	#新 clone 尚未登记；先按真实目标 owner 检查卡牌状态，避免必拒绝对象
	#先登记而留下管理器的身份保活 metadata。原对象不临时换主。
	var card_allowed:bool = true
	if created_clone:
		target._trigger_player_id = id
		card_allowed = EffectManager.card_state_allows(target)
		if !_source_is_current(effect, context, effect_context) or !_source_is_current(target, context, state.target_context) or !card_allowed:
			GameData.effects.erase(target)
			GameData.objects.erase(target)
			return null
	#只有实际登记成功且原来源仍有效才建立补偿尝试。
	if !_source_is_current(effect, context, effect_context) or !_source_is_current(target, context, state.target_context):
		if created_clone:
			GameData.effects.erase(target)
			GameData.objects.erase(target)
		return null
	if not EffectManager.register_effect(target, id):
		#审计故障由原完整恢复门处理，不在普通拒绝分支撤销审计对象。
		if created_clone and not bool(EffectManager.runtime_guard_status().get("paused", false)):
			GameData.effects.erase(target)
			GameData.objects.erase(target)
		return null
	if !_activation_is_current(target, state, in_frame): return null
	var attempts:Dictionary = registration_attempts()
	if !attempts.has(target): attempts[target] = []
	(attempts[target] as Array).append(state)
	#保留既有审计暂停门，不把暂停解释成普通规则拒绝。
	var guard_status:Dictionary = EffectManager.runtime_guard_status()
	if bool(guard_status.get("paused", false)) and str(guard_status.get("reason", "")) == "audit_write_failed":
		return null
	if !created_clone: card_allowed = EffectManager.card_state_allows(target)
	if !_activation_is_current(target, state, in_frame): return null
	if !card_allowed:
		reject_registration(target)
		return null
	if target.has_options():
		var options_allowed:bool = EffectManager.has_available_options(target)
		if !_activation_is_current(target, state, in_frame): return null
		if !options_allowed:
			reject_registration(target)
			return null
	var cost_allowed:bool = EffectManager.can_pay_effect_cost(target)
	if !_activation_is_current(target, state, in_frame): return null
	if !cost_allowed:
		reject_registration(target)
		return null
	#不按时点匹配：命中集合直接记成它自己的时点，关闭时点时照样能被打断
	EffectManager.matched_time_points[target] = target._time_points.duplicate()
	target._trigger_time_points = target._time_points.duplicate()
	EffectManager.resolved_effects.erase(target)
	state.context_written = true
	state.written_matched = EffectManager.matched_time_points[target]
	state.written_trigger = target._trigger_time_points
	state.expected_points = target._time_points.duplicate()
	#强制效果不经询问直接结算，费用在这里付；需要玩家决定的走询问链，由它在确认时付
	if target._is_pure_passive and !target.has_options():
		var paid:bool = EffectManager.pay_effect_cost(target)
		if !_activation_is_current(target, state, in_frame): return null
		if !paid:
			reject_registration(target)
			return null
		accept_registration(target)
		EffectManager.add_to_activation_pool(target)
	elif !EffectManager.decision_queue.has(target):
		EffectManager.decision_queue.append(target)
	if !EffectManager.is_running:
		EffectManager.run_pipeline()
	if !_activation_is_current(target, state, in_frame): return null
	return target
