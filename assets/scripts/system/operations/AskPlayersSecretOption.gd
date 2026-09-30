class_name AskPlayersSecretOption
extends RefCounted

#让多名玩家各自秘密地从同一组选项里选一项（猜拳、预测、宣言……）。
#每人一次独立的选择，按传入顺序依次询问；谁选了哪一项写进 results（{玩家id : 选项下标}），返回的也就是它，
#后面的步骤用 get_dictionary_value / match_func / compare_number 比较结果。放弃选择的玩家不在 results 里。
#选项格式与 ask_player_option 相同，选项自己的 funcs 照常结算（变量表与发起效果共用）。
#reveal 为 true 时，全员选完后公开每人的选择；为 false 时只留在规则日志里，界面不显示。
#选择过程中的"选项使用"事实带 secret_choice 标签，战报据此不公开
func exec(players:Array, options:Array, shown_name:String = "", reveal:bool = false) -> Dictionary:
	var results:Dictionary = {}
	var names:Array = []
	for opt in options:
		names.append(str(opt.get("shown_option_name", "")) if opt is Dictionary else "")
	for raw_id in players:
		var id:int = int(raw_id)
		if !GameData.player_data_library.has(id):
			continue
		var marked:Array = []
		for opt in options:
			var copied:Dictionary = (opt as Dictionary).duplicate(true) if opt is Dictionary else {}
			var tags:Array = (copied.get("tags", []) as Array).duplicate()
			if !tags.has("secret_choice"):
				tags.append("secret_choice")
			copied["tags"] = tags
			marked.append(copied)
		var choice:BaseEffect = AskPlayerOption.new().exec(marked, shown_name, id)
		for i in range(choice._options.size()):
			var writer := _ResultWriter.new()
			writer.results = results
			writer.player_id = id
			writer.index = i
			(choice._options[i]["funcs"] as Array).append(_func_of(writer, "secret_choice_result"))
	if reveal:
		#排在所有人的选择之后结算：借"执行到一半提出的选择按提出顺序依次处理"这条已有流程，
		#追加一个无需询问的收尾效果，轮到它时大家都已选完
		var announcer := _Announcer.new()
		announcer.results = results
		announcer.names = names
		announcer.shown_name = shown_name
		var closing := BaseEffect.new("secret_choice_reveal", [], 0, true, false)
		closing._need_activate = false
		closing._remove_after_trigger = true
		closing.add_func(_func_of(announcer, "secret_choice_reveal"))
		var source:BaseEffect = EffectManager.activating_eff
		EffectManager.register_effect(closing, source._trigger_player_id if source != null else GameData.player_id)
		EffectManager.request_choice(closing)
	return results


func _func_of(instance, func_name:String) -> BaseFunc:
	var f := BaseFunc.new(Callable(instance, "exec"), [], -1, null)
	f._instance = instance
	f._name = func_name
	return f


class _ResultWriter extends RefCounted:
	var results:Dictionary
	var player_id:int
	var index:int
	func exec():
		results[player_id] = index
		return index


class _Announcer extends RefCounted:
	var results:Dictionary
	var names:Array
	var shown_name:String
	func exec():
		var lines:Array = []
		if shown_name != "":
			lines.append(shown_name)
		for id in results.keys():
			var i:int = int(results[id])
			var option_name:String = str(names[i]) if i >= 0 and i < names.size() else str(i)
			lines.append("%s：%s" % [EffectManager.player_shown_name(int(id)), option_name])
		if lines.size() > (1 if shown_name != "" else 0):
			EffectManager.push_message("\n".join(lines), -1)
		return results
