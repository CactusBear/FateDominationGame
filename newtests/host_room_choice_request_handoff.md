# F09 choose_master 窄适配交接（生产调用方未接线）

## 产物与边界
- 唯一生产写：`scripts/net/session/host_room_inbox.gd`，新增独立 `receive_choice(actor:int,args:Dictionary,choose:Callable)->bool`。
- 显式能力签名：`choose(actor:int,seat:int,master_name:String)->bool`；可直接传当前请求的 `selection.choose`，不 bind 首参，不保存 Callable。
- 仅原样迁 `seat is int/name is String` 与权威调用；额外键、零/负 seat、空/空白 name 不加新限制，不归一化。
- `handles/receive/set_settings` 均未改；不把 choose_master 并入现泛型 room 路由。
- Session/Selection/Room/rules 生产文件未写。认证、稳定成员、在线、seq、阶段、publish 和失败 reason 均由 Session 保持。
- 旧权威拒绝只写 `selection.error`，旧 Session 仍按 `room.error if not room.error.is_empty() else "请求无效"`；接线禁止偷换成 selection.error。

## 已读入口与精确接线 payload
- UI：`scripts/net/ui/lobby_screen.gd:680-685` 的 `_choose_master()` 发 `session.request("choose_master", {"seat": choice.seat, "name": choice.name})`。
- 权威：`scripts/net/authority/selection_authority.gd:34-39` 验 controllers 所属、御主声明及规则 choose；ClassPool `available_masters/choose_master` 保持只读原实现。
- Session 锚点：`scripts/net/session/lobby_session.gd:1129-1133`，读回 SHA256 `dfa448a286ca698b3f88b70baac5567aaa3f7bd1f581f4c1c414ff328d598886`；精确锚点出现一次，与本任务首次冻结一致。
- owner 释放后由 main 独立接以下替换（这里只交接，未写 Session）：

旧锚点（tab 缩进）：
```gdscript
		"choose_master":
			if room.phase == "selecting" and args.get("seat") is int and args.get("name") is String:
				ok = selection.choose(sender, args.seat, args.name)
				if ok:
					_publish_selection()
```

替换 payload：
```gdscript
		"choose_master":
			if room.phase == "selecting":
				ok = _host_room_inbox.receive_choice(sender,args,selection.choose)
				if ok:
					_publish_selection()
```

保留收尾 `if not ok: _fail(sender,room.error if not room.error.is_empty() else "请求无效",_request_sequence(message)); return` 及成功 `_publish()`。不碰 start/begin_match/join/identity_ack。接线前重新读锚点与当前 owner 变更，不以整文件 SHA 漂移为由覆盖其他分支。

## 真实专项
命令（原引擎与原 DLL，独占 E 副本、180 秒 watchdog，无测速/全量）：
```text
python -B newtests/host_room_choice_request_runner.py initial
python -B newtests/host_room_choice_request_runner.py green-fixed E:/scratch/pw-8ba2bf92
python -B newtests/host_room_choice_request_runner.py mutation E:/scratch/pw-8ba2bf92
python -B newtests/host_room_choice_request_runner.py final E:/scratch/pw-8ba2bf92
```
- 初始真实 Godot exit 1：新 API 缺失（仅接口 RED，不作为行为 RED）。
- 初次 green exit 1：同栈 WeakRef 观察误判持有；只修测试，在辅助函数返回后观测；原失败日志保留。
- `green-fixed` exit 0，75 checks，failures=[]。
- 独占副本变异 `choose.call(actor,args.seat,args.name)` → `choose.call(actor,0,args.name)`：exit 1，75 checks，7 条行为拒绝，零引擎错误；证明值透传、真实座位及规则专项能抓错。副本随后恢复。
- 最终真实 Godot exit 0，75 checks，failures=[]，stderr 为空，未超时；owned 文件源码摘要等于冻结摘要；Job 活动进程为 0，日志句柄释放。
- `user://`：`E:/scratch/pw-8ba2bf92/appdata/FateDomination`。
- 证据：`E:/scratch/pw-8ba2bf92/evidence/final-verified.json`、`final.stdout.log`、`final.stderr.log`，其他轮次原件同目录。
- API/微型候选池专项运行真实 Selection.setup/choose 与 ClassPool 规则，验证合法、错类型、权威/已选御主拒绝、状态不变、再次合法选择及 Callable 不保留。`_caller_reason` 是对已读收尾表达式的对照，不冒称 Session wire 已测。

## 尚未验收
生产 Session 接线、真实认证/seq/阶段/发布/请求回执整链、窗口与真人包均未在本任务执行；F09 不宣完成。main 接线后单跑直接 Session 分支专项即可，不捆全选人架构。
