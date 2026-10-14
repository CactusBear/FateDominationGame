extends BaseCard
class_name BaseEvent

func clone_data(context:CloneContext):
	if not context.is_copying():
		return context.copy(self)
	if context.prepare_card(self) == null:
		return null
	var cloned = BaseEvent.new(_name, _card_img, context.copy(_score), [], false)
	copy_clone_fields(cloned, context)
	return context.finish_card(self, cloned)


var _score:BaseNumber


func _init(card_name:String, card_img:String, score:BaseNumber = BaseNumber.new(0), effects:Array = [], register_object:bool = true):
	_name = card_name
	_card_img = card_img
	_score = score
	_effects = effects
	
	numbers.insert(0, score)
	if register_object:
		super.add_object()


func edit_score(add_score:BaseNumber = BaseNumber.new(0), set_score:BaseNumber = null):
	if set_score != null:
		_score = set_score
	_score.add(add_score)
