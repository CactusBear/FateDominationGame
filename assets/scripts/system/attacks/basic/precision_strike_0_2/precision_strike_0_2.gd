extends BaseAttack
class_name PrecisionStrike02


func _init():
	super("precision_strike_0_2", "res://assets/scripts/system/attacks/basic/precision_strike_0_2/precision_strike_0_2.png", ["agility"], BaseNumber.new(0), BaseNumber.new(2))
	_category = BaseAttack.CATEGORY_BASIC
	_shown_name = "翻弄"
