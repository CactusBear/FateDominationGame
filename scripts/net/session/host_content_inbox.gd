extends RefCounted

## 无状态内容收件闭包。来源、生命周期、稳定成员和 seq 已由组合根验证。
## 字典均为现有状态引用；队列能力仅同步调用，不保存 Session 或复制批准规则。
func handles(kind:String) -> bool:
	return kind in ["catalog","data_ack","blob_request"]

func receive(room, actor:int, kind:String, args:Dictionary, message_bytes:int, catalog_budget:int, catalogs:Dictionary, confirmed:Dictionary, revision:int, queue_blob:Callable) -> Dictionary:
	match kind:
		"catalog":
			if room.phase != "lobby" or not args.get("entries") is Array:
				return {"ok":false,"reason":"只能在大厅上报条目清单"}
			if message_bytes > catalog_budget:
				return {"ok":false,"reason":"条目清单超过累计消息预算"}
			var catalog = preload("res://scripts/net/content/data_catalog.gd").new()
			var accepted = catalog.accept(args.entries,str(actor))
			if accepted == null:
				return {"ok":false,"reason":"\n".join(catalog.errors)}
			catalogs[actor] = accepted
			return {"ok":true,"catalog_changed":true}
		"data_ack":
			# 旧 revision 的可靠 ACK 不能污染当前确认与身份；seq 仍已消费。
			if args.get("revision") is int and args.revision >= 0 and args.revision < revision:
				return {"ok":true}
			if revision > 0 and args.get("revision") is int and args.revision == revision:
				confirmed[actor] = revision
				room.revision += 1
				return {"ok":true,"publish":true}
			return {"ok":false,"reason":"请求无效"}
		"blob_request":
			if args.get("key") is String and args.get("offset") is int:
				if not queue_blob.call(actor,args.key,args.offset):
					return {"ok":true,"blob_error":args.key}
			# 兼容旧行为：畸形字段没有可关联 key，不启动任务、不发布房间。
			return {"ok":true}
	return {"ok":false,"reason":"请求无效"}

## 管理请求独立分类，不能被前置普通内容 receive 分支吞掉。
func handles_management(kind:String) -> bool:
	return kind in ["server_data_catalog","server_data_prepare","server_data_commit","server_data_cancel"]

## dedicated、owner、大厅和管理连接存在门仍由调用者先检查。
## 能力仅同步委托且不保存；参数真实校验继续由现有 server_data_approval 执行。
## 返回值仅说明是否分派，不代表批准成功；拒绝回执与原文由调用者保留。
func receive_management(actor:int, kind:String, args:Dictionary, dispatch:Callable) -> bool:
	if not handles_management(kind) or not dispatch.is_valid():
		return false
	dispatch.call(actor,kind,args)
	return true
