extends RefCounted

## 只观察调用方明确声明的类/方法；不是注册完备、句柄所有权或删除授权证明。
## 不创建原生对象、不加载扩展、不执行任何方法，不访问 manager 或全局游戏数据。
static func observe(method_contract:Dictionary) -> Dictionary:
	var result:Dictionary = {}
	for native_class in method_contract:
		var exists:bool = ClassDB.class_exists(native_class)
		var methods:Dictionary = {}
		for method in method_contract[native_class]:
			methods[method] = exists and ClassDB.class_has_method(native_class,method)
		result[native_class] = {"exists":exists,"can_instantiate":exists and ClassDB.can_instantiate(native_class),"methods":methods}
	return result

## 仅投影已应用声明；缺失/畸形明确 unknown，绝不填充默认策略或输出额外键。
static func validation_policy(applied_data:Dictionary) -> Dictionary:
	var result:Dictionary = {"enabled":"unknown","budget":"unknown"}
	var enabled:Variant = applied_data.get("random_sim_enabled")
	var budget:Variant = applied_data.get("random_sim_budget_sec")
	if enabled is bool: result.enabled = enabled
	if typeof(budget) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(budget)):
		result.budget = budget
	return result