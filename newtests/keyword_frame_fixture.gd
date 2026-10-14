extends RefCounted

# 仅转接既有进度根：解释器负责建立/核验帧，辅助脚本不造帧、不 bind 消费口。
static func execute(key:String, parameters:Array, context:SessionContext, value_required:bool = false) -> Dictionary:
	var operation:Dictionary = GameProgress.start_progress_operation(key, parameters, context)
	return await GameProgress.wait_progress_operation(operation, value_required)

# 只加载一次的显式模板图；新一代经 CloneContext 复制，不重签旧 runtime。
# 御主仅是原测试的附带技能容器；空效果、零费用、威力 2 和未觉醒声明保持不变。
static func supplemental_templates() -> Array:
	var owner := BaseMaster.new("owner", "owner", "", "", "")
	var extra:Array = LoadGame.load_skills([skill_data("extra_skill")], "", owner)
	var servant:Array = LoadGame.load_skills([skill_data("servant_skill")], "", null)
	var upgrade_data:Dictionary = skill_data("upgrade")
	upgrade_data["is_awakened"] = false
	var upgrade:Array = LoadGame.load_skills([upgrade_data], "", owner, "upgrade_skill")
	owner._specials = {"SKILLS":extra}
	owner._upgrade_skill = upgrade
	return [owner, servant[0]]

static func skill_data(name:String) -> Dictionary:
	return {"skill_name":name, "skill_card_img":"", "attributes":[],
		"cost":{"number":0, "can_change":true, "is_pure_number":true}, "power":{"number":2, "can_change":true, "is_pure_number":true}, "ignore_limit":false, "effects":[]}

# 原 simultaneous 声明逐项交给正式加载器；本代 card/effect/func 同用原 context。
# funcs 参数的数字仍是 BaseNumber，不把普通字典冒充已解析的 typed 参数。
static func simultaneous_cards(context:SessionContext) -> Array:
	var conditional:Dictionary = {"attack_name":"conditional", "attack_card_img":"", "attributes":[],
		"cost":{"number":0, "can_change":true, "is_pure_number":true}, "power":{"number":0, "can_change":true, "is_pure_number":true}, "effects":[{
			"effect_name":"requires_true_name", "time_points":[TimePoints.SELF_CARD_COST_CALCULATED],
			"priority":0, "is_pure_passive":true, "is_residue":false, "effect_numbers":[],
			"funcs":[
				{"func_name":"is_true_name_released", "parameters":[-1], "var_index":0},
				{"func_name":"edit_power", "parameters":[null, BaseNumber.new(1), 0], "var_index":-1,
					"condition":{"self_var":0}}
			]}]}
	var release_card:Dictionary = {"attack_name":"release", "attack_card_img":"", "attributes":[],
		"cost":{"number":0, "can_change":true, "is_pure_number":true}, "power":{"number":0, "can_change":true, "is_pure_number":true}, "effects":[],
		"keywords":[ApplyCardKeywords.TRUE_NAME_RELEASE]}
	return LoadGame.load_attacks([conditional, release_card], "", null, [], context)
