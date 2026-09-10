extends Node


#效果系统的唯一入口：效果池登记、时点检查、询问顺序、优先级结算、时点关闭打断。
#注册为autoload"EffectManager"，所以不能再带class_name(两者会重名冲突)。
#GameProgress只负责游戏回合进程，不再持有任何效果处理逻辑。


#全局效果池。池中效果的_trigger_player_id即其归属玩家，-1表示还没进入游戏
var effect_pool:Array#[BaseEffect]
#当前正在结算的效果，供各effect脚本取上下文
var activating_eff:BaseEffect

#本时点的待决定队列。被动直接入池，主动逐个询问，两者按顺位交错排在同一条队列里
var decision_queue:Array#[BaseEffect]
#本时点确定要发动的效果，全部决定完后按优先级结算
var activation_pool:Array#[BaseEffect]
#正在等待其归属玩家答复的效果，非null时整条流程暂停
var waiting_effect:BaseEffect
#{BaseEffect : Array[String]}，效果是因哪些时点命中的，供关闭时点时判断是否要打断
var matched_time_points:Dictionary
#{BaseEffect : int}，本时点已结算过的效果，避免同一时点内重复触发
var resolved_effects:Dictionary
#{player_id : Array[String]}，本时点被关闭的时点
var closed_time_points:Dictionary
#{BaseEffect : Array[BaseFunc]}，被反制的func，结算时跳过
var countered_funcs:Dictionary
#时点批次编号，每进入一个新时点递增
var time_point_id:int = 0
#结算中标记。结算过程里派发的新时点只追加效果，不另起批次
var is_running:bool = false


#清理本局运行时状态，保留已经加载的游戏资源和效果对象
func reset_runtime():
	effect_pool.clear()
	activating_eff = null
	decision_queue.clear()
	activation_pool.clear()
	waiting_effect = null
	matched_time_points.clear()
	resolved_effects.clear()
	closed_time_points.clear()
	countered_funcs.clear()
	time_point_id = 0
	is_running = false
	for id in GameData.player_data_library.keys():
		var player_data = GameData.player_data_library[id] as Dictionary
		(player_data["self_effects"] as Array).clear()


func get_all_players_id():
	return GameData.player_data_library.keys()


#把-1解析成"当前效果的触发者"，供各effect的player_id参数使用，避免默认成本地玩家
func resolve_player_id(player_id:int) -> int:
	if player_id != -1:
		return player_id
	if activating_eff != null and activating_eff._trigger_player_id != -1:
		return activating_eff._trigger_player_id
	return GameData.player_id


#顺位
#按玩家数据里的order排序。order可被ChangePlOrder改动，所以顺位不等于玩家id
func get_player_order_ids() -> Array:
	var ids = get_all_players_id() as Array
	ids.sort_custom(func(a, b):
		var a_order = (GameDataManager.get_player_data(a)["order"] as BaseNumber).number
		var b_order = (GameDataManager.get_player_data(b)["order"] as BaseNumber).number
		if a_order != b_order:
			return a_order < b_order
		#order相同时用id兜底，保证排序是全序，结果可复现
		return int(a) < int(b)
	)
	return ids


func get_player_order_index(player_id:int) -> int:
	var i = get_player_order_ids().find(player_id)
	if i == -1:
		return GameData.player_max + 1
	return i


#效果池登记
#player_id不为-1时同时把效果登记为该玩家所有，并写入其self_effects供反查
func register_effect(effect:BaseEffect, player_id:int = -1):
	if effect == null:
		return
	if player_id != -1:
		effect._trigger_player_id = player_id
	if !effect_pool.has(effect):
		effect_pool.append(effect)
	if player_id != -1:
		var pl_data = GameDataManager.get_player_data(player_id) as Dictionary
		var self_effects = pl_data["self_effects"] as Array
		if !self_effects.has(effect):
			self_effects.append(effect)


func register_effects(effects:Array, player_id:int = -1):
	for effect in effects:
		if effect is BaseEffect:
			register_effect(effect, player_id)


#效果离场(卡牌被移除游戏等)时取消登记，之后的时点不再检查它
func unregister_effect(effect:BaseEffect):
	if effect == null:
		return
	effect_pool.erase(effect)
	decision_queue.erase(effect)
	activation_pool.erase(effect)
	matched_time_points.erase(effect)
	if waiting_effect == effect:
		waiting_effect = null
	var id = effect._trigger_player_id
	if id != -1:
		var pl_data = GameDataManager.get_player_data(id) as Dictionary
		(pl_data["self_effects"] as Array).erase(effect)


#开局加载完的效果先全部入池，此时还没有归属玩家；
#选完御主/从者后再用register_effects(xx._effects, id)绑定归属
func sync_loaded_effect_pool():
	for effect in GameData.effects:
		register_effect(effect)


#时点流程
#进入一个新时点。调用方(TimePointChecker)负责先把各玩家的current_time_points更新好
func run_time_point():
	if is_running:
		#结算过程中派发的时点只追加效果，交由外层流程继续处理
		collect_current_effects()
		return
	time_point_id += 1
	decision_queue.clear()
	activation_pool.clear()
	matched_time_points.clear()
	resolved_effects.clear()
	closed_time_points.clear()
	countered_funcs.clear()
	waiting_effect = null
	collect_current_effects()
	run_pipeline()


#检查全局效果池，把本时点命中的效果按顺位排进待决定队列
func collect_current_effects():
	var newly_matched:Array = []
	for effect:BaseEffect in effect_pool:
		if effect._trigger_player_id == -1:
			continue
		if resolved_effects.has(effect):
			continue
		if decision_queue.has(effect) or activation_pool.has(effect):
			continue
		if !card_state_allows(effect):
			continue
		var matched = get_matched_time_points(effect)
		if matched.is_empty():
			continue
		matched_time_points[effect] = matched
		#快照触发上下文。start_effect会清空动态时点，所以要在结算前记下来，供When判断分支
		effect._trigger_time_points = matched.duplicate()
		newly_matched.append(effect)
	decision_queue.append_array(newly_matched)
	sort_by_turn_order(decision_queue)


#_need_activate表示"这个效果需不需要卡牌处于激活状态"。
#纯被动不受此限制——规则里"被动："满足条件即强制生效，即使印刷此文本的卡牌未被展示
func card_state_allows(effect:BaseEffect) -> bool:
	if effect._is_pure_passive:
		return true
	if !effect._need_activate:
		return true
	if effect.from is BaseHandCard:
		return (effect.from as BaseHandCard)._is_activating
	return true


#返回效果在其归属玩家的当前时点表里命中的所有时点。
#命中多个时，关掉其中一个不会让效果整体失效
func get_matched_time_points(effect:BaseEffect) -> Array:
	var pl_data = GameDataManager.get_player_data(effect._trigger_player_id) as Dictionary
	var current_tps = pl_data["current_time_points"] as Array
	var closed = closed_time_points.get(effect._trigger_player_id, []) as Array
	var matched:Array = []
	for tp in effect._time_points:
		if closed.has(tp):
			continue
		if current_tps.has(tp) and !matched.has(tp):
			matched.append(tp)
	return matched


#询问顺序：按顺位，同一玩家内按优先级
func sort_by_turn_order(effects:Array):
	var order = get_player_order_ids()
	effects.sort_custom(func(a:BaseEffect, b:BaseEffect):
		var a_index = order.find(a._trigger_player_id)
		var b_index = order.find(b._trigger_player_id)
		if a_index != b_index:
			return a_index < b_index
		if a._priority != b._priority:
			return a._priority < b._priority
		return effect_pool.find(a) < effect_pool.find(b)
	)


#结算顺序：按优先级，同一优先级按顺位
func sort_by_priority(effects:Array):
	var order = get_player_order_ids()
	effects.sort_custom(func(a:BaseEffect, b:BaseEffect):
		if a._priority != b._priority:
			return a._priority < b._priority
		var a_index = order.find(a._trigger_player_id)
		var b_index = order.find(b._trigger_player_id)
		if a_index != b_index:
			return a_index < b_index
		return effect_pool.find(a) < effect_pool.find(b)
	)


#主流程：先决定(交错)，再按优先级结算。结算中产生的新效果同样先决定再结算
func run_pipeline():
	is_running = true
	while true:
		#等玩家答复，由submit_active_choice继续跑
		if waiting_effect != null:
			break
		if !decision_queue.is_empty():
			drain_decision_queue()
			continue
		if !activation_pool.is_empty():
			resolve_one()
			continue
		break
	is_running = false


#被动直接按顺位加入效果池，不询问；遇到需要玩家决定的效果就停下等答复
func drain_decision_queue():
	while !decision_queue.is_empty():
		var effect = decision_queue[0] as BaseEffect
		if is_pruned(effect):
			decision_queue.pop_front()
			continue
		if effect._is_pure_passive:
			decision_queue.pop_front()
			add_to_activation_pool(effect)
			continue
		waiting_effect = effect
		return


#当前正在等待答复的效果，null表示没有待决定的效果
func get_pending_active_effect() -> BaseEffect:
	return waiting_effect


func is_waiting_for_choice() -> bool:
	return waiting_effect != null


#玩家答复。should_activate为false也算走完流程
#——规则里带"你可以"的效果即使不发动，依旧视为遵循了规则
func submit_active_choice(effect:BaseEffect, should_activate:bool) -> bool:
	if effect == null or waiting_effect != effect:
		return false
	decision_queue.erase(effect)
	waiting_effect = null
	if should_activate:
		add_to_activation_pool(effect)
	if !is_running:
		run_pipeline()
	return true


func add_to_activation_pool(effect:BaseEffect):
	if effect == null or activation_pool.has(effect):
		return
	activation_pool.append(effect)
	sort_by_priority(activation_pool)


#结算效果池里优先级最高的一个。一次只结算一个，
#这样它关闭时点或反制其他效果的结果能立刻影响后面还没结算的效果
func resolve_one():
	while !activation_pool.is_empty():
		var effect = activation_pool.pop_front() as BaseEffect
		if is_pruned(effect):
			continue
		if resolved_effects.has(effect):
			continue
		#优先级为-1是未填写的占位符，跳过不结算
		if effect._priority < 0:
			continue
		resolved_effects[effect] = time_point_id
		activating_eff = effect
		activate_effect(effect)
		activating_eff = null
		return


#时点关闭
#关闭某个时点(如结束其他玩家的回合)。因该时点触发、且没有其他命中时点的效果会被打断。
#已经结算完的效果不回滚——规则里没有回退机制。player_id为-1表示关闭所有玩家的该时点
func close_time_point(time_point:String, player_id:int = -1):
	var ids:Array = []
	if player_id != -1:
		ids.append(player_id)
	else:
		ids = get_all_players_id()
	for id in ids:
		var closed = closed_time_points.get(id, []) as Array
		if !closed.has(time_point):
			closed.append(time_point)
		closed_time_points[id] = closed
		var pl_data = GameDataManager.get_player_data(id) as Dictionary
		erase_all(pl_data["current_time_points"] as Array, time_point)
		erase_all(pl_data["dynamic_time_points"] as Array, time_point)
	prune_closed()


func is_time_point_closed(time_point:String, player_id:int) -> bool:
	var closed = closed_time_points.get(player_id, []) as Array
	return closed.has(time_point)


func erase_all(arr:Array, value):
	var i = arr.find(value)
	while i != -1:
		arr.remove_at(i)
		i = arr.find(value)


#把被关闭的时点从各效果的命中集合里剔除，命中集合空掉的效果就被打断
func prune_closed():
	for effect in matched_time_points.keys():
		var matched = matched_time_points[effect] as Array
		var closed = closed_time_points.get(effect._trigger_player_id, []) as Array
		for tp in closed:
			erase_all(matched, tp)
		if matched.is_empty():
			decision_queue.erase(effect)
			activation_pool.erase(effect)
			#正在等待答复的效果也一并打断
			if waiting_effect == effect:
				waiting_effect = null


func is_pruned(effect:BaseEffect) -> bool:
	if !matched_time_points.has(effect):
		return false
	return (matched_time_points[effect] as Array).is_empty()


#反制
#countered_func留空时整个效果不结算；否则只跳过其中一个func，效果里其余func照常
func counter_effect(effect:BaseEffect, countered_func:BaseFunc = null):
	if effect == null:
		return
	if countered_func == null:
		decision_queue.erase(effect)
		activation_pool.erase(effect)
		if waiting_effect == effect:
			waiting_effect = null
		return
	var funcs = countered_funcs.get(effect, []) as Array
	if !funcs.has(countered_func):
		funcs.append(countered_func)
	countered_funcs[effect] = funcs


func is_func_countered(effect:BaseEffect, _func:BaseFunc) -> bool:
	if !countered_funcs.has(effect):
		return false
	return (countered_funcs[effect] as Array).has(_func)


#效果执行
#只管理时点上下文，不推进回合，也不再维护效果批次索引
func start_effect():
	for id in get_all_players_id():
		var pl_data = GameDataManager.get_player_data(id) as Dictionary
		#清空而不是赋新数组，否则别处持有的旧引用会失效
		(pl_data["dynamic_time_points"] as Array).clear()
	TimePointChecker.time_point_update()


func end_effect():
	TimePointChecker.time_point_check()


#把占位符解析成实际值。{"number_index":i}取效果自带的数字，{"self_var":i}取前面func存下的返回值
#返回[是否解析成功, 值]，越界或下标为-1时视为失败
func resolve_placeholder(para, effect:BaseEffect) -> Array:
	if !(para is Dictionary):
		return [true, para]

	if para.has("number_index"):
		var i = para["number_index"] as int
		if i < 0 or i >= effect._using_numbers.size():
			return [false, null]
		return [true, effect._using_numbers[i]]

	if para.has("self_var"):
		var i = para["self_var"] as int
		if i < 0 or i >= effect._self_vars.size():
			return [false, null]
		return [true, effect._self_vars[i]]

	return [true, para]


#判断func的执行条件是否成立
func check_condition(_func:BaseFunc, effect:BaseEffect) -> bool:
	if _func._condition == null:
		return true
	var resolved = resolve_placeholder(_func._condition, effect)
	if !resolved[0]:
		return false
	var value = resolved[1]
	if value is BaseNumber:
		return value.number != 0
	return bool(value)


#执行单个BaseFunc：反制检查、条件检查、延迟绑定、参数解析、调用、写回var_index。
#抽成公共入口，好让循环类operation(ForFunc/ForeachFunc/WhileFunc)复用同一套规则，
#而不是直接调callable绕开self_var/number_index/condition。
#返回[是否真正调用了callable, 调用结果]；未调用时结果为null
func run_base_func(f:BaseFunc, effect:BaseEffect) -> Array:
	if is_func_countered(effect, f):
		return [false, null]
	if !check_condition(f, effect):
		return [false, null]

	var callable = f._func
	#延迟绑定的方法调用，目标对象此刻才从变量表里取出
	if f._self_var_index != -1:
		if f._self_var_index >= effect._self_vars.size():
			return [false, null]
		var target = effect._self_vars[f._self_var_index]
		if target == null or !target.has_method(f._method_name):
			return [false, null]
		callable = Callable(target, f._method_name)
	if !callable.is_valid():
		return [false, null]

	var paras = f._parameters.duplicate()
	var paras_ready:bool = true
	for i in paras.size():
		var resolved = resolve_placeholder(paras[i], effect)
		if !resolved[0]:
			paras_ready = false
			break
		paras[i] = resolved[1]
	#参数解析不出来就跳过这个func，但效果里后续的func照常处理
	if !paras_ready:
		return [false, null]

	var result = callable.callv(paras)
	if f._var_index != -1:
		while effect._self_vars.size() <= f._var_index:
			effect._self_vars.append(null)
		effect._self_vars[f._var_index] = result
	return [true, result]


#按JSON可表达的函数描述{"func_name":.., "parameters":[..], "var_index":-1, "condition":null}
#动态加载operation并执行，规则与load_game.gd里加载func_name的方式一致。
#兼容直接传入BaseFunc(内部/旧代码构造的循环体)。
#用于循环体这类"JSON里无法直接构造BaseFunc/Callable"的场合，
#让self_var既能传数组/次数，也能传循环体本身需要的参数。
#返回同run_base_func：[是否真正调用了callable, 调用结果]
func run_func_descriptor(desc, effect:BaseEffect) -> Array:
	if desc is BaseFunc:
		return run_base_func(desc, effect)

	if !(desc is Dictionary):
		return [false, null]

	var key = desc.get("func_name", "") as String
	if key == "":
		return [false, null]
	var _class_name = LoadGame.func_name_to_class_name(key)
	var func_path = "res://assets/scripts/system/operations/" + _class_name + ".gd"
	if !ResourceLoader.exists(func_path):
		print("没有操作:" + "'" + key + "'")
		return [false, null]

	var func_instance = load(func_path).new()
	var main_callable = Callable(func_instance, "exec")
	var paras = desc.get("parameters", []) as Array
	var var_index = desc.get("var_index", -1) as int
	var condition = desc.get("condition", null)
	var _func = BaseFunc.new(main_callable, paras, var_index, condition)
	#Callable不会保活实例，必须由func自己持有引用，否则调用完就被释放
	_func._instance = func_instance

	return run_base_func(_func, effect)


func activate_effect(effect:BaseEffect):
	start_effect()
	#每次激活都从空白的变量表开始，避免读到上一次激活的残留值
	effect._self_vars = []

	for f:BaseFunc in effect._funcs:
		run_base_func(f, effect)

	end_effect()
