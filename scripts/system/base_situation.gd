extends BaseCard
class_name BaseSituation

func clone_data(context:CloneContext):
	if not context.is_copying():
		return context.copy(self)
	if context.prepare_card(self) == null:
		return null
	var cloned = BaseSituation.new(_name, _card_img, context.copy(_magic), [], false)
	copy_clone_fields(cloned, context)
	return context.finish_card(self, cloned)


var _magic:BaseNumber


func _init(card_name:String, card_img:String, magic:BaseNumber = BaseNumber.new(0), effects:Array = [], register_object:bool = true):
	_name = card_name
	_card_img = card_img
	_magic = magic
	_effects = effects
	
	numbers.insert(0, magic)
	if register_object:
		super.add_object()

func edit_magic(add_magic:BaseNumber = BaseNumber.new(0), set_magic:BaseNumber = null):
	if set_magic != null:
		_magic = set_magic
	_magic.add(add_magic)
