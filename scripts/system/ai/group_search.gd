extends RefCounted

# 同步与分帧只改变驱动节奏，不改变遍历、预算或平分顺序。
const NODE_BUDGET := 4096
const TIMEOUT_USEC := 15000000
const SLICE_USEC := 4000
var items:Array
var modes:Callable
var legal:Callable
var score:Callable
var upper:Callable
var equivalent:Callable
var current:Callable
var stack:Array = []
var best:Dictionary = {}
var best_score:float = -INF
var nodes:int = 0
var pruned:int = 0
var timed_out:bool = false
var cancelled:bool = false
var done:bool = false
var budget:int
var deadline:int

func _init(candidates:Array, mode_query:Callable, legal_query:Callable, score_query:Callable, upper_query:Callable = Callable(), equivalent_query:Callable = Callable(), current_query:Callable = Callable(), node_budget:int = NODE_BUDGET, timeout_usec:int = TIMEOUT_USEC) -> void:
	items = candidates.duplicate()
	modes = mode_query
	legal = legal_query
	score = score_query
	upper = upper_query
	equivalent = equivalent_query
	current = current_query
	budget = maxi(0, node_budget)
	deadline = Time.get_ticks_usec() + maxi(0, timeout_usec)
	stack = [{"cards":[], "hidden":[], "next":0, "seen":{}}]

func _stop() -> bool:
	if current.is_valid() and not current.call():
		cancelled = true
		done = true
	elif Time.get_ticks_usec() >= deadline:
		timed_out = true
		done = true
		print("AI_SEARCH_TIMEOUT nodes=", nodes)
	elif nodes >= budget:
		done = true
	return done

func _consider(cards:Array, flags:Array) -> void:
	if not legal.call(cards, flags): return
	var value:float = score.call(cards, flags)
	if value > best_score:
		best_score = value
		best = {"cards":cards.duplicate(), "hidden":flags.duplicate()}

# 贪心预排序也按节点切片，不能在分帧搜索之前先堵住一整帧。
var _greedy_scores:Array = []
var _greedy_order:Array = []
var _greedy_cards:Array = []
var _greedy_flags:Array = []
var _greedy_index:int = 0
var greedy_done:bool = false

func greedy_advance(slice_usec:int = SLICE_USEC) -> void:
	var until:int = Time.get_ticks_usec() + maxi(1,slice_usec)
	while not greedy_done and not done:
		if _stop(): return
		if _greedy_scores.size() < items.size():
			nodes += 1
			_greedy_scores.append(float(score.call([items[_greedy_scores.size()]],[false])))
		elif _greedy_order.is_empty() and not items.is_empty():
			_greedy_order.assign(range(items.size()))
			_greedy_order.sort_custom(func(a,b): return _greedy_scores[a] > _greedy_scores[b] if _greedy_scores[a] != _greedy_scores[b] else a < b)
		elif _greedy_index < _greedy_order.size():
			var index:int = _greedy_order[_greedy_index]
			_greedy_index += 1
			nodes += 1
			var available:Array = modes.call(_greedy_cards,_greedy_flags,items[index])
			if not available.is_empty():
				var picked:Variant = available[0]
				var value:float = -INF
				for mode in available:
					var v:float = score.call(_greedy_cards + [items[index]],_greedy_flags + [mode])
					if v > value:
						value = v
						picked = mode
				_greedy_cards.append(items[index])
				_greedy_flags.append(picked)
				_consider(_greedy_cards,_greedy_flags)
		else: greedy_done = true
		if Time.get_ticks_usec() >= until: return

func seed_greedy() -> void:
	while not greedy_done and not done: greedy_advance()
func advance(slice_usec:int = SLICE_USEC) -> void:
	var until:int = Time.get_ticks_usec() + maxi(1, slice_usec)
	while not done and not stack.is_empty():
		if _stop(): break
		var frame:Dictionary = stack.back()
		if not frame.get("pending",[]).is_empty():
			nodes += 1
			var mode:Variant = frame.pending.pop_front()
			var cards:Array = frame.cards + [items[frame.index]]
			var flags:Array = frame.hidden + [mode]
			_consider(cards,flags)
			if upper.is_valid() and upper.call(cards,flags,frame.index + 1) <= best_score:
				pruned += 1
			else:
				stack.append({"cards":cards,"hidden":flags,"next":frame.index + 1,"seen":{}})
		elif frame.next >= items.size():
			stack.pop_back()
		else:
			var index:int = frame.next
			frame.next += 1
			var key:Variant = equivalent.call(items[index]) if equivalent.is_valid() else null
			if key != null and frame.seen.has(key): continue
			if key != null: frame.seen[key] = true
			nodes += 1
			frame.index = index
			frame.pending = modes.call(frame.cards,frame.hidden,items[index])
		if Time.get_ticks_usec() >= until: return
	if stack.is_empty(): done = true
func result() -> Dictionary:
	return {"group":{} if cancelled else best, "score":best_score, "nodes":nodes, "pruned":pruned, "timed_out":timed_out, "cancelled":cancelled, "exhausted":stack.is_empty()}

func run_sync() -> Dictionary:
	seed_greedy()
	while not done: advance()
	return result()

func run_async(tree:SceneTree) -> Dictionary:
	while not greedy_done and not done:
		greedy_advance()
		if not greedy_done and not done: await tree.process_frame
	while not done:
		advance()
		if not done: await tree.process_frame
	return result()
