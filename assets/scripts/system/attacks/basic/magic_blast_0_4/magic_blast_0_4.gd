extends BaseAttack
class_name MagicBlast04


func _init():
	super("magic_blast_0_4", "res://assets/scripts/system/attacks/basic/magic_blast_0_4/magic_blast_0_4.png", ["magic"], BaseNumber.new(0), BaseNumber.new(4))
	_category = BaseAttack.CATEGORY_BASIC
	_shown_name = "高位魔术"
