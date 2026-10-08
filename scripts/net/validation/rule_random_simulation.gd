extends RefCounted

static func room_options(settings:Dictionary, humans:int) -> Dictionary:
	if not settings.has("random_sim_enabled") or not settings.has("random_sim_budget_sec"): return {}
	var count:int = maxi(int(settings.minimum), humans + int(settings.ai_count))
	var guard:Dictionary = settings.get("runtime_guard", {}).duplicate(true)
	if not guard.get("enabled", false): guard = {"enabled":true,"steps":0,"seconds":settings.random_sim_budget_sec}
	return {"enabled":settings.random_sim_enabled,"seconds":settings.random_sim_budget_sec,"selection_mode":settings.selection_mode,"player_ids":Array(range(count)),"guard":guard}

## 只能在独立预检进程使用；复用正式选人和权威规则，不接管真人会话。
func run(tree:SceneTree, mode_config:Dictionary, player_ids:Array, enabled:bool, seconds:float, guard:Dictionary, seeds:Array = []) -> Dictionary:
	var report:Dictionary = {"ok":false, "enabled":enabled, "budget_seconds":seconds, "cases":[], "effects":[], "warnings":[], "errors":[]}
	if not is_finite(seconds) or seconds < 0:
		report.errors.append("随机模拟时间预算无效")
		return report
	if not enabled or seconds == 0:
		report.ok = true
		return report
	if tree == null or GameStart._started or player_ids.is_empty() or not guard.get("enabled", false) or not preload("res://scripts/match/rule_budget.gd").new().configure(guard):
		report.errors.append("随机模拟需要独立规则会话、显式席位及已启用的保护配置")
		return report
	if not mode_config.get("script") is String or not ResourceLoader.exists(mode_config.script):
		report.errors.append("随机模拟选人模式未声明")
		return report
	var script = load(mode_config.script)
	if not script is Script or not script.can_instantiate() or not is_instance_of(script.new(), preload("res://scripts/selection/selection_mode.gd")):
		report.errors.append("随机模拟选人模式类型无效")
		return report
	var seats:Dictionary = {}
	for id in player_ids:
		if not id is int or id < 0 or seats.has(id):
			report.errors.append("随机模拟席位无效或重复")
			return report
		seats[id] = 0
	for value in seeds:
		if not value is int:
			report.errors.append("复现种子必须为整数")
			return report
	# 载入器隔离入口不会自动重建地图；沿既有完整会话复位重建批准数据。
	GameStart.end_session()
	var started_msec:int = Time.get_ticks_msec()
	var deadline:int = started_msec + int(seconds * 1000.0)
	var stream = preload("res://scripts/match/rule_random.gd")
	while Time.get_ticks_msec() < deadline and (seeds.is_empty() or report.cases.size() < seeds.size()):
		var match_seed:int = Crypto.new().generate_random_bytes(8).decode_s64(0) if seeds.is_empty() else seeds[report.cases.size()]
		stream.start_seed(match_seed)
		var selection = preload("res://scripts/net/authority/selection_authority.gd").new()
		if not selection.setup(script.new(), seats, GameStart.get_masters_can_use(), GameStart.get_servants_can_use(), mode_config):
			report.errors.append(selection.error)
			break
		var authority = preload("res://scripts/net/authority/match_authority.gd").new()
		var entry:Dictionary = {"seed":str(match_seed), "assignments":{}, "rounds":0, "steps":0, "completed":false, "status":"running", "effects":[]}
		for id in selection.rules.get_assignments():
			var assignment:Dictionary = selection.rules.get_assignments()[id]
			entry.assignments[str(id)] = {"master":assignment.master._name, "servant":assignment.servant._name}
		if not authority.start(selection, guard):
			report.errors.append(authority.error)
			break
		authority.driver.step_interval = 0.0
		while Time.get_ticks_msec() < deadline and not GameProgress.is_game_over and not EffectManager.runtime_guard_status().paused:
			authority.step(1.0 / 60.0)
			entry.steps += 1
			await tree.process_frame
		entry.rounds = GameProgress.current_round
		entry.completed = GameProgress.is_game_over
		if EffectManager.runtime_guard_status().paused:
			entry.status = "guard_paused"
			entry.diagnostic = authority.guard_diagnostic()
			report.warnings.append("模拟规则达到协作预算，疑似异常；不能据此确定死循环：%s / %s / %s" % [entry.diagnostic.get("player_name", "未知玩家"), entry.diagnostic.get("card", "未知来源"), entry.diagnostic.get("effect", "未知效果")])
		elif entry.completed:
			entry.status = "completed"
		else:
			entry.status = "time_budget"
			report.warnings.append("随机模拟时间已用尽，当前对局未结束")
		for fact in GameLog.query({"type":"effect"}, null):
			var name:String = str(fact.get("data", {}).get("effect_name", ""))
			if not name.is_empty() and not entry.effects.has(name): entry.effects.append(name)
			if not name.is_empty() and not report.effects.has(name): report.effects.append(name)
		report.cases.append(entry)
		authority.close_archive()
		GameStart.end_session()
		await tree.process_frame
		if entry.status == "guard_paused": break
	stream.stop_tracking()
	report.elapsed_seconds = float(Time.get_ticks_msec() - started_msec) / 1000.0
	report.ok = report.errors.is_empty()
	return report
