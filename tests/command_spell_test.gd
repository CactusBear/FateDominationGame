extends Node
# 令咒回归：胜场奖励必须在真实 BattleResolver 胜场记录之后发生；
# 移动是选择一个显式位置的免费效果，且仅能从深山町/新都发动。
const Observer = preload("res://tests/round47_public_test_observer.gd")
var keepalive:Array = []
var fixture_context:SessionContext = null

func check(ok:bool, label:String) -> void:
	Observer.check(ok, label)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	Observer.reset()
	_setup()
	_test_delayed_battle_reward()
	_setup()
	_test_delayed_reward_expires()
	_setup()
	_test_effect_announcement_is_player_readable()
	_setup()
	_test_waiting_preserves_following_timepoint()
	_setup()
	_test_free_targeted_move()
	_setup()
	_test_invalid_origin_does_not_spend_spell()
	_setup()
	_test_battle_end_restores_seal()
	_setup()
	_test_restore_respects_dynamic_limit()
	_setup()
	_test_battle_end_decline_restores_nothing()
	_setup()
	await _test_ai_defaults_to_restore_seal()
	_setup()
	await _test_move_tip_and_announcement()
	var file := FileAccess.open("res://command_spell_test_result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": Observer.checks, "failures": Observer.failures}))
	file.close()
	Observer.finish(get_tree())

func _setup() -> void:
	var reset:Dictionary = EffectManager.reset_runtime()
	check(reset.ok, "fixture reset returns its original context")
	fixture_context = reset.get("context") as SessionContext
	GameLog.reset()
	GameLog.set_context(1, "action")
	GameData.player_data_library.clear()
	GameData.player_id = 0
	GameProgress.current_round = 1
	GameProgress.current_phase_index = 2
	GameProgress.current_player_id = 0
	for id in range(3):
		var data := GameData.new_player_data()
		data.is_out = false
		data.magic.number = 20
		data.command_spell_count.number = 3
		GameData.player_data_library[id] = data
	for area in MapData.areas:
		area._events.clear()
		for loc in area._locations:
			loc._players.clear()
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.ACTION_PHASE, TimePoints.NON_CLIMAX])
	TimePointChecker.dynamic_time_point([TimePoints.ACTION_PHASE, TimePoints.NON_CLIMAX], 0, null, fixture_context)

func _command_effect() -> BaseEffect:
	for template in LoadCommandSpell.command_spells.values():
		if template != null and template._name == "normal_command_spell":
			var card = _runtime_template(template)
			if card == null:
				return null
			keepalive.append(card)
			var effect:BaseEffect = card._effects[0]
			EffectManager.register_effect(effect, 0)
			return effect
	return null

func _runtime_template(template):
	var clone := CloneContext.new()
	if not clone.configure_template(fixture_context, [template]):
		return null
	var copied:Dictionary = clone.copy_result(template, fixture_context)
	return copied.object if copied.ok else null

func _choose(effect:BaseEffect, option_index:int) -> bool:
	return EffectManager.request_manual_activation(effect, 0) and EffectManager.submit_option_choice(effect, [option_index])

func _place(area:BaseMapArea, player_id:int, slot:int = 0) -> bool:
	return SetLocation.new().exec(area._locations[slot], player_id, false, true, true, fixture_context)

func _test_delayed_battle_reward() -> void:
	_place(MapData.miyama, 0, 0)
	_place(MapData.miyama, 1, 1)
	GameDataManager.get_player_data(0).power.number = 20
	var effect := _command_effect()
	check(effect != null and _choose(effect, 1), "power command option is accepted")
	var before:int = GameDataManager.get_player_data(0).score.number
	var battle := BattleResolver.new(fixture_context).exec([0, 1])
	var detail:Dictionary = battle.details_by_area.get(MapData.miyama._area_name, {})
	var reported:int = int((detail.get("score_gained", {}) as Dictionary).get(0, 0))
	var after:int = GameDataManager.get_player_data(0).score.number
	check(detail.get("winners", []).has(0), "reward fixture records a real battle win")
	check(after - before == reported, "battle report includes the command reward in actual net score")
	check(reported == int(detail.get("total_score", 0)) + 2, "command reward adds two score beyond the base pool")
	var original_fact = GameLog.last({"type": "effect", "object": effect}, null)
	var delayed_fact = null
	# 事实筛选器不负责嵌套字段；按实际效果身份查出延迟结算记录。
	for fact in GameLog.query({"type": "effect"}, null):
		if str(fact.data.get("effect_name", "")) == "scheduled_effect":
			delayed_fact = fact
	check(original_fact != null and delayed_fact != null and
		str(delayed_fact.data.get("source_name", "")) != "" and
		delayed_fact.data.get("source_name") == original_fact.data.get("source_name"),
		"settled delayed reward records the original readable source")
	Observer.trace("delayed battle reward")

func _test_delayed_reward_expires() -> void:
	var effect := _command_effect()
	check(effect != null and _choose(effect, 1), "unused delayed reward is scheduled")
	var scheduled = null
	for candidate in EffectManager.effect_pool:
		if candidate is BaseEffect and candidate._name == "scheduled_effect":
			scheduled = candidate
	check(scheduled != null and scheduled._expire_time_points.has(TimePoints.DAY_END),
		"delayed reward carries its declared day-end expiry")
	check(scheduled != null and scheduled.get_shown_name() == effect.get_shown_name(),
		"delayed reward inherits the original player-readable effect text")
	check(scheduled != null and scheduled.from == effect.from,
		"delayed reward inherits the original source object")
	var batch_before:int = EffectManager.time_point_id
	TimePointChecker.global_time_point([TimePoints.DAY_END], null, fixture_context)
	check(EffectManager.time_point_id == batch_before + 1, "a new timepoint increments the batch id")
	check(scheduled != null and not EffectManager.effect_pool.has(scheduled), "unused delayed reward expires at day end")
	var score_before:int = GameDataManager.get_player_data(0).score.number
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_WIN], 0, null, fixture_context)
	check(GameDataManager.get_player_data(0).score.number == score_before,
		"an expired delayed reward cannot carry into a later round")

func _test_effect_announcement_is_player_readable() -> void:
	var master := BaseMaster.new("announcement_master", "测试御主", "", "", "")
	GameDataManager.get_player_data(0).master = master
	var produced:Array = LoadHelper.load_effects([{
		"effect_name":"announcement_probe", "time_points":[], "priority":0,
		"is_pure_passive":true, "is_residue":false, "effect_numbers":[], "funcs":[]
	}], master, fixture_context)
	check(produced.size() == 1, "announcement fixture creates a sourced runtime effect")
	if produced.size() != 1:
		return
	var effect:BaseEffect = produced[0]
	effect._shown_name = "测试能力"
	effect._trigger_player_id = 0
	effect.from = master
	effect._funcs = LoadHelper.load_funcs([{"func_name": "edit_score", "parameters": [null, BaseNumber.new(1), 0], "var_index": -1}], effect, fixture_context)
	EffectManager.register_effect(effect, 0)
	EffectManager.add_to_activation_pool(effect)
	EffectManager.run_pipeline()
	check(GameDataManager.get_player_data(0).score.number == 1, "announcement follows a real applied effect")
	check(EffectManager.messages.size() == 1 and int(EffectManager.messages[0].get("player_id", 0)) == -1,
		"pipeline flush publishes a public broadcast ticket")
	var messages:Array = EffectManager.pop_messages(1)
	var text:String = "\n".join(messages)
	check(text.contains("测试御主：测试能力"), "announcement keeps the actor and readable effect text")
	check(not text.contains("【测试御主】"), "announcement does not repeat an identical actor and source")
	check(EffectManager.pop_messages(0).is_empty(), "announcement is consumed exactly once")
	Observer.trace("announcement pipeline")

func _test_waiting_preserves_following_timepoint() -> void:
	var sentinels := LoadHelper.load_effects([{
		"effect_name": "queued_day_end_probe", "time_points": [TimePoints.DAY_END],
		"priority": 0, "is_pure_passive": true, "is_residue": false, "effect_numbers": [], "funcs": [
			{"func_name": "edit_score", "parameters": [null, BaseNumber.new(1), 0], "var_index": -1}]
	}, {
		"effect_name": "queued_day_start_probe", "time_points": [TimePoints.DAY_START],
		"priority": 0, "is_pure_passive": true, "is_residue": false, "effect_numbers": [], "funcs": [
			{"func_name": "edit_score", "parameters": [null, BaseNumber.new(10), 0], "var_index": -1}]
	}], null, fixture_context)
	EffectManager.register_effects(sentinels, 0)
	var effect := _command_effect()
	check(effect != null and EffectManager.request_manual_activation(effect, 0), "command spell opens a real pending choice")
	var batch_before:int = EffectManager.time_point_id
	TimePointChecker.global_time_point([TimePoints.DAY_END], null, fixture_context)
	TimePointChecker.global_time_point([TimePoints.DAY_START], null, fixture_context)
	check(EffectManager.waiting_effect == effect, "a following timepoint does not overwrite the pending choice")
	check(EffectManager.time_point_id == batch_before and GameDataManager.get_player_data(0).score.number == 0,
		"the following timepoint waits in order")
	check(EffectManager.submit_option_choice(effect, [0]), "pending command choice resolves")
	check(EffectManager.waiting_effect == null and GameDataManager.get_player_data(0).score.number == 11,
		"queued timepoint runs after the choice resolves")
	check(EffectManager.time_point_id > batch_before, "queued timepoint runs in a later batch")
	var chosen:Array = Observer.names(effect._name)
	var queued:Array = Observer.names("queued_day_end_probe")
	check(chosen == ["edit_magic"] and queued == ["edit_score"] and Observer.names("queued_day_start_probe") == ["edit_score"],
		"choice and both deferred timepoints each execute exactly once")
	var facts:Array = GameLog.query({"type": "effect"}, null)
	var settled:Array = []
	for fact in facts:
		settled.append(str(fact.data.get("effect_name", "")))
	check(settled == ["queued_day_end_probe", "queued_day_start_probe", effect._name],
		"accepted choice releases queued timepoints in FIFO order before its branch settles")
	var calls_before:int = GameLog.all_func_calls().size()
	EffectManager.run_pipeline()
	check(GameLog.all_func_calls().size() == calls_before and GameDataManager.get_player_data(0).score.number == 11,
		"idle pipeline cannot replay a drained timepoint")
	Observer.trace("deferred timepoint")

func _test_free_targeted_move() -> void:
	_place(MapData.miyama, 0, 0)
	var data:Dictionary = GameDataManager.get_player_data(0)
	var origin:BaseLocation = data.location
	var magic_before:int = data.magic.number
	var spells_before:int = data.command_spell_count.number
	var effect := _command_effect()
	check(effect != null and _choose(effect, 2), "move command option opens an explicit location choice")
	var has_location_api:bool = EffectManager.has_method("get_pending_location_selection") and EffectManager.has_method("submit_location_selection")
	check(has_location_api, "effect manager exposes generic location selection")
	if has_location_api:
		var accepted:bool = EffectManager.submit_location_selection(effect, MapData.magic_workshop0)
		check(accepted and data.location == MapData.magic_workshop0, "command move reaches chosen arbitrary location")
		check(data.magic.number == magic_before, "command move spends no magic")
		check(data.command_spell_count.number == spells_before - 1, "command move spends one command spell")
		check(data.location != origin, "command move changes location")

## 战斗结束时点（battle_end）：事件牌「遏制第三方威胁」= 此战场胜者可恢复1枚令咒。
## 形态是"有选项效果"（恢复令咒 / 不恢复令咒），不是单纯的发动/放弃确认。
## 这条同时验：① 战斗结算后引擎真的派发了 battle_end 时点；② 时点按"一场战斗一次"派发
## （逐个参战者派发会让胜者收到多次选择、令咒被加多次）。
func _test_battle_end_restores_seal() -> void:
	_place(MapData.miyama, 0, 0)
	_place(MapData.miyama, 1, 1)
	GameDataManager.get_player_data(0).power.number = 20
	var pending := _battle_end_choice(0)
	check(pending != null and pending._name == "contain_third_party_restore_seal_choice", "battle end offers the event's seal restore to the winner")
	check(pending != null and pending.has_options() and pending._options.size() == 2, "the seal restore is an options effect")
	if pending != null and pending.has_options():
		check(str(pending._options[0].get("shown_option_name")) == "恢复令咒", "first option restores the seal")
		check(str(pending._options[1].get("shown_option_name")) == "不恢复令咒", "second option declines explicitly")
	check(EffectManager.submit_option_choice(pending, [0]), "choosing restore is accepted")
	check(GameDataManager.get_player_data(0).command_spell_count.number == 1, "battle end area effect restores one command spell")
	check(GameDataManager.get_player_data(1).command_spell_count.number == 3, "the loser gets no command spell from the winner effect")
	# 明确放弃的那一项必须真的什么都不做
	check(EffectManager.waiting_effect == null, "one battle queues exactly one seal choice")
	check(EventResolver.new().clear_all(fixture_context).ok, "fixture clears events with original context")


func _test_restore_respects_dynamic_limit() -> void:
	var data:Dictionary = GameDataManager.get_player_data(0)
	data["command_spell_limit"] = BaseNumber.new(4)
	_place(MapData.miyama, 0, 0)
	_place(MapData.miyama, 1, 1)
	data.power.number = 20
	var pending := _battle_end_choice(4)
	check(pending != null and EffectManager.submit_option_choice(pending, [0]),
		"restore at a raised limit resolves")
	check(data.command_spell_count.number == 4, "restore never exceeds the current command spell limit")
	check(EventResolver.new().clear_all(fixture_context).ok, "fixture clears events with original context")

	_setup()
	data = GameDataManager.get_player_data(0)
	data["command_spell_limit"] = BaseNumber.new(5)
	_place(MapData.miyama, 0, 0)
	_place(MapData.miyama, 1, 1)
	data.power.number = 20
	pending = _battle_end_choice(4)
	check(pending != null and EffectManager.submit_option_choice(pending, [0]),
		"restore below a raised limit resolves")
	check(data.command_spell_count.number == 5, "restore can reach a command spell limit above three")
	check(EventResolver.new().clear_all(fixture_context).ok, "fixture clears events with original context")


## 胜者选择"不恢复令咒"时令咒不变——选项要有真实分支，不能两个选项都加令咒
func _test_battle_end_decline_restores_nothing() -> void:
	_place(MapData.miyama, 0, 0)
	_place(MapData.miyama, 1, 1)
	GameDataManager.get_player_data(0).power.number = 20
	var pending := _battle_end_choice(3)
	check(pending != null and pending.has_options(), "decline case gets the same options effect")
	check(EffectManager.submit_option_choice(pending, [1]), "choosing decline is accepted")
	check(GameDataManager.get_player_data(0).command_spell_count.number == 3, "decline option restores nothing")
	check(EventResolver.new().clear_all(fixture_context).ok, "fixture clears events with original context")

## AI 必须默认恢复令咒：魔力为 0 的 AI 也不该放弃这个零成本收益
## （原来的"魔力≥1"门槛会让它连选项都不看就放弃）
func _test_ai_defaults_to_restore_seal() -> void:
	var ui = load("res://assets/scenes/game_scene/tactical_board_ui.tscn").instantiate()
	get_tree().root.add_child(ui)
	await get_tree().process_frame
	ui.set_process(false)
	_setup()
	_place(MapData.miyama, 0, 0)
	_place(MapData.miyama, 1, 1)
	GameDataManager.get_player_data(0).power.number = 20
	GameDataManager.get_player_data(0).magic.number = 0
	var pending := _battle_end_choice(0)
	check(pending != null, "ai case queues the seal choice")
	if pending != null:
		ui._resolve_bot_active_effect(pending, 0)
	check(GameDataManager.get_player_data(0).command_spell_count.number == 1, "ai defaults to restoring the seal even at zero magic")
	check(EventResolver.new().clear_all(fixture_context).ok, "fixture clears events with original context")
	ui.queue_free()

## 摆好一场真实战斗并挂上「遏制第三方威胁」，返回结算后排队给胜者的那个待决效果
func _battle_end_choice(winner_spells:int = 0) -> BaseEffect:
	GameDataManager.get_player_data(0).command_spell_count.number = winner_spells
	# 走真实挂载链路：克隆模板 → 挂到战区 → 登记效果
	var template = null
	for card in LoadEvent.events:
		if card._name == "contain_third_party":
			template = card
	var event = _runtime_template(template) as BaseEvent
	check(event != null, "battle event fixture clones the trusted template into runtime")
	if event == null:
		return null
	AddMapAreaEvents.new().exec(MapData.miyama, event)
	check(EventResolver.new().register_entered(event, fixture_context), "fixture registers event with original context")
	BattleResolver.new(fixture_context).exec([0, 1])
	return EffectManager.waiting_effect

func _test_invalid_origin_does_not_spend_spell() -> void:
	_place(MapData.magic_workshop, 0, 0)
	var data:Dictionary = GameDataManager.get_player_data(0)
	var spells_before:int = data.command_spell_count.number
	var origin:BaseLocation = data.location
	var effect := _command_effect()
	check(effect != null and not EffectManager.is_option_available(effect, 2), "command move rejects a workshop origin before payment")
	check(data.command_spell_count.number == spells_before, "invalid command move origin spends no command spell")
	check(data.location == origin, "invalid command move origin does not relocate")


## 令咒的两项界面要求，必须在挂了真实界面的场景里验：
## ① 选中"移动"后要告诉玩家下一步该点哪里（只验引擎有等待状态是不够的）；
## ② 令咒公布要报出选中的是哪一项，并且其他玩家也看得到（只推给触发者＝没公布）。
func _test_move_tip_and_announcement() -> void:
	var ui = load("res://assets/scenes/game_scene/tactical_board_ui.tscn").instantiate()
	get_tree().root.add_child(ui)
	await get_tree().process_frame
	ui.set_process(false)
	ui._local_player_id = 0
	# 界面实例化会跑一次 GameStart，必须再 _setup() 把玩家数据换成测试夹具
	_setup()
	_place(MapData.miyama, 0, 0)
	EffectManager.pop_messages(0)
	EffectManager.pop_messages(1)
	var effect := _command_effect()
	check(effect != null and _choose(effect, 2), "move choice opens the location wait")
	ui._refresh_pending_input_tip()
	ui._refresh_clickable_strength()
	var tip := ui.get_node_or_null("Bottom_PlayerDock/TacticalDeskLayout/Section_PlayBattleZone/VBox/ZoneTip") as Label
	check(tip != null and tip.text.begins_with("请点击要移动到"), "move choice shows an operation tip")
	# 选了移动后，有合法落点的战区必须亮金框提示（呼吸边框 visible=true）。
	# 以前直接落入常规移动判据，把令咒移动错判成交战/单向无法操作，导致金框不亮
	var ws_glow := ui.area_workshop.get_node_or_null("ClickableGlow") as Control if ui.area_workshop != null else null
	check(ws_glow != null and ws_glow.visible, "areas with legal target slots glow during command move")
	var before_spells:int = GameDataManager.get_player_data(0).command_spell_count.number
	check(EffectManager.submit_location_selection(effect, MapData.magic_workshop0), "move location is accepted")
	check(GameDataManager.get_player_data(0).command_spell_count.number == before_spells - 1, "accepted move spends the command spell")
	# 令咒耗尽后：卡位盖纯灰半透明遮罩，一眼看出没有剩余令咒
	GameDataManager.get_player_data(0).command_spell_count.number = 0
	ui._refresh_command_spell_action()
	var cs_node := ui.get_node_or_null(ui.COMMAND_SPELL_CARD_PATH) as Control
	var exh_overlay: Control = cs_node.get_node_or_null("ExhaustedOverlay") if cs_node != null else null
	check(exh_overlay != null and exh_overlay.visible, "exhausted command spell gets gray overlay")
	check(exh_overlay != null and exh_overlay.get_node_or_null("OverlayIcon") == null, "exhausted overlay carries no eye icon")
	# 公布发生在位置提交后的结算里，所以在这里读消息队列
	# 公布要报出选中的选项名，且非触发者也看得到才算"公布"。
	# 消息队列取走即移除，所以这里只对非触发者取一次消息来验
	var other:Array = EffectManager.pop_effect_results(1)
	var joined:String = "\n".join(other)
	check(joined.contains("移动"), "announcement names the chosen option")
	check(not other.is_empty(), "announcement is visible to every player")
	get_tree().root.remove_child(ui)
	ui.free()
