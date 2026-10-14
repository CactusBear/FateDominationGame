extends Node
# B23: public-entry business probe for battle_resolver.gd original line 271.
# No private members, routing spy, stderr inspection, or synthetic result/logs.
var checks:int = 0
var failures:Array = []

func check(ok:bool, label:String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
	print("CHECK ", label, " ", ok)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var positive:Array = probe_case("positive", 2)
	var control:Array = probe_case("zero_pool", 0)
	check(positive == [2, 2] and control == [0, 0] and positive != control,
		"positive scout income differs from zero-pool control")
	print("RESULT checks=", checks, " failures=", JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

func probe_case(label:String, pool:int) -> Array:
	var lifecycle:Dictionary = EffectManager.reset_runtime()
	MapData.reset_board()
	var area:BaseMapArea = GetMapAreaByName.new().exec("侦察")
	check(area != null and not GetMapAreaScoreNeedWin.new().exec(area),
		label + ": scout is a non-battle area")
	EditMapAreaScore.new().exec(area, BaseNumber.new(pool))
	check(GetMapAreaScore.new().exec(area).number == pool, label + ": declared reward pool")
	var controller:int = AddPlayer.new().exec(-1, [], {"score": 30}, lifecycle.context)
	var independent:int = AddPlayer.new().exec(-1, [], {"score": 10, "power": 99}, lifecycle.context)
	var controlled:int = AddPlayer.new().exec(controller, [], {"score": 20, "power": 0}, lifecycle.context)
	var participants:Array = [independent, controlled]
	check(GameDataManager.represented_id(controlled) == controller and controlled != controller,
		label + ": controlled entry has a distinct representative")
	check(not is_same(GameDataManager.get_player_data(controlled).score,
		GameDataManager.get_player_data(controller).score), label + ": score is explicitly unshared")
	for id in participants:
		check(SetLocation.new().exec(MapData.scout0, id, false, true, true, lifecycle.context),
			"%s: participant %d placed through public entry" % [label, id])
	TimePointChecker.set_phase_time_points([TimePoints.BATTLE_PHASE], lifecycle.context)
	GameLog.reset()
	GameLog.set_context(1, "battle")
	var before:Dictionary = {}
	for id in participants + [controller]:
		before[id] = int(GameDataManager.get_player_data(id).score.number)
	var result:Dictionary = BattleResolver.new(lifecycle.context).exec(participants)
	var detail:Dictionary = result.get("details_by_area", {}).get("侦察", {})
	check(not detail.is_empty() and detail.get("needs_win") == false,
		label + ": public report marks no victory requirement")
	check(detail.get("players") == participants and detail.get("winners") == participants,
		label + ": report preserves original participant ids irrespective of power")
	check(not result.get("winners_by_area", {}).has("侦察") and result.get("draw_areas", []).is_empty(),
		label + ": scout is not a battle victory or draw")
	check(detail.get("powers") == {} and detail.get("competition_score") == pool
		and detail.get("total_score") == pool and detail.get("event_score") == 0,
		label + ": report contains the declared scout pool without power comparison")
	var gained:Dictionary = detail.get("score_gained", {})
	var deltas:Array = []
	for id in participants:
		var delta:int = int(GameDataManager.get_player_data(id).score.number) - int(before[id])
		deltas.append(delta)
		check(delta == pool, "%s: participant %d actual delta expected=%d got=%d" % [label, id, pool, delta])
		check(gained.has(id) and gained.get(id) == pool,
			"%s: participant %d reported income expected=%d got=%s" % [label, id, pool, str(gained.get(id))])
		var facts:Array = GameLog.query({"type": "score_add", "actor": id}, null)
		check((facts.size() == 1 and facts[0].data.get("delta") == pool
			and facts[0].data.get("now") == int(before[id]) + pool) if pool > 0 else facts.is_empty(),
			"%s: participant %d score_add fact matches exact income and owner" % [label, id])
		var points:Array = GameLog.query({"type": "time_point", "actor": id, "tags": [TimePoints.SCORE_ADD]}, null)
		check(points.size() == (1 if pool > 0 else 0),
			"%s: participant %d SCORE_ADD occurs only for positive income" % [label, id])
	check(gained.size() == 2 and not gained.has(controller), label + ": report never substitutes controller id")
	check(GameDataManager.get_player_data(controller).score.number == before[controller]
		and GameLog.query({"type": "score_add", "actor": controller}, null).is_empty(),
		label + ": unshared controller receives no scout income")
	check(GameLog.query({"type": "time_point", "tags": [TimePoints.BATTLE_WIN]}, null).is_empty()
		and GameLog.query({"type": "battle"}, null).is_empty(), label + ": scout never emits BATTLE_WIN or battle facts")
	var tail:Array = []
	for fact in GameLog.query({}, null):
		if fact.type == "score_add":
			tail.append("score:%d" % fact.actor)
		elif fact.type == "time_point" and fact.data.get("time_points", []).has(TimePoints.SCORE_ADD):
			tail.append("point:%d" % fact.actor)
		elif fact.type == "time_point" and fact.data.get("time_points", []).has(TimePoints.BATTLE_END):
			tail.append("end")
	var expected:Array = ["score:%d" % independent, "point:%d" % independent,
		"score:%d" % controlled, "point:%d" % controlled, "end"] if pool > 0 else ["end"]
	check(tail == expected, label + ": exact score-fact SCORE_ADD and BATTLE_END order")
	check(not EffectManager.is_running and not EffectManager.is_waiting_for_choice(),
		label + ": synchronous fixture leaves no pending effects")
	for id in participants + [controller]:
		SetPlayerData.new().exec("is_out", true, id)
	return deltas
