extends Node

## 测试声明只提供规则输入；不写生产对象字段、不伪造等待、不实例化 UI。
## 所有被测命令均经公开权威 submit -> dispatcher -> MatchCommands -> 规则引擎。
const Authority = preload("res://scripts/net/authority/match_authority.gd")
const Selection = preload("res://scripts/net/authority/selection_authority.gd")
const Mode = preload("res://scripts/selection/class_pool_selection.gd")
const State = preload("res://scripts/match/rule_state.gd")
const RandomStream = preload("res://scripts/match/rule_random.gd")
var checks: int = 0
var failures: Array = []
var kind: String = ""
var authority

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
	print("CHECK ", kind, " ", label, " ", ok)

func _ready() -> void:
	call_deferred("run")

func start(enabled: bool = false) -> bool:
	RandomStream.start_seed(775041)
	var selection = Selection.new()
	# 正式角色模板，正式选人模式；限制职阶池只是确定性输入，不更改模板。
	var config: Dictionary = {"regular_classes": ["saber", "assassin"], "per_class_count": 1,
		"special_count": 0, "randomize_initial_order": false}
	var prepared: bool = selection.setup(Mode.new(), {0: 101, 1: 202},
		GameStart.get_masters_can_use(), GameStart.get_servants_can_use(), config)
	check(prepared, "真实选人规则建立")
	if not prepared: return false
	check(selection.choose(101, 0, "emiya_shirou"), "席位0真实选择御主")
	check(selection.choose(202, 1, "kuzuki_souichirou"), "席位1真实选择御主")
	authority = Authority.new()
	check(authority.declare_broadcast_confirmation(enabled), "启动前显式声明播报政策")
	var accepted: bool = authority.start(selection)
	check(accepted, "真实权威开局: " + authority.error)
	check(not EffectManager.is_waiting_for_choice(), "开局规则完成无伪造等待")
	return accepted and not EffectManager.is_waiting_for_choice()

func number(value: int) -> Dictionary:
	return {"number": value, "can_change": true, "is_pure_number": true}

func descriptor(name: String, parameters: Array, variable: int = -1) -> Dictionary:
	return {"func_name": name, "parameters": parameters, "var_index": variable}

func open_effect(label: String, targets: bool, cancellable: bool = true) -> BaseEffect:
	var funcs: Array = [descriptor("edit_score", [null, {"number_index": 0}, -1])]
	if targets:
		funcs = [descriptor("get_activating_eff", [], 0),
			descriptor("get_property", [{"self_var": 0}, "_selected_player"], 1),
			descriptor("edit_score", [null, {"number_index": 0}, {"self_var": 1}])]
	var option: Dictionary = {"shown_option_name": "测试声明：真实战果与费用", "allow_cancel": cancellable,
		"max_uses": 1, "tags": ["choice_submit_real"], "funcs": funcs}
	if targets:
		option.select_players = {"candidates": [descriptor("get_active_players_id", [])], "min": 1, "max": 1}
	var declaration: Dictionary = {"effect_name": label, "time_points": ["self_" + label],
		"priority": 0, "is_pure_passive": false, "is_residue": false, "need_activate": false,
		"cost": number(1), "effect_numbers": [number(2)], "max_choices": 1,
		"options": [option]}
	# 由与 JSON 相同的正式加载器构造，不把 _chosen_selection/等待字段作为输入。
	var effect: BaseEffect = LoadHelper.load_effects([declaration], GameDataManager.find_player_data(0).master)[0]
	EffectManager.register_effect(effect, 0)
	TimePointChecker.dynamic_time_point([label], 0)
	check(EffectManager.get_pending_active_effect() == effect, "真实时点产生待选项: " + label)
	return effect

func rule_state() -> Dictionary:
	return {"rules": State.capture_runtime(authority.builder.ids), "revision": authority.current_revision()}

func submit(peer: int, command: String, args: Dictionary) -> bool:
	var view: Dictionary = authority.view_for(peer)
	return authority.submit(peer, view.seq, command, args)

func reject_same(peer: int, seq: int, command: String, args: Dictionary, label: String) -> void:
	var before: Dictionary = rule_state()
	check(not authority.submit(peer, seq, command, args), label + "拒绝")
	check(rule_state() == before, label + "完整规则/运行上下文/修订不变")

func resources() -> Array:
	return [GameDataManager.find_player_data(0).magic.number,
		GameDataManager.find_player_data(0).score.number, GameDataManager.find_player_data(1).score.number]

func facts(effect: BaseEffect, type: String) -> Array:
	return GameLog.query({"type": type, "object": effect}, null, -1)

func pay_facts(effect: BaseEffect) -> Array:
	return GameLog.query({"tags": "magic_spend", "object": effect, "data": {"purpose": "effect_cost"}}, null, -1)

func open_player(effect: BaseEffect) -> void:
	var eid: int = authority.builder.ids.id_for(effect)
	check(submit(101, "option_choice", {"effect": eid, "choices": [{"index": 0, "count": 1}]}), "真实选项提交建立目标等待")
	check(EffectManager.get_pending_player_selection().get("effect") == effect, "规则目标等待属于原效果")
	check(pay_facts(effect).is_empty() and EffectManager.get_option_use_count(effect, 0) == 0, "延迟目标提交前没有扣费或用量")

func verify_settled(effect: BaseEffect, before: Array, target: int) -> void:
	var after: Array = resources()
	check(after[0] == before[0] - 1, "声明魔力费用恰扣一次")
	check(after[target + 1] == before[target + 1] + 2 and after[2 - target] == before[2 - target], "真实 edit_score 只给声明目标战果+2")
	check(EffectManager.get_option_use_count(effect, 0) == 1 and facts(effect, "option_used").size() == 1, "选项用量与事实各一次")
	var payments: Array = pay_facts(effect)
	check(payments.size() == 1 and payments[0].actor == 0 and payments[0].data.spent == 1, "真实支付事实记录付款人和费用")
	check(not EffectManager.is_waiting_for_choice(), "结算后等待解除")
	var calls: Array = GameLog.all_func_calls()
	var executed: int = 0
	for entry in calls:
		if entry.get("effect_name") == effect._name and entry.get("func_name") == "edit_score" and entry.get("status") == "executed": executed += 1
	check(executed == 1, "操作执行日志证实真实 edit_score 恰执行一次")

func player_case() -> void:
	var effect: BaseEffect = open_effect("choice_submit_player", true)
	open_player(effect)
	var eid: int = authority.builder.ids.id_for(effect)
	var view: Dictionary = authority.view_for(101)
	for picks in [[999], [], [1, 1], [0, 1], ["1"]]:
		reject_same(101, view.seq, kind, {"effect": eid, "players": picks}, "非法目标" + str(picks))
	var other: Dictionary = authority.view_for(202)
	reject_same(202, other.seq, kind, {"effect": eid, "players": [1]}, "其他席位")
	var before: Array = resources()
	check(authority.submit(101, view.seq, kind, {"effect": eid, "players": [1]}), "合法目标经真实权威提交接受")
	verify_settled(effect, before, 1)
	check(effect._selected_player == 1 and effect._selected_players == [1], "实际结算读取原选择")
	reject_same(101, view.seq, kind, {"effect": eid, "players": [1]}, "原视图重复")
	view = authority.view_for(101)
	reject_same(101, view.seq, kind, {"effect": eid, "players": [1]}, "新视图已结算效果重复")
	var next: BaseEffect = open_effect("choice_submit_player_next", true)
	open_player(next)
	view = authority.view_for(101)
	reject_same(101, view.seq, kind, {"effect": eid, "players": [1]}, "新等待中旧效果过期")
	check(EffectManager.get_pending_player_selection().get("effect") == next, "旧答复未消耗新目标等待")
	check(submit(101, "cancel_choice", {"effect": authority.builder.ids.id_for(next)}), "公开取消收尾新夹具")

func option_case() -> void:
	var effect: BaseEffect = open_effect("choice_submit_option", false)
	var eid: int = authority.builder.ids.id_for(effect)
	var view: Dictionary = authority.view_for(101)
	for choices in [[], [{"index": -1, "count": 1}], [{"index": 0, "count": 0}],
		[{"index": 0, "count": 2}], [{"index": 0, "count": 1}, {"index": 0, "count": 1}],
		[{"index": 0, "count": 1, "quantity": 2}]]:
		reject_same(101, view.seq, kind, {"effect": eid, "choices": choices}, "非法选项" + str(choices))
	var other: Dictionary = authority.view_for(202)
	reject_same(202, other.seq, kind, {"effect": eid, "choices": [{"index": 0, "count": 1}]}, "其他席位")
	var before: Array = resources()
	check(authority.submit(101, view.seq, kind, {"effect": eid, "choices": [{"index": 0, "count": 1}]}), "合法选项经真实权威提交接受")
	verify_settled(effect, before, 0)
	reject_same(101, view.seq, kind, {"effect": eid, "choices": [{"index": 0, "count": 1}]}, "原视图重复")
	view = authority.view_for(101)
	reject_same(101, view.seq, kind, {"effect": eid, "choices": [{"index": 0, "count": 1}]}, "新视图已结算效果重复")
	var next: BaseEffect = open_effect("choice_submit_option_next", false)
	view = authority.view_for(101)
	reject_same(101, view.seq, kind, {"effect": eid, "choices": [{"index": 0, "count": 1}]}, "新等待中旧效果过期")
	check(EffectManager.get_pending_active_effect() == next, "旧选项未消耗新等待")
	check(submit(101, "cancel_choice", {"effect": authority.builder.ids.id_for(next)}), "公开取消收尾新夹具")

func cancel_case() -> void:
	# 同样带费用和非空效果体的禁止取消声明先实际结算，证明夹具并非无法执行的空壳。
	var mandatory: BaseEffect = open_effect("choice_submit_mandatory", true, false)
	open_player(mandatory)
	var mid: int = authority.builder.ids.id_for(mandatory)
	var view: Dictionary = authority.view_for(101)
	reject_same(101, view.seq, kind, {"effect": mid}, "显式禁止取消")
	var control: Array = resources()
	check(authority.submit(101, view.seq, "player_choice", {"effect": mid, "players": [1]}), "同规则付费选人对照实际接受")
	verify_settled(mandatory, control, 1)
	var effect: BaseEffect = open_effect("choice_submit_cancel", true, true)
	open_player(effect)
	var eid: int = authority.builder.ids.id_for(effect)
	view = authority.view_for(101)
	reject_same(101, view.seq, kind, {"effect": eid, "extra": true}, "额外取消字段")
	var other: Dictionary = authority.view_for(202)
	reject_same(202, other.seq, kind, {"effect": eid}, "取消他人等待")
	var before: Array = resources()
	var calls: int = GameLog.all_func_calls().size()
	check(authority.submit(101, view.seq, kind, {"effect": eid}), "合法取消经真实权威接受")
	check(not EffectManager.is_waiting_for_choice() and effect._selected_players.is_empty(), "取消清除等待与目标")
	check(resources() == before and EffectManager.get_option_use_count(effect, 0) == 0 and pay_facts(effect).is_empty() and facts(effect, "option_used").is_empty(), "取消不结算不扣費不消费次数")
	check(GameLog.all_func_calls().size() == calls, "取消没有执行原效果体")
	reject_same(101, view.seq, kind, {"effect": eid}, "原视图重复取消")
	view = authority.view_for(101)
	reject_same(101, view.seq, kind, {"effect": eid}, "新视图重复取消")
	reject_same(101, view.seq, "player_choice", {"effect": eid, "players": [1]}, "取消后原目标答复")
	reject_same(101, view.seq, "option_choice", {"effect": eid, "choices": [{"index": 0, "count": 1}]}, "取消后原选项答复")
	EffectManager.run_pipeline()
	check(resources() == before and GameLog.all_func_calls().size() == calls and pay_facts(effect).is_empty(), "再次驱动管线不恢复原选择也不重复扣费")
	var next: BaseEffect = open_effect("choice_submit_cancel_next", true)
	open_player(next)
	view = authority.view_for(101)
	reject_same(101, view.seq, kind, {"effect": eid}, "新等待中的过期取消")
	check(EffectManager.get_pending_player_selection().get("effect") == next, "过期取消不关闭新等待")
	check(submit(101, "player_choice", {"effect": authority.builder.ids.id_for(next), "players": [1]}), "取消后新选择仍可真实结算")
	verify_settled(next, before, 1)
	check(pay_facts(effect).is_empty() and EffectManager.get_option_use_count(effect, 0) == 0, "新选择完成后原取消选择仍没有任何费用或用量")

func reach_broadcast() -> bool:
	# 正式无界面驱动器逐席执行真实部署/行动/战斗；不写阶段或战报等待字段。
	for _i in range(80):
		if GameProgress.is_battle_broadcast_pending(): return true
		if GameProgress.is_game_over: return false
		if EffectManager.is_waiting_for_choice():
			var answered: bool = false
			for peer in [101, 202]:
				var prompt: Dictionary = authority.pending_for(peer)
				if prompt.is_empty(): continue
				print("PRELUDE_PROMPT ", JSON.stringify(prompt))
				if prompt.get("allow_cancel", false):
					answered = submit(peer, "cancel_choice", {"effect": prompt.effect})
				break
			if not answered:
				print("PRELUDE_BLOCKED mandatory rule input or guard requires explicit prerequisite")
				return false
			continue
		print("PRELUDE_TURN ", GameProgress.current_round, " ", GameProgress.get_current_phase().get("name"), " ", GameProgress.current_player_id)
		authority.driver.run_bot_turn(GameProgress.current_player_id)
	print("PRELUDE_BLOCKED bounded prelude did not reach battle wait")
	return false

func broadcast_case() -> void:
	check(reach_broadcast(), "真实规则行动与战斗产生播报等待")
	if not GameProgress.is_battle_broadcast_pending(): return
	var batch: int = GameProgress.battle_broadcast_batch_id()
	var round_before: int = GameProgress.current_round
	var result: Dictionary = GameProgress.last_battle_result.duplicate(true)
	check(batch > 0 and not result.is_empty() and GameProgress.get_current_phase().name == "battle", "实际战报结算后停在战斗阶段")
	check(GameProgress.battle_broadcast_confirmers() == [0, 1] and GameProgress.battle_broadcast_confirmed().is_empty(), "真人两席都尚未确认")
	var unchanged: Dictionary = rule_state()
	for _i in range(4): authority.step(1.0)
	check(rule_state() == unchanged and GameProgress.current_round == round_before and GameProgress.last_battle_result == result, "未确认分支:正常权威tick不清理战报不推进回合不重算")
	var view: Dictionary = authority.view_for(101)
	for args in [{"batch_id": batch + 1}, {"batch_id": batch, "seat": 1}, {"batch_id": str(batch)}]:
		reject_same(101, view.seq, kind, args, "无效确认" + str(args))
	reject_same(999, view.seq, kind, {"batch_id": batch}, "无控制席确认")
	check(authority.submit(101, view.seq, kind, {"batch_id": batch}), "首席合法确认真实接受")
	check(GameProgress.battle_broadcast_confirmed() == [0] and GameProgress.is_battle_broadcast_pending() and GameProgress.current_round == round_before and GameProgress.last_battle_result == result, "部分确认分支:仅记本人确认且仍阻止回合清理")
	reject_same(101, view.seq, kind, {"batch_id": batch}, "原视图重复首席确认")
	view = authority.view_for(101)
	reject_same(101, view.seq, kind, {"batch_id": batch}, "新视图重复首席确认")
	var retained_locations: Array = [GameDataManager.find_player_data(0).location, GameDataManager.find_player_data(1).location]
	check(submit(202, kind, {"batch_id": batch}), "末席合法确认真实接受")
	# 回合收尾可能在异步规则等待后续行；不强行改进度。
	for _i in range(4):
		if GameProgress.current_round > round_before: break
		await get_tree().process_frame
	check(not GameProgress.is_battle_broadcast_pending() and GameProgress.battle_broadcast_batch_id() == 0, "确认完成释放旧屏障")
	check(GameProgress.current_round == round_before + 1 and GameProgress.get_current_phase().get("name") == "prepare", "确认分支:真实回合收尾进入下一回合准备阶段")
	for seat in [0, 1]:
		var data: Dictionary = GameDataManager.find_player_data(seat)
		check(data.location == null and data.last_turn_location == retained_locations[seat], "确认后真实移出棋盘且保留上回合位置" + str(seat))
	view = authority.view_for(202)
	reject_same(202, view.seq, kind, {"batch_id": batch}, "释放后重复末席确认")
	check(reach_broadcast(), "下一回合真实战斗建立新批次")
	if not GameProgress.is_battle_broadcast_pending(): return
	var next_batch: int = GameProgress.battle_broadcast_batch_id()
	check(next_batch > batch and GameProgress.battle_broadcast_confirmed().is_empty(), "新批次身份前进而非复用旧确认")
	view = authority.view_for(101)
	reject_same(101, view.seq, kind, {"batch_id": batch}, "新战报等待中旧批次过期")
	check(submit(101, kind, {"batch_id": next_batch}) and submit(202, kind, {"batch_id": next_batch}), "新批次仍可经两次真实确认继续")

func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	kind = args[0] if not args.is_empty() else ""
	print("DIAGNOSTIC_USER_PATH ", OS.get_user_data_dir())
	check(kind in ["player_choice", "option_choice", "cancel_choice", "confirm_broadcast"], "明确单kind专项参数")
	if failures.is_empty() and start(kind == "confirm_broadcast"):
		match kind:
			"player_choice": player_case()
			"option_choice": option_case()
			"cancel_choice": cancel_case()
			"confirm_broadcast": await broadcast_case()
	print("RESULT ", JSON.stringify({"suite": kind, "checks": checks, "failures": failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
