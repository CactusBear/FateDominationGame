extends BaseAttack
class_name ForeignerClass


func _init():
	super("foreigner_class", "res://assets/scripts/system/attacks/class/foreigner_class/foreigner_class.png", ["special"], BaseNumber.new(1), BaseNumber.new(0))
	_category = BaseAttack.CATEGORY_CLASS
	_shown_name = "领域外生命"
	_effects = LoadGame.load_effects(_effects_data(), self)


func _effects_data() -> Array:
	return [
		{
			"effect_name": "foreigner_true_name_plus_power",
			"shown_effect_name": "【真名解放】你和降临者各获得合计威力+6，将此牌加入降临者的弃牌堆",
			"time_points": ['self_true_name_release'],
			"priority": 0,
			"is_pure_passive": false,
			"is_residue": false,
			"effect_numbers": [],
			"funcs": [
				{ "func_name": "do_nothing", "parameters": [], "var_index": -1 }
			]
		}
	]
