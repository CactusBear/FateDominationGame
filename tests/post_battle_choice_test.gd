extends Node
# 阶段边界回归，不是 BattleResolver 单元测试：必须从最后行动者的真实入口触发。
# 旧实现会在 BATTLE_END 建立选择后立刻派 PHASE_END，抹掉等待并清走事件。
var failures:Array = []
var checks:int = 0
const CHOICE_NAME:String = "contain_third_party_restore_seal_choice"

func check(ok:bool, label:String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
	print("CHECK ", label, " ", ok)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	# 交换两位胜者的决定，排除锚点玩家代答或选择状态被共用。
	await _test_post_battle_choices({1: 0, 2: 1}, "first restores")
	await _test_post_battle_choices({1: 1, 2: 0}, "second restores")
	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func _setup() -> BaseEvent:
	EventResolver.new().clear_all()
	SituationResolver.new().clear_all()
	EffectManager.reset_runtime()
	GameLog.reset()
	GameData.player_data_library.clear()
	GameData.player_id = 0
	GameProgress.current_round = 1
	GameProgress.current_phase_index = 3
	GameProgress.current_phase_player_index = 0
	GameProgress.current_player_id = -1
	GameProgress.is_game_over = false
	GameProgress.has_battle_resolved = false
	GameProgress.last_battle_result = {}
	GameProgress.total_rounds.number = 11
	# 下一回合不随机抽入无关效果；不改事件本身或决策管线。
	GameProgress.event_placements = []
	MapData.event_deck.clear()
	MapData.event_discard.clear()
	MapData.situations.clear()
	for area in MapData.areas:
		for location in area._locations:
			location._players.clear()
	for id in range(3):
		var data:Dictionary = GameData.new_player_data()
		data.is_out = false
		data.order.number = id
		data.command_spell_count.number = 0
		data.power.number = 0 if id == 0 else 20
		GameData.player_data_library[id] = data
		# 效果落位不记部署，避免席位不同的地利破坏并列胜者夹具。
		check(SetLocation.new().exec(MapData.miyama._locations[0], id, false, true), "fixture places participant %d" % id)
	var template:BaseEvent = null
	for card in LoadEvent.events:
		if card._name == "contain_third_party":
			template = card
			break
	check(template != null, "fixture loads the real contain_third_party event")
	if template == null:
		return null
	var event:BaseEvent = CloneObject.new().exec(template) as BaseEvent
	check(event != null, "fixture clones the event")
	if event == null:
		return null
	AddMapAreaEvents.new().exec(MapData.miyama, event)
	EventResolver.new().register_entered(event)
	# begin_phase 建立真实阶段时点和首位行动者，不直接伪造战后选择。
	GameProgress.begin_phase()
	return event

func _test_post_battle_choices(options:Dictionary, label:String) -> void:
	var event:BaseEvent = _setup()
	if event == null:
		return
	check(GameProgress.current_player_id == 0, label + ": first battle actor")
	check(GameProgress.end_current_player_action(), label + ": first actor finishes")
	check(GameProgress.current_player_id == 1, label + ": second battle actor")
	check(GameProgress.end_current_player_action(), label + ": second actor finishes")
	check(GameProgress.current_player_id == 2, label + ": last battle actor")
	check(_battle_entries().is_empty(), label + ": no battle before last actor finishes")
	check(GameProgress.end_current_player_action(), label + ": last actor triggers settlement")
	var battles:Array = _battle_entries()
	check(battles.size() == 3, label + ": one battle fact per participant")
	for entry in battles:
		var winners:Array = entry.data.get("winners", [])
		check(winners.size() == 2 and winners.has(1) and winners.has(2), label + ": real tied winners exclude anchor loser")
	var scores:Array = _scores()
	check(scores[0] == 0 and scores[1] > 0 and scores[1] == scores[2], label + ": battle awards tied winners once")
	_check_wait_boundary(event, label + ": after settlement")
	# 原缺陷在此明确报等待丢失；不要继续给 null 提交而变成脚本错误。
	if not EffectManager.is_waiting_for_choice():
		check(false, label + ": winner choice survived end_phase")
		return
	var answered:Array = []
	for choice_index in range(2):
		var pending:BaseEffect = EffectManager.get_pending_active_effect()
		check(pending != null, label + ": winner has pending choice %d" % choice_index)
		if pending == null:
			return
		var winner:int = pending._trigger_player_id
		check(pending._name == CHOICE_NAME and pending.has_options() and pending._options.size() == 2, label + ": real restore/decline options")
		check(options.has(winner) and not answered.has(winner), label + ": each winner decides independently")
		if not options.has(winner) or answered.has(winner):
			return
		# 模拟 UI 重复尝试自动推进及跨帧等待；均不能取消/重建选择。
		for attempt in range(2):
			check(not GameProgress.end_current_player_action(), label + ": pending choice blocks advance %d" % attempt)
			await get_tree().process_frame
			check(EffectManager.get_pending_active_effect() == pending, label + ": pending identity survives wait")
			_check_wait_boundary(event, label + ": waiting for %d" % winner)
			check(_scores() == scores, label + ": waiting does not award score again")
		check(EffectManager.submit_option_choice(pending, [options[winner]]), label + ": winner submits own option")
		answered.append(winner)
		if choice_index == 0:
			_check_wait_boundary(event, label + ": one winner still unanswered")
	check(answered.size() == 2 and answered.has(1) and answered.has(2), label + ": both winners answered exactly once")
	check(not EffectManager.is_waiting_for_choice(), label + ": all choices drained")
	for id in range(3):
		var expected:int = 1 if options.get(id, -1) == 0 else 0
		check(GameDataManager.get_player_data(id).command_spell_count.number == expected, label + ": correct seal result for %d" % id)
	# 允许提交后自动续行，或由现有 UI 的推进入口续行；绝不直接 end_phase/重派时点。
	await get_tree().process_frame
	if GameProgress.current_round == 1 and str(GameProgress.get_current_phase().get("name", "")) == "battle":
		check(GameProgress.end_current_player_action(), label + ": public entry resumes completed settlement")
	await get_tree().process_frame
	check(GameProgress.current_round == 2 and str(GameProgress.get_current_phase().get("name", "")) == "prepare", label + ": resumes at next round prepare")
	check(not GameProgress.is_game_over, label + ": continuation does not end game")
	check(not MapData.miyama._events.has(event), label + ": answered event leaves board")
	check(MapData.event_discard.count(event) == 1, label + ": answered event discarded exactly once")
	check(_battle_entries().size() == 3 and _time_point_count(TimePoints.BATTLE_END) == 1, label + ": continuation never repeats battle")
	check(_scores() == scores, label + ": continuation never repeats score reward")
	for id in range(3):
		var expected:int = 1 if options.get(id, -1) == 0 else 0
		check(GameDataManager.get_player_data(id).command_spell_count.number == expected, label + ": continuation preserves seal result for %d" % id)
	check(_time_point_count(TimePoints.PHASE_END) == 1 and _time_point_count(TimePoints.DAY_END) == 1, label + ": round closes exactly once")
	check(not EffectManager.is_waiting_for_choice(), label + ": no stale winner choice next round")

func _check_wait_boundary(event:BaseEvent, label:String) -> void:
	check(GameProgress.current_round == 1 and str(GameProgress.get_current_phase().get("name", "")) == "battle", label + ": stays in battle round")
	check(GameProgress.has_battle_resolved, label + ": remembers settled battle")
	check(EffectManager.is_waiting_for_choice(), label + ": retains winner wait")
	check(MapData.miyama._events.has(event) and not MapData.event_discard.has(event), label + ": event stays on board")
	check(_battle_entries().size() == 3 and _time_point_count(TimePoints.BATTLE_END) == 1, label + ": settlement remains unique")
	check(_time_point_count(TimePoints.PHASE_END) == 0 and _time_point_count(TimePoints.DAY_END) == 0, label + ": no premature closing time points")

func _battle_entries() -> Array:
	return GameLog.query({"type": "battle", "place": MapData.miyama._area_name}, null)

func _time_point_count(time_point:String) -> int:
	return GameLog.query({"type": "time_point", "tags": [time_point]}, null).size()

func _scores() -> Array:
	var result:Array = []
	for id in range(3):
		result.append(GameDataManager.get_player_data(id).score.number)
	return result
