extends BaseAttack
class_name MooncancerClass


func _init():
	super("mooncancer_class", "res://assets/scripts/system/attacks/class/mooncancer_class/mooncancer_class.png", ["magic"], BaseNumber.new(0), BaseNumber.new(4))
	_category = BaseAttack.CATEGORY_CLASS
	_shown_name = "月之癌"
	_effects = LoadGame.load_effects(_effects_data(), self)


func _effects_data() -> Array:
	return [
		{
			"effect_name": "mooncancer_event_swap",
			"shown_effect_name": "行动阶段：将你所在地点的事件牌与一张月之圣杯的事件牌互换",
			"time_points": ['self_action_phase'],
			"priority": 0,
			"is_pure_passive": false,
			"is_residue": false,
			"effect_numbers": [],
			"funcs": [
				{ "func_name": "do_nothing", "parameters": [], "var_index": -1 }
			]
		}
	]
