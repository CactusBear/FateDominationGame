extends BaseAttack
class_name AvengerClass


func _init():
	super("avenger_class", "res://assets/scripts/system/attacks/class/avenger_class/avenger_class.png", ["special"], BaseNumber.new(1), BaseNumber.new(0))
	_category = BaseAttack.CATEGORY_CLASS
	_shown_name = "复仇者"
	_effects = LoadGame.load_effects(_effects_data(), self)


func _effects_data() -> Array:
	return [
		{
			"effect_name": "avenger_other_attacks_plus_one",
			"shown_effect_name": "战斗阶段：你的其余攻击威力+1",
			"time_points": ['self_battle_phase'],
			"priority": 0,
			"is_pure_passive": true,
			"is_residue": false,
			"effect_numbers": [
				{ "number": 1, "can_change": true, "is_pure_number": true }
			],
			"funcs": [
				{ "func_name": "get_eff_source_card", "parameters": [], "var_index": 0 },
				{ "func_name": "modify_attack_power_by_attribute", "parameters": [[], {"number_index": 0}, null, null, {"self_var": 0}], "var_index": -1 }
			]
		},
		{
			"effect_name": "avenger_unspeakable_hatred_residue",
			"shown_effect_name": "无声业火·残留：此牌残留至你在一场战斗中战胜一名对手为止",
			"time_points": ['self_battle_win'],
			"priority": 0,
			"is_pure_passive": true,
			"is_residue": false,
			"effect_numbers": [],
			"funcs": [
				{ "func_name": "do_nothing", "parameters": [], "var_index": -1 }
			]
		}
	]
