extends BaseAttack
class_name MagicBlast02


func _init():
	super("magic_blast_0_2", "res://assets/scripts/system/attacks/basic/magic_blast_0_2/magic_blast_0_2.png", ["magic"], BaseNumber.new(0), BaseNumber.new(2))
	_category = BaseAttack.CATEGORY_BASIC
	_shown_name = "低位魔术"
