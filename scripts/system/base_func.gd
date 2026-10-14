extends RefCounted
class_name BaseFunc

# 资格和能力认证是两道门；本类只保存可信生产者捕获的原会话来源。
# 不读取 current_token，不把模板、旧函数或旧 Callable 洗成当前来源。
var _runtime_context:SessionContext = null
var _definition_callable:Callable

# 由独立 worker 在进入规则解释前单向封闭；不是任意脚本的 OS 沙箱。
# RA-00 尚无可执行的能力闭包证明，封闭域全部 unknown，不以 TABLE 登记冒充 admitted。
static var _capability_domain_sealed:bool = false
static func seal_capability_domain() -> void:
	_capability_domain_sealed = true

static func interpreter_entry_status(key:Variant) -> Dictionary:
	if LoadHelper.registered_script(key) == null:
		return {"ok":false, "status":&"unknown", "reason":&"unregistered_interpreter_entry"}
	if _capability_domain_sealed:
		return {"ok":false, "status":&"unknown", "reason":&"unproven_capability_closure", "support_violations":[&"adapter_script_method_getter_listener_closure"]}
	return {"ok":true, "reason":&"registered_interpreter"}

# 入口登记不是影子域能力证明。以下门只准 TABLE 精确 Script 的 exec，
# 闭包参数/条件再递归校验；来源校验保持独立，不以当前会话给陌生方法补票。
class RegisteredCallable extends RefCounted:
	var callback:Callable
	var receiver:Object
	func _init(source:Callable):
		callback = source
		receiver = source.get_object()
	func invoke(...arguments):
		if arguments.is_empty() or not is_same(arguments[-1], self):
			return null
		arguments.pop_back()
		if not BaseFunc._callable_capability_valid(callback, []) or not LoadHelper._runtime_descriptors_supported(arguments, []):
			return null
		return callback.callv(arguments)

func execution_capability_status() -> Dictionary:
	if _self_var_index != -1 or not _callable_capability_valid(_definition_callable, []) or not LoadHelper._runtime_descriptors_supported(_parameters, []) or not LoadHelper._runtime_descriptors_supported(_condition, []):
		return {"ok":false, "status":&"unknown", "reason":&"undeclared_interpreter_capability"}
	return {"ok":true, "reason":&"registered_interpreter"}

static func _callable_capability_valid(callback:Callable, visited:Array) -> bool:
	if _capability_domain_sealed or not callback.is_valid():
		return false
	var receiver = callback.get_object()
	for seen in visited:
		if is_same(seen, receiver):
			return false
	visited.append(receiver)
	if receiver is RuntimeCallable or receiver is RegisteredCallable:
		var bound:Array = callback.get_bound_arguments()
		if callback.get_method() != &"invoke" or callback.get_unbound_arguments_count() != 0 or bound.size() != 1 or not is_same(bound[0], receiver):
			return false
		return _callable_capability_valid(receiver.callback, visited)
	if LoadHelper.registered_callable_script(callback) == null:
		return false
	return LoadHelper._runtime_descriptors_supported(callback.get_bound_arguments(), visited)

static func _registered_callable(callback:Callable) -> Callable:
	if not _callable_capability_valid(callback, []):
		return Callable()
	var captured = RegisteredCallable.new(callback)
	return Callable(captured, "invoke").bind(captured)


# Callable 不保活接收对象。包装器显式保活原接收者；额外绑定自身保活包装器。
# 参数与返回值原样传递，不复制 Dictionary/Array 或游戏对象。
class RuntimeCallable extends RefCounted:
	var callback:Callable
	var context:SessionContext
	var receiver:Object
	func _init(source:Callable, captured:SessionContext):
		callback = source
		context = captured
		receiver = source.get_object()
	func invoke(...arguments):
		if arguments.is_empty() or not is_same(arguments[-1], self):
			return null
		arguments.pop_back()
		if not SessionGeneration.validate_context(context).get("ok", false):
			return null
		if not BaseFunc._value_source_valid(callback, context, []) or not BaseFunc._value_source_valid(arguments, context, [], true):
			return null
		if not BaseFunc._callable_capability_valid(callback, []) or not LoadHelper._runtime_descriptors_supported(arguments, []):
			return null
		var result = callback.callv(arguments)
		if not SessionGeneration.validate_context(context).get("ok", false):
			return null
		return result

# 显式可信捕获入口；不能为已经捕获的旧 Callable 重贴新 context。
# 原回调的能力审查仍由解释器/调用方负责，来源有效不是方法权限。
static func capture_runtime_callable(callback:Callable, context:SessionContext) -> Callable:
	if not _callable_capability_valid(callback, []):
		return Callable()
	if not SessionGeneration.validate_context(context).get("ok", false):
		return Callable()
	if not _value_source_valid(callback, context, []):
		return Callable()
	if callback.get_object() is RuntimeCallable:
		return callback
	var captured = RuntimeCallable.new(callback, context)
	return Callable(captured, "invoke").bind(captured)

# 工厂必须先完成服务登记；外来同形句柄、跨局改绑和旧闭包均拒绝。
func bind_runtime_context(context:Variant) -> bool:
	if not context is SessionContext or not SessionGeneration.validate_context(context).get("ok", false):
		return false
	var registered:Dictionary = SessionGeneration.origin_of(self)
	if not registered.get("ok", false) or not is_same(registered.get("context"), context):
		return false
	if _runtime_context != null:
		return is_same(_runtime_context, context) and runtime_source_status().get("ok", false)
	# 动态方法、参数回调与条件都必须先过能力门，之后才进行原来源绑定。
	if not execution_capability_status().get("ok", false):
		return false
	if not _value_source_valid(_definition_callable, context, []) or not _value_source_valid(_parameters, context, []) or not _value_source_valid(_condition, context, []):
		return false
	_runtime_context = context
	# 只包装 Callable 叶子，保留所有原容器/对象 identity；先预验，失败不半包装。
	_capture_parameter_callables(_parameters, context, [])
	if _condition is Callable:
		_condition = capture_runtime_callable(_condition, context)
	else:
		_capture_parameter_callables(_condition, context, [])
	_func = capture_runtime_callable(_definition_callable, context)
	return _func.is_valid()

func runtime_context() -> SessionContext:
	return _runtime_context

# EM 必须在帧、condition、placeholder、自变量、方法目标和游戏日志之前调用。
# effect/context 都必须与原函数同域；新 effect 不能替旧 f 领票。
func runtime_source_status(effect:BaseEffect = null, context:SessionContext = null) -> Dictionary:
	var status:Dictionary = SessionGeneration.validate_context(_runtime_context)
	if not status.get("ok", false):
		return status
	if effect != null:
		status = effect.runtime_source_status()
		if not status.get("ok", false):
			return status
		if not is_same(effect.runtime_context().token(), _runtime_context.token()):
			return {"ok":false, "reason":&"stale_session"}
	if context != null:
		status = SessionGeneration.validate_context(context)
		if not status.get("ok", false):
			return status
		if not is_same(context.token(), _runtime_context.token()):
			return {"ok":false, "reason":&"stale_session"}
	if not _value_source_valid(_parameters, _runtime_context, [], true) or not _value_source_valid(_condition, _runtime_context, [], true):
		return {"ok":false, "reason":&"stale_session"}
	return {"ok":true, "reason":&"current"}

# 仅获取已捕获 callable，不在消费时绑定未知方法或签发来源。
func runtime_callable(effect:BaseEffect, context:SessionContext) -> Callable:
	if effect == null or context == null or not runtime_source_status(effect, context).get("ok", false) or not execution_capability_status().get("ok", false):
		return Callable()
	return _func

# 捕获参数与原 callback 的绑定参数一并验来源。visited 按实际引用截断容器环。
static func _value_source_valid(value, context:SessionContext, visited:Array, require_captured:bool = false) -> bool:
	if value is BaseFunc or value is BaseEffect:
		var source:SessionContext = value.runtime_context()
		return SessionGeneration.validate_context(source).get("ok", false) and is_same(source.token(), context.token())
	if value is Callable:
		if not value.is_valid():
			return false
		var receiver = value.get_object()
		if receiver is RuntimeCallable:
			return SessionGeneration.validate_context(receiver.context).get("ok", false) and is_same(receiver.context.token(), context.token())
		if require_captured:
			return false
		if receiver is BaseFunc or receiver is BaseEffect:
			if not _value_source_valid(receiver, context, visited, require_captured):
				return false
		return _value_source_valid(value.get_bound_arguments(), context, visited, true)
	if value is Array or value is Dictionary:
		for seen in visited:
			if is_same(seen, value):
				return true
		visited.append(value)
		if value is Dictionary:
			for key in value:
				if key is Callable or not _value_source_valid(key, context, visited, require_captured) or not _value_source_valid(value[key], context, visited, require_captured):
					return false
		else:
			for item in value:
				if not _value_source_valid(item, context, visited, require_captured):
					return false
	return true

static func _capture_parameter_callables(value, context:SessionContext, visited:Array) -> void:
	if not (value is Array or value is Dictionary):
		return
	for seen in visited:
		if is_same(seen, value):
			return
	visited.append(value)
	for key in (value.keys() if value is Dictionary else range(value.size())):
		var item = value[key]
		if item is Callable:
			value[key] = capture_runtime_callable(item, context)
		else:
			_capture_parameter_callables(item, context, visited)

func clone_data(context):
	var cloned:BaseFunc
	var paras:Array = context.copy_value(_parameters)
	var condition = context.copy_value(_condition)
	if _self_var_index != -1:
		cloned = BaseFunc.new_method_func(_self_var_index, _method_name, paras, _var_index, condition)
	else:
		var instance = null
		var registered = LoadHelper.registered_callable_script(_definition_callable)
		if registered != null:
			instance = registered.new()
		var callable = Callable(instance, "exec") if instance != null else _definition_callable
		cloned = BaseFunc.new(callable, paras, _var_index, condition)
		cloned._instance = instance
	cloned._name = _name
	cloned._if_affect_power = _if_affect_power
	cloned._priority = _priority
	cloned._func_target_player = _func_target_player
	cloned._func_target_property = _func_target_property
	# 模板 clone 仍无资格；runtime clone 保留原句柄，过期也不清 stamp。
	cloned._runtime_context = _runtime_context
	if _runtime_context != null and _self_var_index == -1:
		cloned._func = capture_runtime_callable(cloned._definition_callable, _runtime_context)
	return cloned

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
#func名(下划线形式，如 edit_score)，执行日志用它标识这条操作
var _name:String = ""

func _init(f:Callable, ps:Array, var_index:int = -1, condition = null):
	_definition_callable = f
	_parameters = ps
	_var_index = var_index
	_condition = condition
	# 构造不签来源票；参数/条件也拒绝未知能力，不留半合法 Callable。
	_func = _registered_callable(f) if execution_capability_status().get("ok", false) else Callable()

# 尚无具名方法能力声明；保留工厂签名，但不给旧 EM 可据以动态绑定的下标。
# 空 Callable 既不能获来源票，也不会进入 self_var 分支；不返回 null 诱发调用方解引用。
static func new_method_func(_requested_self_var_index:int, method_name:String, ps:Array, var_index:int = -1, condition = null) -> BaseFunc:
	var f = BaseFunc.new(Callable(), ps, var_index, condition)
	f._method_name = method_name
	return f
