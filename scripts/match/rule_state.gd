extends RefCounted

## 采集显式规则对象图，不恢复对象，也不把缺少调用栈的快照声明为完整状态。
const Ids = preload("res://scripts/match/net_ids.gd")
const GraphSession = preload("res://scripts/match/graph_session.gd")

## 编码是单向关联投影，不是资格凭据；服务元数据不进入规则图。
class ProjectionIds extends "res://scripts/match/net_ids.gd":
	const Token = preload("res://scripts/system/session_token.gd")
	const Context = preload("res://scripts/system/session_context.gd")
	const Generation = preload("res://scripts/system/session_generation.gd")
	var _handles:Dictionary = {}

	func _handle_id(handle:Object) -> int:
		if not _handles.has(handle):
			_handles[handle] = _handles.size() + 1
		return _handles[handle]

	func encode(value, depth:int = 0):
		if _capture_collections and not error.is_empty():
			return null
		if depth > 128:
			error = "存档数据嵌套过深"
			return null
		if value is WeakRef:
			return encode(value.get_ref(), depth + 1)
		if value is Token:
			return ["session_token", _handle_id(value)]
		if value is Context:
			return ["session_context", _handle_id(value), str(value.origin()), encode(value.token(), depth + 1)]
		if value is Generation:
			return ["session_service", null]
		return super.encode(value, depth)

## 保留调用者业务对象 ID/预算/数据归一化，句柄号仅属于本次投影。
static func project(ids, roots:Dictionary, collections:bool = false) -> Dictionary:
	var projection = ProjectionIds.new()
	projection._by_instance = ids._by_instance
	projection._objects = ids._objects
	projection.data_root = ids.data_root
	projection.max_capture_collections = ids.max_capture_collections
	projection.max_capture_comparisons = ids.max_capture_comparisons
	var result:Dictionary = projection.snapshot_graph(roots) if collections else projection.snapshot(roots)
	ids.error = projection.error
	return result

## A1-04 的已实现投影边界；声明本身不是运行证明或可执行状态核。
static func a1_projection_contract() -> Dictionary:
	return {
		"schema": "a1-session-projection/v1",
		"capture_context": "explicit_issued_SessionContext_at_capture; never_derive_at_restore",
		"restore_gate": "validate_original_context_before_first_rule_write",
		"leaves": ["session_token", "session_context", "session_service"],
		"handles": "projection_local_alias_ids; preserve_origin; exclude_process_instance_ids",
		"evidence": "same_frozen_real_graph_and_required_runtime_checks",
		"not_proven": ["executable_fork", "full_passive_state", "full_rng_closure", "whole_action_completion"]
	}

## 发现合同不是准入资格；首次完整支持证明由后续真实图/隔离专项提供。
static func support_manifest() -> Dictionary:
	return {
		"schema": "rule-attempt-support/v1",
		"status": "unknown",
		"proof": "not_complete",
		# 仅组合局部机制登记视图，既有 required_* 与全仓 unknown 原样保留。
		"local_adapters": {"graph":GraphSession.local_support_view()},
		"a1_projection": a1_projection_contract(),
		"required_roots": ["broadcast_requires_confirm", "players", "registry", "registered_effects",
			"game_data", "progress", "map", "effects", "time_points", "facts", "log_context",
			"restrictions", "attributes", "attack_templates", "event_templates", "situation_templates",
			"spell_templates", "ai_scope", "ai_attempts", "execution_context"],
		"required_adapters": ["pure_fields", "collection_identity_abi", "callable_rebinding",
			"static_isolation", "rule_journal_trace", "metadata_lifo", "known_rng",
			"owned_continuations", "owned_delivery", "isolated_sinks", "a1_origin_validation"],
		"state_domains": ["players/map/seats/cards/effects/registry/number_fields",
			"cycles/aliases/order/key_presence", "Callable/WeakRef/script_connections",
			"autoload/statics/templates/restrictions/ai", "usage/chosen/layers/selection/metadata",
			"journal/trace/synchronous_listeners", "waiting/continuations/owned_tickets", "declared_rng"],
		"scope": {"parent": "preserve_capture_prestate", "child": "restore_only_owned_changes",
			"success": "release_private_prestate_not_parent_commit", "failure": "abort_only_owned_tickets"},
		"nonrollbackable": ["session_token/context/service_bindings", "audit_identity",
			"transport_serial/broadcast_batch", "delivered_external_observations"],
		"completion": "whole_declared_action/listeners/owned_continuations/pure_postcondition; pending_is_not_completed",
		"support_violations": ["full_graph_not_proven", "fork_rebinding_not_proven", "pure_get_set_not_proven",
			"rng_closure_not_proven", "input_version_not_proven", "completion_not_proven", "sink_isolation_not_proven"]
	}

## 单向导出只使用私有编码表；不向现有 live NetIds 分配身份，不承诺可执行 fork。
static func capture_passive(execution_context: Dictionary = {}, export_limits: Dictionary = {}) -> Dictionary:
	var private_ids = Ids.new()
	for key in export_limits:
		if key not in ["max_capture_collections", "max_capture_comparisons"] or not export_limits[key] is int or export_limits[key] <= 0:
			return {"status": "unknown", "export": {}, "error": "被动导出预算声明无效",
				"support_violations": ["invalid_export_limits"]}
		private_ids.set(key, export_limits[key])
	var exported: Dictionary = capture_graph(private_ids, execution_context)
	return {"status": "unknown", "export": exported, "error": private_ids.error,
		"support_violations": support_manifest().support_violations}

static func capture(ids, execution_context: Dictionary = {}) -> Dictionary:
	var roots: Dictionary = _roots()
	if not execution_context.is_empty():
		roots["execution_context"] = execution_context
	return project(ids, roots)

static func capture_graph(ids, execution_context: Dictionary = {}) -> Dictionary:
	var roots: Dictionary = _roots()
	if not execution_context.is_empty():
		roots["execution_context"] = execution_context
	return project(ids, roots, true)

static func capture_runtime(ids) -> Dictionary:
	# 调度图包含函数/来源帧；execution_context 仅查询资格，不能替代规则快照。
	# 保留帧内原 context，由既有投影编码为叶子；不从快照推断或刷新来源。
	var context: Dictionary = EffectManager.execution_runtime_snapshot().duplicate()
	var runs: Array = []
	for active in context.runs:
		var item: Dictionary = active.duplicate()
		item.run = _run_without_report(item.run)
		runs.append(item)
	context.runs = runs
	context.suspended_run = _run_without_report(context.suspended_run)
	context["guard"] = EffectManager.runtime_guard_status()
	context["random"] = preload("res://scripts/match/rule_random.gd").snapshot()
	return capture_graph(ids, context)

static func _run_without_report(run: Dictionary) -> Dictionary:
	var result: Dictionary = run.duplicate()
	result.erase("state_before")
	return result

static func _roots() -> Dictionary:
	# 展示队列不是规则输入；保留执行队列、等待、变量、牌序和次数。
	# 活动调用栈由 capture_runtime 单独采集；普通录制检查点位于外部动作之间。
	# _registration_owners 是弱引用保活表，回收时机取决于进程内引用计数，规则身份已由 self_effects 记录。
	var effects: Dictionary = Ids.script_fields(EffectManager, ["messages", "effect_results", "_message_serial", "_pending_announcements", "_function_frames", "_active_runs", "_runtime_guard", "_guard_run", "_guard_frames", "_resume_frames", "_guard_continuations", "_draining_guard_continuations", "_guard_transactions", "_transaction_scope", "_continuation_transactions", "_batch_transactions", "_registration_owners"])
	var paused: Dictionary = {}
	var paused_runs: Dictionary = EffectManager.paused_runs_snapshot()
	for choice in paused_runs:
		var item: Dictionary = paused_runs[choice]
		# 手动效果差值报告含进程实例号，只用于展示。
		item.run = _run_without_report(item.run)
		paused[choice] = item
	effects["_paused_runs"] = paused
	var ai_state: Dictionary = DummyBot.capture_attempts()
	var attempts: Array = []
	for instance in ai_state.attempted_effect_ids:
		var object = instance_from_id(int(instance))
		if object != null:
			attempts.append(object)
	return {
		"broadcast_requires_confirm": GameProgress.battle_broadcast_requires_confirm,
		"players": GameData.player_data_library,
		"registry": GameData.objects,
		"registered_effects": GameData.effects,
		"game_data": Ids.script_fields(GameData, ["player_data_library", "objects", "effects", "effects_signals", "_model"]),
		# _model 是同一批字段的存储容器（属性 getter 已逐项读出）；整体编码会把排除项（如进程内会话序号）带回哈希。
		"progress": Ids.script_fields(GameProgress, ["_session_serial", "_battle_broadcast_consumer", "_battle_broadcast_batch_serial", "_model"]),
		"map": Ids.script_fields(MapData, ["_model"]),
		"effects": effects,
		"time_points": Ids.script_fields(TimePointChecker),
		"facts": GameLog.query({}, null),
		"log_context": [GameLog.current_round, GameLog.current_phase, GameLog.max_rounds],
		"restrictions": AbilityRestrictions.entries,
		"attributes": Attributes.custom_attributes,
		"attack_templates": LoadAttack._attack_datas,
		"event_templates": LoadEvent.events,
		"situation_templates": [LoadSituation.situations, LoadSituation.climax_situations],
		"spell_templates": LoadCommandSpell.command_spells,
		"ai_scope": ai_state.scope,
		"ai_attempts": attempts
	}
