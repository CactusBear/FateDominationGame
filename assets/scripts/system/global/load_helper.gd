class_name LoadHelper
extends RefCounted


#卡牌 JSON 加载的共享工具类：数字解析、效果解析、func_name 转类名、卡背解析。
#独立成 class_name 供 LoadGame / LoadAttack / LoadEvent / LoadSituation 复用，
#避免 LoadAttack / LoadEvent 直接引用 LoadGame autoload 造成编译期循环依赖。
#本类只依赖 class_name（BaseEffect / BaseFunc / BaseNumber），不引用任何 autoload。


#把下划线命名的 func_name 转成 PascalCase 类名（如 get_location -> GetLocation）。
static func func_name_to_class_name(func_name:String) -> String:
	var parts = func_name.split("_")
	var _class_name = ""
	for part in parts:
		if part == "":
			continue
		_class_name += part.substr(0, 1).to_upper() + part.substr(1)
	return _class_name


#把 JSON 数字字典解析成 BaseNumber。JSON 里的数字一律解析成 float，
#整数值要还原成 int，否则 is_float 会全部判成 true。
static func load_number(number:Dictionary):
	var raw = number["number"]
	if raw is float and raw == floor(raw) and !number.get("is_float", false):
		raw = int(raw)
	var num = BaseNumber.new(raw, number["can_change"], number["is_pure_number"])
	return num


#把 JSON 效果数组解析成 BaseEffect 数组。from 为效果归属对象。
static func load_effects(effects:Array, from) -> Array:
	var eff_arr:Array
	for eff:Dictionary in effects:
		var priority = eff["priority"] as int
		var is_pure_passive = eff["is_pure_passive"] as bool
		var is_residue = eff["is_residue"] as bool
		var numbers = eff["effect_numbers"] as Array
		var nums:Array
		for number:Dictionary in numbers:
			var num = load_number(number)
			nums.append(num)
		
		var effect = BaseEffect.new(eff["effect_name"], eff["time_points"], priority, is_pure_passive, is_residue)
		effect._shown_name = eff.get("shown_effect_name", "")
		effect.from = from
		effect.set_numbers(nums)
		effect._using_numbers = nums
		#from 和 numbers 都已就绪，此时才能把数字登记到所属对象上
		effect.register_numbers_to_source()
		for _func:Dictionary in eff["funcs"]:
			var condition = _func.get("condition", null)
			var var_index = _func.get("var_index", -1)
			var paras = _func.get("parameters", []) as Array

			if _func.has("func_name"):
				var key = _func["func_name"] as String
				var _class_name = func_name_to_class_name(key)
				var func_path = "res://assets/scripts/system/operations/" + _class_name + ".gd"
				if !ResourceLoader.exists(func_path):
					print("没有操作:" + "'" + key + "'")
					continue
				var func_instance = load(func_path).new()
				var main_callable = Callable(func_instance, "exec")
				var eff_func = BaseFunc.new(main_callable, paras, var_index, condition)
				#Callable 不会保活实例，必须由 func 自己持有引用，否则加载完就被释放
				eff_func._instance = func_instance
				effect.add_func(eff_func)

			elif _func.has("self_var"):
				#调用存在变量表里的对象自身的方法。目标对象只在效果激活时才存在，
				#所以这里只记下下标和方法名，绑定推迟到 activate_effect
				var self_var_index = _func["self_var"] as int
				if self_var_index == -1: continue
				var method_name = _func.get("sub_func", "") as String
				if method_name == "": continue
				var eff_func = BaseFunc.new_method_func(self_var_index, method_name, paras, var_index, condition)
				effect.add_func(eff_func)
		
		eff_arr.append(effect)
	
	return eff_arr


#卡类型 → 通用卡背文件名。卡背是通用的，按类型分类放在 data/card_backs 里
static var CARD_BACK_FILES = {
	"master" : "master_card_back.png",
	"servant" : "servant_card_back.png",
	"attack" : "attack_card_back.png",
	"skill" : "skill_card_back.png",
	"event" : "event_card_back.png",
	"situation" : "situation_card_back.png",
	"climax_situation" : "climax_situation_card_back.png",
	"command_spell" : "command_spell_card_back.png",
	"upgrade_skill" : "upgrade_skill_card_back.png"
}


#解析卡背路径：JSON里card_back_img非空就用同目录的特殊卡背，否则用data/card_backs里的通用卡背。
#每个json都可以写card_back_img覆盖通用卡背，不写就用类型对应的通用卡背
static func resolve_card_back(card_back_img:String, dir_path:String, type_name:String) -> String:
	if card_back_img != "":
		return dir_path + "/" + card_back_img
	if !CARD_BACK_FILES.has(type_name):
		return ""
	return "res://data/card_backs/" + CARD_BACK_FILES[type_name]
