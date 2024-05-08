extends BaseCard
class_name BaseSituation


var _magic:int


func _init(card_name:String, card_img:String, magic:int = 0, effects:Array[BaseEffect] = []):
	_card_name = card_name
	_card_img = card_img
	_magic = magic
	_effects = effects
	super.add_object()
