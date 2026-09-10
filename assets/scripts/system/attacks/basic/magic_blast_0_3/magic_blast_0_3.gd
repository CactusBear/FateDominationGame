extends BaseAttack
class_name MagicBlast03


func _init():
	super("magic_blast_0_3", "res://assets/scripts/system/attacks/basic/magic_blast_0_3/magic_blast_0_3.png", ["magic"], BaseNumber.new(0), BaseNumber.new(3))
	_category = BaseAttack.CATEGORY_BASIC
	_shown_name = "中位魔术"
