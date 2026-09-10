extends BaseAttack
class_name PhysicalAttack02


func _init():
	super("physical_attack_0_2", "res://assets/scripts/system/attacks/basic/physical_attack_0_2/physical_attack_0_2.png", ["strength"], BaseNumber.new(0), BaseNumber.new(2))
	_category = BaseAttack.CATEGORY_BASIC
	_shown_name = "迫击"
