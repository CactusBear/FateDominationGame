extends RefCounted
class_name BaseFunc

var _func:Callable
var _parameters:Array
var _var_index:int = -1
var _func_used:bool = false
var _if_affect_power:bool = false
var _priority:int
var _func_target_player:int
var _func_target_property
#执行条件。null表示无条件执行；也可以填字面量或{"self_var":i}、{"number_index":i}占位符，
#占位符会在效果激活时与_parameters用同一套规则替换，替换结果为真才执行本func
var _condition = null
#延迟绑定的方法调用。_self_var_index不为-1时，_func在激活时才从_self_vars[_self_var_index]取出对象绑定_method_name
var _self_var_index:int = -1
var _method_name:String = ""
#持有效果脚本实例的强引用。Callable只存ObjectID不保活，这里不留引用的话
#RefCounted实例会在加载结束后立刻释放，Callable随之失效
var _instance

func _init(f:Callable, ps:Array, var_index:int = -1, condition = null):
	_func = f
	_parameters = ps
	_var_index = var_index
	_condition = condition


#创建延迟绑定的方法调用func，目标对象在效果激活时才从_self_vars里取出
static func new_method_func(self_var_index:int, method_name:String, ps:Array, var_index:int = -1, condition = null) -> BaseFunc:
	var f = BaseFunc.new(Callable(), ps, var_index, condition)
	f._self_var_index = self_var_index
	f._method_name = method_name
	return f
