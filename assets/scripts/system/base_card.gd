extends BaseObject
class_name BaseCard



var _card_img:String
#卡背图。JSON里card_back_img为空时，用data/card_backs里的通用卡背
var _card_back_img:String = ""
var _effects:Array#[BaseEffect]
#属性。属性主要出现在攻击卡上，但事件、目标等非手牌卡也可能带有属性，所以放在卡牌基类上
var _attributes:Array#[String]
#明置/暗置状态。手牌以外，新都的暗置事件牌等也要能翻面，所以放在卡牌基类上。
#手牌暗置时不计入合计威力、也不消耗魔力(伊莉雅斯菲尔暗置检查等效果依赖此字段)，
#翻面统一走SetCardConcealed，不要在效果里手动加减威力
var _is_concealed:bool = false
#这张卡展示的是哪个buff的状态(御主物品卡：黑泥、宝石、天之衣等)。没有对应buff时为空。
#物品卡和buff是两个独立对象，这里存引用而不是拷状态——buff的激活状态会变，
#渲染时要读的是它此刻的值(未激活的卡面要盖深红遮罩)。对应关系写在JSON的relate_buff里
var _relate_buff

func edit_card_name(card_name:String):
	_name = card_name

func set_effects(effects:Array):
	_effects = effects

func set_concealed(T_or_F:bool):
	_is_concealed = T_or_F

func edit_attribute(add_attributes:Array = [], del_attributes:Array = [], set_attributes:Array = [""]):
	if set_attributes != [""]:
		#复制一份，否则后面的增删会改到调用方传进来的数组
		_attributes = set_attributes.duplicate()
	_attributes.append_array(add_attributes)
	for del in del_attributes:
		var i = _attributes.find(del)
		if i != -1:
			_attributes.pop_at(i)

func has_attribute(attribute:String) -> bool:
	return _attributes.has(attribute)
