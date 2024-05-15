extends BaseCard
class_name BaseEvent


var _score:BaseNumber


func _init(card_name:String, card_img:String, score:BaseNumber = BaseNumber.new(0), effects:Array = []):
	_name = card_name
	_card_img = card_img
	_score = score
	_effects = effects
	
	numbers.insert(0, score)
	super.add_object()


func edit_score(add_score:BaseNumber = BaseNumber.new(0), set_score:BaseNumber = null):
	if set_score != null:
		_score = set_score
	_score.add(add_score)
