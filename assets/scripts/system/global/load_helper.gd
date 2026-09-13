class_name LoadHelper
extends RefCounted


#卡牌 JSON 加载的共享工具类：数字解析、效果解析、func_name 转类名、卡背解析。
#独立成 class_name 供 LoadGame / LoadAttack / LoadEvent / LoadSituation 复用，
#避免 LoadAttack / LoadEvent 直接引用 LoadGame autoload 造成编译期循环依赖。
#本类只依赖 class_name（BaseEffect / BaseFunc / BaseNumber），不引用任何 autoload。


#卡数据根目录。故意用不带前缀的相对路径：这样它在编辑器里指向项目根的 data/，
#导出后指向可执行文件同级的 data/，玩家能直接看到并增改卡牌 JSON 与图片。
#不要改成 res://——那会把 data 打进 pck，外部就看不见也加不了卡了。
const DATA_DIR := "data"
const CARD_BACKS_DIR := DATA_DIR + "/card_backs"

#图片缓存，避免同一张图反复读盘解码。{路径 : Texture2D}
static var _texture_cache:Dictionary = {}


#统一的图片加载入口。外部 data 里新丢进来的图没有 .import 记录，
#load() 在导出后会失败，所以先试 load()(命中编辑器导入缓存/包内资源)，
#失败再用 Image 运行时读盘。两条路都失败返回 null，调用方自行决定是否留空。
static func load_texture(path:String) -> Texture2D:
	if path == "":
		return null
	if _texture_cache.has(path):
		return _texture_cache[path]
	var tex:Texture2D = null
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is Texture2D:
			tex = res
	if tex == null:
		#运行时读盘：支持玩家自行放入的、未经 Godot 导入的图片
		var img := Image.new()
		if img.load(path) == OK:
			tex = ImageTexture.create_from_image(img)
	if tex != null:
		_texture_cache[path] = tex
	return tex


#图片是否可用。取代散落各处的 ResourceLoader.exists()——
#外部未导入的图 ResourceLoader.exists() 为 false 但实际能读，只看它会漏掉玩家自加的图
static func texture_exists(path:String) -> bool:
	if path == "":
		return false
	if _texture_cache.has(path):
		return true
	if ResourceLoader.exists(path):
		return true
	return FileAccess.file_exists(path)


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
		#time_points默认OR(命中任一即触发)；写 require_all_time_points:true 改为AND，
		#要求列出的时点全部同时成立（如"高潮回合"且"自己的行动阶段"）
		effect._time_points_require_all = eff.get("require_all_time_points", false)
		effect.from = from
		effect.set_numbers(nums)
		effect._using_numbers = nums
		if eff.has("cost"):
			effect._cost = eff["cost"]
		#from 和 numbers 都已就绪，此时才能把数字登记到所属对象上
		effect.register_numbers_to_source()
		#多选效果(如令咒三选一、宝石魔术选项)：options非空时每个选项自带一套funcs，
		#写法与效果的funcs完全一致，玩家选中哪几个才结算哪几个，效果自身的_funcs留空不用。
		#max_choices不写默认1(单选)；填>1限定一次提交最多用几次(次数加总)；填-1不限数量随便选。
		#reset_counts_each_round/consumes_source_resource声明这组用量限制的生命周期与资源绑定，
		#quantity_range让某个选项在选中的同时还要求玩家额外选一个范围内的数量(如"弃1-3张")
		if eff.has("options"):
			var opts:Array = []
			for opt:Dictionary in eff["options"]:
				var opt_dict := {
					"shown_option_name": opt.get("shown_option_name", ""),
					"funcs": load_funcs(opt.get("funcs", []), effect),
					"max_uses": opt.get("max_uses", -1) as int
				}
				if opt.has("quantity_range"):
					opt_dict["quantity_range"] = opt["quantity_range"]
				opts.append(opt_dict)
			effect._options = opts
			effect._max_choices = eff.get("max_choices", 1) as int
			effect._max_total_uses = eff.get("max_total_uses", -1) as int
			effect._reset_counts_each_round = eff.get("reset_counts_each_round", false) as bool
			effect._consumes_source_resource = eff.get("consumes_source_resource", false) as bool
		else:
			for f in load_funcs(eff["funcs"], effect):
				effect.add_func(f)
		
		eff_arr.append(effect)
	
	return eff_arr


#把 JSON 的 funcs 数组解析成 BaseFunc 数组，不挂到任何效果上。
#load_effects 解析效果自身的 funcs 与每个多选一选项的 funcs 都复用这一份逻辑
static func load_funcs(funcs:Array, effect:BaseEffect) -> Array:
	var result:Array = []
	for _func:Dictionary in funcs:
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
			result.append(eff_func)

		elif _func.has("self_var"):
			#调用存在变量表里的对象自身的方法。目标对象只在效果激活时才存在，
			#所以这里只记下下标和方法名，绑定推迟到 activate_effect
			var self_var_index = _func["self_var"] as int
			if self_var_index == -1: continue
			var method_name = _func.get("sub_func", "") as String
			if method_name == "": continue
			var eff_func = BaseFunc.new_method_func(self_var_index, method_name, paras, var_index, condition)
			result.append(eff_func)
	return result


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


#真正把卡"放进"某个数组的 operation，以及该数组在 parameters 里的位置。
#只有这些才算放入动作：get_player_deck 之类的查询只是把数组取进变量表，取来也可能是为了
#抽牌/数张数/查牌，出现它本身不代表往里放（阴炁弹就是取数组后把自己移出游戏）
static var ARRAY_INSERT_FUNCS := {
	"add_to_array": 1,        # exec(item, arr, index)        -> arr 是目标
	"draw_card_by_card": 2,   # exec(card, from, to, to_index)-> to 是目标
	"draw_card_by_index": 1,  # exec(from, to, ...)           -> to 是目标
}
#把玩家牌库取进变量表的查询 operation
static var DECK_QUERY_FUNCS := ["get_player_deck"]


#某张卡（按 JSON 里的名字）是否会被 effects_data 里的某条效果放进玩家牌库。
#判据是数据流追踪而不是"出现了某个函数名"：
#  ① 先找出 get_player_deck 把牌库存进了哪些 var_index；
#  ② 再看是否有放入型 operation 的【目标数组参数位】引用了这些 var_index。
#两者都满足才算入牌库。循环体（for_func）里的放入动作要递归进去看（葛木的蛇就在 for_func 内）。
#"要加入牌库会在效果中说明"是本项目既有约定，这里只读效果声明，不在数据里另加冗余字段。
#只能在加载阶段用原始 JSON 调用：BaseFunc 不保留 func_name（只存 Callable），运行时无法反查。
static func is_card_inserted_to_deck(card_name:String, effects_data:Array) -> bool:
	if card_name == "":
		return false
	for eff in effects_data:
		if not (eff is Dictionary):
			continue
		var funcs = eff.get("funcs", [])
		if not (funcs is Array):
			continue
		#这条效果是否提到了这张卡；不提就不是搬它
		if not _funcs_mention_name(funcs, card_name):
			continue
		var deck_vars := {}
		_collect_deck_vars(funcs, deck_vars)
		if deck_vars.is_empty():
			continue
		if _funcs_insert_into_vars(funcs, deck_vars):
			return true
	return false


#递归收集"把玩家牌库存进变量表"的 var_index
static func _collect_deck_vars(funcs:Array, out:Dictionary) -> void:
	for f in funcs:
		if not (f is Dictionary):
			continue
		if DECK_QUERY_FUNCS.has(str(f.get("func_name", ""))):
			var vi = f.get("var_index", -1)
			if typeof(vi) == TYPE_FLOAT or typeof(vi) == TYPE_INT:
				if int(vi) != -1:
					out[int(vi)] = true
		for nested in _nested_func_lists(f):
			_collect_deck_vars(nested, out)


#递归判断是否有放入型 operation 的目标数组参数位指向 deck_vars 里的变量
static func _funcs_insert_into_vars(funcs:Array, deck_vars:Dictionary) -> bool:
	for f in funcs:
		if not (f is Dictionary):
			continue
		var fname := str(f.get("func_name", ""))
		if ARRAY_INSERT_FUNCS.has(fname):
			var target_pos:int = ARRAY_INSERT_FUNCS[fname]
			var ps = f.get("parameters", [])
			if ps is Array and target_pos < ps.size():
				var target = ps[target_pos]
				if target is Dictionary and target.has("self_var"):
					if deck_vars.has(int(target["self_var"])):
						return true
		for nested in _nested_func_lists(f):
			if _funcs_insert_into_vars(nested, deck_vars):
				return true
	return false


#递归判断这批 func 描述里是否出现过某个名字字面量
static func _funcs_mention_name(funcs:Array, target_name:String) -> bool:
	for f in funcs:
		if not (f is Dictionary):
			continue
		for p in (f.get("parameters", []) if f.get("parameters") is Array else []):
			if typeof(p) == TYPE_STRING and str(p) == target_name:
				return true
		for nested in _nested_func_lists(f):
			if _funcs_mention_name(nested, target_name):
				return true
	return false


#取出一个 func 描述的参数里嵌套的 func 描述数组（如 for_func / if_func 的循环体、分支体）
static func _nested_func_lists(f:Dictionary) -> Array:
	var result:Array = []
	for p in (f.get("parameters", []) if f.get("parameters") is Array else []):
		if p is Array:
			var only_func_descs := true
			for item in p:
				if not (item is Dictionary and item.has("func_name")):
					only_func_descs = false
					break
			if only_func_descs and not p.is_empty():
				result.append(p)
		elif p is Dictionary and p.has("func_name"):
			result.append([p])
	return result


#放大分类的三档取值。card=可放大+完整卡牌说明；avatar=可放大但只显示名字；
#token=可放大该小图标，只显示名字与层数，不走卡牌式说明
const ZOOM_KIND_CARD := "card"
const ZOOM_KIND_AVATAR := "avatar"
const ZOOM_KIND_TOKEN := "token"
static var ZOOM_KINDS := [ZOOM_KIND_CARD, ZOOM_KIND_AVATAR, ZOOM_KIND_TOKEN]


#解析某张图片的放大分类。每条图片路径旁边自带一条 zoom_kind 声明它是什么：
#  多图对象(御主同时有头像/御主卡/令咒卡)写 "<图片字段>_zoom_kind"，
#  单图对象直接写同级 "zoom_kind"。
#刻意不做兜底猜测：声明缺失就返回空串，UI 据此不给放大——
#靠字段名或尺寸去猜会在外部玩家新增卡时静默猜错，宁可不放大也不要错分类。
static func resolve_zoom_kind(data:Dictionary, img_field:String) -> String:
	var kind := str(data.get(img_field + "_zoom_kind", ""))
	if kind == "":
		kind = str(data.get("zoom_kind", ""))
	if !ZOOM_KINDS.has(kind):
		return ""
	return kind


#解析卡背路径：JSON里card_back_img非空就用同目录的特殊卡背，否则用data/card_backs里的通用卡背。
#每个json都可以写card_back_img覆盖通用卡背，不写就用类型对应的通用卡背
static func resolve_card_back(card_back_img:String, dir_path:String, type_name:String) -> String:
	if card_back_img != "":
		return dir_path + "/" + card_back_img
	if !CARD_BACK_FILES.has(type_name):
		return ""
	#与其余卡数据一致，走外部 data 目录：导出后玩家能看到并替换卡背
	return CARD_BACKS_DIR + "/" + CARD_BACK_FILES[type_name]


#把御主物品卡(黑泥、宝石、天之衣等)接上它展示的那个buff。对应关系写在数据里
#(物品卡的relate_buff字段)，没声明就不关联——不靠名字后缀之类的猜法，
#猜错会让"未激活"的遮罩静默盖到错误的卡上，比不盖更难发现。
#存的是buff实例引用：激活状态会变，渲染时读的必须是此刻的值
static func bind_things_to_buffs(things_data:Array, thing_objs:Array, buffs:Array) -> void:

	for i in range(mini(things_data.size(), thing_objs.size())):
		var buff_name: String = str((things_data[i] as Dictionary).get("relate_buff", ""))
		if buff_name == "":
			continue
		for buff in buffs:
			if str(buff._name) == buff_name:
				thing_objs[i]._relate_buff = buff
				break
