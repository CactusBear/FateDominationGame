class_name GameLog
extends RefCounted

#游戏日志的对外入口。职责只有两件：
#  ① 把游戏对象/数值整理成日志能存的样子（数值记数字、对象按用途留引用或记身份）；
#  ② 把回合/阶段/效果上下文喂给底层两个组件。
#底层 EventJournal（事实存储+筛选）与 ExecutionTrace（执行追踪）都不认识游戏类型，
#改规则层或改底层都不会互相牵动。
#引擎只负责记与查，不解释任何一条事实的规则含义：type 与 data 由记录方声明、
#查询方按条件筛，新增一种可查的事实不需要改这里。
#用 static 存放（与 LoadAttack._attack_datas 同一种做法），不注册 autoload，
#也正因此不引用任何 autoload——当前回合/阶段由外部 set_context 推进。

#保留多少个回合的日志。<=0 表示整局都留着（默认）
static var max_rounds:int = 0

static var _journal := EventJournal.new()
static var _trace := ExecutionTrace.new()

#当前上下文，由 GameProgress 推进回合/阶段时设置
static var current_round:int = 0
static var current_phase:String = ""


static func set_context(round_num:int, phase_name:String) -> void:
	current_round = round_num
	current_phase = phase_name


#记一条事实，返回它的隔离副本。object 保留场上对象引用（效果链要靠它取卡）；
#tags/data 里的数值记成普通数字、容器深拷贝一份
static func record(type:String, actor:int = -1, target:int = -1, place:String = "",
		object = null, tags:Array = [], params:Dictionary = {}) -> Dictionary:
	return _journal.record({
		"round" : current_round,
		"phase" : current_phase,
		"type" : type,
		"actor" : actor,
		"target" : target,
		"place" : place,
		"object" : object,
		"tags" : _freeze(tags),
		"data" : _freeze(params),
	})


#按条件查，返回隔离副本。round_offset：0=本回合、-1=上一回合、null=不限回合；limit>0 取最近这么多条
static func query(filter:Dictionary = {}, round_offset = 0, limit:int = -1) -> Array:
	return _journal.query(filter, current_round, round_offset, limit)


#最近一条命中（没有则 null），用于"上一次发生的…是什么"
static func last(filter:Dictionary = {}, round_offset = 0):
	var got:Array = query(filter, round_offset, 1)
	return got[0] if got.size() > 0 else null


#记录玩家某项数值资源的变化。prefix 由记录方给，日志不解释它是什么资源；
#增加/减少分成两种事件，查询方按 type 筛。没变化返回 null（不记空事实）
static func record_resource_change(prefix:String, player_id:int, before, now):
	if before == now:
		return null
	var delta = now - before
	return record(prefix + ("_add" if delta > 0 else "_decrease"), player_id, -1, "", null, [],
		{"delta": delta, "now": now})


#回合推进时调用：裁掉超过保留上限的旧条目
static func begin_round() -> void:
	if max_rounds <= 0:
		return
	_journal.trim_rounds(current_round - max_rounds + 1)


static func reset() -> void:
	_journal.reset()
	_trace.reset()
	current_round = 0
	current_phase = ""


#--- 执行追踪：把效果上下文提取出来交给 trace，trace 本身不认识效果 ---

static func begin_execution() -> int:
	return _trace.begin_execution()


static func end_execution(eid:int = 0) -> void:
	_trace.end_execution(eid)


#返回 call_id（不是内部条目）：外部只拿编号做句柄，改不了内部记录
static func begin_func_call(effect, func_name:String, raw_params:Array, resolved_params:Array) -> int:
	return _trace.begin_call(_effect_context(effect), func_name,
		_snapshot(raw_params), _snapshot(resolved_params))


static func end_func_call(call_id:int, result, status:String) -> void:
	_trace.end_call(call_id, _snapshot(result), status)


#循环类 operation（ForFunc/ForeachFunc/WhileFunc）用这两个压/弹循环路径
static func push_loop(index:int) -> void:
	_trace.loop_stack.append(index)


static func pop_loop() -> void:
	if !_trace.loop_stack.is_empty():
		_trace.loop_stack.pop_back()


#执行日志的只读快照（调试/验证/回放用）。返回隔离副本：
#调用方怎么改都改不到内部历史。用函数不用属性，避免 reset 重新赋值后引用失效
static func all_func_calls() -> Array:
	return _snapshot(_trace.calls)


static func _effect_context(effect) -> Dictionary:
	return {
		"round" : current_round,
		"phase" : current_phase,
		"effect_name" : effect._name if effect != null else "",
		"trigger_player_id" : effect._trigger_player_id if effect != null else -1,
		"trigger_time_points" : (effect._trigger_time_points.duplicate() if effect != null else []),
	}


#事实日志用：数值记成数字、容器深拷贝，对象保留引用（data 里极少数要保留的引用）
static func _freeze(value):
	if value is BaseNumber:
		return value.number
	if value is Array:
		var copied:Array = []
		for item in value:
			copied.append(_freeze(item))
		return copied
	if value is Dictionary:
		var copied:Dictionary = {}
		for key in value:
			copied[key] = _freeze(value[key])
		return copied
	return value


#执行日志用：数值记成数字、活对象只记身份（类型+名字+实例 id），不把活对象塞进历史
static func _snapshot(value):
	if value is BaseNumber:
		return value.number
	if value is Array:
		var copied:Array = []
		for item in value:
			copied.append(_snapshot(item))
		return copied
	if value is Dictionary:
		var copied:Dictionary = {}
		for key in value:
			copied[key] = _snapshot(value[key])
		return copied
	if value is Object:
		var script = value.get_script()
		return {
			"object_class" : script.resource_path.get_file().get_basename() if script != null else "",
			"object_name" : (value as BaseObject)._name if value is BaseObject else "",
			"object_id" : value.get_instance_id(),
		}
	return value
