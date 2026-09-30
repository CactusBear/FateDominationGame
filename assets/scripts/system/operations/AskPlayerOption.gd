class_name AskPlayerOption
extends RefCounted

#效果执行到这一步时，让一名玩家从几个选项里选。
#只负责「建立这次选择并交给 EffectManager 暂停等待」：选完后做什么写在每个选项自己的 funcs 里，
#选项字段与效果自带 options 完全同一份解析（max_uses、select_cards、activation_requirements……都能用）。
#选项里的步骤与发起它的效果共用变量表和效果数字：能读前面算出的结果，后面的步骤也能读选项里算出的结果。
#返回建好的选择效果，调用方一般不用管它。
#player_id 为 -1 时是发动这条效果的玩家；max_choices 与效果的同名字段含义一致（1 单选，-1 不限）。
func exec(options:Array, shown_name:String = "", player_id:int = -1, max_choices:int = 1) -> BaseEffect:
	var source:BaseEffect = EffectManager.activating_eff
	var id:int = EffectManager.resolve_player_id(player_id)
	var choice := BaseEffect.new(source._name + "_choice" if source != null else "ask_player_option", [], 0, false, false)
	choice._shown_name = shown_name if shown_name != "" else (str(source._shown_name) if source != null else "")
	choice._need_activate = false
	choice._remove_after_trigger = true
	choice._max_choices = max_choices
	if source != null:
		choice.from = source.from
		choice._using_numbers = source._using_numbers
		choice.numbers = source.numbers
		choice._trigger_time_points = source._trigger_time_points.duplicate()
	choice._options = LoadHelper.load_effect_options(options, choice)
	EffectManager.register_effect(choice, id)
	EffectManager.request_choice(choice)
	return choice
