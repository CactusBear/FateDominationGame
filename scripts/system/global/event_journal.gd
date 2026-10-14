class_name EventJournal
extends RefCounted

signal recorded(entry: Dictionary)

#事实日志：按"回合 + 阶段"顺序记下发生过的、可查询的事实。
#只负责"存 + 按条件筛 + 返回隔离副本"，不认识玩家/效果/数值对象——
#记录方（GameLog 适配层）在调用前就把数值转成普通数字、把容器整理好。
# entries 保留公开 mutable root ABI；query 才返回隔离副本。
# 版本只证明下列受管入口，不证明 escaped raw aliases 的 writer 闭包。
var entries:Array = []:
	set(value):
		if is_same(entries, value): return
		# 初始化赋值不发行版本；F 的 D 壳/旧反射 clone 各有独立 owner metadata。
		if has_meta(MANAGED_WRITER_META):
			if not _managed_can_advance(true): return
			_managed_advance(true)
		entries = value

const MANAGED_WRITER_ABI:StringName = &"event_journal/managed_writer/1"
const MANAGED_WRITER_META:StringName = &"event_journal_managed_writer"
const MANAGED_VERSION_MAX:int = 9223372036854775807
const ManagedGeneration = preload("res://scripts/system/session_generation.gd")

func _init() -> void:
	# 复用现有 owner metadata 图外能力（不是 Script 规则字段/新 registry）。
	# 固定原始无类型槽：[受管写版本, 根替换版本, reset 生命周期]。
	set_meta(MANAGED_WRITER_META, [0, 0, 0])

func _managed_writer_backing() -> Array:
	return get_meta(MANAGED_WRITER_META)

func _managed_can_advance(root_change:bool = false, lifecycle_change:bool = false, writes:int = 1) -> bool:
	var backing:Array = _managed_writer_backing()
	return not backing.is_read_only() and backing[0] <= MANAGED_VERSION_MAX - writes and (not root_change or backing[1] < MANAGED_VERSION_MAX) and (not lifecycle_change or backing[2] < MANAGED_VERSION_MAX)

func _managed_advance(root_change:bool = false, lifecycle_change:bool = false) -> void:
	var backing:Array = _managed_writer_backing()
	backing[0] += 1
	if root_change: backing[1] += 1
	if lifecycle_change: backing[2] += 1

# 纯观察值，不是 C admission/防伪票。owner/root 保原引用，不能冻结原历史。
# 原 context 可选但不得补 current；带来源的观察在来源失效后永远不匹配。
func managed_writer_snapshot(original_context:Variant = null) -> Dictionary:
	if original_context != null and not ManagedGeneration.validate_context(original_context).get("ok", false):
		return _managed_observation_result("UNSUPPORTED", "stale_original_context")
	var backing:Array = _managed_writer_backing()
	var covered:Array = [&"record", &"trim_rounds", &"reset", &"restore_rule_state", &"entries_identity_assignment"]
	var uncovered:Array = [&"raw_root_contents", &"raw_retained_nested", &"generic_container_restore", &"legacy_F_install_without_version_plan", &"arbitrary_Object_native_thread_metadata"]
	covered.make_read_only()
	uncovered.make_read_only()
	var result:Dictionary = {"status":"COMPLETED", "reason":"", "abi":MANAGED_WRITER_ABI,
		"scope":&"managed_entries_only", "closure_status":"UNSUPPORTED", "owner":self,
		"root":entries, "lifecycle":backing[2], "writer_version":backing[0],
		"root_slot_version":backing[1], "original_context":original_context,
		"covered":covered, "uncovered":uncovered}
	result.make_read_only()
	return result

func managed_writer_matches(expected:Variant, original_context:Variant = null) -> bool:
	if not expected is Dictionary: return false
	if not expected.get("status") is String or expected.status != "COMPLETED": return false
	if not expected.get("abi") is StringName or expected.abi != MANAGED_WRITER_ABI or not expected.get("scope") is StringName or expected.scope != &"managed_entries_only": return false
	if not is_same(expected.get("owner"), self) or not is_same(expected.get("root"), entries) or not is_same(expected.get("original_context"), original_context): return false
	if original_context != null and not ManagedGeneration.validate_context(original_context).get("ok", false): return false
	var backing:Array = _managed_writer_backing()
	return expected.get("writer_version") is int and expected.get("root_slot_version") is int and expected.get("lifecycle") is int and expected.writer_version == backing[0] and expected.root_slot_version == backing[1] and expected.lifecycle == backing[2]

# 后继 F 聚合 owner 专用的零写计划；不 stage、不 install、不授执行权。
# 同一个 Core 写集须包含此 raw 槽和完整 journal 写集；seal 前复验 expected。
# 仅原位 contents/retained patch。Object 根槽换根没有 callback-free 原载体，仍不支持。
# 可在原 Core participant.seal 预建；安装期只消费 raw 槽，不调本 owner。
func prepare_managed_install_version(expected:Dictionary, original_context:Variant = null) -> Dictionary:
	if entries.is_read_only() or not _rule_scopes.is_empty():
		return _managed_observation_result("UNSUPPORTED", "managed_install_boundary_closed")
	if not managed_writer_matches(expected, original_context) or not _managed_can_advance():
		return _managed_observation_result("UNSUPPORTED", "managed_install_version_drift_or_exhausted")
	var write:Dictionary = {"target":_managed_writer_backing(), "key":0, "value":expected.writer_version + 1, "kind":&"journal"}
	write.make_read_only()
	var result:Dictionary = {"status":"COMPLETED", "reason":"", "abi":MANAGED_WRITER_ABI,
		"owner":self, "root":entries, "expected":expected, "write":write,
		"closure_status":"UNSUPPORTED", "requires_complete_write_set":true}
	result.make_read_only()
	return result

func _managed_observation_result(status:String, reason:String) -> Dictionary:
	var result:Dictionary = {"status":status, "reason":reason, "abi":MANAGED_WRITER_ABI, "closure_status":"UNSUPPORTED"}
	result.make_read_only()
	return result
var _rule_scopes:Array = []
# D journal only：在发同步信号之前核 native 连接差集；不能 seal 才发现已逃逸。
var _atomic_graph
var _atomic_expected_connections:Array = []
var _atomic_reason:String = ""

func _atomic_record_guard() -> bool:
	if _atomic_graph == null: return true
	var root:Dictionary = FactAtomicDomain.resolve_root(&"rule_journal_trace")
	if root.status != "COMPLETED" or not is_same(root.value.journal, self):
		_atomic_reason = "private_fact_service_outside_frame"
		return false
	if recorded.get_connections() != _atomic_expected_connections:
		_atomic_reason = "unclassified_private_fact_connection"
		return false
	return _atomic_reason.is_empty()

# A4 owner ABI：登记只表达受信创建者的角色，不是对任意 callback 的沙箱证明。
# standalone record 仍同步 emit；A4 只在 D 连规则参与者，提交后按登记表通知观察者。
enum FactConnectionRole { RULE_PARTICIPANT, DISPLAY_OBSERVER }
var _fact_connections:Array = []
var _fact_connection_revision:int = 0
var _fact_batches:Dictionary = {}
var _fact_publication_generation:int = 0
const FactAtomicPlan = preload("res://scripts/system/atomic_action_plan.gd")
const FactAtomicDomain = preload("res://scripts/system/atomic_execution_domain.gd")

func register_fact_connection(listener:Callable, role:int) -> Dictionary:
	if role not in [FactConnectionRole.RULE_PARTICIPANT, FactConnectionRole.DISPLAY_OBSERVER] or not listener.is_valid():
		return {"status":"UNSUPPORTED", "reason":"invalid_fact_connection_role"}
	var actual:Array = recorded.get_connections()
	var ordinal:int = -1
	for i in range(actual.size()):
		if actual[i].callable == listener:
			if int(actual[i].flags) != 0:
				return {"status":"UNSUPPORTED", "reason":"fact_connection_flags_not_supported"}
			ordinal = i
	if ordinal < 0:
		return {"status":"UNSUPPORTED", "reason":"fact_connection_not_connected"}
	for declaration in _fact_connections:
		if declaration.callable == listener:
			return {"status":"UNSUPPORTED", "reason":"fact_connection_already_registered"}
	_fact_connections.append({"callable":listener, "role":role, "ordinal":ordinal, "flags":0})
	_fact_connection_revision += 1
	return {"status":"COMPLETED", "reason":""}

func unregister_fact_connection(listener:Callable) -> bool:
	for i in range(_fact_connections.size()):
		if _fact_connections[i].callable == listener:
			_fact_connections.remove_at(i)
			_fact_connection_revision += 1
			return true
	return false

func fact_connection_manifest() -> Dictionary:
	var actual:Array = recorded.get_connections()
	if actual.size() != _fact_connections.size():
		return {"status":"UNSUPPORTED", "reason":"unclassified_fact_connection"}
	var ordered:Array = []
	for i in range(actual.size()):
		var declaration = null
		for candidate in _fact_connections:
			if candidate.callable == actual[i].callable: declaration = candidate
		if declaration == null or int(actual[i].flags) != declaration.flags or declaration.ordinal != i or not actual[i].callable.is_valid():
			return {"status":"UNSUPPORTED", "reason":"fact_connection_identity_drift"}
		ordered.append(declaration.duplicate(false))
	return {"status":"COMPLETED", "reason":"", "revision":_fact_connection_revision, "connections":ordered}

func fact_connections_match(expected:Dictionary) -> bool:
	var now:Dictionary = fact_connection_manifest()
	return now.status == "COMPLETED" and expected.get("revision") == now.revision and expected.get("connections") == now.connections

# graph 属于受信聚合 owner：必须是同一个 identity memo，不从 query 副本重建。
func fork_history(graph) -> Dictionary:
	if not _rule_scopes.is_empty():
		return {"status":"UNSUPPORTED", "reason":"active_journal_scope"}
	return graph.fork_value(entries)

# 零 live 写：真正 silent install 仅由冻结 P0 install_sealed 统一执行。
func stage_batch_silent(domain, prepared_entries:Array, plan_identity:RefCounted, expected:Dictionary) -> Dictionary:
	if not fact_connections_match(expected) or FactAtomicPlan.inspect(plan_identity).get("state") != "PREPARED":
		return {"status":"UNSUPPORTED", "reason":"journal_batch_not_prevalidated"}
	var staged:Dictionary = domain.stage_container_contents(entries, prepared_entries, &"journal")
	if staged.status != "COMPLETED": return staged
	var handle:RefCounted = RefCounted.new()
	var terminal:Dictionary = {"state":"COMMITTED", "notification_boundary":"after_complete_install", "retained_facts":prepared_entries.size()}
	terminal.make_read_only()
	var connections:Array = []
	for declaration in expected.connections:
		if declaration.role != FactConnectionRole.DISPLAY_OBSERVER: continue
		var frozen:Dictionary = declaration.duplicate(false)
		frozen.make_read_only()
		connections.append(frozen)
	connections.make_read_only()
	_fact_batches[handle] = {"plan":plan_identity, "generation":_fact_publication_generation, "connections":connections, "terminal":terminal, "notified":false}
	return {"status":"COMPLETED", "reason":"", "notification_handle":handle}

# 只发完整批终态值；真 receipt/不透明 batch 双身份验证，不 emit recorded。
func notify_complete_batch(commit_receipt:Variant, notification_handle:Variant) -> Dictionary:
	if FactAtomicDomain.publication_is_open() or FactAtomicDomain.current_frame().status == "COMPLETED" or not (notification_handle is RefCounted) or not _fact_batches.has(notification_handle):
		return {"status":"UNSUPPORTED", "reason":"unknown_or_closed_journal_notification"}
	var batch:Dictionary = _fact_batches[notification_handle]
	var saved:Dictionary = FactAtomicPlan.inspect(batch.plan)
	if saved.get("state") != "COMMITTED" or not is_same(saved.receipt, commit_receipt):
		return {"status":"UNSUPPORTED", "reason":"journal_receipt_not_saved_committed"}
	if batch.notified: return {"status":"COMPLETED", "reason":"already_notified"}
	batch.notified = true
	if batch.generation != _fact_publication_generation: return {"status":"COMPLETED", "reason":"stale_session_not_notified"}
	for declaration in batch.connections:
		if declaration.role == FactConnectionRole.DISPLAY_OBSERVER and declaration.callable.is_valid() and recorded.is_connected(declaration.callable):
			declaration.callable.call(batch.terminal)
	return {"status":"COMPLETED", "reason":""}


# 只保存日志拥有的容器；Object/Callable 是借用叶子，目标状态须由完整图核负责。
# 浅存每个容器的槽位并按引用去重，既保留别名/循环，也不按内容误认同值父事实。
class ContainerState extends RefCounted:
	var _containers:Array = []

	func capture(roots:Array) -> bool:
		_containers.clear()
		var pending:Array = roots.duplicate()
		while not pending.is_empty():
			var value = pending.pop_back()
			if not (value is Array or value is Dictionary): continue
			var seen:bool = false
			for saved in _containers:
				if is_same(saved.target, value):
					seen = true
					break
			if seen: continue
			if value.is_read_only():
				_containers.clear()
				return false
			_containers.append({"target":value, "items":value.duplicate()})
			if value is Dictionary:
				pending.append_array(value.keys())
				pending.append_array(value.values())
			else:
				pending.append_array(value)
		return true

	func can_restore() -> bool:
		for saved in _containers:
			if saved.target.is_read_only(): return false
		return true

	func restore() -> bool:
		if not can_restore(): return false
		for saved in _containers:
			var target = saved.target
			target.clear()
			if target is Array:
				target.append_array(saved.items)
			else:
				for key in saved.items: target[key] = saved.items[key]
		return true

	func release() -> void:
		_containers.clear()

class RuleScope extends RefCounted:
	var owner:WeakRef
	var lifecycle:int
	var root:Array
	var containers = ContainerState.new()
	var listeners:Array = []

# 内部 adapter 前态，不是规则准入凭据；scope 必须串行嵌套，不能跨 reset 使用。
func capture_rule_state():
	var state = RuleScope.new()
	state.owner = weakref(self)
	state.lifecycle = _managed_writer_backing()[2]
	state.root = entries
	state.listeners = recorded.get_connections()
	if not state.containers.capture([entries]): return null
	_rule_scopes.append(state)
	return state

func _owns_rule_state(state) -> bool:
	return state is RuleScope and state.owner.get_ref() == self and state.lifecycle == _managed_writer_backing()[2] and not _rule_scopes.is_empty() and is_same(_rule_scopes.back(), state)

func can_restore_rule_state(state) -> bool:
	# 不擅自改接监听；可达目标/连接闭包必须由调用方完整核验。
	return _owns_rule_state(state) and recorded.get_connections() == state.listeners and state.containers.can_restore() and _managed_can_advance(not is_same(entries, state.root), false, 1 if is_same(entries, state.root) else 2)

func restore_rule_state(state) -> bool:
	if not can_restore_rule_state(state): return false
	# 全部可恢复性先验后，第一次 native 写之前涨版本；重入观察不见旧版本。
	# 不比较 captured writer_version，scope 内合法自写仍可恢复。
	_managed_advance()
	if not state.containers.restore(): return false
	entries = state.root
	return release_rule_state(state)

func release_rule_state(state) -> bool:
	if not _owns_rule_state(state): return false
	_rule_scopes.pop_back()
	state.containers.release()
	state.root = []
	state.listeners.clear()
	return true

func reset() -> void:
	if _atomic_graph != null:
		_atomic_reason = "private_journal_reset_requires_lifecycle"
		return
	# readonly/exhaustion 零规则写、零版本写；成功空 reset 仍是生命周期边界。
	if entries.is_read_only() or not _managed_can_advance(false, true): return
	_managed_advance(false, true)
	_fact_publication_generation += 1
	for state in _rule_scopes:
		state.containers.release()
		state.root = []
		state.listeners.clear()
	_rule_scopes.clear()
	entries.clear()


#记一条事实，返回它的隔离副本。容器会再复制一层，调用方之后改自己的数据不影响历史；
#object 保留引用（效果链要靠它取卡），只把 tags/data 复制一层
func record(entry:Dictionary) -> Dictionary:
	if entries.is_read_only() or not _managed_can_advance(): return {}
	if not _atomic_record_guard(): return {}
	if _atomic_graph != null:
		var admitted:Dictionary = _atomic_graph.admit(entry)
		if admitted.status != "COMPLETED":
			_atomic_reason = admitted.reason
			return {}
		entry = admitted.value
	var stored:Dictionary = entry.duplicate()
	stored["tags"] = _deep_copy(entry.get("tags", []))
	stored["data"] = _deep_copy(entry.get("data", {}))
	entries.append(stored)
	_managed_advance()
	if recorded.has_connections():
		recorded.emit(_isolate(stored))
	return _isolate(stored)


#按条件查。filter 每个键都要求命中：type/actor/target/place 直接比，
#tags 有交集即中，data 给定键值全等。
#current_round 由调用方传入（journal 不自己维护回合）
func query(filter:Dictionary, current_round:int, round_offset, limit:int = -1) -> Array:
	var got:Array = []
	if round_offset == null:
		for entry in entries:
			if _matches(entry, filter):
				got.append(entry)
	else:
		var want_round:int = current_round + int(round_offset)
		#倒序扫但绝不提前 break：日志允许补记/导入不同回合的事实，
		#追加顺序不等于回合顺序，只有「条目回合 == 目标回合才收集」是安全的
		for i in range(entries.size() - 1, -1, -1):
			var entry:Dictionary = entries[i]
			if int(entry.get("round", 0)) != want_round:
				continue
			if _matches(entry, filter):
				got.append(entry)
		got.reverse()
	#先按 limit 截取再复制：只要最近几条时不必把命中的每一条都拷一遍
	if limit > 0 and got.size() > limit:
		got = got.slice(got.size() - limit)
	var isolated:Array = []
	for entry in got:
		isolated.append(_isolate(entry))
	return isolated


#裁掉比 oldest 更旧的条目
func trim_rounds(oldest:int) -> void:
	if entries.is_read_only() or not _managed_can_advance(): return
	var kept:Array = []
	for entry in entries:
		if int(entry.get("round", 0)) >= oldest:
			kept.append(entry)
	if kept.size() == entries.size(): return
	_managed_advance()
	entries.assign(kept)


func _matches(entry:Dictionary, filter:Dictionary) -> bool:
	for key in filter.keys():
		var want = filter[key]
		match str(key):
			"tags":
				if !_shares_tag(entry.get("tags", []), want):
					return false
			"data":
				if !_data_matches(entry.get("data", {}), want):
					return false
			_:
				#与 data 同一个语义：字段不存在不算"显式为 null"，不能命中
				if !entry.has(key) or entry[key] != want:
					return false
	return true


func _shares_tag(has, want) -> bool:
	var has_arr:Array = has if has is Array else []
	var want_arr:Array = want if want is Array else [want]
	for t in want_arr:
		if has_arr.has(t):
			return true
	return false


func _data_matches(data, want) -> bool:
	#条件写错（如 data 给成字符串）不能当成"没有这个条件"放行，否则不匹配的也会算命中
	if !(want is Dictionary):
		push_warning("GameLog: data 条件必须是字典，收到 " + str(typeof(want)))
		return false
	if !(data is Dictionary):
		return false
	for k in want.keys():
		if !(data as Dictionary).has(k) or data[k] != want[k]:
			return false
	return true


func _isolate(entry:Dictionary) -> Dictionary:
	var copied:Dictionary = entry.duplicate()
	copied["tags"] = _deep_copy(entry.get("tags", []))
	copied["data"] = _deep_copy(entry.get("data", {}))
	return copied


func _deep_copy(value, memo:Array = []):
	if value is Array or value is Dictionary:
		for pair in memo:
			if is_same(pair[0], value): return pair[1]
		var copied = [] if value is Array else {}
		memo.append([value, copied])
		if value is Array:
			for item in value: copied.append(_deep_copy(item, memo))
		else:
			for key in value: copied[key] = _deep_copy(value[key], memo)
		return copied
	return value
