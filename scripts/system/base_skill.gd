extends BaseHandCard
class_name BaseSkill

func clone_data(context):
	var cloned = BaseSkill.new(_name, _card_img, _attributes.duplicate(), context.copy(_cost), context.copy(_power), _ignore_limit, [])
	copy_clone_fields(cloned, context)
	cloned._is_awakened = _is_awakened
	return cloned


var _ignore_limit:bool = false
#升华技是否已觉醒。未觉醒的升华技玩家尚未获得，卡面朝下只显示升华技卡背。
#由JSON声明，效果可以改写它——谁在什么时候觉醒是数据的事，代码不写死
var _is_awakened:bool = true

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
