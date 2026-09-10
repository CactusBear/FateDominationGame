extends BaseAttack
class_name PrecisionStrike15


func _init():
	super("precision_strike_1_5", "res://assets/scripts/system/attacks/basic/precision_strike_1_5/precision_strike_1_5.png", ["agility"], BaseNumber.new(1), BaseNumber.new(5))
	_category = BaseAttack.CATEGORY_BASIC
	_shown_name = "刹那的一击"
