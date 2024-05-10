extends BaseObject
class_name BaseCard



var _card_name:String
var _card_img:String
var _effects:Array[BaseEffect]

func edit_card_name(card_name:String):
	_card_name = card_name

func set_effects(effects:Array):
	_effects = effects
