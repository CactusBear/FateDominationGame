extends BaseObject
class_name BaseEffect

func clone_data(context):
	var cloned = BaseEffect.new(_name, _time_points.duplicate(), _priority, _is_pure_passive, _is_residue)
	copy_clone_fields(cloned, context)
	cloned._need_activate = _need_activate
	cloned._source_bound = _source_bound
	cloned._expire_time_points = _expire_time_points.duplicate()
	cloned._time_points_require_all = _time_points_require_all
	cloned._cost = context.copy_value(_cost)
	cloned.set_numbers(context.copy_value(numbers))
	cloned._using_numbers = cloned.numbers
	cloned._funcs = context.copy(_funcs)
	cloned._power_query = _power_query.duplicate(true)
	cloned._max_choices = _max_choices
	cloned._max_total_uses = _max_total_uses
	cloned._reset_counts_each_round = _reset_counts_each_round
	cloned._consumes_source_resource = _consumes_source_resource
	cloned._remove_after_trigger = _remove_after_trigger
	cloned._selected_location = null
	cloned._selected_players = []
	cloned._selected_player = -1
	for opt in _options:
		if opt is Dictionary:
			var copied:Dictionary = context.copy_value(opt)
			copied["funcs"] = context.copy(opt.get("funcs", []))
			if opt.has("activation_requirements"):
				var copied_requirements:Array = []
				for requirement in opt.get("activation_requirements", []):
					if requirement is Dictionary:
						copied_requirements.append({
							"message": str(requirement.get("message", "")),
							"funcs": context.copy(requirement.get("funcs", []))
						})
				copied["activation_requirements"] = copied_requirements
			cloned._options.append(copied)
	cloned._once_per_game = _once_per_game
	cloned._is_manual = _is_manual
	#选择、用量、触发上下文沿用构造默认值；原所属对象的数字索引不变。
	return cloned

var _power_query:Array = []
var _time_points:Array#[String]
#时点匹配模式：false(默认)=命中任一时点即触发；true=必须同时命中_time_points里的全部时点。
#AND模式用于"两个时点同时成立才算"的规则，例如宝石魔术的高潮版要求
#"高潮回合(self_climax)"且"正处于自己的行动阶段(self_action_phase)"，
#单写一个时点都表达不了，写两个又会被OR语义放宽成"任一满足"
var _time_points_require_all:bool = false
var _funcs:Array#[BaseFunc]
var _is_pure_passive:bool = false
# 只响应自身作为时点来源的效果，由卡牌数据声明；独立监听不设置此项。
var _source_bound:bool = false
# 未命中目标时点、但命中这里声明的任一时点时注销；空数组表示永久等待。
var _expire_time_points:Array = []
var _need_activate:bool = true
var _is_residue:bool = false
var _self_vars:Array
var _priority:int
var _using_numbers:Array
var _cost = null
#每局限一次：声明后该效果本局只触发一次，判断依据是游戏日志里的效果触发记录
var _once_per_game:bool = false
#手动发动：声明后不由时点自动询问，只由玩家在它自己声明的时点里主动发动(如令咒)。
#time_points 在这类效果上表达的是"允许发动的时机窗口"，而不是自动触发时机
var _is_manual:bool = false
#选项分支：{"shown_option_name":String, "funcs":Array[BaseFunc],
#  "max_uses":int(单个选项在本次重置周期内最多能用几次，-1不限，默认-1),
#  "quantity_range":[min,max](可选。声明后玩家选中该项时还需额外选一个范围内的数量)}。
#非空时结算走_chosen_selection里选中的各分支funcs，而不是_funcs
var _options:Array = []
#这一次提交(一次呼出/一次弹窗)最多能选几项：1=单选(默认)，>1=多选，-1=不限数量随便选几个
var _max_choices:int = 1
#跨多次呼出累计的用量上限(次数加总)，-1表示不限(默认)——用于"本回合/本周期总计至多用Y次"，
#与_max_choices是两个不同维度：_max_choices管这一次选几个，_max_total_uses管很多次呼出加起来最多几次
var _max_total_uses:int = -1
#玩家提交的选择：{选项下标:int -> 本次用了几次:int}。单选/简单多选时每项的次数都是1，
#"同一选项一次提交里连用多次"也走这同一个字典，只是次数>1
var _chosen_selection:Dictionary = {}
#{选项下标:本次重置周期内累计已用次数}。配合_max_total_uses/选项自己的max_uses做限制；
#是否重置由_reset_counts_each_round决定，不重置就是全局永久计数
var _option_use_counts:Dictionary = {}
#{选项下标:玩家为该选项额外选择的数量}。选项声明quantity_range时才会有值，
#供效果的funcs后续通过{"option_quantity_index":i}占位符取用(留给具体func实现时读取)
var _option_quantities:Dictionary = {}
#是否在每回合开始时(ROUND_START_RESET)自动清空_option_use_counts/_option_quantities。
#默认false=不重置(全局永久上限)；宝石这类"每回合限额"的效果需要声明为true
var _reset_counts_each_round:bool = false
#是否在选中生效时消耗来源对象(effect.from)的_buff_level层数(duck-typed，不限定BaseBuff)。
#层数不足时对应选项不可选；多个效果共享同一个from对象时天然共享同一份资源池
var _consumes_source_resource:bool = false
# 延迟/一次性监听效果在首次实际结算后自动从效果池移除，避免后续同类时点重复执行。
var _remove_after_trigger:bool = false
#玩家为"需要挑牌"的选项实际选中的牌（运行期状态，由 EffectManager.submit_card_selection 写入）。
#选项上的声明写在 option 的 select_cards 里；效果链想读这些牌，用现成的
#get_activating_eff + get_property("_selected_cards") 即可，不必为选牌单开一个 operation
var _selected_cards:Array = []
# 选项级 select_location 的提交结果；效果 funcs 通过 get_property 读取。
var _selected_location:BaseLocation = null
# 选项级 select_players 的提交结果（玩家id数组）。只选一名时同时写 _selected_player，
# 让效果链不必为了"取第0个"再引入一个下标 operation：
# get_activating_eff + get_property("_selected_player") 就能直接把目标喂给任意 func 的玩家参数位
var _selected_players:Array = []
var _selected_player:int = -1
#激活瞬间的触发上下文快照。start_effect会清空各玩家的动态时点，所以要在清空前记下来
var _trigger_player_id:int = -1
var _trigger_time_points:Array


func _init(effect_name:String, time_points:Array, priority:int = -1, is_pure_passive:bool = false, is_residue:bool = false):
	_name = effect_name
	_time_points = time_points
	_funcs = []
	_priority = priority
	_is_pure_passive = is_pure_passive
	_is_residue = is_residue

	super.add_object()
	GameData.effects.append(self)


#是否是选项类效果(单选/多选/数量选择)：有选项时UI要弹选项列表，不是普通的确认/放弃二选一
func has_options() -> bool:
	return !_options.is_empty()


#是否允许一次提交里用超过1次(次数加总>1)：max_choices != 1
func allows_multi_choice() -> bool:
	return _max_choices != 1


#记录某个选项玩家额外选择的数量(如"弃置1-3张"里选中的具体张数)，供funcs后续读取
func set_option_quantity(option_index:int, quantity:int) -> void:
	_option_quantities[option_index] = quantity


func get_option_quantity(option_index:int) -> int:
	return _option_quantities.get(option_index, 0) as int


#把效果自带的数字按效果名登记到所属对象上，供外部效果按"效果名+下标"寻址。
#from和numbers都要先赋值，所以由加载方在两者就绪后调用
func register_numbers_to_source():
	if !(from is BaseObject):
		return
	var _from = from as BaseObject
	_from.effect_numbers[_name] = numbers



func edit_effect_name(effect_name:String):
	_name = effect_name
	
func edit_time_points(add_time_points:Array = [], del_time_points:Array = [], set_time_points:Array = [""]):
	if set_time_points != [""]:
		_time_points = set_time_points
	_time_points.append_array(add_time_points)
	for del in del_time_points:
		var i = _time_points.find(del)
		if i != -1:
			_time_points.pop_at(i)

func edit_funcs(add_funcs:Array = [], set_funcs:Array = []):
	if set_funcs != []:
		_funcs = set_funcs
	_funcs.append_array(add_funcs)


func add_func(_func:BaseFunc):
	_funcs.append(_func)

func del_func(_func:BaseFunc):
	var i = _funcs.find(_func)
	while i != -1:
		_funcs.remove_at(i)
		i = _funcs.find(_func)

func set_passive(T_or_F:bool):
	_is_pure_passive = T_or_F

func set_need_activate(T_or_F:bool):
	_need_activate = T_or_F

func set_is_residue(T_or_F:bool):
	_is_residue = T_or_F
