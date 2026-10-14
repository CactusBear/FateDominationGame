extends RefCounted
## 已认证房主管理暂停规则的同步收件闭包；不保存 Session 或长期状态。
## 管理暂停、当前 owner、连接身份与 seq 门由 Session 唯一裁决。

func handles(kind:String) -> bool:
	return kind in ["guard_continue", "guard_skip", "guard_restart", "guard_lobby"]

func receive(phase:String, actor:int, kind:String, args:Dictionary, continue_guard:Callable, guard_error:Callable) -> Dictionary:
	# 保留原参数条件；不发明 pause/resume/retry，也不解释 checkpoint。
	if not handles(kind) or phase != "playing" or args.size() != 1 or not args.get("view_seq") is int:
		return {"ok":false,"reason":"只有房主可以继续暂停的规则执行"}
	# 视图版本、暂停状态、完整回滚、预算和审计全部复用唯一权威入口。
	if not continue_guard.call(actor,args.view_seq,kind):
		return {"ok":false,"reason":str(guard_error.call())}
	return {"ok":true,"lobby":kind == "guard_lobby"}