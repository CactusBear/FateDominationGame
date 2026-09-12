extends BaseCard
class_name BaseHandCard


#_attributes、edit_attribute、_is_concealed、set_concealed已移至BaseCard，事件等非手牌卡也能带属性和明暗状态
var _cost:BaseNumber
var _is_activating:bool = false
var _power:BaseNumber
#关闭状态：技能牌关闭后返回技能区，攻击牌关闭后转为暗置(佐佐木小次郎等效果)
var _is_closed:bool = false
#单张卡费用折扣，与玩家层的attack_cost_discount叠加生效
var _cost_discount:BaseNumber = BaseNumber.new(0)




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

func set_closed(T_or_F:bool):
	_is_closed = T_or_F
