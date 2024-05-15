extends BaseHandCard
class_name BaseSkill


var _ignore_limit:bool = false

func _init(card_name:String, card_img:String, attributes:Array, cost:BaseNumber = BaseNumber.new(0), power:BaseNumber = BaseNumber.new(0), ignore_limit:bool = false, effects:Array = []):
	_name = card_name
	_card_img = card_img
	_attributes = attributes
	_cost = cost
	_power = power
	_effects = effects
	_ignore_limit = ignore_limit
	
	numbers.insert(0, cost)
	numbers.insert(1, power)
	super.add_object()




func set_ignore_limit(T_or_F:bool):
	_ignore_limit = T_or_F
