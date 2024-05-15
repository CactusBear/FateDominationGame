extends BaseCard
class_name BaseSituation


var _magic:BaseNumber


func _init(card_name:String, card_img:String, magic:BaseNumber = BaseNumber.new(0), effects:Array = []):
	_name = card_name
	_card_img = card_img
	_magic = magic
	_effects = effects
	
	numbers.insert(0, magic)
	super.add_object()

func edit_magic(add_magic:BaseNumber = BaseNumber.new(0), set_magic:BaseNumber = null):
	if set_magic != null:
		_magic = set_magic
	_magic.add(add_magic)
