extends BaseAttack
class_name PrecisionStrike04


func _init():
	super("precision_strike_0_4", "res://assets/scripts/system/attacks/basic/precision_strike_0_4/precision_strike_0_4.png", ["agility"], BaseNumber.new(0), BaseNumber.new(4))
	_category = BaseAttack.CATEGORY_BASIC
	_shown_name = "瞬间的一击"
