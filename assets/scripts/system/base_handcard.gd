extends BaseCard
class_name BaseHandCard

func clone_data(context):
	var cloned = BaseHandCard.new()
	copy_clone_fields(cloned, context)
	cloned._cost = context.copy(_cost)
	cloned._power = context.copy(_power)
	cloned.numbers = [cloned._cost, cloned._power]
	cloned.add_object()
	return cloned

func copy_clone_fields(cloned, context) -> void:
	super.copy_clone_fields(cloned, context)
	cloned._is_activating = false
	cloned._is_closed = false
	cloned._cost_discount = context.copy(_cost_discount)
	cloned._play_requirements = context.copy_value(_play_requirements)
	cloned._shown_notes = context.copy_value(_shown_notes)
	cloned._need_extra_play = _need_extra_play


#_attributes、edit_attribute、_is_concealed、set_concealed已移至BaseCard，事件等非手牌卡也能带属性和明暗状态
var _cost:BaseNumber
var _is_activating:bool = false
var _power:BaseNumber
#关闭状态：技能牌关闭后返回技能区，攻击牌关闭后转为暗置(佐佐木小次郎等效果)
var _is_closed:bool = false
#单张卡费用折扣，与玩家层的attack_cost_discount叠加生效
var _cost_discount:BaseNumber = BaseNumber.new(0)
#打出条件：由卡自己的数据声明，每项形如{type, value, shown_note}。
#引擎按 type 判断能否打出(未识别的type不拦)，界面按 shown_note 出说明行
var _play_requirements:Array = []
#卡面印的纯提示行(不含规则)，界面原样列出
var _shown_notes:Array = []
#此牌须靠"追加打出"(add_attack/add_skill，不计常规出牌上限)进场，常规出牌被拒
var _need_extra_play:bool = false




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
