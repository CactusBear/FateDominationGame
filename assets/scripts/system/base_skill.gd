extends BaseCard
class_name BaseSkill


var _attributes:Array#[String]
var _cost:int
var _power:int
var _ignore_limit:bool = false

func _init(card_name:String, card_img:String, attributes:Array, cost:int = 0, power:int = 0, ignore_limit:bool = false, effects:Array = []):
	_card_name = card_name
	_card_img = card_img
	_attributes = attributes
	_cost = cost
	_power = power
	_effects = effects
	_ignore_limit = ignore_limit
	super.add_object()


func edit_attribute(add_attributes:Array = [], del_attributes:Array = [], set_attributes:Array = [""]):
	if set_attributes != [""]:
		_attributes = set_attributes
	_attributes.append_array(add_attributes)
	for del in del_attributes:
		var i = _attributes.find(del)
		if i != -1:
			_attributes.pop_at(i)

func edit_cost(add_cost:int = 0, set_cost:int = -1):
	if set_cost != 1:
		_cost = set_cost
	_cost += add_cost

func edit_power(add_power:int = 0, set_power:int = -1):
	if set_power != 1:
		_power = set_power
	_power += add_power

func set_ignore_limit(T_or_F:bool):
	_ignore_limit = T_or_F
