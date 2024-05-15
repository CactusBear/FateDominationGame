extends BaseCard
class_name BaseHandCard


var _attributes:Array#[String]
var _cost:BaseNumber
var _is_activating:bool = false
var _power:BaseNumber




func edit_attribute(add_attributes:Array = [], del_attributes:Array = [], set_attributes:Array = [""]):
	if set_attributes != [""]:
		_attributes = set_attributes
	_attributes.append_array(add_attributes)
	for del in del_attributes:
		var i = _attributes.find(del)
		if i != -1:
			_attributes.pop_at(i)

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
