extends BaseAttack
class_name PrecisionStrike03


func _init():
	super("precision_strike_0_3", "res://assets/scripts/system/attacks/basic/precision_strike_0_3/precision_strike_0_3.png", ["agility"], BaseNumber.new(0), BaseNumber.new(3))
	_category = BaseAttack.CATEGORY_BASIC
	_shown_name = "高速移动"
