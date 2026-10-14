class_name AskPlayerOption
extends RefCounted

#效果执行到这一步时，让一名玩家从几个选项里选。
#只负责「建立这次选择并交给 EffectManager 暂停等待」：选完后做什么写在每个选项自己的 funcs 里，
#选项字段与效果自带 options 完全同一份解析（max_uses、select_cards、activation_requirements……都能用）。
#选项里的步骤与发起它的效果共用变量表和效果数字：能读前面算出的结果，后面的步骤也能读选项里算出的结果。
#返回建好的选择效果，调用方一般不用管它。
#player_id 为 -1 时是发动这条效果的玩家；max_choices 与效果的同名字段含义一致（1 单选，-1 不限）。
func exec(options:Array, shown_name:String = "", player_id:int = -1, max_choices:int = 1) -> BaseEffect:
	# 只承接已验函数帧的原来源；activating_eff 只提供父效果数据，不能签发来源。
	var execution:Dictionary = EffectManager.execution_context()
	if not execution.get("ok", false):
		return null
	var context:SessionContext = execution.get("context") as SessionContext
	if context == null:
		return null
	var source:BaseEffect = EffectManager.activating_eff
	var id:int = EffectManager.resolve_player_id(player_id)
	#构造会写入对象总表；未知成员必须在建立选择及解析选项前拒绝。
	if id != -1 and GameDataManager.find_player_data(id).is_empty():
		return null
	# 复用可信工厂，只改变来源接线；所有选择字段仍沿原来的赋值与解析路径。
	var declaration:Dictionary = {
		"effect_name": source._name + "_choice" if source != null else "ask_player_option",
		"time_points": [], "priority": 0, "is_pure_passive": false, "is_residue": false,
		"effect_numbers": [], "funcs": []
	}
	var produced:Array = LoadHelper.load_effects([declaration], null, context)
	if produced.size() != 1:
		return null
	var choice:BaseEffect = produced[0]
	choice._shown_name = shown_name if shown_name != "" else (str(source._shown_name) if source != null else "")
	choice._need_activate = false
	choice._remove_after_trigger = true
	choice._max_choices = max_choices
	if source != null:
		choice.from = source.from
		choice._using_numbers = source._using_numbers
		choice.numbers = source.numbers
		choice._trigger_time_points = source._trigger_time_points.duplicate()
	choice._options = LoadHelper.load_effect_options(options, choice, context)
	if not EffectManager.register_effect(choice, id):
		#审计暂停保留恢复所需对象；普通拒绝只清理此次尚未发布的选择。
		if not bool(EffectManager.runtime_guard_status().get("paused", false)):
			GameData.effects.erase(choice)
			GameData.objects.erase(choice)
		return null
	if not EffectManager.request_choice(choice, context):
		# 请求拒绝不等于已建立等待；沿用审计暂停的对象保留约定。
		if not bool(EffectManager.runtime_guard_status().get("paused", false)):
			EffectManager.unregister_effect(choice)
			GameData.effects.erase(choice)
			GameData.objects.erase(choice)
		return null
	return choice
