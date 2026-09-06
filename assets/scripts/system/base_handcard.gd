extends BaseCard
class_name BaseHandCard


#_attributes与edit_attribute已移至BaseCard，事件等非手牌卡也能带属性
var _cost:BaseNumber
var _is_activating:bool = false
var _power:BaseNumber




func edit_cost(add_cost:BaseNumber = BaseNumber.new(0), set_cost:BaseNumber = null):
	if set_cost != null:
		_cost = set_cost
	_cost.add(add_cost)

func edit_power(add_power:BaseNumber = BaseNumber.new(0), set_power:BaseNumber = null):
	if set_power != null:
		_power = set_power
	_power.add(add_power)

func set_if_activating(T_or_F:bool):
	_is_activating = T_or_F
