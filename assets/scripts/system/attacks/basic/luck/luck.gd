extends BaseAttack
class_name Luck


func _init():
	super("luck", "res://assets/scripts/system/attacks/basic/luck/luck.png", ["special"], BaseNumber.new(0), BaseNumber.new(4))
	_category = BaseAttack.CATEGORY_BASIC
	_shown_name = "幸运"
	_effects = LoadGame.load_effects(_effects_data(), self)


func _effects_data() -> Array:
	return [
		{
			"effect_name": "luck_ignore_defeat",
			"shown_effect_name": "战斗阶段：你本回合无视【败北】效果",
			"time_points": ['self_battle_phase'],
			"priority": 0,
			"is_pure_passive": true,
			"is_residue": false,
			"effect_numbers": [],
			"funcs": [
				{ "func_name": "remove_defeat", "parameters": [], "var_index": -1 }
			]
		}
	]
