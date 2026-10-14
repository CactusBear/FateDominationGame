extends Node

var _model = SessionGeneration.ModelBacking.new({
	"total_rounds":BaseNumber.new(11),
	"current_round":0,
	"current_phase_index":-1,
	"current_phase_player_index":0,
	"current_player_id":-1,
	"is_game_over":false,
	"has_battle_resolved":false,
	"_battle_result_state":-1,
	"_phase_end_pending":false,
	"_phase_end_dispatched":false,
	"_phase_player_end_dispatched":false,
	"_phase_end_running":false,
	"last_battle_result":{},
	"_battle_broadcast_pending":false,
	"battle_broadcast_requires_confirm":false,
	"_battle_broadcast_batch_serial":0,
	"_battle_broadcast_consumer":null,
	"_battle_broadcast_confirmed":[],
	"_deploy_time_points_dispatched":{},
	"climax_keep_counts":{
	8: BaseNumber.new(4),
	9: BaseNumber.new(3),
	10: BaseNumber.new(2)
},
	"card_deal_rules":[
	{"special_key" : "ATTACKS", "area" : "deck", "shuffle" : true, "concealed" : false},
	{"special_key" : "SKILLS", "area" : "servant_skills", "shuffle" : false, "concealed" : false}
],
	"event_placements":[
	{"area_name" : "深山町", "concealed" : false},
	{"area_name" : "新都", "concealed" : true}
],
	"phases":[
	{
		"name" : "prepare",
		"start" : TimePoints.PREPARE_PHASE_START,
		"mid" : TimePoints.PREPARE_PHASE,
		"end" : TimePoints.PREPARE_PHASE_END
	},
	{
		"name" : "outpost",
		"start" : TimePoints.OUTPOST_PHASE_START,
		"mid" : TimePoints.OUTPOST_PHASE,
		"end" : TimePoints.OUTPOST_PHASE_END
	},
	{
		"name" : "action",
		"start" : TimePoints.ACTION_PHASE_START,
		"mid" : TimePoints.ACTION_PHASE,
		"end" : TimePoints.ACTION_PHASE_END
	},
	{
		"name" : "battle",
		"start" : TimePoints.BATTLE_PHASE_START,
		"mid" : TimePoints.BATTLE_PHASE,
		"end" : TimePoints.BATTLE_PHASE_END
	}
],
	"_round_start_state":{},
	"_round_end_running":false,
	"_session_serial":0
})


#游戏回合进程推进器：回合 -> 阶段 -> 各玩家在该阶段的自己的回合。
#只负责把时点交给TimePointChecker派发，效果的发现、询问、结算全部在EffectManager里。


#总回合数。规则数字不写死，特殊效果可以改动
var total_rounds:BaseNumber:
	get: return _model.read(&"total_rounds", null)
	set(value): _model.write(&"total_rounds", value)

var current_round:int:
	get: return _model.read(&"current_round", 0)
	set(value): _model.write(&"current_round", value)
#当前阶段下标，-1表示还没进入任何阶段
var current_phase_index:int:
	get: return _model.read(&"current_phase_index", 0)
	set(value): _model.write(&"current_phase_index", value)
#当前阶段里轮到第几个玩家(按顺位)
var current_phase_player_index:int:
	get: return _model.read(&"current_phase_player_index", 0)
	set(value): _model.write(&"current_phase_player_index", value)
#当前正在进行自己阶段的玩家
var current_player_id:int:
	get: return _model.read(&"current_player_id", 0)
	set(value): _model.write(&"current_player_id", value)
var is_game_over:bool:
	get: return _model.read(&"is_game_over", false)
	set(value): _model.write(&"is_game_over", value)
var has_battle_resolved:bool:
	get: return _model.read(&"has_battle_resolved", false)
	set(value): _model.write(&"has_battle_resolved", value)
#-1 是本回合尚未发起；PENDING/STOP 也表示已发起，不能再 exec 重发战果。
#整数控制字段可由既有规则对象图捕获，不增加全局 last_result 或新引用类。
var _battle_result_state:int:
	get: return _model.read(&"_battle_result_state", 0)
	set(value): _model.write(&"_battle_result_state", value)
#阶段收尾可跨玩家选择暂停；续行只走尚未完成的步骤，不重复玩家行动或结束时点。
var _phase_end_pending:bool:
	get: return _model.read(&"_phase_end_pending", false)
	set(value): _model.write(&"_phase_end_pending", value)
var _phase_end_dispatched:bool:
	get: return _model.read(&"_phase_end_dispatched", false)
	set(value): _model.write(&"_phase_end_dispatched", value)
#玩家级阶段结束时点与全局阶段结束时点分开记账，避免续行重复派发。
var _phase_player_end_dispatched:bool:
	get: return _model.read(&"_phase_player_end_dispatched", false)
	set(value): _model.write(&"_phase_player_end_dispatched", value)
#同步结算调用尚未返回时，禁止效果或其他调用方重入阶段收尾。
var _phase_end_running:bool:
	get: return _model.read(&"_phase_end_running", false)
	set(value): _model.write(&"_phase_end_running", value)
#本回合战斗阶段结算结果，供最终回合判定胜负时查询深山町战斗胜者
var last_battle_result:Dictionary:
	get: return _model.read(&"last_battle_result", {})
	set(value): _model.write(&"last_battle_result", value)
#战斗结算后、全部在局玩家确认播报前保持暂停：玩家逐个确认，全部确认后继续推进。
var _battle_broadcast_pending:bool:
	get: return _model.read(&"_battle_broadcast_pending", false)
	set(value): _model.write(&"_battle_broadcast_pending", value)
#等待是调用方的显式规则声明；无界面和 AI 推演缺省不等待。
var battle_broadcast_requires_confirm:bool:
	get: return _model.read(&"battle_broadcast_requires_confirm", false)
	set(value): _model.write(&"battle_broadcast_requires_confirm", value)
#输送批次身份不属于可回滚规则状态；进程内只增不减，reset 不重置。
var _battle_broadcast_batch_serial:int:
	get: return _model.read(&"_battle_broadcast_batch_serial", 0)
	set(value): _model.write(&"_battle_broadcast_batch_serial", value)
#展示登记只标识当前消费者，不决定规则等待或回滚资格。
var _battle_broadcast_consumer:Object:
	get: return _model.read(&"_battle_broadcast_consumer", null)
	set(value): _model.write(&"_battle_broadcast_consumer", value)
#本次播报已确认的玩家（无重复）。全部在局玩家确认后才清位并继续推进。
var _battle_broadcast_confirmed:Array:
	get: return _model.read(&"_battle_broadcast_confirmed", [])
	set(value): _model.write(&"_battle_broadcast_confirmed", value)
#部署事实的玩家级时点每回合每名玩家只派一次；普通部署后还会经过行动阶段，
#不能用"本回合有过deploy日志"在后续阶段重复派发。
var _deploy_time_points_dispatched:Dictionary:
	get: return _model.read(&"_deploy_time_points_dispatched", {})
	set(value): _model.write(&"_deploy_time_points_dispatched", value)
var climax_keep_counts:Dictionary:
	get: return _model.read(&"climax_keep_counts", {})
	set(value): _model.write(&"climax_keep_counts", value)
#开局时从从者的_specials发放到玩家区域的内容。
#取不到键就当没有，以后从者多出别的卡在这里加一行即可，不写死
var card_deal_rules:Array:
	get: return _model.read(&"card_deal_rules", [])
	set(value): _model.write(&"card_deal_rules", value)
#每回合开始时事件牌的放置计划：抽几张、放哪个战场、明置还是暗置。
#规则数字不写死，默认是深山町一张明置、新都一张暗置，效果可以改动它
var event_placements:Array:
	get: return _model.read(&"event_placements", [])
	set(value): _model.write(&"event_placements", value)

#四个阶段：准备、前哨、行动、战斗
var phases:Array:
	get: return _model.read(&"phases", [])
	set(value): _model.write(&"phases", value)


#按order排序的玩家顺位，顺位可被ChangePlOrder改动
func get_ordered_player_ids() -> Array:
	return GameDataManager.get_domain_ordered_player_ids()


func get_current_phase() -> Dictionary:
	if current_phase_index < 0 or current_phase_index >= phases.size():
		return {}
	return phases[current_phase_index]


#某名玩家此刻"视为处于"哪些阶段。缺省就是当前阶段本身；
#玩家数据 phase_as 声明了当前阶段的映射时整组替换（可多个、也可为空表示本阶段什么都不做）。
#例：天堂之孔 {"prepare":["prepare","outpost","action"], "outpost":[], "action":[]}；
#    无极 {"battle":["battle","action"]}。映射内容全部由数据写入，这里不认识任何卡
func effective_phase_names(player_id:int) -> Array:
	var current:String = str(get_current_phase().get("name", ""))
	if current == "":
		return []
	if !GameData.player_data_library.has(player_id):
		return [current]
	var mapping = GameData.player_data_library[player_id].get("phase_as", {})
	if mapping is Dictionary and (mapping as Dictionary).has(current) and mapping[current] is Array:
		return (mapping[current] as Array).duplicate()
	return [current]


#这名玩家此刻是否视为处于某阶段（常规出牌、部署、阶段能力窗口都按它判定）
func is_phase_for(player_id:int, phase_name:String) -> bool:
	return effective_phase_names(player_id).has(phase_name)


#这名玩家此刻视为处于的各阶段的持续时点（phases 表里的 mid），供阶段窗口派发与手动能力查询共用
func effective_phase_mids(player_id:int) -> Array:
	var mids:Array = []
	var names:Array = effective_phase_names(player_id)
	for phase_data in phases:
		if names.has(str(phase_data.get("name", ""))) and !mids.has(phase_data["mid"]):
			mids.append(phase_data["mid"])
	return mids


#独立启动先换代；编排启动只接受已签发的原 context，不给旧来源补票。
func start_game(startup_context:Variant = null) -> Dictionary:
	if SessionGeneration.in_private_frame(): return _progress_failure(&"unsupported_domain_startup_services")
	var prepared:Dictionary = reset_progress(battle_broadcast_requires_confirm, startup_context)
	if not prepared.ok:
		return prepared
	var context:SessionContext = prepared.context
	#新的一局：历史日志清空
	GameLog.reset()
	if not _progress_context_valid(context):
		return _progress_failure(&"stale_session")
	EffectManager.sync_loaded_effect_pool()
	if not _progress_context_valid(context):
		return _progress_failure(&"stale_session")
	var events:Dictionary = MapData.reset_event_deck(context)
	if not events.ok: return events
	if not _progress_context_valid(context):
		return _progress_failure(&"stale_session")
	var situations:Dictionary = MapData.reset_situation_deck(context)
	if not situations.ok: return situations
	if not _progress_context_valid(context):
		return _progress_failure(&"stale_session")
	var dealt:Dictionary = deal_player_cards(-1, context)
	if not dealt.ok: return dealt
	if not _progress_context_valid(context):
		return _progress_failure(&"stale_session")
	TimePointChecker.set_phase_time_points([TimePoints.GAME], context)
	if not _progress_context_valid(context):
		return _progress_failure(&"stale_session")
	if not EffectManager.defer_until_runtime_guard_complete(Callable(self, "_dispatch_game_start").bind(context), context):
		_dispatch_game_start(context)
	if not _progress_context_valid(context):
		return _progress_failure(&"stale_session")
	if not _round_start_state.get("ok", true): return _round_start_state
	return {"ok":true, "context":context, "reason":&"current"}


func _dispatch_game_start(context:SessionContext) -> void:
	var idle:Dictionary = await wait_progress_state({"ok":true, "completed":true, "context":context}, context)
	if not idle.ok: return
	if not _progress_context_valid(context):
		return
	TimePointChecker.global_time_point([TimePoints.GAME_START], null, context)
	var dispatched:Dictionary = await wait_progress_state({"ok":true, "completed":true, "context":context}, context)
	if not dispatched.ok: return
	if not _progress_context_valid(context):
		return
	if not EffectManager.defer_until_runtime_guard_complete(Callable(self, "start_round").bind(context), context):
		start_round(context)


#公共重置用途显式声明：默认开启新域；结束编排必须用 invalidate，不可又开域。
#外层传 context 时只清进度；它不是新局/当前票自动修复入口。
func reset_progress(requires_confirm:bool = false, startup_context:Variant = null, lifecycle:StringName = &"begin") -> Dictionary:
	if SessionGeneration.in_private_frame():
		var private_source:Dictionary = SessionGeneration.private_lifecycle()
		if private_source.status != "COMPLETED": return _progress_failure(&"missing_private_lifecycle")
		if domain_model_status().status != "COMPLETED": return _progress_failure(&"unbound_model_backing")
		var service = private_source.service
		var authenticated:Dictionary = service.begin_reset(lifecycle, startup_context)
		if not authenticated.ok: return _progress_failure(authenticated.reason)
		# 原清值算法一次；不是模拟 ok，不改 L，也不派外部回调。
		var cleared:bool = _clear_progress_values(requires_confirm, authenticated.context)
		service.finish_reset(cleared)
		if not cleared: return _progress_failure(&"stale_session")
		return {"ok":true, "context":authenticated.context, "reason":&"private_reset_completed"}
	var context:SessionContext = null
	if lifecycle == &"invalidate":
		if startup_context != null:
			return _progress_failure(&"unbound_origin")
		preload("res://scripts/system/session_generation.gd").invalidate_generation(&"game_progress.reset_progress")
	elif lifecycle == &"begin":
		if startup_context == null:
			var begun:Dictionary = preload("res://scripts/system/session_generation.gd").begin_generation(&"game_progress.reset_progress")
			if not begun.ok:
				return _progress_failure(begun.reason)
			var derived:Dictionary = preload("res://scripts/system/session_generation.gd").derive_context(begun.token, &"game_progress.startup")
			if not derived.ok:
				return derived
			context = derived.context
		else:
			if not startup_context is SessionContext:
				return _progress_failure(&"unbound_origin")
			var valid:Dictionary = preload("res://scripts/system/session_generation.gd").validate_context(startup_context)
			if not valid.ok:
				return _progress_failure(valid.reason)
			context = startup_context
	else:
		return _progress_failure(&"unbound_origin")
	if not _clear_progress_values(requires_confirm, context):
		return _progress_failure(&"stale_session")
	return {"ok":true, "context":context, "reason":&"invalidated" if lifecycle == &"invalidate" else &"current"}


func _progress_failure(reason:StringName) -> Dictionary:
	return {"ok":false, "context":null, "reason":reason}


# 生命周期编排操作用既有可信效果工厂与公开执行器建立正规根/函数帧。
# 回执保活原 root；不向目标卡 bind，不借 router 的 context 假装创建帧。
func start_progress_operation(key:String, parameters:Array, context:SessionContext) -> Dictionary:
	if SessionGeneration.in_private_frame(): return {"ok":false, "completed":true, "context":context, "reason":&"unsupported_domain_effect_service"}
	var source:Dictionary = SessionGeneration.validate_context(context)
	if not source.ok: return {"ok":false, "context":context, "reason":source.reason, "completed":true}
	var roots:Array = LoadHelper.load_effects([{"effect_name":"progress:" + key, "time_points":[], "priority":0,
		"is_pure_passive":true, "is_residue":false, "effect_numbers":[],
		"funcs":[{"func_name":key, "parameters":parameters, "var_index":0}]}], null, context)
	if roots.size() != 1: return {"ok":false, "context":context, "reason":&"unbound_origin", "completed":true}
	var root:BaseEffect = roots[0]
	var members:Array = EffectManager.get_all_players_id()
	if members.is_empty(): return {"ok":false, "context":context, "reason":&"unknown_player", "completed":true}
	# 锚点只承载现有 EM 等待身份；业务目标始终在 parameters 内，绝不改变规则对象归属。
	root._remove_after_trigger = true
	if not EffectManager.register_effect(root, int(members[0])): return {"ok":false, "context":context, "reason":&"operation_rejected", "completed":true}
	EffectManager.activate_effect(root)
	return {"ok":true, "context":context, "root":root, "completed":false}

func wait_progress_operation(operation:Dictionary, value_required:bool = true) -> Dictionary:
	if not operation.get("ok", false): return operation
	var context:SessionContext = operation.context
	while _progress_context_valid(context) and (EffectManager.is_running or EffectManager.is_waiting_for_choice() or get_tree().paused):
		await get_tree().process_frame
	if not _progress_context_valid(context): return {"ok":false, "context":context, "reason":&"stale_session", "completed":true}
	var root:BaseEffect = operation.root
	if not root.runtime_source_status().ok or root._self_vars.is_empty():
		return {"ok":false, "context":context, "reason":&"operation_rejected", "completed":true}
	var value = root._self_vars[0]
	if value == null and value_required: return {"ok":false, "context":context, "reason":&"operation_rejected", "completed":true}
	if value is Dictionary and not value.get("ok", true): return value
	return {"ok":true, "context":context, "value":value, "completed":true}

# 普通 choice 与 guard 共用此本地保活协程；每帧只复验，不重新派操作。
func wait_progress_state(state:Dictionary, context:SessionContext) -> Dictionary:
	if not is_same(state.get("context"), context): return {"ok":false, "context":context, "reason":&"unbound_origin", "completed":true}
	while _progress_context_valid(context) and state.get("ok", false) and (not state.get("completed", false) or EffectManager.is_running or EffectManager.is_waiting_for_choice() or get_tree().paused):
		await get_tree().process_frame
	if not _progress_context_valid(context): return {"ok":false, "context":context, "reason":&"stale_session", "completed":true}
	return state

func _progress_context_valid(context:Variant) -> bool:
	return preload("res://scripts/system/session_generation.gd").validate_context(context).ok


#null 只用于可信的新公共推进调用；保存/延迟的 Callable 必须传捕获值。
func _capture_progress_context(context:Variant = null) -> SessionContext:
	# S1 的 EM/TPC/resolver 域闭包未交接；不在 D 消费处 derive/bind。
	if SessionGeneration.in_private_frame(): return null
	if context != null:
		return context if context is SessionContext and _progress_context_valid(context) else null
	var current:Dictionary = preload("res://scripts/system/session_generation.gd").current_token()
	if not current.ok:
		return null
	var derived:Dictionary = preload("res://scripts/system/session_generation.gd").derive_context(current.token, &"game_progress.advance")
	return derived.context if derived.ok else null


#清值不签票；关闭域清理也必须在重入后确认仍关闭。
func _clear_progress_values(requires_confirm:bool, context:SessionContext) -> bool:
	if context != null and not _progress_context_valid(context):
		return false
	if context == null and preload("res://scripts/system/session_generation.gd").current_token().ok:
		return false
	_session_serial += 1
	is_game_over = false
	current_round = 0
	current_phase_index = -1
	current_phase_player_index = 0
	current_player_id = -1
	has_battle_resolved = false
	_battle_result_state = -1
	_phase_end_pending = false
	_phase_end_dispatched = false
	_phase_player_end_dispatched = false
	_phase_end_running = false
	_round_end_running = false
	_round_start_state = {}
	_battle_broadcast_pending = false
	_battle_broadcast_confirmed = []
	_deploy_time_points_dispatched.clear()
	battle_broadcast_requires_confirm = requires_confirm
	_battle_broadcast_consumer = null
	last_battle_result.clear()
	return _progress_context_valid(context) if context != null else not preload("res://scripts/system/session_generation.gd").current_token().ok


#把每名玩家从者的_specials按card_deal_rules发放到对应区域。
#发出去的是克隆体、模板留在从者身上：否则牌堆里的牌会改到同一组数字和效果，
#重开一局也会带着上一局的状态。
#player_id 传具体玩家时只发给他一个人——换从者这类效果只需重发当事玩家的牌，
#不能顺手把其他玩家已有的牌堆也重置掉
func deal_player_cards(player_id: int = -1, source_context:Variant = null) -> Dictionary:
	if SessionGeneration.in_private_frame(): return {"ok":false, "context":null, "reason":&"unsupported_domain_runtime_factory"}
	var context:SessionContext = source_context as SessionContext
	if not _progress_context_valid(context):
		return {"ok":false, "context":context, "reason":&"unbound_origin"}
	var ids: Array = [player_id] if player_id != -1 else GameDataManager.get_active_player_ids()
	for id in ids:
		if not _progress_context_valid(context): return {"ok":false, "context":context, "reason":&"stale_session"}
		var player_data:Dictionary = GameDataManager.find_player_data(id)
		if player_data.is_empty(): return {"ok":false, "context":context, "reason":&"unknown_player"}
		var servant = player_data.get("servant")
		if servant == null or not "_specials" in servant: continue
		var prepared:Dictionary = {}
		for rule in card_deal_rules:
			if rule.get("shuffle", false) and not ShuffleArray.can_shuffle():
				return {"ok":false, "context":context, "reason":&"unknown_random_stream"}
			prepared[rule.area] = servant._specials.get(rule.special_key, [])
		# 角色已由 S0 工厂生产；这里只继承 runtime，绝不重配模板/补票。
		var copied:Dictionary = CloneContext.new().copy_result(prepared, context)
		if not copied.ok: return copied
		# 全部洗牌先验成功后再发布区域，未知流拒绝不留下先发布的非洗牌区。
		for rule in card_deal_rules:
			var cards:Array = copied.object[rule.area]
			if rule.get("shuffle", false) and ShuffleArray.new().exec(cards) == null:
				return {"ok":false, "context":context, "reason":&"unknown_random_stream"}
		for rule in card_deal_rules:
			var cards:Array = copied.object[rule.area]
			for card in cards:
				if not _progress_context_valid(context): return {"ok":false, "context":context, "reason":&"stale_session"}
				if rule.get("concealed", false): card.set_concealed(true)
			player_data[rule.area] = cards
			for card in cards:
				if not RegisterObjectEffects.can_register_object(card, id, context): return {"ok":false, "context":context, "reason":&"operation_rejected"}
				preload("res://scripts/system/operation_router.gd").exec_registered("register_object_effects", [card, id, context], context)
				if not _progress_context_valid(context): return {"ok":false, "context":context, "reason":&"stale_session"}
	return {"ok":true, "context":context, "reason":&"current"}

# 通用 runtime 复制入口：必须显式原来源；拒绝与空数组分开。
func clone_cards(cards:Array, context:SessionContext = null) -> Dictionary:
	if SessionGeneration.in_private_frame(): return {"ok":false, "context":null, "reason":&"unsupported_domain_runtime_factory"}
	var source:Dictionary = SessionGeneration.validate_context(context)
	if not source.ok: return {"ok":false, "object":null, "context":context, "reason":source.reason}
	return CloneContext.new().copy_result(cards, context)


#结束本局。winners 由调用方（VictoryResolver 的结果）传入：
#谁获胜是胜负规则的事，这里只负责把结局作为事实记下来并告知玩家。
#空数组是规则里真实存在的结局（圣杯溢出，全员判负），不能当作"还没算出来"
func end_game(winners:Array = []):
	if SessionGeneration.in_private_frame(): return
	is_game_over = true
	#胜者标记唯一写入点：自然终局(VictoryResolver)与立即胜利(EndGame)共用。
	for id in GameData.player_data_library.keys():
		(GameData.player_data_library[id] as Dictionary)["is_victory"] = winners.has(int(id))
	var names:Array = []
	for id in winners:
		names.append(EffectManager.player_shown_name(int(id)))
	GameLog.record("game_end", -1, -1, "", null, ["game_end"],
		{"winners": winners.duplicate(), "round": current_round})
	if winners.is_empty():
		#规则：并列且决胜仍无法分出唯一胜者时，圣杯溢出，所有人都输
		EffectManager.push_message("圣杯溢出，全员判负")
	else:
		EffectManager.push_message("游戏结束，胜者：" + "、".join(names))
	TimePointChecker.set_phase_time_points([])
	TimePointChecker.global_time_point([TimePoints.GAME_END])


#回合
func start_round(source_context:Variant = null):
	var context:SessionContext = _capture_progress_context(source_context)
	if context == null:
		return
	if _phase_end_running or _battle_result_blocks_tail():
		return
	if is_game_over:
		return
	current_round += 1
	if current_round > total_rounds.number:
		#兜底路径（正常在 end_round 就结束了）：结束前同样要判定胜负，
		#否则这条路径会以"没有胜者"收场，看起来像游戏无法正常结束
		_round_end_running = false
		end_game(VictoryResolver.new().exec(last_battle_result))
		return
	#回合号立即生效：这一回合记的每条日志都归到新回合下，不能等到 begin_phase 才更新，
	#否则开局抽局势牌/事件牌、DAY_START 这些日志会记到上一回合
	#回合边界不属于任何阶段，不能沿用上一回合最后一个阶段的名字；
	#阶段名由随后第一次 begin_phase 写进来
	GameLog.set_context(current_round, "")
	current_phase_index = -1
	current_phase_player_index = 0
	current_player_id = -1
	has_battle_resolved = false
	_battle_result_state = -1
	#新回合开始：日志裁掉超过保留上限的旧条目
	GameLog.begin_round()
	refresh_first_player(context)
	#每回合开始时重置本回合类记录字段，并派发ROUND_START_RESET供效果监听
	EffectManager.reset_round_option_counts()
	if not _progress_context_valid(context):
		return
	_round_start_state = {"ok":true, "completed":false, "context":context, "phase": "reset", "players": GameDataManager.get_active_player_ids(), "index": 0}
	_resume_round_start(_round_start_state, context)

#回合号和日志边界已建立，尾部只保存原流程的阶段与玩家游标。
func _resume_round_start(state:Dictionary, context:SessionContext) -> void:
	if not is_same(state.get("context"), context) or not _progress_context_valid(state.get("context")):
		state.merge({"ok":false, "completed":true, "reason":&"stale_session"}, true)
		return
	while not is_game_over and _progress_context_valid(context):
		match state.phase:
			"reset":
				if state.index >= state.players.size():
					state.phase = "window"
					continue
				var id:int = state.players[state.index]
				state.index += 1
				#玩家字段统一走 set_player_data 原语（带原来源），不在流程层直接改字典。
				SetPlayerData.new().exec("temp_locations", [], id, context)
				TimePointChecker.dynamic_time_point([TimePoints.ROUND_START_RESET], id, null, context)
			"window":
				state.phase = "refill_setup"
				TimePointChecker.set_phase_time_points([TimePoints.DAY], context)
			"refill_setup":
				#重置效果可能改变顺位，所以仍在补牌前读取当前顺位。
				state.players = get_ordered_player_ids()
				state.index = 0
				state.phase = "refill"
			"refill":
				if state.index >= state.players.size():
					state.phase = "situation"
					continue
				var id:int = state.players[state.index]
				state.index += 1
				#上限仍读数据，牌堆处理仍由原补牌 operation 负责。
				var operation:Dictionary = start_progress_operation("refill_hand", [id, GameData.player_hand_limit(id)], context)
				var refill:Dictionary = await wait_progress_operation(operation)
				if not refill.ok:
					state.merge(refill, true)
					return
			"situation":
				state.phase = "day_start"
				var activation:Dictionary = SituationResolver.new().activate(context)
				var activated:Dictionary = await wait_progress_state(activation, context)
				if not activated.ok:
					state.merge(activated, true)
					return
			"day_start":
				state.phase = "events"
				TimePointChecker.global_time_point([TimePoints.DAY_START], null, context)
			"events":
				state.phase = "advance"
				var placing:Dictionary = EventResolver.new().place(event_placements, context)
				var placed:Dictionary = await wait_progress_state(placing, context)
				if not placed.ok:
					state.merge(placed, true)
					return
			"advance":
				state.completed = true
				advance_phase(context)
				return
		if not _progress_context_valid(context):
			return
		while _progress_context_valid(context) and (EffectManager.is_running or EffectManager.is_waiting_for_choice() or get_tree().paused):
			await get_tree().process_frame


var _round_start_state:Dictionary:
	get: return _model.read(&"_round_start_state", {})
	set(value): _model.write(&"_round_start_state", value)
var _round_end_running:bool:
	get: return _model.read(&"_round_end_running", false)
	set(value): _model.write(&"_round_end_running", value)
#局部协程取消序号，独立于共享会话资格；不是来源凭证。
var _session_serial:int:
	get: return _model.read(&"_session_serial", 0)
	set(value): _model.write(&"_session_serial", value)


#等待回合结束期间的玩家抉择。返回 false 表示等待期间对局已被结束，调用方应立即退出
func _wait_round_choices(context:SessionContext, serial:int) -> bool:
	if not _progress_context_valid(context) or serial != _session_serial:
		return false
	# process_frame 信号在场景树暂停时仍会发出，暂停期间不能自动续行回合收尾。
	while EffectManager.is_waiting_for_choice() or get_tree().paused:
		await get_tree().process_frame
		if serial != _session_serial or not _progress_context_valid(context):
			return false
	return true


func end_round(source_context:Variant = null):
	var context:SessionContext = _capture_progress_context(source_context)
	if context == null:
		return
	var serial:int = _session_serial
	if _phase_end_running or _battle_result_blocks_tail():
		return
	if _round_end_running:
		return
	_round_end_running = true
	current_phase_index = -1
	current_phase_player_index = 0
	current_player_id = -1
	TimePointChecker.set_phase_time_points([TimePoints.DAY], context)
	if not _progress_context_valid(context):
		return
	TimePointChecker.global_time_point([TimePoints.DAY_END], null, context)
	if not await _wait_round_choices(context, serial):
		return
	if climax_keep_counts.has(current_round):
		TimePointChecker.global_time_point([TimePoints.CLIMAX_START], null, context)
		if not await _wait_round_choices(context, serial):
			return
		ClimaxResolver.new().exec(climax_keep_counts[current_round], context)
		if not await _wait_round_choices(context, serial):
			return
		TimePointChecker.global_time_point([TimePoints.CLIMAX_END], null, context)
		if not await _wait_round_choices(context, serial):
			return
	if current_round == total_rounds.number or GameDataManager.get_active_player_ids().size() <= 1:
		#胜者由 VictoryResolver 判定（战果最高 → 并列看深山町胜者 → 仍并列则圣杯溢出），
		#结果传给 end_game 记进日志并提示玩家；这里不重复判定规则
		_round_end_running = false
		end_game(VictoryResolver.new().exec(last_battle_result))
		return
	for id in GameDataManager.get_active_player_ids():
		if not _progress_context_valid(context):
			return
		var player_data:Dictionary = GameDataManager.find_player_data(id)
		if player_data.is_empty(): return
		var original_location = player_data.get("location")
		SetPlayerData.new().exec("last_turn_location", original_location, id, context)
		SetPlayerData.new().exec("is_battle", false, id, context)
		#规则：回合结束时将每名御主的立牌移除版图（下回合前哨阶段重新部署）。
		#必须在记完 last_turn_location 之后调用，否则查不到本回合结束时的位置
		#路由 context 不进入业务参数；false 也可能是原本无位置的合法 no-op。
		var removed:Variant = preload("res://scripts/system/operation_router.gd").exec_registered("remove_from_board", [id, context], context)
		#同步 LEAVE_LOCATION 可能换局/换同 ID 成员，旧尾部不能接到新对象上。
		if not _progress_context_valid(context) or serial != _session_serial or not is_same(player_data, GameDataManager.find_player_data(id)):
			return
		if original_location != null and (typeof(removed) != TYPE_BOOL or not removed):
			return
		#残留牌留在场上，回合结束不处理（残留牌只在自身效果满足条件时自行关闭）
		preload("res://scripts/system/operation_router.gd").exec_registered("discard_played_cards", [id], context)
		if not _progress_context_valid(context):
			return
		#先清理再重建合计威力基线：规则上残留牌跨回合留场并继续提供威力，
		#所以基线是留场明置牌的威力之和，同时丢弃回合内的非卡牌来源加成
		preload("res://scripts/system/operation_router.gd").exec_registered("sync_power", [id], context)
		if not _progress_context_valid(context):
			return
		#规则：合计威力加成只在本回合有效，回合一结束就归零
		(player_data["total_power_bonus"] as BaseNumber).set_num(BaseNumber.new(0))
	#规则：【败北】状态持续至回合结束
	if not _progress_context_valid(context):
		return
	if not DefeatBuff.clear_all(context): return
	if not _progress_context_valid(context):
		return
	#规则：回合结束时弃置所有激活的局势牌和事件牌
	var cleared_situation:Dictionary = SituationResolver.new().clear_all(context)
	if not cleared_situation.ok: return
	if not _progress_context_valid(context):
		return
	var cleared_events:Dictionary = EventResolver.new().clear_all(context)
	if not cleared_events.ok: return
	if not _progress_context_valid(context):
		return
	#地利修正类效果（远隔操作地利翻倍、占领高地、卫宫地利变3倍）只在本回合有效：
	#把各席位的地利按印刷基线还原，否则同一席位的地利会跨回合越乘越大，
	#而且改的是共享地图数据，会连带影响之后占据该席位的其他玩家
	preload("res://scripts/system/operation_router.gd").exec_registered("restore_location_benefits", [], context)
	if not _progress_context_valid(context):
		return
	#规则：每个回合结束时，将回合顺位顺时针后移一位（原第二位成为新回合首位）
	preload("res://scripts/system/operation_router.gd").exec_registered("change_pl_order", [null, BaseNumber.new(-1)], context)
	if not _progress_context_valid(context):
		return
	_round_end_running = false
	start_round(context)


#顺位第一的玩家即先手，供只看is_first的效果使用
func refresh_first_player(context:Variant = null):
	var ids = get_ordered_player_ids()
	for i in ids.size():
		SetPlayerData.new().exec("is_first", i == 0, ids[i], context)


#阶段
func advance_phase(source_context:Variant = null):
	var context:SessionContext = _capture_progress_context(source_context)
	if context == null:
		return
	if is_game_over or _phase_end_running or _battle_broadcast_pending:
		return
	if _phase_end_pending:
		end_phase(context)
		return
	current_phase_index += 1
	current_phase_player_index = 0
	current_player_id = -1
	if current_phase_index >= phases.size():
		end_round(context)
		return
	begin_phase(context)


#规则：高潮局势牌生效的回合（第9/10/11回合）称为高潮回合。
#"高潮"是回合属性而不是独立阶段——这些回合里玩家的各阶段同时处于高潮状态，
#所以效果写 self_climax 表达的是"高潮回合里我的阶段"。
#回合号不写死，直接问局势牌池里登记了哪些高潮回合（与SituationResolver同源）
func is_climax_round() -> bool:
	return LoadSituation.climax_situations.has(current_round)


func begin_phase(source_context:Variant = null):
	var context:SessionContext = _capture_progress_context(source_context)
	if context == null:
		return
	var phase = get_current_phase()
	if phase.is_empty():
		return
	_phase_end_pending = false
	_phase_end_dispatched = false
	_phase_player_end_dispatched = false
	#整个阶段内都成立的时点。高潮回合额外挂CLIMAX、非高潮回合挂NON_CLIMAX，
	#成对派发让效果两边都能表达（"仅高潮"与"仅非高潮"）
	#日志上下文：当前回合与阶段名，之后记的每一条事实都带上它
	GameLog.set_context(current_round, str(phase.get("name", "")))
	var phase_tps:Array = [TimePoints.DAY, TimePoints.PHASE, phase["mid"]]
	phase_tps.append(TimePoints.CLIMAX if is_climax_round() else TimePoints.NON_CLIMAX)
	TimePointChecker.set_phase_time_points(phase_tps, context)
	if not _progress_context_valid(context):
		return
	if not EffectManager.defer_until_runtime_guard_complete(Callable(self, "_begin_phase_events").bind(phase, context), context):
		_begin_phase_events(phase, context)

#阶段固定窗口完成后才翻计划事件；翻牌完成后才派发阶段开始。
func _begin_phase_events(phase:Dictionary, context:SessionContext) -> void:
	var idle:Dictionary = await wait_progress_state({"ok":true, "completed":true, "context":context}, context)
	if not idle.ok: return
	if not _progress_context_valid(context):
		return
	#规则：行动阶段开始时展示暗置放置的事件牌（基础规则写明是"位于新都"的那张）。
	#翻在派发阶段时点之前：阶段能力跑的时候应该已经看得到这张明置牌
	if str(phase.get("name", "")) == "action":
		var reveal:Dictionary = EventResolver.new().start_reveal(event_placements, context)
		var revealed:Dictionary = await wait_progress_state(reveal, context)
		if not revealed.ok: return
	if not _progress_context_valid(context):
		return
	if not EffectManager.defer_until_runtime_guard_complete(Callable(self, "_dispatch_phase_start").bind(phase, context), context):
		_dispatch_phase_start(phase, context)

func _dispatch_phase_start(phase:Dictionary, context:SessionContext) -> void:
	var idle:Dictionary = await wait_progress_state({"ok":true, "completed":true, "context":context}, context)
	if not idle.ok: return
	if not _progress_context_valid(context):
		return
	TimePointChecker.global_time_point([TimePoints.PHASE_START, phase["start"]], null, context)
	var dispatched:Dictionary = await wait_progress_state({"ok":true, "completed":true, "context":context}, context)
	if not dispatched.ok: return
	if not _progress_context_valid(context):
		return
	if not EffectManager.defer_until_runtime_guard_complete(Callable(self, "next_player_in_phase").bind(context), context):
		next_player_in_phase(context)


#等待接口已涵盖发动、选牌、选位置及选玩家；执行中的管线也不能被阶段推进打断。
func _effects_block_progress() -> bool:
	return EffectManager.is_running or EffectManager.is_waiting_for_choice()


#只读控制状态；不由战报内容、广播消费者存在与否或 bool(对象) 推断。
func battle_resolution_state() -> int:
	return _battle_result_state


func _battle_result_refuses_tail() -> bool:
	return _battle_result_state == BattleResolver.ResultState.REJECTED_NO_EFFECT \
		or _battle_result_state == BattleResolver.ResultState.COMMITTED_STOP


#未发起不拦合法非战斗终局；已发起但未封存不能走回合/终局旁路。
func _battle_result_blocks_tail() -> bool:
	return _battle_result_state != -1 and _battle_result_state != BattleResolver.ResultState.SEALED


#展示消费者登记不启用确认屏障；调用方必须另行声明 requires_confirm。
func register_battle_broadcast_consumer(consumer: Object) -> void:
	_battle_broadcast_consumer = consumer


func unregister_battle_broadcast_consumer(consumer: Object) -> void:
	if _battle_broadcast_consumer == consumer:
		_battle_broadcast_consumer = null


#仅供展示层查询消费者是否存活；规则不能根据此结果决定等待。
func has_battle_broadcast_consumer() -> bool:
	return _battle_broadcast_consumer != null and is_instance_valid(_battle_broadcast_consumer)


func is_battle_broadcast_pending() -> bool:
	return _battle_broadcast_pending


#不等待时没有可确认批次；恢复等待状态后必须换发身份以拒绝旧确认。
func battle_broadcast_batch_id() -> int:
	return _battle_broadcast_batch_serial if _battle_broadcast_pending else 0


func renew_battle_broadcast_batch() -> void:
	if _battle_broadcast_pending:
		_battle_broadcast_batch_serial += 1


func battle_broadcast_confirmed() -> Array:
	return _battle_broadcast_confirmed.duplicate()


func can_confirm_battle_broadcast(player_id:int, batch_id:int) -> bool:
	return _battle_broadcast_pending and batch_id > 0 and batch_id == battle_broadcast_batch_id() \
		and battle_broadcast_confirmers().has(player_id) and not is_battle_broadcast_confirmed(player_id)


#新输送调用方必须提供明确批次；旧本地/录制单参数入口保持兼容。
func confirm_battle_broadcast_batch(player_id:int, batch_id:int) -> bool:
	if not can_confirm_battle_broadcast(player_id, batch_id):
		return false
	confirm_battle_broadcast(player_id)
	return true


#播报需要哪些玩家确认：本局仍在场的玩家。人数不写死，读活跃玩家列表。
func battle_broadcast_confirmers() -> Array:
	return GameDataManager.get_active_player_ids()


func battle_broadcast_confirmed_count() -> int:
	return _battle_broadcast_confirmed.size()


#某名玩家是否已确认本次播报。
func is_battle_broadcast_confirmed(player_id:int) -> bool:
	return _battle_broadcast_confirmed.has(int(player_id))


#某名玩家确认本次播报；全部在局玩家都确认后才清位并继续推进。
#不在场玩家（已被淘汰）无需确认，也不能推进确认进度。
func confirm_battle_broadcast(player_id:int) -> void:
	if not _battle_broadcast_pending:
		return
	var pid:int = int(player_id)
	var confirmers:Array = battle_broadcast_confirmers()
	if not confirmers.has(pid):
		return
	if not _battle_broadcast_confirmed.has(pid):
		_battle_broadcast_confirmed.append(pid)
	for id in confirmers:
		if not _battle_broadcast_confirmed.has(int(id)):
			return
	_battle_broadcast_pending = false
	_battle_broadcast_confirmed.clear()
	advance_phase()


func _dispatch_player_phase_end(phase:Dictionary, context:SessionContext) -> void:
	if not _progress_context_valid(context):
		return
	var phase_end:String = str(phase.get("end", ""))
	if !EffectManager.has_player_time_point_listener(phase_end):
		return
	for id in get_ordered_player_ids():
		if not _progress_context_valid(context):
			return
		var player_data:Dictionary = GameDataManager.get_player_data(int(id))
		if bool(player_data.get("is_out", false)):
			continue
		TimePointChecker.player_time_point([phase_end], int(id), null, context)


func end_phase(source_context:Variant = null):
	var context:SessionContext = _capture_progress_context(source_context)
	if context == null:
		return
	if is_game_over or _phase_end_running or _effects_block_progress() or _battle_broadcast_pending:
		return
	var phase = get_current_phase()
	if phase.is_empty():
		return
	_phase_end_pending = true
	_phase_end_running = true
	if phase["name"] == "battle" and _battle_result_state == -1:
		var outcome:Array = BattleResolver.new().exec_result(GameDataManager.get_board_player_ids(), BaseNumber.new(1))
		if not _progress_context_valid(context):
			return
		last_battle_result = outcome[1]
		_battle_result_state = outcome[0]
		# 已完成胜负与基础奖励才记结算；拒绝/中途停止不算成功。
		# 战后选择（含结算后的审计等待）仍由独立封存门拦住收尾。
		if _battle_result_state == BattleResolver.ResultState.PENDING_POST_BATTLE or _battle_result_state == BattleResolver.ResultState.SEALED:
			has_battle_resolved = true
	#BATTLE_END 的选择尚未完成时保留阶段、事件和原决策队列，不能开 PHASE_END 新批次。
	if is_game_over or _effects_block_progress():
		_phase_end_running = false
		return
	# 战后选择全部结束后封存本次实得，不能把阶段结束收益混入战报。
	if phase["name"] == "battle":
		var sealed_state:int = BattleResolver.finalize_result_state(last_battle_result, _battle_result_state)
		if not _progress_context_valid(context):
			return
		_battle_result_state = sealed_state
		if _battle_result_state != BattleResolver.ResultState.SEALED:
			_phase_end_running = false
			return
	#战斗结果已经封存后，才派玩家级"战斗阶段结束"；阶段结束收益不回写战报快照。
	if !_phase_player_end_dispatched:
		_phase_player_end_dispatched = true
		_dispatch_player_phase_end(phase, context)
	if not _progress_context_valid(context):
		return
	if is_game_over or _effects_block_progress():
		_phase_end_running = false
		return
	if !_phase_end_dispatched:
		#先记已派发，避免结束效果回调重入或稍后续行时重发同一时点。
		_phase_end_dispatched = true
		TimePointChecker.global_time_point([TimePoints.PHASE_END, phase["end"]], null, context)
	if not _progress_context_valid(context):
		return
	_phase_end_running = false
	if is_game_over or _effects_block_progress():
		return
	_phase_end_pending = false
	#战斗结算完毕并派发完 PHASE_END 后：显式声明需要确认时才暂停。
	#封存完成而非 Dictionary/明细非空是播报资格；合法无人参战也可确认。
	#声明与展示消费者的存在、销毁或暂停无关。
	if phase["name"] == "battle" and _battle_result_state == BattleResolver.ResultState.SEALED and not is_game_over and battle_broadcast_requires_confirm:
		_battle_broadcast_pending = true
		_battle_broadcast_confirmed = []
		renew_battle_broadcast_batch()
		return
	advance_phase(context)


#规则：每个阶段开始时，所有玩家按回合顺位，从顺位第一的玩家开始以顺时针依次进行自己的阶段。
#派发出去的是phase["mid"]，触发者拿到self_xxx_phase，其他人拿到others_xxx_phase，
#所以"当前玩家先处理完自己的效果，再轮到下一位"是时点表本身带来的，不需要额外的排序逻辑
func next_player_in_phase(source_context:Variant = null):
	var context:SessionContext = _capture_progress_context(source_context)
	if context == null:
		return
	if is_game_over or _phase_end_running:
		return
	if _phase_end_pending:
		end_phase(context)
		return
	var phase = get_current_phase()
	if phase.is_empty():
		return
	var ids = get_ordered_player_ids()
	while current_phase_player_index < ids.size() and _progress_context_valid(context):
		var id:int = ids[current_phase_player_index]
		current_phase_player_index += 1
		var player_data = GameDataManager.get_player_data(id) as Dictionary
		if player_data["is_out"]:
			continue
		current_player_id = id
		#玩家级阶段开始只在确有声明监听时补派。全局阶段开始已经在begin_phase派过，
		#这里不能用dynamic_time_point重复派原始时点，否则全局监听会按玩家执行多次。
		TimePointChecker.clear_player_scope_time_points(context)
		var phase_start:String = str(phase.get("start", ""))
		if EffectManager.has_player_time_point_listener(phase_start):
			TimePointChecker.player_time_point([phase_start], current_player_id, null, context)
		if not _progress_context_valid(context):
			return
		#高潮/非高潮与阶段时点一起按玩家派发：触发者拿到self_climax或self_non_climax，
		#效果因此能表达"高潮回合里我的阶段"（如宝石魔术放宽上限）与"仅非高潮回合"
		#阶段窗口按"视为处于的阶段"派发：没有 phase_as 声明时就是当前阶段本身，与原行为一致
		var tps:Array = effective_phase_mids(id)
		tps.append(TimePoints.CLIMAX if is_climax_round() else TimePoints.NON_CLIMAX)
		#玩家级窗口的清理已在上面完成；动态阶段时点保留原有全局时点语义。
		TimePointChecker.dynamic_time_point(tps, current_player_id, null, context)
		return
	end_phase(context)


#部署原语在成功落位后会先记deploy事实；阶段推进器在当事人的动作收尾处
#消费这条事实并派玩家级部署时点。没有成功事实就不派，避免把"有地点"误当部署。
func _dispatch_deploy_time_point_if_recorded(player_id:int, context:SessionContext) -> void:
	if not _progress_context_valid(context): return
	var dispatch_key:String = "%d:%d" % [current_round, player_id]
	if _deploy_time_points_dispatched.has(dispatch_key):
		return
	if GameLog.last({"type": "deploy", "actor": player_id}, 0) == null:
		return
	_deploy_time_points_dispatched[dispatch_key] = true
	TimePointChecker.player_time_point([TimePoints.DEPLOY], player_id, null, context)


#当前玩家完成本阶段行动后使用的唯一推进入口。
func end_current_player_action(source_context:Variant = null) -> bool:
	var context:SessionContext = _capture_progress_context(source_context)
	if context == null:
		return false
	if is_game_over or get_current_phase().is_empty():
		return false
	#效果等待任意玩家输入或正在执行时，阶段行动不能绕过管线继续推进。
	#统一在进程层拦截，避免UI、AI和其他调用方各自实现不同的保护。
	if _phase_end_running or _effects_block_progress():
		return false
	#最后行动者已经完成行动：答复后由同一个公开入口续行收尾，不重做行动或结束时点。
	if _phase_end_pending:
		end_phase(context)
		return _progress_context_valid(context) and not _battle_result_refuses_tail()
	#完成条件查询不判断主体资格；玩家行动分支拒绝缺失玩家，且不按需建库。
	if current_player_id == -1 or GameDataManager.find_player_data(current_player_id).is_empty():
		return false
	var completion_block := action_completion_block_reason(current_player_id)
	if not _progress_context_valid(context):
		return false
	if completion_block != "":
		EffectManager.push_message(completion_block, current_player_id)
		return false
	if is_phase_for(current_player_id, "action"):
		if not RegularPlay.completed(current_player_id):
			if not RegularPlay.finalize(current_player_id, true, context):
				return false
	if not _progress_context_valid(context):
		return false
	_dispatch_deploy_time_point_if_recorded(current_player_id, context)
	if not _progress_context_valid(context):
		return false
	next_player_in_phase(context)
	return _progress_context_valid(context) and not _battle_result_refuses_tail()

## 与真实推进入口共用完成条件；仅查询，不记日志、不派发时点或提示。
func can_end_current_player_action() -> bool:
	if is_game_over or get_current_phase().is_empty() or _phase_end_running or _effects_block_progress():
		return false
	if _phase_end_pending:
		return not _battle_result_refuses_tail()
	return current_player_id != -1 and action_completion_block_reason(current_player_id).is_empty()

## 只读查询玩家在有效阶段映射下尚未满足的行动完成条件，空串表示没有条件阻断。
## 不判断当前行动者、阶段有效性、游戏结束或管线等待；这些拦截仍由推进入口外层负责。
## 不建玩家、不发消息、不记日志或派发时点；未知 ID 保留旧返回值但不再按需建玩家。
func action_completion_block_reason(player_id: int) -> String:
	if is_phase_for(player_id, "outpost") and GameDataManager.find_player_data(player_id).get("location") == null:
		return "尚未完成前哨部署"
	if is_phase_for(player_id, "action"):
		#旧默认玩家没有行动声明及可出牌，原因为空；不调用会按需建玩家的常规出牌查询。
		if not GameData.player_data_library.has(player_id):
			return ""
		var reason := ActionRules.block_reason(player_id)
		if reason != "":
			return reason
		if not RegularPlay.can_end(player_id):
			return "尚未满足常规出牌最低要求"
	return ""


#供UI和各处派发临时时点
func process_time_point(time_point:String, player_id:int = -1):
	if SessionGeneration.in_private_frame(): return
	if player_id == -1:
		TimePointChecker.global_time_point([time_point])
		return
	TimePointChecker.dynamic_time_point([time_point], player_id)

# 只提供原始写集 backing 与 D 映射；没有 owner install/commit。
func publication_backing() -> Dictionary:
	return _model.backing()

func bind_domain_model(domain:Variant, private_state:Dictionary) -> Dictionary:
	return _model.bind(domain, private_state)

func domain_model_status() -> Dictionary:
	return _model.resolve()
