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
	var source:BaseEffect = EffectManager.activating_eff
	for raw_id in players:
		var id:int = int(raw_id)
		if !GameData.player_data_library.has(id):
			continue
		var choice := BaseEffect.new(effect_name, [], 0, false, false)
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
			choice._options = LoadHelper.load_effect_options(options, choice)
		for func_data in funcs:
			if func_data is Dictionary:
				choice._funcs.append(LoadHelper.load_funcs([func_data], choice)[0])
			elif func_data is BaseFunc:
				choice._funcs.append(func_data.clone_data(CloneContext.new()))
		EffectManager.register_effect(choice, id)
		EffectManager.decision_queue.append(choice)
		queued.append(choice)
	return queued
