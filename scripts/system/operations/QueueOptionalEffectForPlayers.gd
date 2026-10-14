class_name QueueOptionalEffectForPlayers
extends RefCounted

#给一组玩家分别排入一次可选择发动/放弃的即时效果。
#只负责「逐人建立选择并排队」，不认识令咒、战果、卡名或具体规则；
#具体动作由调用方传入 funcs（单一动作）或 options（多个互斥选项），显示文案由 shown_name 传入。
#每名玩家得到独立 BaseEffect，选择与触发者互不串扰。
#
#funcs 与 options 二选一：数据要表达"恢复令咒/不恢复令咒"这类多个互斥分支时传 options，
#每条分支自带自己的 funcs（解析与效果自带 options 完全同一份实现，字段支持不会分叉）。
func exec(players:Array, funcs:Array, shown_name:String = "", effect_name:String = "queued_optional_effect", options:Array = []) -> Array:
	var queued:Array = []
	# 五实参 ABI 不变：只继承已验函数帧，activating_eff 仅提供数字环境。
	var execution:Dictionary = EffectManager.execution_context()
	if not execution.get("ok", false):
		return queued
	var context:SessionContext = execution.get("context") as SessionContext
	if context == null:
		return queued
	var state:Dictionary = EffectManager.record_loop_state({"players":players.duplicate(), "funcs":funcs,
		"shown_name":shown_name, "effect_name":effect_name, "options":options,
		"source":EffectManager.activating_eff, "queued":queued, "index":0, "pending":null, "completed":false}, self)
	if state.is_empty(): return queued
	return _resume_queue(state)


# 只接当前未登记选择及剩余玩家；已成功前缀与已解析 choice 均保留原 identity。
func _resume_queue(state:Dictionary) -> Array:
	var queued:Array = state.queued
	if state.completed: return queued
	var context:SessionContext = state.context
	var source:BaseEffect = state.source
	var funcs:Array = state.funcs
	var options:Array = state.options
	var shown_name:String = state.shown_name
	var effect_name:String = state.effect_name
	while int(state.index) < state.players.size():
		var id:int = int(state.players[int(state.index)])
		var choice:BaseEffect = state.pending
		if choice != null:
			if not _queue_registered_choice(state, choice, id): return queued
			continue
		if !GameData.player_data_library.has(id):
			state.index = int(state.index) + 1
			continue
		var declaration:Dictionary = {
			"effect_name":effect_name, "time_points":[], "priority":0,
			"is_pure_passive":false, "is_residue":false, "effect_numbers":[], "funcs":[]
		}
		var produced:Array = LoadHelper.load_effects([declaration], null, context)
		if produced.size() != 1:
			return queued
		choice = produced[0]
		choice._shown_name = shown_name
		choice._need_activate = false
		choice._remove_after_trigger = true
		choice._trigger_player_id = id
		choice._trigger_time_points = []
		#延续来源效果的数字上下文，让 descriptors 可继续用 number_index；
		#只复制引用上下文，不改来源效果或玩家数据
		if source != null:
			choice._using_numbers = source._using_numbers
			choice.numbers = source.numbers
		choice._funcs = []
		#选项分支：funcs 留空，动作写在每个选项自己的 funcs 里
		if !options.is_empty():
			choice._options = LoadHelper.load_effect_options(options, choice, context)
			if choice._options.size() != options.size():
				_discard_unpublished(choice)
				return queued
		for func_data in funcs:
			if func_data is Dictionary:
				var parsed:Array = LoadHelper.load_funcs([func_data], choice, context)
				if parsed.size() != 1:
					_discard_unpublished(choice)
					return queued
				choice._funcs.append(parsed[0])
			elif func_data is BaseFunc:
				# 已有 runtime 函数只能继承自己的原来源；不把外来实例当模板授权。
				if not func_data.runtime_source_status(choice, context).get("ok", false):
					_discard_unpublished(choice)
					return queued
				var copied:Dictionary = CloneContext.new().copy_result(func_data, context)
				var cloned:BaseFunc = copied.get("object") as BaseFunc
				if not copied.get("ok", false) or cloned == null or not cloned.runtime_source_status(choice, context).get("ok", false):
					_discard_unpublished(choice)
					return queued
				choice._funcs.append(cloned)
		state.pending = choice
		if not _queue_registered_choice(state, choice, id): return queued
	state.completed = true
	return queued


func _queue_registered_choice(state:Dictionary, choice:BaseEffect, id:int) -> bool:
	var registration:Dictionary = EffectManager.register_native_effect_result(choice, id)
	if registration.status != "COMPLETED":
		# 只消费控制信封；审计、父帧与单次尾票均由 EM owner 管理。
		_discard_unpublished(choice)
		if bool(EffectManager.runtime_guard_status().get("paused", false)): return false
	else:
		EffectManager.decision_queue.append(choice)
		state.queued.append(choice)
	state.pending = null
	state.index = int(state.index) + 1
	return true


# 与 AskPlayerOption 相同的未发布对象生命周期合同；不注销未登记对象、不做规则 undo。
func _discard_unpublished(choice:BaseEffect) -> void:
	if not bool(EffectManager.runtime_guard_status().get("paused", false)):
		GameData.effects.erase(choice)
		GameData.objects.erase(choice)
