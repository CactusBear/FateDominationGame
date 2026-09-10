extends BaseAttack
class_name PhysicalAttack03


func _init():
	super("physical_attack_0_3", "res://assets/scripts/system/attacks/basic/physical_attack_0_3/physical_attack_0_3.png", ["strength"], BaseNumber.new(0), BaseNumber.new(3))
	_category = BaseAttack.CATEGORY_BASIC
	_shown_name = "强打"
