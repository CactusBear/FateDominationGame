extends RefCounted

## 只校验主机身份请求的 kind 与 args 信封；不读取 Session、身份、房间或连接状态。
## 认证密钥、owner/member、在线席位、请求序号和继承事务仍由 Session/绑定协调器负责。

func validate(kind:String, args:Dictionary) -> Dictionary:
	match kind:
		"join":
			# 仅复用原两字段形状门；保留全部 args，凭据及成员验证仍在真实身份入口。
			if not args.get("name") is String or not args.get("spectator") is bool:
				return {"ok":false,"reason":"请求无效"}
			return {"ok":true}
		"identity_candidates":
			if not args.is_empty():
				return {"ok":false,"reason":"候选查询不接受身份参数"}
			return {"ok":true}
		"identity_inherit":
			if args.size() != 3 or not args.get("target_member") is int or not args.get("successor_member") is int or not args.get("revision") is int:
				return {"ok":false,"reason":"继承请求字段无效"}
			return {"ok":true}
		_:
			return {"ok":false,"reason":"身份请求类型无效"}
