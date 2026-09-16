class_name ExecutionTrace
extends RefCounted

#执行追踪：一次效果执行里每次 func 调用的开始/结束/父子关系/循环路径。
#只负责追踪本身，不认识卡牌规则、玩家解析、效果私有字段、数值对象——
#上下文与参数快照都由 GameLog（适配层）在调用前准备好传进来。
#存的是"当时的值"：数值已经是数字，活对象已经是身份标识，历史不跟着对象之后的变化走

var calls:Array = []            # 执行日志条目（调试/验证/回放用，读为主）
var next_execution_id:int = 0
var next_call_id:int = 0
var execution_stack:Array = []  # 存 execution_id
var call_stack:Array = []       # 存条目 Dictionary 本身，按条目定位收栈
var loop_stack:Array = []       # 循环路径，由循环类 operation 压/弹
#每个执行进入时的循环栈深度：结束时恢复到该深度，只清掉本执行期间新增的层。
#异常收尾若只清栈不恢复深度，本执行里压了循环却抛错没弹，残留会污染之后的调用
var loop_depths:Array = []


func reset() -> void:
	calls = []
	next_execution_id = 0
	next_call_id = 0
	execution_stack = []
	call_stack = []
	loop_stack = []
	loop_depths = []


func begin_execution() -> int:
	next_execution_id += 1
	execution_stack.append(next_execution_id)
	loop_depths.append(loop_stack.size())
	return next_execution_id


#结束一次执行。显式传编号时按编号定位收栈（幂等：找不到就什么都不做，不误弹别的）；
#不传编号时才结束栈顶。
func end_execution(eid:int = 0) -> void:
	var target:int = eid
	if target <= 0 and !execution_stack.is_empty():
		target = int(execution_stack[execution_stack.size() - 1])
	var start:int = execution_stack.find(target) if target > 0 else -1
	if start != -1:
		#target 与比它更内层、还没结束的执行一起收尾：
		#内层若抛错没走到自己的 end_execution，它的调用也在这里清掉，不会永远留在栈上
		var closing:Array = []
		for i in range(start, execution_stack.size()):
			closing.append(int(execution_stack[i]))
		var kept:Array = []
		for call in call_stack:
			if closing.has(int(call.get("execution_id", -1))):
				if call.get("status", "") == "running":
					call["status"] = "aborted"
			else:
				kept.append(call)
		call_stack = kept
		#循环栈恢复到这些执行里最早进入时的深度：它们压的循环层一并清掉，
		#外层（start 之前）的循环层不动
		if start < loop_depths.size():
			loop_stack.resize(int(loop_depths[start]))
			loop_depths.resize(start)
		execution_stack.resize(start)
		return
	#显式传了编号但找不到：这次执行已经被收过了，幂等地什么都不做，不误弹栈顶
	if eid > 0:
		return
	if !execution_stack.is_empty():
		execution_stack.pop_back()
		loop_depths.pop_back()


func begin_call(ctx:Dictionary, func_name:String, raw_snapshot, resolved_snapshot) -> int:
	next_call_id += 1
	var eid:int = execution_stack[execution_stack.size() - 1] if !execution_stack.is_empty() else 0
	var parent_id:int = 0
	if !call_stack.is_empty():
		parent_id = int((call_stack[call_stack.size() - 1] as Dictionary).get("call_id", 0))
	var entry:Dictionary = {
		"call_id" : next_call_id,
		"parent_call_id" : parent_id,
		"execution_id" : eid,
		"round" : ctx.get("round", 0),
		"phase" : ctx.get("phase", ""),
		"effect_name" : ctx.get("effect_name", ""),
		"func_name" : func_name,
		"raw_parameters" : raw_snapshot,
		"resolved_parameters" : resolved_snapshot,
		"return_value" : null,
		"status" : "running",
		"trigger_player_id" : ctx.get("trigger_player_id", -1),
		"trigger_time_points" : (ctx.get("trigger_time_points", []) as Array).duplicate(),
		"loop_path" : loop_stack.duplicate(),
	}
	call_stack.append(entry)
	calls.append(entry)
	return next_call_id


#按 call_id 结束一次调用：把返回值快照与最终状态填回 begin 落下的那条。
#幂等：编号不在活动调用栈里（已结束/已随执行收尾/编号错）时不改任何东西，
#重复结束不会把已写好的结果改掉。本条之后的残留（嵌套里抛错没结束的调用）
#一并标成 aborted 弹出
func end_call(call_id:int, result_snapshot, status:String) -> void:
	if call_id <= 0:
		return
	var idx:int = -1
	for i in range(call_stack.size() - 1, -1, -1):
		if int((call_stack[i] as Dictionary).get("call_id", -1)) == call_id:
			idx = i
			break
	if idx == -1:
		return
	var entry:Dictionary = call_stack[idx]
	entry["return_value"] = result_snapshot
	entry["status"] = status
	for i in range(call_stack.size() - 1, idx, -1):
		var dangling = call_stack[i]
		if dangling is Dictionary and dangling.get("status", "") == "running":
			dangling["status"] = "aborted"
		call_stack.remove_at(i)
	call_stack.remove_at(idx)
