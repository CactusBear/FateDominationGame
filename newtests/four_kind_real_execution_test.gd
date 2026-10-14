extends Node

## 独立正式开局；不构造/改写玩家、阶段、卡牌或效果的运行态。
## 四个用例通过 -- <kind> 分别执行；只有权威提交可以推进测试局面。
const Authority = preload("res://scripts/net/authority/match_authority.gd")
const Selection = preload("res://scripts/net/authority/selection_authority.gd")
const State = preload("res://scripts/match/rule_state.gd")
const RandomStream = preload("res://scripts/match/rule_random.gd")
const PEER := 101
const SEAT := 0
var authority = Authority.new()
var checks := 0
var failures: Array[String] = []
var kind := ""

func check(ok: bool, label: String) -> bool:
	checks += 1
	print("CHECK ", kind, " ", label, " ", ok)
	if not ok: failures.append(label)
	return ok

func _ready() -> void:
	call_deferred("run")

func snapshot() -> Dictionary:
	# 完整声明的规则对象图含资源、牌区、等待、时点、日志及随机流；不含展示提示队列。
	return State.capture_runtime(authority.builder.ids).duplicate(true)

func submit(command: String, args: Dictionary) -> bool:
	var view: Dictionary = authority.view_for(PEER)
	if view.is_empty(): return false
	return authority.submit(PEER, view.seq, command, args)

func refused(command: String, args: Dictionary, label: String) -> void:
	var view: Dictionary = authority.view_for(PEER)
	var before := snapshot()
	var revision: int = authority.current_revision()
	check(not authority.submit(PEER, view.seq, command, args), label + " rejected")
	check(snapshot() == before and authority.current_revision() == revision, label + " rule graph resources facts unchanged")

func stale(command: String, args: Dictionary, sequence: int, label: String) -> void:
	var before := snapshot()
	var revision: int = authority.current_revision()
	for attempt in range(2):
		check(not authority.submit(PEER, sequence, command, args) and authority.error == "视图已过期", label + " stale replay %d rejected" % attempt)
		check(snapshot() == before and authority.current_revision() == revision, label + " replay %d no second settlement" % attempt)

func start() -> bool:
	RandomStream.start_seed(350035)
	var selection = Selection.new()
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LoadHelper.get_data_dir().path_join("selection_modes.json"))).modes[0]
	if not check(selection.setup(load(config.script).new(), {SEAT: PEER}, GameStart.get_masters_can_use(), GameStart.get_servants_can_use(), config), "formal selection setup"):
		return false
	var available: Array = selection.rules.available_masters(SEAT)
	if not check(not available.is_empty(), "formal master candidates"):
		return false
	if not check(selection.choose(PEER, SEAT, available[0]._name), "authenticated selection choose"):
		return false
	if not check(authority.start(selection), "real authority GameStart"):
		return false
	return check(GameProgress.current_player_id == SEAT and not GameDataManager.find_player_data(SEAT).is_empty(), "real seat and phase established")

func reach_outpost() -> bool:
	for step in range(8):
		if GameProgress.is_phase_for(SEAT, "outpost"): return true
		if EffectManager.is_waiting_for_choice():
			print("MISSING_PRECONDITION outpost blocked by ", JSON.stringify(authority.pending_for(PEER)))
			return false
		if not submit("end_action", {}):
			print("MISSING_PRECONDITION phase progression ", authority.error)
			return false
	return false

func reach_action() -> bool:
	if not check(reach_outpost(), "commands reach real outpost"):
		return false
	# 魔术工坊是真实非战场，避免暗置整组被战场明置最低要求阻断。
	if not check(DeployRules.deployable_areas().has(MapData.magic_workshop), "formal workshop deployment candidate"):
		return false
	if not check(submit("deploy", {"area": authority.builder.ids.id_for(MapData.magic_workshop)}), "real deploy command"):
		return false
	for step in range(8):
		if GameProgress.is_phase_for(SEAT, "action"): return true
		if not submit("end_action", {}):
			print("MISSING_PRECONDITION action progression ", authority.error)
			return false
	return false

func concealed_case() -> void:
	if not check(reach_action(), "real action phase"):
		return
	var data: Dictionary = GameDataManager.find_player_data(SEAT)
	var card: BaseAttack
	for candidate in RegularPlay.candidates(SEAT):
		if candidate is BaseAttack and RegularPlay.in_play_zone(data, candidate) and not candidate._is_concealed:
			card = candidate
			break
	if not check(card != null, "real held faceup attack exists"):
		print("MISSING_PRECONDITION faceup BaseAttack in declared play zone")
		return
	var args := {"card": authority.builder.ids.id_for(card), "concealed": true}
	refused("set_concealed", {"card": -42, "concealed": true}, "unknown card")
	var view: Dictionary = authority.view_for(PEER)
	var before := snapshot()
	var magic = data.magic.number
	var power = data.power.number
	var counts_before: bool = CardCountsPower.new().exec(card, SEAT)
	var card_power = card._power.number
	check(authority.submit(PEER, view.seq, "set_concealed", args), "legal flip accepted by real rules")
	check(card._is_concealed and snapshot() != before, "held attack actually concealed")
	var counts_after: bool = CardCountsPower.new().exec(card, SEAT)
	var delta = card_power * (int(counts_after) - int(counts_before))
	check(data.magic.number == magic and data.power.number == power + delta and RegularPlay.in_play_zone(data, card), "declared flip power delta no fee no zone transfer")
	stale("set_concealed", args, view.seq, "same flip")
	stale("set_concealed", {"card":args.card, "concealed":false}, view.seq, "old view cannot undo flip")

func group_case() -> void:
	if not check(reach_action(), "real action phase"):
		return
	var data: Dictionary = GameDataManager.find_player_data(SEAT)
	var cards: Array = []
	var hidden: Array = []
	for candidate in RegularPlay.candidates(SEAT):
		if candidate is BaseAttack and RegularPlay.in_play_zone(data, candidate):
			cards.append(candidate)
			hidden.append(true)
			if cards.size() >= RegularPlay.minimum(SEAT): break
	if not check(RegularPlay.can_submit_group(SEAT, cards, hidden), "declared hidden attack group is legal"):
		print("MISSING_PRECONDITION legal all-hidden formal attack group min=", RegularPlay.minimum(SEAT), " available=", cards.size())
		return
	var card_ids: Array = []
	for card in cards: card_ids.append(authority.builder.ids.id_for(card))
	# 非空、类型正确、身份正确，但不足声明最低数量；真实 submit_group 校验拒绝。
	if check(RegularPlay.minimum(SEAT) > 1, "declared minimum enables genuine rule rejection"):
		refused("play_group", {"cards":[card_ids[0]], "hidden":[true]}, "under declared minimum")
	var args := {"cards":card_ids, "hidden":hidden}
	var view: Dictionary = authority.view_for(PEER)
	var magic = data.magic.number
	var power = data.power.number
	var played: int = data.played_cards.size()
	var log_count: int = RegularPlay.played_count(SEAT)
	check(authority.submit(PEER, view.seq, "play_group", args), "legal group accepted by real submit_group")
	var exact_zones := true
	for card in cards:
		exact_zones = exact_zones and data.played_cards.has(card) and not RegularPlay.in_play_zone(data, card) and card._is_concealed
	check(exact_zones and data.played_cards.size() == played + cards.size(), "exact submitted identities enter played zone once")
	check(data.magic.number == magic and data.power.number == power, "declared hidden group zero fee zero visible power")
	check(RegularPlay.completed(SEAT) and RegularPlay.played_count(SEAT) == log_count + cards.size(), "real play facts and completion recorded")
	stale("play_group", args, view.seq, "group")
	refused("play_group", args, "fresh view cannot play already committed cards")

func end_case() -> void:
	if not check(reach_outpost(), "real outpost without deployment"):
		return
	check(not GameProgress.can_end_current_player_action() and GameDataManager.find_player_data(SEAT).get("location") == null, "declared deployment obligation blocks end")
	refused("end_action", {}, "real unfinished deployment")
	if not check(submit("deploy", {"area":authority.builder.ids.id_for(MapData.magic_workshop)}), "real deployment satisfies obligation"):
		return
	if not check(GameProgress.can_end_current_player_action(), "rules allow completed outpost end"):
		return
	var view: Dictionary = authority.view_for(PEER)
	var before := snapshot()
	var phase: int = GameProgress.current_phase_index
	var round: int = GameProgress.current_round
	var data: Dictionary = GameDataManager.find_player_data(SEAT)
	var magic = data.magic.number
	var location = data.location
	check(authority.submit(PEER, view.seq, "end_action", {}), "real completed outpost end accepted")
	check(snapshot() != before and (GameProgress.current_phase_index != phase or GameProgress.current_round != round), "actual phase advances once")
	check(GameProgress.is_phase_for(SEAT, "action") and data.magic.number == magic and data.location == location, "declared next action phase no duplicate deployment fee")
	stale("end_action", {}, view.seq, "end")

func activate_case() -> void:
	if not check(reach_action(), "real action phase"):
		return
	var effect: BaseEffect
	# 从真实持有令咒实例取效果，不新建效果、登记或伪造窗口。
	for card in GetPlCommandSpellOutGame.new().exec(SEAT):
		for candidate in card._effects:
			if EffectManager.can_manual_activate(candidate, SEAT):
				effect = candidate
				break
	if not check(effect != null and effect.has_options(), "held JSON command spell manually activatable"):
		print("MISSING_PRECONDITION held registered manual command spell at declared action window")
		return
	var eid: int = authority.builder.ids.id_for(effect)
	var args := {"effect":eid}
	refused("activate", {"effect":-42}, "unknown manual effect")
	var data: Dictionary = GameDataManager.find_player_data(SEAT)
	var magic = data.magic.number
	var seals = data.command_spell_count.number
	var view: Dictionary = authority.view_for(PEER)
	check(authority.submit(PEER, view.seq, "activate", args), "real request_manual_activation accepted")
	check(EffectManager.get_pending_active_effect() == effect and authority.pending_for(PEER).get("effect") == eid, "actual pipeline waits on exact held effect")
	check(data.magic.number == magic and data.command_spell_count.number == seals, "activate stage does not prepay declared cost")
	stale("activate", args, view.seq, "activation")
	refused("activate", args, "fresh activation blocked while exact effect pending")
	# 查真实数据声明的增魔选项与数值，而非按文案猜效果。
	var option_index := -1
	for index in range(effect._options.size()):
		if effect._options[index].get("tags", []).has("command_spell_gain_magic"):
			option_index = index
			break
	if not check(option_index >= 0, "JSON declares gain magic option"):
		return
	var declared: Dictionary = effect._options[option_index]
	var number_index: int = declared.funcs[0]._parameters[1].number_index
	var gain = effect.numbers[number_index].number
	var cost: Dictionary = effect._cost
	check(cost.get("type") == "command_spell" and declared.funcs[0]._name == "edit_magic", "resource assertions sourced from JSON declarations")
	var choice := {"effect":eid, "choices":[{"index":option_index,"count":1}]}
	var choice_view: Dictionary = authority.view_for(PEER)
	check(authority.submit(PEER, choice_view.seq, "option_choice", choice), "real option command completes activated effect")
	check(data.magic.number == magic + gain and data.command_spell_count.number == seals - cost.amount, "real declared magic gain and seal payment exactly once")
	check(EffectManager.get_pending_active_effect() != effect, "real activated pending settles")
	stale("option_choice", choice, choice_view.seq, "settled activated option")
	stale("activate", args, view.seq, "old activation after settlement")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	kind = args[0] if not args.is_empty() else ""
	if check(kind in ["set_concealed", "play_group", "end_action", "activate"], "explicit supported case") and start():
		match kind:
			"set_concealed": concealed_case()
			"play_group": group_case()
			"end_action": end_case()
			"activate": activate_case()
	GameStart.end_session()
	print("RESULT ", JSON.stringify({"suite":kind,"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
