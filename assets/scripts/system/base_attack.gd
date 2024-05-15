extends BaseHandCard
class_name BaseAttack


func _init(card_name:String, card_img:String, attributes:Array, cost:BaseNumber = BaseNumber.new(0), power:BaseNumber = BaseNumber.new(0), effects:Array = []):
	_name = card_name
	_card_img = card_img
	_attributes = attributes
	_cost = cost
	_power = power
	_effects = effects
	
	numbers.insert(0, cost)
	numbers.insert(1, power)
	super.add_object()

