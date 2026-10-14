extends RefCounted

const Search = preload("res://scripts/system/ai/group_search.gd")

# B 档声明数值估计：威力/魔力增量作启发价值，魔力不冒称已结算威力。
# shortcut: 未知/条件/变量链记零；需要真实因果评分时必须先具备严格无副作用沙箱。
static func declared_power(funcs:Array, effect:BaseEffect, quantities:Dictionary = {}) -> int:
	var total:int = 0
	for fn in funcs:
		if not fn is BaseFunc or fn._condition != null: continue
		var p:Array = fn._parameters
		var slot:int = 1
		if fn._name == "edit_data_number":
			if p.is_empty() or not p[0] is String or p[0] not in ["power","total_power_bonus"]: continue
			slot = 2
		elif fn._name not in ["edit_power","edit_magic"]: continue
		if p.size() <= slot: continue
		var actor:Variant = p[slot + 1] if p.size() > slot + 1 else -1
		if actor != null and not (actor is int or actor is float): continue
		if actor != null and actor != -1 and actor != effect._trigger_player_id: continue
		var value:Variant = p[slot]
		if value is Dictionary:
			if value.has("number_index"):
				var index:int = int(value.number_index)
				value = effect.numbers[index] if index >= 0 and index < effect.numbers.size() else 0
			elif value.has("option_quantity_index"):
				value = quantities.get(int(value.option_quantity_index), 0)
			else: value = 0
		if value is BaseNumber: total += int(value.number)
		elif value is int or value is float: total += int(value)
	return total

static func prepare(effect:BaseEffect, bot_id:int, force:bool = false) -> Dictionary:
	var baseline:int = int(GetPlayerTotalPower.breakdown(bot_id).total)
	var empty := {"activate":false, "selection":{}, "quantities":{}, "estimate":baseline, "tier":"B"}
	if not EffectManager.can_pay_effect_cost(effect): return {"plan":empty}
	if not effect.has_options():
		var delta:int = declared_power(effect._funcs, effect)
		return {"plan":{"activate":force or delta > 0 or not EffectManager.choice_allows_cancel(effect), "selection":{}, "quantities":{}, "estimate":baseline + delta, "tier":"B"}}
	var items:Array = range(effect._options.size())
	var mode_query:Callable = func(cards:Array, flags:Array, index:int) -> Array:
		var used:int = 0
		for flag in flags: used += int(flag.count)
		var cap:int = Search.NODE_BUDGET
		for limit in [effect._max_choices, effect._max_total_uses - EffectManager.get_total_use_count(effect) if effect._max_total_uses != -1 else -1, EffectManager.get_source_resource_level(effect)]:
			if limit != -1: cap = mini(cap, maxi(0, int(limit) - used))
		var opt:Dictionary = effect._options[index]
		if int(opt.get("max_uses",-1)) != -1: cap = mini(cap, int(opt.max_uses) - EffectManager.get_option_use_count(effect,index))
		var result:Array = []
		var bounds:Array = opt.get("quantity_range", [0,0])
		# shortcut: 不限次数/数量空间只展开节点预算内前缀；有精确效果模拟时再升级。
		for count in range(1, maxi(0,cap) + 1):
			if not EffectManager.is_option_available(effect,index,count): break
			for quantity in range(int(bounds[0]), mini(int(bounds[1]) + 1, int(bounds[0]) + Search.NODE_BUDGET)):
				result.append({"count":count, "quantity":quantity})
				if result.size() >= Search.NODE_BUDGET: return result
		return result
	var legal_query:Callable = func(cards:Array, flags:Array) -> bool:
		var selection:Dictionary = {}
		for i in cards.size(): selection[cards[i]] = int(flags[i].count)
		return EffectManager.validate_selection(effect,selection)
	var score_query:Callable = func(cards:Array, flags:Array) -> float:
		var value:int = baseline
		for i in cards.size():
			value += declared_power(effect._options[cards[i]].get("funcs",[]), effect, {cards[i]:flags[i].quantity}) * int(flags[i].count) if flags[i] is Dictionary else 0
		return value
	var search = Search.new(items,mode_query,legal_query,score_query)
	return {"search":search,"baseline":baseline,"force":force,"effect":effect,"empty":empty}

static func complete(state:Dictionary) -> Dictionary:
	if state.has("plan"): return state.plan
	var search = state.search
	var group:Dictionary = search.result().group
	if group.is_empty() or (search.best_score <= state.baseline and not state.force and EffectManager.choice_allows_cancel(state.effect)): return state.empty
	var selection:Dictionary = {}
	var quantities:Dictionary = {}
	for i in group.cards.size():
		selection[group.cards[i]] = group.hidden[i].count
		quantities[group.cards[i]] = group.hidden[i].quantity
	return {"activate":true, "selection":selection, "quantities":quantities, "estimate":search.best_score, "tier":"B", "nodes":search.nodes}


static func plan(effect:BaseEffect, bot_id:int, force:bool = false) -> Dictionary:
	var state:Dictionary = prepare(effect,bot_id,force)
	if state.has("search"):
		while not state.search.done: state.search.advance()
	return complete(state)

static func run_sliced(search,tree:SceneTree,greedy:bool = false) -> Dictionary:
	var projector = load("res://scripts/match/rule_state.gd")
	var ids = preload("res://scripts/match/net_ids.gd").new()
	var before:PackedByteArray = var_to_bytes(projector.capture(ids))
	while not search.done:
		if greedy and not search.greedy_done: search.greedy_advance()
		else: search.advance()
		if not search.done:
			await tree.process_frame
			if var_to_bytes(projector.capture(ids)) != before:
				search.cancelled = true
				search.done = true
	return search.result()

static func plan_async(effect:BaseEffect,bot_id:int,tree:SceneTree,force:bool = false) -> Dictionary:
	var state:Dictionary = prepare(effect,bot_id,force)
	if state.has("search"):
		var result:Dictionary = await run_sliced(state.search,tree)
		if result.cancelled or not effect.runtime_source_status().ok: return {"cancelled":true}
	return complete(state)
static func selection_search(candidates:Array,low:int,high:int,required:Array,value:Callable):
	var cap:int = candidates.size() if high == -1 else mini(high,candidates.size())
	var legal:Callable = func(cards:Array, _flags:Array) -> bool:
		if cards.size() < low or cards.size() > cap: return false
		for card in required:
			if not cards.has(card): return false
		return true
	var modes:Callable = func(cards:Array,_flags:Array,item) -> Array:
		var missing:int = 0
		for card in required:
			if not cards.has(card) and card != item: missing += 1
		return [false] if cards.size() + 1 + missing <= cap else []
	var score:Callable = func(cards:Array, _flags:Array) -> float:
		var total:float = 0
		for card in cards: total += float(value.call(card))
		return total
	return Search.new(candidates,modes,legal,score)

static func choose(candidates:Array,low:int,high:int,required:Array,value:Callable) -> Array:
	return selection_search(candidates,low,high,required,value).run_sync().group.get("cards",[])

static func choose_async(candidates:Array,low:int,high:int,required:Array,value:Callable,tree:SceneTree) -> Dictionary:
	return await run_sliced(selection_search(candidates,low,high,required,value),tree,true)
