extends RefCounted

## 采集显式规则对象图，不恢复对象，也不把缺少调用栈的快照声明为完整状态。
const Ids = preload("res://scripts/match/net_ids.gd")

static func capture(ids, execution_context: Dictionary = {}) -> Dictionary:
	var roots: Dictionary = _roots()
	if not execution_context.is_empty():
		roots["execution_context"] = execution_context
	return ids.snapshot(roots)

static func capture_graph(ids, execution_context: Dictionary = {}) -> Dictionary:
	var roots: Dictionary = _roots()
	if not execution_context.is_empty():
		roots["execution_context"] = execution_context
	return ids.snapshot_graph(roots)

static func capture_runtime(ids) -> Dictionary:
	var context: Dictionary = EffectManager.execution_context().duplicate()
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
	var effects: Dictionary = Ids.script_fields(EffectManager, ["messages", "effect_results", "_pending_announcements", "_function_frames", "_active_runs", "_runtime_guard", "_guard_run", "_guard_frames", "_resume_frames", "_guard_continuations", "_draining_guard_continuations", "_guard_transactions", "_transaction_scope", "_continuation_transactions", "_batch_transactions"])
	var paused: Dictionary = {}
	for choice in EffectManager._paused_runs:
		var item: Dictionary = EffectManager._paused_runs[choice].duplicate()
		# 手动效果差值报告含进程实例号，只用于展示。
		item.run = _run_without_report(item.run)
		paused[choice] = item
	effects["_paused_runs"] = paused
	var attempts: Array = []
	for instance in DummyBot._phase_attempted_effect_ids:
		var object = instance_from_id(int(instance))
		if object != null:
			attempts.append(object)
	return {
		"broadcast_registered": GameProgress.has_battle_broadcast_consumer(),
		"players": GameData.player_data_library,
		"registry": GameData.objects,
		"registered_effects": GameData.effects,
		"game_data": Ids.script_fields(GameData, ["player_data_library", "objects", "effects", "effects_signals"]),
		"progress": Ids.script_fields(GameProgress, ["_session_serial", "_battle_broadcast_consumer"]),
		"map": Ids.script_fields(MapData),
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
		"ai_scope": DummyBot._phase_attempt_scope,
		"ai_attempts": attempts
	}
