extends BaseAttack
class_name PhysicalAttack04


func _init():
	super("physical_attack_0_4", "res://assets/scripts/system/attacks/basic/physical_attack_0_4/physical_attack_0_4.png", ["strength"], BaseNumber.new(0), BaseNumber.new(4))
	_category = BaseAttack.CATEGORY_BASIC
	_shown_name = "浑身的一击"
