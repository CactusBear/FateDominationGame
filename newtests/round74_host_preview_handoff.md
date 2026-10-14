# F09 preview_group：交 sa-1-04d0237a 串行接线

状态：模块和局部契约已真实验证；生产 Session 尚未接线，不宣称 F09 完成。

## 稳定 API

已有 `scripts/net/session/host_match_request_inbox.gd` 新增：

`receive_preview(args:Dictionary, preview:Callable) -> Dictionary`

- Session 先保留来源、认证、稳定 member、在线、协议 seq 及 `room.phase == "playing"` 门。
- `preview(sequence:int, cards:Array, hidden:Array) -> Dictionary` 是只捕获局部权威和可信 sender 的请求作用域同步闭包，不使用 `Callable.bind` 预绑定首参数。
- malformed：`{"ok":false,"reason":"组合预览请求无效"}`，不调用能力。
- valid：`{"ok":true,"request_id":args.request_id,"result":authority_result}`。外层 ok 表示形状有效；权威 `{ok:false}` 仍要沿原 signal/send 回传，不能变成 `_fail`。
- 不新增 kind/handles 框架；现 `receive()` / match_command 完全不改。
- 不新增暂停规则、长度/数组元素/非负整数限制，不复制私有规则，不保存任何能力或发送结果。

## 已亲读精确替换 anchor

`lobby_session.gd` 1008–1017，唯一以下整块，由 Session 唯一 writer 替换：

```gdscript
		"preview_group":
			if room.phase == "playing" and args.get("request_id") is int and args.get("view_seq") is int and args.get("cards") is Array and args.get("hidden") is Array:
				var result: Dictionary = match_authority.preview_group(sender, args.view_seq, args.cards, args.hidden)
				if sender == 1:
					group_preview_received.emit(args.request_id, result)
				else:
					_send(sender, {"kind": "group_preview", "request_id": args.request_id, "result": result}, 1)
			else:
				_fail(sender, "组合预览请求无效", _request_sequence(message))
			return
```

替换 payload（不改外围门；变量仅当前 match arm）:

```gdscript
		"preview_group":
			if room.phase != "playing":
				_fail(sender, "组合预览请求无效", _request_sequence(message))
				return
			var preview_authority = match_authority
			var preview:Callable = func(sequence:int, cards:Array, hidden:Array) -> Dictionary:
				return preview_authority.preview_group(sender,sequence,cards,hidden)
			var preview_result:Dictionary = _host_match_request_inbox.receive_preview(args,preview)
			if not preview_result.ok:
				_fail(sender, preview_result.reason, _request_sequence(message))
				return
			if sender == 1:
				group_preview_received.emit(preview_result.request_id, preview_result.result)
			else:
				_send(sender, {"kind": "group_preview", "request_id": preview_result.request_id, "result": preview_result.result}, 1)
			return
```

接线后 Session writer 必须实际验证本人 signal / 远端 send、phase 及前置授权门；模块 alone 不代表完成。

## 已执行

- `python -B newtests/round74_host_preview_runner.py red`：wrapper exit 0；真实 Godot exit 1、唯一预期缺 API failure，非解析错误。
- `python -B newtests/round74_host_preview_runner.py green E:/scratch/round71-host-match-500c3489d8db486990d4d798436459e8`：exit 0。
- preview contract：真实 Godot PID 15056、exit 0、32 checks、failures=[]。
- 原 round71 match_command contract：真实 Godot PID 3816、exit 0、27 checks、failures=[]。
- 报告：`E:/scratch/round71-host-match-500c3489d8db486990d4d798436459e8/evidence/preview-verification.json`。
- 同一 E 独占 freeze；父子环境 APPDATA/LOCALAPPDATA/TEMP/TMP/TMPDIR 都为 E；Job active_owned_processes=0。
- 未跑全量、测速、旧包 audit 或导出；不修改正式 DLL/preset/Session。
