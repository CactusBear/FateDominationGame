extends Node

var checks:int = 0
var failures:Array = []
var counts:Dictionary = {"cards":0, "effects":0, "funcs":0}

# 可信角色复制后注入未授权新卡，专门验证 GameStart 必须消费发牌拒绝。
class BrokenFactoryMaster extends BaseMaster:
	func clone_data(context):
		var cloned:BaseMaster = super.clone_data(context)
		var foreign := BaseCard.new()
		foreign._initial_zone = "out_of_game.others"
		foreign._initial_count = 1
		cloned._specials["ATTACKS"] = [foreign]
		return cloned

func check(ok:bool, label:String) -> void:
	checks += 1
	if not ok: failures.append(label)
	print("CHECK ", label, " ", ok)

func fresh() -> SessionContext:
	GameStart.reset()
	return GameData.reset_game_session([0, 1]).context

func effect() -> BaseEffect:
	return LoadHelper.load_effects([{"effect_name":"card-s0", "time_points":[], "priority":0, "is_pure_passive":true, "is_residue":false, "effect_numbers":[], "funcs":[{"func_name":"do_nothing", "parameters":[]}]}], null)[0]

func card() -> BaseCard:
	var result := BaseCard.new()
	result._effects = [effect()]
	result._effects[0].from = result
	result._initial_zone = "out_of_game.others"
	result._initial_count = 2
	var child := BaseCard.new()
	child._effects = [effect()]
	child._effects[0].from = child
	result._attached_cards = [child]
	return result

func children(value) -> Array:
	if value is Array: return value
	if value is Dictionary: return value.values()
	if value is BaseCard: return [value._effects, value._attached_cards]
	if value is BaseMaster: return [value._effects, value._specials, value._upgrade_skill, value._other_things]
	if value is BaseServant: return [value._effects, value._specials]
	if value is BaseEffect:
		var result:Array = [value._funcs]
		for option in value._options:
			result.append(option.get("funcs", []))
			for requirement in option.get("activation_requirements", []):
				result.append(requirement.get("funcs", []))
		return result
	return []

func audit(value, source:SessionContext, template:bool = false) -> void:
	if value is BaseCard or value is BaseEffect or value is BaseFunc:
		var status:Dictionary = SessionGeneration.origin_of(value)
		check(status.reason == &"unbound_origin" if template else status.ok and is_same(status.context.token(), source.token()), "template untouched" if template else "runtime graph same domain")
		if value is BaseCard: counts.cards += 1
		if value is BaseEffect:
			counts.effects += 1
			check(value.runtime_context() == null if template else value.runtime_source_status().ok, "effect runtime binding")
		if value is BaseFunc:
			counts.funcs += 1
			check(value.runtime_context() == null if template else value.runtime_source_status().ok, "function runtime binding")
	for child in children(value): audit(child, source, template)

func deal(id:int, source:SessionContext):
	for method in MasterManager.get_method_list():
		if method.name == "deal_initial_master_cards":
			return MasterManager.callv(method.name, [id, source] if method.args.size() == 2 else [id])
	return null

func role_cases() -> void:
	var source:SessionContext = fresh()
	var master := BaseMaster.new("s0-master", "", "", "", "")
	master._specials = {"ATTACKS":[card()]}
	master._upgrade_skill = [card()]
	master._other_things = [card()]
	var servant := BaseServant.new("s0-servant", "", "", "", "")
	servant._specials = {"SKILLS":[card()]}
	GameData.loaded_masters.append(master)
	GameData.loaded_servants.append(servant)
	var data:Dictionary = GameDataManager.find_player_data(0)
	data.master = master
	data.servant = servant
	check(MasterManager.bind_master_effects(0, source), "no-direct-effect master accepted")
	check(ServantManager.bind_servant_effects(0, source), "no-direct-effect servant accepted")
	check(not is_same(master, data.master) and not is_same(servant, data.servant), "subcards trigger runtime factory")
	audit(data.master, source)
	audit(data.servant, source)
	audit(master, source, true)
	audit(servant, source, true)
	var runtime_master = data.master
	check(MasterManager.bind_master_effects(0, source) and is_same(data.master, runtime_master), "current runtime retains identity")
	var dealt = deal(0, source)
	check(dealt is bool and dealt, "initial cards explicit bool accepted")
	check(data.out_of_game.others.size() == 2, "declared initial count produced")
	for item in data.out_of_game.others:
		check(item is BaseCard, "no null append")
		if item is BaseCard:
			audit(item, source)
			check(EffectManager.effect_pool.has(item._effects[0]), "initial card effect registered")
	var before:int = data.out_of_game.others.size()
	var foreign := BaseMaster.new("foreign", "", "", "", "")
	foreign._specials = {"ATTACKS":[card()]}
	check(not MasterManager.prepare_role_runtime(foreign, source).ok, "unlisted unbound role is not a template")
	runtime_master._specials.ATTACKS.append(card())
	check(not MasterManager.prepare_role_runtime(runtime_master, source).ok, "runtime cannot authorize new unbound child")
	dealt = deal(0, source)
	check(dealt is bool and not dealt and data.out_of_game.others.size() == before, "mixed runtime/unbound deal fails before append")
	runtime_master._specials.ATTACKS.pop_back()
	var next:SessionContext = fresh()
	data = GameDataManager.find_player_data(0)
	data.master = runtime_master
	check(not MasterManager.bind_master_effects(0, next), "stale role children cannot wash with new context")
	dealt = deal(0, next)
	check(dealt is bool and not dealt and data.out_of_game.others.is_empty(), "stale initial cards rejected without append")
	GameData.loaded_masters.append(runtime_master)
	check(not MasterManager.prepare_role_runtime(runtime_master, next).ok, "stale runtime mixed into trusted pool still rejected")
	check(not MasterManager.bind_master_effects(0, source), "old action context refuses")
	check(not MasterManager.bind_master_effects(999, next), "unknown player refuses")

func bare_card_cases() -> void:
	var source:SessionContext = fresh()
	var master := BaseMaster.new("s0-bare", "", "", "", "")
	var bare := BaseCard.new()
	bare._initial_zone = "out_of_game.others"
	bare._initial_count = 1
	bare._attached_cards = [BaseCard.new()]
	master._specials = {"ATTACKS":[bare]}
	GameData.loaded_masters.append(master)
	var data:Dictionary = GameDataManager.find_player_data(0)
	data.master = master
	var dealt = deal(0, source)
	check(dealt is bool and dealt and data.out_of_game.others.size() == 1, "trusted initial template factory works before role binding")
	for item in data.out_of_game.others: audit(item, source)
	check(MasterManager.bind_master_effects(0, source), "effectless role and child cards accepted")
	check(not is_same(data.master, master), "effectless cards still trigger factory")
	audit(data.master, source)
	audit(master, source, true)
	var stamped:BaseCard = data.master._specials.ATTACKS[0]
	var status:Dictionary = SessionGeneration.origin_of(stamped)
	check(status.ok, "effectless child has original binding")
	if not status.ok: return
	var original_origin:StringName = status.context.origin()
	var next:SessionContext = fresh()
	var other := BaseMaster.new("s0-expired", "", "", "", "")
	other._specials = {"ATTACKS":[stamped]}
	GameData.loaded_masters.append(other)
	check(not MasterManager.prepare_role_runtime(other, next).ok, "expired card inside fresh trusted role rejects")
	check(SessionGeneration.origin_of(stamped).reason == &"stale_session", "expired card stays expired after factory refusal")
	check(original_origin != &"", "expired-card fixture had real original origin")
	var unknown = deal(999, next)
	check(unknown is bool and not unknown and GameDataManager.find_player_data(999).is_empty(), "initial-deal unknown player does not create data")

func formal_case() -> void:
	GameStart.end_session()
	preload("res://scripts/match/rule_random.gd").start_seed(709)
	var started:bool = GameStart.game_start([0, 1])
	print("FORMAL_STATE started=", started, " round=", GameProgress.current_round, " phase=", GameProgress.current_phase_index)
	check(started, "formal GameStart role opening succeeds")
	if started:
		for _frame in range(8): await get_tree().process_frame
		check(GameProgress.current_round == 1, "formal startup reaches real first round")
		var source:SessionContext = SessionGeneration.derive_context(SessionGeneration.current_token().token, &"s0.formal-audit").context
		for id in [0, 1]:
			var data:Dictionary = GameDataManager.find_player_data(id)
			check(data.master is BaseMaster and data.servant is BaseServant, "formal roles present")
			audit(data.master, source)
			audit(data.servant, source)
			audit(data.out_of_game, source)
			audit(data.deck, source)
			audit(data.hand_cards, source)
		for role in GameData.loaded_masters + GameData.loaded_servants: audit(role, source, true)
		for spell in LoadCommandSpell.command_spells.values(): audit(spell, source, true)
	GameStart.end_session()

func startup_refusal() -> void:
	var broken := BrokenFactoryMaster.new("s0-broken", "", "", "", "")
	GameData.loaded_masters = [broken]
	GameData.loaded_servants = []
	preload("res://scripts/match/rule_random.gd").start_seed(709)
	var started:bool = GameStart.game_start([0, 1])
	check(not started and not GameStart._started, "GameStart consumes initial-deal refusal")
	check(not SessionGeneration.current_token().ok, "initial-deal refusal closes startup domain")
	check(GameDataManager.find_player_data(0).out_of_game.others.is_empty(), "initial-deal refusal appends nothing")
	check(GameProgress.current_round == 0, "initial-deal refusal prevents progress")
	GameStart.end_session()

func _ready() -> void: call_deferred("run")
func run() -> void:
	print("ENV ", OS.get_user_data_dir())
	role_cases()
	bare_card_cases()
	if not OS.get_cmdline_user_args().has("unit"):
		await formal_case()
	else:
		GameStart.end_session()
	startup_refusal()
	GameData.release_game_objects()
	print("RESULT ", JSON.stringify({"suite":"card_s0_role_startup", "checks":checks, "failures":failures, "counts":counts}))
	get_tree().quit(0 if failures.is_empty() else 1)
