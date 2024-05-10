extends BaseCard
class_name BaseEvent


var _score:int


func _init(card_name:String, card_img:String, score:int = 0, effects:Array = []):
	_card_name = card_name
	_card_img = card_img
	_score = score
	_effects = effects
	super.add_object()


func edit_score(add_score:int = 0, set_score:int = -1):
	if set_score != 1:
		_score = set_score
	_score += add_score
