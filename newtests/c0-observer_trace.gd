extends RefCounted

# 只拉公共隔离快照；规则图从不持有这个观察器或测试账本。
static func snapshot(value):
	if value is BaseNumber:
		return value.number
	if value is Array:
		var result:Array = []
		for item in value: result.append(snapshot(item))
		return result
	if value is Dictionary:
		var result:Dictionary = {}
		for key in value: result[key] = snapshot(value[key])
		return result
	if value is Object:
		var script = value.get_script()
		return {"object_class":script.resource_path.get_file().get_basename() if script != null else "", "object_name":value._name if value is BaseObject else "", "object_id":value.get_instance_id()}
	return value

static func cutoff() -> int:
	var last:int = 0
	for call in GameLog.all_func_calls(): last = maxi(last, int(call.call_id))
	return last

static func samples(after:int, body:Array, points:Array) -> Dictionary:
	var calls:Array = GameLog.all_func_calls()
	calls.sort_custom(func(a,b): return a.call_id < b.call_id)
	var by_id:Dictionary = {}
	for call in calls: by_id[call.call_id] = call
	var values:Array = []
	var paths:Array = []
	var issues:Array = []
	var statuses:Array = []
	var leaf:Dictionary = body.back()
	for call in calls:
		if call.call_id <= after or call.effect_name != "native-tail-test" or call.func_name != leaf.func_name:
			continue
		statuses.append(call.status)
		var parent:Dictionary = by_id.get(call.parent_call_id, {})
		if parent.is_empty() or parent.call_id <= after or parent.func_name != "while_func" or parent.effect_name != "native-tail-test" or parent.raw_parameters != snapshot([body, true, 3]) or parent.trigger_time_points != points or call.trigger_time_points != points or call.execution_id != parent.execution_id or call.execution_id <= 0 or call.raw_parameters != snapshot(leaf.parameters):
			issues.append("unmatched sample provenance")
			continue
		if call.status != "executed":
			issues.append("non-executed sample: " + str(call.status))
			continue
		if call.loop_path.size() != parent.loop_path.size() + 1 or call.loop_path.slice(0, parent.loop_path.size()) != parent.loop_path:
			issues.append("invalid sample loop path")
			continue
		values.append(call.return_value)
		paths.append(call.loop_path.back())
	return {"values":values,"paths":paths,"issues":issues,"statuses":statuses}

static func notifications(after:int, points:Array) -> Dictionary:
	var count:int = 0
	var issues:Array = []
	for call in GameLog.all_func_calls():
		if call.call_id <= after or call.effect_name != "guard-activated": continue
		if call.func_name != "store_value" or call.raw_parameters != [true] or call.resolved_parameters != [true] or call.trigger_time_points != points or call.execution_id <= 0 or not call.loop_path.is_empty() or call.parent_call_id != 0 or call.status != "executed" or call.return_value != true:
			issues.append("unmatched notification witness")
		else:
			count += 1
	return {"count":count,"issues":issues}
