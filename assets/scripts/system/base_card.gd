extends BaseObject
class_name BaseCard

func clone_data(context):
	var cloned = BaseCard.new()
	copy_clone_fields(cloned, context)
	cloned.add_object()
	return cloned


func copy_clone_fields(cloned, context) -> void:
	super.copy_clone_fields(cloned, context)
	cloned._card_img = _card_img
	cloned._card_back_img = _card_back_img
	cloned._attributes = context.copy_value(_attributes)
	cloned._relate_buff = _relate_buff
	cloned._is_concealed = false
	cloned._keywords = context.copy_value(_keywords)
	cloned._initial_zone = _initial_zone
	cloned._initial_count = _initial_count
	cloned._effects = context.copy_effects(_effects, cloned)



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
#这张卡带的词条(如真名解放)。词条是"一类牌共有的规则行为"，
#由卡自己在JSON里显式声明词条名，引擎按词条名执行对应规则——
#不去扫卡面文案里的【xx】字样(文案是给人看的，措辞一变行为就跟着错)，
#也不在每张带词条的牌里把同一段规则复制一遍。
#未识别的词条不做任何事，只当说明用，加新词条不必改老数据
var _keywords:Array = []
#开局放置区域由卡牌数据显式声明；空值表示不自动放置。
#当前支持的路径由开局流程白名单解释，未知值不产生行为。
var _initial_zone:String = ""
var _initial_count:int = 1

func has_keyword(keyword:String) -> bool:
	return _keywords.has(keyword)

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
