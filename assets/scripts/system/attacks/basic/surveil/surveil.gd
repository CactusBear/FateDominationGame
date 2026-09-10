extends BaseAttack
class_name Surveil


func _init():
	super("surveil", "res://assets/scripts/system/attacks/basic/surveil/surveil.png", ["special"], BaseNumber.new(1), BaseNumber.new(3))
	_category = BaseAttack.CATEGORY_BASIC
	_shown_name = "疾行"
	_effects = LoadGame.load_effects(_effects_data(), self)


func _effects_data() -> Array:
	return [
		{
			"effect_name": "surveil_move",
			"shown_effect_name": "行动阶段：无视交战状态，沿箭头移动至下一地点",
			"time_points": ['self_action_phase'],
			"priority": 0,
			"is_pure_passive": false,
			"is_residue": false,
			"effect_numbers": [
				{ "number": 1, "can_change": true, "is_pure_number": true }
			],
			"funcs": [
				{ "func_name": "move", "parameters": [{"number_index": 0}, null, null, true], "var_index": -1 }
			]
		}
	]
