extends BaseAttack
class_name PhysicalAttack15


func _init():
	super("physical_attack_1_5", "res://assets/scripts/system/attacks/basic/physical_attack_1_5/physical_attack_1_5.png", ["strength"], BaseNumber.new(1), BaseNumber.new(5))
	_category = BaseAttack.CATEGORY_BASIC
	_shown_name = "会心的一击"
