class_name CostText
extends RefCounted

## 解析效果自身显式声明的消耗资源项。
## 卡牌的 _cost 是“打出这张牌”的费用，不是“发动牌上能力”的费用；
## 能力没有声明 cost 时不显示资源行，也不会在确认发动时扣卡牌费用。
## 消耗条目解析：只读效果数据，不依赖界面实例，供新旧控制器共用
static func effect_cost_items(effect: BaseEffect) -> Array[String]:
	var costs: Array[String] = []
	if effect == null:
		return costs
	if effect._cost != null:
		_collect(effect._cost, costs)
	return costs

## 收集 cost 声明（支持单个 Dictionary 或 Array）
static func _collect(cost_data, out_costs: Array[String]) -> void:
	if cost_data is Dictionary:
		var one := _format_item(cost_data)
		if one != "":
			out_costs.append(one)
	elif cost_data is Array:
		for item in cost_data:
			if item is Dictionary:
				var one := _format_item(item)
				if one != "":
					out_costs.append(one)

## 格式化单项消耗：资源名 + 数字，无量词
static func _format_item(c_dict: Dictionary) -> String:
	var type_str: String = str(c_dict.get("type", "")).to_lower()
	var amount: int = int(c_dict.get("amount", 1))
	var res_name: String = str(c_dict.get("name", ""))
	match type_str:
		"buff":
			return "%s %d" % [res_name if res_name != "" else "状态", amount]
		"magic":
			return "魔力 %d" % amount
		"command_spell":
			return "令咒 %d" % amount
		_:
			return "%s %d" % [res_name, amount] if res_name != "" else ""

## 拼接消耗资源行：有消耗才追加，无消耗整行不显示
static func attach_line(base_text: String, cost_items: Array[String]) -> String:
	if cost_items.is_empty():
		return base_text
	return base_text + "\n消耗资源：" + "、".join(cost_items)
