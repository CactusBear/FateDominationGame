class_name AskPlayerNumber
extends RefCounted

#效果执行到这一步时，让一名玩家在 [min_value, max_value] 里选一个数（上下限可以是前面算出的变量）。
#复用"选项 + 数量"那套已有的输入：建一个只有一项、声明了 quantity_range 的选择，
#界面与 AI 都按已有的数量选择器处理，不另开一种输入类型。
#选中的数写进 result（一个 BaseNumber），返回的也就是它：后面的步骤用 var_index 存下这个返回值，
#等玩家选完（效果恢复执行）时读到的就是玩家选的数；放弃选择时保持 min_value。
#player_id 为 -1 时是发动这条效果的玩家
func exec(min_value, max_value, player_id:int = -1, shown_name:String = "") -> BaseNumber:
	var low:int = int(min_value.number if min_value is BaseNumber else min_value)
	var high:int = int(max_value.number if max_value is BaseNumber else max_value)
	if high < low:
		high = low
	var result := BaseNumber.new(low)
	#上下限相同就没有可选的，直接给出
	if high == low:
		return result
	var choice:BaseEffect = AskPlayerOption.new().exec([{
		"shown_option_name": shown_name,
		"quantity_range": [low, high],
		"funcs": []
	}], shown_name, player_id)
	#选择结算时把玩家定的数量写进 result。直接挂一个内部 func，不经 JSON
	var writer := _QuantityWriter.new()
	writer.target = result
	writer.choice = choice
	var f := BaseFunc.new(Callable(writer, "exec"), [], -1, null)
	f._instance = writer
	f._name = "ask_player_number_result"
	(choice._options[0]["funcs"] as Array).append(f)
	return result


class _QuantityWriter extends RefCounted:
	var target:BaseNumber
	var choice
	func exec():
		if choice == null or target == null:
			return null
		var qty:int = choice.get_option_quantity(0)
		if qty > 0:
			target.set_num(BaseNumber.new(qty))
		return target
