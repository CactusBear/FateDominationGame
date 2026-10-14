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
static var _live_context:Dictionary = {"round":0, "phase":"", "max_rounds":0}
static var max_rounds:int:
	get: return _context_view().get("max_rounds", 0)
	set(value): _write_context("max_rounds", value)

static var _live_journal := EventJournal.new()
static var _live_trace := ExecutionTrace.new()
# raw facade 保留旧 ABI；D 内不借 live，D 的 raw 根赋值明确 unsupported。
static var _journal:
	get:
		var state = fact_service_view()
		return state.journal if state != null else null
	set(value):
		if FactDomain.current_frame().status == "COMPLETED": _domain_unsupported("raw_journal_replacement")
		else: _live_journal = value
static var _trace:
	get:
		var state = fact_service_view()
		return state.trace if state != null else null
	set(value):
		if FactDomain.current_frame().status == "COMPLETED": _domain_unsupported("raw_trace_replacement")
		else: _live_trace = value
# 展示票据独立于 _journal 的规则对象图；回滚不能复活已 abort 的 generation。
static var _live_fact_delivery = preload("res://scripts/system/global/fact_delivery.gd").new()
static var _fact_delivery:
	get:
		if FactDomain.current_frame().status == "COMPLETED":
			_domain_unsupported("raw_live_delivery_in_domain")
			var state = fact_service_view()
			return state.local_delivery if state != null else null
		return _live_fact_delivery
	set(value):
		if FactDomain.current_frame().status == "COMPLETED": _domain_unsupported("raw_delivery_replacement")
		else: _live_fact_delivery = value
const FactTransactionStatus = preload("res://scripts/system/global/fact_delivery.gd").TransactionStatus

#当前上下文，由 GameProgress 推进回合/阶段时设置
static var current_round:int:
	get: return _context_view().get("round", 0)
	set(value): _write_context("round", value)
static var current_phase:String:
	get: return _context_view().get("phase", "")
	set(value): _write_context("phase", value)
static var _live_scopes:Array = []
static var _rule_fact_scopes:Array:
	get:
		var state = fact_service_view()
		return state.scopes if state != null else []
const RuleFactGeneration = preload("res://scripts/system/session_generation.gd")
const FactDomain = preload("res://scripts/system/atomic_execution_domain.gd")
const FactPlan = preload("res://scripts/system/atomic_action_plan.gd")
static var _fact_services:Dictionary = {}
static var _fact_faults:Dictionary = {}

class FactDomainState extends RefCounted:
	var domain
	var context
	var plan_identity:RefCounted
	var association:Variant
	var execution_binding:Variant
	var frame_marker:Variant
	var graph
	var journal = EventJournal.new()
	var trace = ExecutionTrace.new()
	var scopes:Array = []
	var log_context:Dictionary = {}
	var live_journal
	var live_trace
	var live_context
	var connections:Dictionary = {}
	var journal_generation:int = 0
	var private_connections:Array = []
	var delivery:Dictionary = {}
	var live_delivery
	var local_delivery = preload("res://scripts/system/global/fact_delivery.gd").new()
	var reason:String = ""
	var sealed:bool = false

static func bind_fact_service(domain, state:FactDomainState) -> Dictionary:
	if FactDomain.publication_is_open() or FactDomain.current_frame().status == "COMPLETED" or _fact_services.has(domain):
		return {"status":"UNSUPPORTED", "reason":"fact_service_binding_closed"}
	var linked:Dictionary = FactPlan.validate_execution_binding(state.association, state.context)
	if linked.status != "COMPLETED": return {"status":"UNSUPPORTED", "reason":linked.reason}
	if linked.binding_kind != "ASSOCIATION" or linked.phase != "OPEN" or not is_same(linked.domain_identity, domain.identity()) or not is_same(linked.plan_identity, state.plan_identity): return {"status":"UNSUPPORTED", "reason":"fact_service_association_mismatch"}
	var result:Dictionary = domain.bind_root(&"rule_journal_trace", state)
	if result.status != "COMPLETED": return result
	_fact_services[domain] = state
	return result

static func unbind_fact_service(domain, state:FactDomainState) -> void:
	if is_same(_fact_services.get(domain), state):
		_fact_services.erase(domain)
		_fact_faults.erase(domain)

static func _domain_unsupported(reason:String) -> void:
	var frame:Dictionary = FactDomain.current_frame()
	if frame.status != "COMPLETED": return
	_fact_faults[frame.domain] = reason
	var state = _fact_services.get(frame.domain)
	if state != null and state.reason.is_empty(): state.reason = reason

# 唯一静态路由门：无 D 帧保持旧 live 语义；有 D 帧必须复验显式原 FRAME。
# 工厂 ASSOCIATION 固定归属，FRAME 每次 invocation 由聚合 owner 传入。
# 此认证只闭合事实服务归属，不能代替 C admission / G 完整图 / E 闭包。
static func fact_service_view():
	var frame:Dictionary = FactDomain.current_frame()
	if frame.status != "COMPLETED":
		return {"journal":_live_journal, "trace":_live_trace, "log_context":_live_context, "scopes":_live_scopes}
	var state = _fact_services.get(frame.domain)
	var root:Dictionary = FactDomain.resolve_root(&"rule_journal_trace")
	if state == null or root.status != "COMPLETED" or not is_same(root.value, state) or not is_same(state.context, frame.original_context):
		_domain_unsupported("unverified_fact_service_frame")
		return null
	# 不 execution_binding/current/derive/bind 补票；显式 marker 不允许 null 降级。
	var verified:Dictionary = FactPlan.validate_execution_binding(state.execution_binding, state.context, frame.marker)
	if verified.status != "COMPLETED" or verified.binding_kind != "FRAME" or not is_same(verified.frame_marker, state.frame_marker) or not is_same(verified.plan_identity, state.plan_identity) or not is_same(verified.plan_identity, frame.plan_identity) or not is_same(verified.domain_identity, frame.domain.identity()):
		_domain_unsupported("unverified_fact_service_frame")
		return null
	return state

static func _context_view() -> Dictionary:
	var state = fact_service_view()
	return state.log_context if state != null else {}

static func _write_context(key:String, value:Variant) -> void:
	var state = fact_service_view()
	if state != null: state.log_context[key] = value


# 组合 adapter；不是完整规则图快照，不拥有审计、展示票据或监听目标状态。
class RuleFactScope extends RefCounted:
	var context
	var journal
	var journal_state
	var trace
	var trace_fields:Dictionary = {}
	var trace_containers = EventJournal.ContainerState.new()
	var log_context:Array = []

	func release() -> void:
		trace_containers.release()
		trace_fields.clear()
		log_context.clear()
		context = null
		journal = null
		journal_state = null
		trace = null

# 独立实例入口：不替换 live statics、不接 FactDelivery、不 print/写盘。
# 初始历史/对象重绑由 shadow session 提供；绝不自动复制 live object 引用。
class ShadowSink extends RefCounted:
	var journal = EventJournal.new()
	var trace = ExecutionTrace.new()
	var current_round:int = 0
	var current_phase:String = ""

	func set_context(round_num:int, phase_name:String) -> void:
		current_round = round_num
		current_phase = phase_name

	func record(type:String, actor:int = -1, target:int = -1, place:String = "",
			object = null, tags:Array = [], params:Dictionary = {}) -> Dictionary:
		return GameLog._record_into(journal, current_round, current_phase, type, actor, target, place, object, tags, params)

	func query(filter:Dictionary = {}, round_offset = 0, limit:int = -1) -> Array:
		return journal.query(filter, current_round, round_offset, limit)

	func last(filter:Dictionary = {}, round_offset = 0):
		var got:Array = query(filter, round_offset, 1)
		return got[0] if not got.is_empty() else null

static func new_shadow_sink() -> ShadowSink:
	return ShadowSink.new()

# context 必须是调用者原始来源，缺省不补当前票；只捕获明确日志字段。
static func capture_rule_facts(context):
	if fact_service_view() == null: return null
	if not RuleFactGeneration.validate_context(context).ok: return null
	var state = RuleFactScope.new()
	state.context = context
	state.journal = _journal
	state.trace = _trace
	# raw counters 先 reattach，后写旧 scalar ABI；readonly 预检也覆盖原 counter 根。
	state.trace_fields = {"_counters":_trace._counters, "calls":_trace.calls, "next_execution_id":_trace.next_execution_id,
		"next_call_id":_trace.next_call_id, "execution_stack":_trace.execution_stack,
		"call_stack":_trace.call_stack, "loop_stack":_trace.loop_stack, "loop_depths":_trace.loop_depths}
	if not state.trace_containers.capture(state.trace_fields.values()): return null
	state.journal_state = _journal.capture_rule_state()
	if state.journal_state == null: return null
	state.log_context = [current_round, current_phase, max_rounds]
	_rule_fact_scopes.append(state)
	return state

static func _owns_rule_facts(state) -> bool:
	return state is RuleFactScope and not _rule_fact_scopes.is_empty() and is_same(_rule_fact_scopes.back(), state) and is_same(_journal, state.journal) and is_same(_trace, state.trace) and RuleFactGeneration.validate_context(state.context).ok

static func restore_rule_facts(state) -> bool:
	if fact_service_view() == null: return false
	if not _owns_rule_facts(state): return false
	# 全部预验证在第一次写入前；异常连接/只读容器不伪称恢复完成。
	if not _journal.can_restore_rule_state(state.journal_state) or not state.trace_containers.can_restore(): return false
	if not _journal.restore_rule_state(state.journal_state): return false
	if not state.trace_containers.restore(): return false
	for key in state.trace_fields: _trace.set(key, state.trace_fields[key])
	current_round = state.log_context[0]
	current_phase = state.log_context[1]
	max_rounds = state.log_context[2]
	_rule_fact_scopes.pop_back()
	state.release()
	return true

static func release_rule_facts(state) -> bool:
	if fact_service_view() == null: return false
	if not _owns_rule_facts(state): return false
	if not _journal.release_rule_state(state.journal_state): return false
	_rule_fact_scopes.pop_back()
	state.release()
	return true



#只订阅新事实，不回放历史；延迟调度先检查事务资格，再调用展示消费者。
static func observe_facts(listener:Callable) -> void:
	if FactDomain.current_frame().status == "COMPLETED":
		_domain_unsupported("legacy_observe_facts_in_domain")
		return
	var enqueue:Callable = _fact_delivery.enqueue
	if not _journal.recorded.is_connected(enqueue):
		_journal.recorded.connect(enqueue)
	_fact_delivery.observe(listener)


static func unobserve_facts(listener:Callable) -> void:
	if FactDomain.current_frame().status == "COMPLETED":
		_domain_unsupported("legacy_unobserve_facts_in_domain")
		return
	_fact_delivery.unobserve(listener)


# 只读隔离投影：status 为 FactTransactionStatus；仅 PENDING 带原 generation/state。
# NOT_PENDING 不能区分提交、中止、未开始；查询不触发投递、不消费或改变事务。
static func fact_transaction_status(transaction_id:int) -> Dictionary:
	if FactDomain.current_frame().status == "COMPLETED":
		_domain_unsupported("legacy_fact_transaction_status_in_domain")
		return {"status":FactTransactionStatus.NOT_PENDING}
	return _fact_delivery.transaction_status(transaction_id)


static func begin_fact_transaction(transaction_id:int) -> void:
	if FactDomain.current_frame().status == "COMPLETED":
		_domain_unsupported("legacy_begin_fact_transaction_in_domain")
		return
	_fact_delivery.begin(transaction_id)


static func commit_fact_transaction(transaction_id:int) -> void:
	if FactDomain.current_frame().status == "COMPLETED":
		_domain_unsupported("legacy_commit_fact_transaction_in_domain")
		return
	_fact_delivery.commit(transaction_id)


static func abort_fact_transaction(transaction_id:int) -> void:
	if FactDomain.current_frame().status == "COMPLETED":
		_domain_unsupported("legacy_abort_fact_transaction_in_domain")
		return
	_fact_delivery.abort(transaction_id)


# EffectManager.reset_runtime 也会调用；不重置规则历史或展示订阅。
static func reset_fact_delivery() -> void:
	if FactDomain.current_frame().status == "COMPLETED":
		_domain_unsupported("legacy_reset_fact_delivery_in_domain")
		return
	_fact_delivery.reset()


static func set_context(round_num:int, phase_name:String) -> void:
	current_round = round_num
	current_phase = phase_name


#记一条事实，返回它的隔离副本。object 保留场上对象引用（效果链要靠它取卡）；
#tags/data 里的数值记成普通数字、容器深拷贝一份
static func record(type:String, actor:int = -1, target:int = -1, place:String = "",
		object = null, tags:Array = [], params:Dictionary = {}) -> Dictionary:
	var state = fact_service_view()
	if state == null: return {}
	if state is FactDomainState:
		var admitted:Dictionary = state.graph.admit([object, tags, params])
		if admitted.status != "COMPLETED":
			_domain_unsupported(admitted.reason)
			return {}
		return _record_into(state.journal, current_round, current_phase, type, actor, target, place, admitted.value[0], admitted.value[1], admitted.value[2])
	return _record_into(state.journal, current_round, current_phase, type, actor, target, place, object, tags, params)

static func _record_into(journal:EventJournal, round_num:int, phase_name:String,
		type:String, actor:int, target:int, place:String, object, tags:Array, params:Dictionary) -> Dictionary:
	return journal.record({
		"round" : round_num,
		"phase" : phase_name,
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
	var state = fact_service_view()
	if state == null: return []
	if state is FactDomainState:
		var admitted:Dictionary = state.graph.admit(filter)
		if admitted.status != "COMPLETED":
			_domain_unsupported(admitted.reason)
			return []
		return state.journal.query(admitted.value, current_round, round_offset, limit)
	return state.journal.query(filter, current_round, round_offset, limit)


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


#真实支付入口调用，替代普通资源变化记录，避免一笔扣费显示两行。
#实际余额没有减少时不记支付，包括无限魔力、零费用和失败动作。
static func record_resource_payment(prefix:String, player_id:int, before, now, purpose:String, source = null):
	var spent = max(0, before - now)
	if spent <= 0:
		return null
	return record(prefix + "_decrease", player_id, -1, "", source, [prefix + "_spend"],
		{"delta": -spent, "now": now, "spent": spent, "purpose": purpose})


#回合推进时调用：裁掉超过保留上限的旧条目
static func begin_round() -> void:
	if fact_service_view() == null: return
	if max_rounds <= 0:
		return
	_journal.trim_rounds(current_round - max_rounds + 1)


static func reset() -> void:
	if FactDomain.current_frame().status == "COMPLETED":
		_domain_unsupported("legacy_reset_in_domain")
		return
	for state in _rule_fact_scopes: state.release()
	_rule_fact_scopes.clear()
	reset_fact_delivery()
	_journal.reset()
	_trace.reset()
	current_round = 0
	current_phase = ""


#--- 执行追踪：把效果上下文提取出来交给 trace，trace 本身不认识效果 ---

static func begin_execution() -> int:
	if fact_service_view() == null: return 0
	return _trace.begin_execution()


static func end_execution(eid:int = 0) -> void:
	if fact_service_view() == null: return
	_trace.end_execution(eid)


#返回 call_id（不是内部条目）：外部只拿编号做句柄，改不了内部记录
static func begin_func_call(effect, func_name:String, raw_params:Array, resolved_params:Array) -> int:
	var state = fact_service_view()
	if state == null: return 0
	if state is FactDomainState:
		var admitted:Dictionary = state.graph.admit([effect, raw_params, resolved_params])
		if admitted.status != "COMPLETED":
			_domain_unsupported(admitted.reason)
			return 0
		effect = admitted.value[0]
		raw_params = admitted.value[1]
		resolved_params = admitted.value[2]
	return state.trace.begin_call(_effect_context(effect), func_name,
		_snapshot(raw_params), _snapshot(resolved_params))


static func end_func_call(call_id:int, result, status:String) -> void:
	var state = fact_service_view()
	if state == null: return
	if state is FactDomainState:
		var admitted:Dictionary = state.graph.admit(result)
		if admitted.status != "COMPLETED":
			_domain_unsupported(admitted.reason)
			return
		result = admitted.value
	state.trace.end_call(call_id, _snapshot(result), status)


#循环类 operation（ForFunc/ForeachFunc/WhileFunc）用这两个压/弹循环路径
static func push_loop(index:int) -> void:
	if fact_service_view() == null: return
	_trace.loop_stack.append(index)


static func pop_loop() -> void:
	if fact_service_view() == null: return
	if !_trace.loop_stack.is_empty():
		_trace.loop_stack.pop_back()


#执行日志的只读快照（调试/验证/回放用）。返回隔离副本：
#调用方怎么改都改不到内部历史。用函数不用属性，避免 reset 重新赋值后引用失效
static func all_func_calls() -> Array:
	if fact_service_view() == null: return []
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
static func _freeze(value, memo:Array = []):
	if value is BaseNumber: return value.number
	if value is Array or value is Dictionary:
		for pair in memo:
			if is_same(pair[0], value): return pair[1]
		var copied = [] if value is Array else {}
		memo.append([value, copied])
		if value is Array:
			for item in value: copied.append(_freeze(item, memo))
		else:
			for key in value: copied[key] = _freeze(value[key], memo)
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
		var identity_object:Object = value
		var state = fact_service_view()
		if state is FactDomainState:
			var bound:Dictionary = state.graph._lookup(value, true)
			if not bound.found:
				_domain_unsupported("unbound_trace_object_identity")
				return null
			identity_object = bound.value
		var script = value.get_script()
		return {
			"object_class" : script.resource_path.get_file().get_basename() if script != null else "",
			"object_name" : (value as BaseObject)._name if value is BaseObject else "",
			"object_id" : identity_object.get_instance_id(),
		}
	return value
