class_name ActivateEffect
extends RefCounted

#让一项已经存在的效果作为某名玩家的一次使用进入结算（"再用一次某能力""组合使用""发动对手的能力"）。
#不看它的时点是否命中——发动时机由调用方决定；但仍遵守效果自己的规则：
#失去文字/被禁用/每局一次/需激活、选项次数与资源、费用，都照常经由同一条询问与结算链。
#效果已归属别的玩家时复制一份给这名玩家用，用完即移除，不改原效果的归属与用量。
#返回实际排进结算的那个效果，被规则拦下时返回 null
func exec(effect:BaseEffect, player_id:int = -1):

	if effect == null:
		return null
	var id:int = EffectManager.resolve_player_id(player_id)
	var target:BaseEffect = effect
	if effect._trigger_player_id != -1 and effect._trigger_player_id != id:
		target = CloneObject.new().exec(effect) as BaseEffect
		if target == null:
			return null
		target._remove_after_trigger = true
	EffectManager.register_effect(target, id)
	if !EffectManager.card_state_allows(target):
		return null
	if target.has_options() and !EffectManager.has_available_options(target):
		return null
	if !EffectManager.can_pay_effect_cost(target):
		return null
	#不按时点匹配：命中集合直接记成它自己的时点，关闭时点时照样能被打断
	EffectManager.matched_time_points[target] = target._time_points.duplicate()
	target._trigger_time_points = target._time_points.duplicate()
	EffectManager.resolved_effects.erase(target)
	#强制效果不经询问直接结算，费用在这里付；需要玩家决定的走询问链，由它在确认时付
	if target._is_pure_passive and !target.has_options():
		if !EffectManager.pay_effect_cost(target):
			return null
		EffectManager.add_to_activation_pool(target)
	elif !EffectManager.decision_queue.has(target):
		EffectManager.decision_queue.append(target)
	if !EffectManager.is_running:
		EffectManager.run_pipeline()
	return target
