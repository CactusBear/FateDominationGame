extends BaseHandCard
class_name BaseAttack

#攻击牌类别：用字段区分，不新建子类。
const CATEGORY_BASIC := "basic"          #基础攻击牌（右下角标 Basic Attack）
const CATEGORY_NON_BASIC := "non_basic"  #非基础（从者/御主专属攻击牌）
const CATEGORY_CLASS := "class"          #职阶攻击牌（会进牌库的职阶卡）


var _category:String = CATEGORY_NON_BASIC


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
