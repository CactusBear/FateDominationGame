extends BaseCard
class_name BaseSituation


var _magic:int


func _init(card_name:String, card_img:String, magic:int = 0, effects:Array = []):
	_name = card_name
	_card_img = card_img
	_magic = magic
	_effects = effects
	
	numbers.insert(0, magic)
	super.add_object()

func edit_magic(add_magic:int = 0, set_magic = null):
	if set_magic != null:
		_magic = set_magic
	_magic += add_magic
