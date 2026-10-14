extends Node
const Search = preload("res://scripts/system/ai/group_search.gd")
var checks:int = 0
var failures:Array = []
func check(label:String,ok:bool) -> void:
	checks += 1
	print("CHECK ",label," ",ok)
	if not ok: failures.append(label)
func _ready() -> void: call_deferred("run")
func make_search(n:int = 6,budget:int = Search.NODE_BUDGET, prune:bool = false):
	var items:Array = range(n)
	var modes:Callable = func(cards:Array,_flags:Array,_card) -> Array: return [false,true] if cards.size() < 3 else []
	var legal:Callable = func(cards:Array,flags:Array) -> bool: return cards.size() >= 2 and flags.has(false)
	var score:Callable = func(cards:Array,flags:Array) -> float:
		var total:float = 0
		for i in cards.size():
			if not flags[i]: total += cards[i] + 1
		return total
	var upper:Callable = func(cards:Array,flags:Array,start:int) -> float:
		var total:float = score.call(cards,flags)
		for i in range(start,n): total += i + 1
		return total
	return Search.new(items,modes,legal,score,upper if prune else Callable(),Callable(),Callable(),budget)
func brute(search) -> float:
	var best:float = -INF
	var total:int = int(pow(3,search.items.size()))
	for encoded in range(total):
		var value:int = encoded
		var cards:Array = []
		var flags:Array = []
		for item in search.items:
			var mode:int = value % 3
			value = value / 3
			if mode > 0:
				cards.append(item)
				flags.append(mode == 2)
		if cards.size() <= 3 and search.legal.call(cards,flags): best = maxf(best,search.score.call(cards,flags))
	return best
func run() -> void:
	var search = make_search()
	var oracle:float = brute(search)
	var sync:Dictionary = search.run_sync()
	check("matches independent ternary brute force",sync.score == oracle and sync.exhausted)
	var synergy = make_search()
	var original_score:Callable = synergy.score
	synergy.score = func(cards:Array,flags:Array) -> float: return original_score.call(cards,flags) + (100 if cards.has(0) and cards.has(1) and not flags[0] else 0)
	synergy.upper = func(_cards,_flags,_start): return INF
	var synergy_oracle:float = brute(synergy)
	check("infinite upper preserves dynamic synergy optimum",synergy.run_sync().score == synergy_oracle)
	var pruned:Dictionary = make_search(6,Search.NODE_BUDGET,true).run_sync()
	check("printed upper pruning retains optimum",pruned.score == oracle and pruned.pruned > 0)
	var async_search = make_search()
	async_search.seed_greedy()
	var frames:int = 0
	while not async_search.done:
		async_search.advance(1)
		if not async_search.done:
			frames += 1
			await get_tree().process_frame
	var asynchronous:Dictionary = async_search.result()
	check("sync and sliced exact group and node count",sync.group == asynchronous.group and sync.nodes == asynchronous.nodes and frames > 0)
	check("repeat deterministic including ties",make_search().run_sync() == sync)
	check("empty hand returns no group",make_search(0).run_sync().group.is_empty())
	var duplicate = make_search(6)
	duplicate.items = [0,0,0,1,1,1]
	duplicate.equivalent = func(item): return item
	var duplicate_oracle:float = brute(duplicate)
	check("same-layer dedup retains distinct copies at depth",duplicate.run_sync().score == duplicate_oracle)
	check("minimum two rejects single candidate",make_search(1).run_sync().group.is_empty())
	var large = make_search(18,64)
	large.seed_greedy()
	var greedy:float = large.best_score
	while not large.done: large.advance()
	check("18 candidates obey nodes and retain greedy",large.nodes <= 64 and large.best_score >= greedy)
	var timeout = make_search()
	timeout.seed_greedy()
	var fallback:Dictionary = timeout.best.duplicate(true)
	timeout.deadline = Time.get_ticks_usec()
	timeout.advance()
	check("expired wall deadline retains incumbent",timeout.timed_out and timeout.result().group == fallback)
	var cancelled = make_search()
	cancelled.seed_greedy()
	cancelled.current = func(): return false
	cancelled.advance()
	check("changed position discards incumbent",cancelled.cancelled and cancelled.result().group.is_empty())
	var many:Array = range(24)
	var wall = Search.new(many,func(_c,_h,_i): return [false,true],func(c,_h): return not c.is_empty(),func(c,_h): return c.size(),Callable(),Callable(),Callable(),1000000000)
	var started:int = Time.get_ticks_usec()
	var wall_result:Dictionary = await wall.run_async(get_tree())
	var elapsed:int = Time.get_ticks_usec() - started
	print("AI_TIMEOUT_EVIDENCE elapsed_usec=",elapsed," budget=",Search.NODE_BUDGET," safety_usec=",Search.TIMEOUT_USEC," nodes=",wall.nodes)
	check("real 15 second safety timeout has legal best",wall_result.timed_out and not wall_result.group.is_empty() and elapsed >= Search.TIMEOUT_USEC and elapsed < Search.TIMEOUT_USEC + 1000000)
	print("RESULT ",JSON.stringify({"suite":"ai_group_search","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
