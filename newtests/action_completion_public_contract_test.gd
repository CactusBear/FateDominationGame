extends Node
const FixtureClone = preload("res://newtests/fixture_clone.gd")
# 本局原来源取自 reset_runtime 回执；夹具对 operation 显式传入，不从全局补票。
var ctx: SessionContext = null
func _reset_ctx() -> SessionContext:
	var reset: Dictionary = EffectManager.reset_runtime()
	return reset.get("context") if reset.get("ok", false) else null

# 公开原因查询只检查行动条件；阶段有效性和管线等待仍由生产入口外层检查。
var failures:Array = []
var checks:int = 0
var keepalive:Array = []

func check(ok:bool, label:String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
	print("CHECK ", label, " ", ok)

func _ready() -> void:
	call_deferred("run")

func setup(phase:int) -> void:
	ctx = _reset_ctx()
	GameProgress.reset_progress()
	GameLog.reset()
	GameData.player_data_library.clear()
	for id in range(2):
		var data:Dictionary = GameData.new_player_data()
		data.order.number = id
		data.is_out = false
		data.magic.number = 20
		data.command_spell_count.number = 3
		GameData.player_data_library[id] = data
	GameData.player_id = 0
	EventResolver.new().clear_all()
	SituationResolver.new().clear_all()
	GameProgress.current_round = 1
	GameProgress.current_phase_index = phase
	GameProgress.begin_phase()
	EffectManager.pop_messages(0)

func query_is_readonly(expected:String, label:String, player_id:int = 0) -> void:
	var ids:Array = GameData.player_data_library.keys()
	var facts:Array = GameLog.query({}, null).duplicate()
	var batch:int = EffectManager.time_point_id
	var phase:Array = TimePointChecker.phase_time_points.duplicate()
	var windows:Array = []
	for id in ids:
		var data:Dictionary = GameData.player_data_library[id]
		windows.append([data.current_time_points.duplicate(), data.dynamic_time_points.duplicate(), data.location, data.magic.number])
	var progress:Array = [GameProgress.current_player_id, GameProgress.current_phase_index, GameProgress.current_phase_player_index]
	check(GameProgress.action_completion_block_reason(player_id) == expected and GameProgress.action_completion_block_reason(player_id) == expected, label + " exact repeated reason")
	var after:Array = []
	for id in ids:
		var data:Dictionary = GameData.player_data_library[id]
		after.append([data.current_time_points.duplicate(), data.dynamic_time_points.duplicate(), data.location, data.magic.number])
	check(GameData.player_data_library.keys() == ids and GameLog.query({}, null) == facts and EffectManager.time_point_id == batch and TimePointChecker.phase_time_points == phase and after == windows and progress == [GameProgress.current_player_id, GameProgress.current_phase_index, GameProgress.current_phase_player_index] and EffectManager.pop_messages(0).is_empty(), label + " no players facts timepoints resources progress or messages changed")

func rejection_matches(reason:String, label:String) -> void:
	query_is_readonly(reason, label)
	check(not GameProgress.can_end_current_player_action(), label + " production can_end rejects")
	check(not GameProgress.end_current_player_action() and EffectManager.pop_messages(0) == [reason], label + " actual execution rejects with query reason")

func add_attacks() -> void:
	var data:Dictionary = GameData.player_data_library[0]
	for i in range(2):
		data.hand_cards.append(BaseAttack.new("completion_probe_%d" % i, "", [], BaseNumber.new(0), BaseNumber.new(1)))

func command_effect() -> BaseEffect:
	for template in LoadCommandSpell.command_spells.values():
		if template != null and template._name == "normal_command_spell":
			var card = FixtureClone.clone_template(template, ctx)
			keepalive.append(card)
			GameData.player_data_library[0].out_of_game.command_spell.append(card)
			RegisterObjectEffects.new().exec(card, 0, ctx)
			return card._effects[0]
	return null

func run() -> void:
	setup(1)
	rejection_matches("尚未完成前哨部署", "undeployed outpost")
	query_is_readonly("尚未完成前哨部署", "unknown outpost preserves old null-location reason without creation", 999)
	check(DeployRules.deploy_to_area(DeployRules.deployable_areas()[0], 0) != null, "outpost deploy uses real rule")
	query_is_readonly("", "deployed outpost")
	check(GameProgress.can_end_current_player_action() and GameProgress.end_current_player_action() and GameProgress.current_player_id == 1, "deployed outpost execution advances")

	setup(2)
	add_attacks()
	check(RegularPlay.has_legal_add(0), "minimum fixture has legal cards")
	rejection_matches("尚未满足常规出牌最低要求", "action minimum")
	var effect:BaseEffect = command_effect()
	check(effect != null and EffectManager.can_manual_activate(effect, 0), "declared requirement fixture has usable command spell")
	GameData.player_data_library[0][ActionRules.REQUIREMENT_KEY] = [ActionRules.COMMAND_SPELL_USED]
	rejection_matches("本回合必须使用一枚令咒", "declared action block precedes minimum")
	GameData.player_data_library[0].phase_as = {"action":["outpost", "action"]}
	rejection_matches("尚未完成前哨部署", "outpost check precedes action block")
	GameData.player_data_library[0].phase_as = {}
	GameLog.record(ActionRules.COMMAND_SPELL_USED, 0)
	rejection_matches("尚未满足常规出牌最低要求", "fulfilled declaration leaves minimum block")

	setup(2)
	query_is_readonly("", "no legal cards permits action completion")
	query_is_readonly("", "unknown action preserves old default no-candidates reason without creation", 999)
	check(GameProgress.can_end_current_player_action(), "no legal cards production can_end accepts")
	check(not RegularPlay.completed(0) and GameProgress.end_current_player_action() and RegularPlay.completed(0) and GameProgress.current_player_id == 1, "actual action completion still finalizes and advances")

	setup(0)
	query_is_readonly("", "prepare has no action completion conditions")
	check(GameProgress.can_end_current_player_action() and GameProgress.end_current_player_action() and GameProgress.current_player_id == 1, "prepare completion advances normally")
	GameProgress.reset_progress()
	query_is_readonly("", "unstarted reason is not global eligibility")
	check(not GameProgress.can_end_current_player_action() and not GameProgress.end_current_player_action(), "outer stage checks still reject unstarted lifecycle")

	setup(2)
	effect = command_effect()
	check(effect != null and EffectManager.request_manual_activation(effect, 0) and EffectManager.is_waiting_for_choice(), "real pending input fixture")
	query_is_readonly("", "pending input is outside action condition reason")
	check(not GameProgress.can_end_current_player_action() and not GameProgress.end_current_player_action(), "outer pipeline checks still reject pending input")

	ctx = _reset_ctx()
	setup(1)
	var diagnostic_script = load("res://tests/net_v2_one_round_test.gd")
	check(diagnostic_script != null and diagnostic_script.can_instantiate(), "actual net_v2 diagnostic script parses without running round")
	var diagnostic = diagnostic_script.new()
	diagnostic.session = preload("res://scripts/net/session/lobby_session.gd").new()
	var path:String = "user://action_completion_diagnostic.jsonl"
	diagnostic.trace_file = FileAccess.open(path, FileAccess.WRITE)
	diagnostic.observe(true)
	diagnostic.trace_file.close()
	var row:Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path).strip_edges())
	check(row.get("completion_block") == GameProgress.action_completion_block_reason(0) and row.get("completion_block") == "尚未完成前哨部署", "actual net_v2 diagnostic reads shared public reason in short fixture")
	diagnostic.session.close()
	diagnostic.free()
	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
