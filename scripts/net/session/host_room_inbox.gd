extends RefCounted

## 请求作用域的房间管理闭包。Session 已先认证来源、映射稳定 actor、消费 seq 并检查在线。
## 不拥有 Room/Session/身份/选人状态；具体规则解析与配置安装只在当前调用中使用。
const Room = preload("res://scripts/net/session/room_state.gd")

func handles(kind:String) -> bool:
	return kind in ["ready","settings","transfer","kick"]

func receive(room:Room, actor:int, kind:String, args:Dictionary, content_ready:bool, adoption_pending:bool, selection_config:Dictionary, modes:Array, masters:Array, servants:Array, resolve_rules:Callable, install_selection:Callable) -> bool:
	match kind:
		"ready":
			if args.get("ready") is bool:
				if args.ready and not content_ready:
					room.error = "本局内容尚未确定，请等待房主检查并采用内容" if adoption_pending else "请先下载本局内容，完成后才能准备"
				else:
					return room.set_ready(actor,args.ready)
		"settings":
			if args.get("changes") is Dictionary:
				return set_settings(room,actor,args.changes,selection_config,modes,masters,servants,resolve_rules,install_selection)
		"transfer":
			if args.get("target") is int: return room.transfer_owner(actor,args.target)
		"kick":
			if args.get("target") is int: return room.kick(actor,args.target)
	return false

## 仅适配 choose_master 载荷；阶段、认证、seq、错误选择与发布仍由 Session 决定。
## choose 是当前请求的权威能力，不保存它，也不拥有选人状态。
func receive_choice(actor:int, args:Dictionary, choose:Callable) -> bool:
	if args.get("seat") is int and args.get("name") is String:
		return choose.call(actor,args.seat,args.name)
	return false

## 仅适配 start 的能力调用；原请求没有载荷字段，不新增形状或 actor 取值限制。
## 授权、阶段、数据与选人准备由 Session 提供；发布与失败回执留在调用方，不保存能力。
func receive_start(actor:int, is_owner:Callable, can_start:Callable, data_ready:Callable, prepare_selection:Callable, start:Callable) -> bool:
	if is_owner.call(actor) and can_start.call() and data_ready.call() and prepare_selection.call():
		return start.call(actor)
	return false

## 完整候选事务：复用 Room 验证，不复制房主/在线/字段规则；全部拒绝完成后再提交。
func set_settings(room:Room, actor:int, changes:Dictionary, selection_config:Dictionary, modes:Array, masters:Array, servants:Array, resolve_rules:Callable, install_selection:Callable) -> bool:
	if not changes.has("selection_mode") or changes.selection_mode == room.settings.selection_mode or selection_config.is_empty():
		return room.set_settings(actor,changes)
	var candidate = Room.new()
	candidate.owner = room.owner
	candidate.phase = room.phase
	candidate.settings = room.settings.duplicate(true)
	candidate.members = room.members.duplicate(true)
	candidate.revision = room.revision
	if not candidate.set_settings(actor,changes):
		room.error = candidate.error
		return false
	var configs:Array = modes.filter(func(config): return config is Dictionary and config.get("id") == changes.selection_mode)
	if configs.size() != 1:
		room.error = "选人模式未声明或声明重复"
		return false
	var rules = resolve_rules.call(configs[0])
	if rules == null: return false
	if not candidate.configure_rules({"capacity":rules.capacity(masters,servants,configs[0])}):
		room.error = candidate.error
		return false
	if not install_selection.call(configs[0],masters,servants): return false
	room.settings = candidate.settings
	room.members = candidate.members
	room.revision = candidate.revision
	return true
