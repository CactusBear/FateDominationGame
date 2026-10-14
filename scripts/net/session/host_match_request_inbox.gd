extends RefCounted
## 已通过 Session 来源/身份/在线/seq 与各请求生命周期门的对局请求小闭包。
## 只验证输入形状、同步分派一次并捕获结果；不持有能力，不发布、不发回执。
## submit 已由组合根绑定可信成员；视图/座位/规则/审计仍由唯一权威入口裁决。

func receive(kind:String, args:Dictionary, submit:Callable, read_reason:Callable) -> Dictionary:
	if kind != "match_command" or not args.get("view_seq") is int or not args.get("command") is String or not args.get("params") is Dictionary:
		return {"ok":false,"reason":"请求无效","dispatched":false}
	var ok:bool = submit.call(args.view_seq,args.command,args.params)
	# 必须在 caller 发布前采集；展示路径可能覆盖 authority.error。
	var reason:String = read_reason.call()
	if not ok and reason.is_empty(): reason = "引擎拒绝该对局操作"
	return {"ok":ok,"reason":reason,"dispatched":true}

## Session 已检查 playing；preview 只绑定唯一权威与可信成员，不保存 Callable。
## ok 仅表示请求形状有效；权威拒绝/私有规则结果仍原样交给 caller 发布。
func receive_preview(args:Dictionary, preview:Callable) -> Dictionary:
	if not args.get("request_id") is int or not args.get("view_seq") is int or not args.get("cards") is Array or not args.get("hidden") is Array:
		return {"ok":false,"reason":"组合预览请求无效"}
	var result:Dictionary = preview.call(args.view_seq,args.cards,args.hidden)
	return {"ok":true,"request_id":args.request_id,"result":result}

## 原开局请求没有必填字段或字段取值限制；外层非字典沿用协议拒因。
## ok 表示形状有效且能力已分派；result 原样承载实际开局结果。
## owner/phase/data_ready、事务与发布仍由 caller 负责。
func receive_begin_match(args:Variant, begin:Callable) -> Dictionary:
	if not args is Dictionary:
		return {"ok":false,"code":"invalid_args","reason":"协议字段无效","dispatched":false}
	if not begin.is_valid():
		return {"ok":false,"code":"missing_capability","reason":"开局能力未提供","dispatched":false}
	var result:Dictionary = begin.call()
	return {"ok":true,"dispatched":true,"result":result}

## caller 保留暂停/owner/playing 与请求世代门；这里只验证原有唯一视图字段。
## 不解释能力结果，不执行大厅迁移、清镜像、发布或回执。
func receive_match_finished_lobby(args:Variant, finish:Callable) -> Dictionary:
	if not args is Dictionary or args.size() != 1 or not args.get("view_seq") is int:
		return {"ok":false,"code":"invalid_args","reason":"只有在线房主能以有效终局视图返回大厅","dispatched":false}
	if not finish.is_valid():
		return {"ok":false,"code":"missing_capability","reason":"终局返回大厅能力未提供","dispatched":false}
	var result:Dictionary = finish.call(args.view_seq)
	return {"ok":true,"dispatched":true,"result":result}

## 原三字段形状门先于能力；认证、在线 owner、批次/可信离线座位仍由 caller 裁决。
## seats 原引用、原顺序交付，不遍历、不去重、不发布广播。
func receive_broadcast_confirm_absent(args:Variant, confirm:Callable) -> Dictionary:
	if not args is Dictionary or args.size() != 3 or not args.get("view_seq") is int or not args.get("batch_id") is int or not args.get("seats") is Array:
		return {"ok":false,"code":"invalid_args","reason":"参数必须恰为 view_seq/batch_id/seats","dispatched":false}
	if not confirm.is_valid():
		return {"ok":false,"code":"missing_capability","reason":"离线广播确认能力未提供","dispatched":false}
	var result:Dictionary = confirm.call(args.view_seq,args.batch_id,args.seats)
	return {"ok":true,"dispatched":true,"result":result}

