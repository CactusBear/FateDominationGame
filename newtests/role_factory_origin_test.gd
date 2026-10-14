extends Node

var checks:int = 0
var failures:Array = []
var failure_role:BaseObject
var seen:Dictionary = {}

class SpellRegistrationConflict extends BaseEffect:
	var source:SessionContext
	var report:Dictionary
	func clone_data(context):
		var cloned:BaseEffect = super.clone_data(context)
		var binding:Dictionary = SessionGeneration.bind_origin(cloned, source.token(), &"role-origin.spell-clone")
		report.bound = binding.ok and cloned.bind_runtime_context(binding.context)
		report.registered = EffectManager.register_effects([cloned], 1)
		report.runtime = cloned
		return cloned

class RegistrationObserver extends RefCounted:
	var host:Node
	func _init(owner:Node): host = owner
	func _notification(what:int):
		if what == NOTIFICATION_PREDELETE: host.prepare_registration_failure()

func check(ok:bool, label:String) -> void:
	checks += 1
	if not ok: failures.append(label)
	print("CHECK ", label, " ", ok)

# 原 ABI 只有一个参数；仍调用真实旧入口并把 void 当不满足 bool 契约，避免解析错误冒充 RED。
func bind(manager:Node, method:String, id:int, source:Variant = null) -> Variant:
	for descriptor:Dictionary in manager.get_method_list():
		if descriptor.name == method:
			return manager.callv(method, [id, source] if descriptor.args.size() >= 2 else [id])
	return null

func rejected(value:Variant) -> bool:
	return value is bool and not value

func accepted(value:Variant) -> bool:
	return value is bool and value

func template_effect() -> BaseEffect:
	return LoadHelper.load_effects([{"effect_name":"role-origin", "time_points":[], "priority":0, "is_pure_passive":true, "is_residue":false, "effect_numbers":[], "funcs":[{"func_name":"do_nothing", "parameters":[]}]}], null)[0]

func reset_fixture() -> SessionContext:
	GameStart.reset()
	return GameData.reset_game_session([0, 1]).context

func fixture_role(kind:String) -> BaseObject:
	var role:BaseObject = BaseMaster.new("role-origin-master", "", "", "", "") if kind == "master" else BaseServant.new("role-origin-servant", "", "", "", "")
	role._effects = [template_effect()]
	role._effects[0].from = role
	# 创建侧加入显式加载池；S0 内部 configure_template 仅授权这个根 identity。
	var pool:Array = GameData.loaded_masters if kind == "master" else GameData.loaded_servants
	pool.append(role)
	GameDataManager.find_player_data(0)[kind] = role
	return role

func manager_cases(kind:String, manager:Node, method:String) -> void:
	var source:SessionContext = reset_fixture()
	var role:BaseObject = fixture_role(kind)
	var effect:BaseEffect = role._effects[0]
	check(rejected(bind(manager, method, 0)), kind + " missing origin rejected as bool")
	check(effect.runtime_context() == null and not EffectManager.effect_pool.has(effect), kind + " refusal leaves template unbound")
	check(rejected(bind(manager, method, 0, SessionContext.new(source.token(), &"forged"))), kind + " unissued context rejected")
	var next:SessionContext = reset_fixture()
	GameDataManager.find_player_data(0)[kind] = role
	check(rejected(bind(manager, method, 0, source)), kind + " old context rejected")
	check(rejected(bind(manager, method, 999, next)) and GameDataManager.find_player_data(999).is_empty(), kind + " unknown player refuses without creating data")
	check(accepted(bind(manager, method, 0, next)), kind + " same-session template factory registers")
	var runtime:BaseObject = GameDataManager.find_player_data(0)[kind]
	var current:BaseEffect = runtime._effects[0]
	check(not is_same(current, effect) and effect.runtime_context() == null, kind + " runtime distinct and template stays unbound")
	check(current.runtime_source_status().ok and is_same(current.runtime_context().token(), next.token()) and EffectManager.effect_pool.has(current), kind + " real effect source and pool current")
	check(current._funcs[0].runtime_source_status(current).ok, kind + " runtime function inherits explicit domain")
	check(is_same(current.from, runtime), kind + " effect owner points to runtime role")
	check(accepted(bind(manager, method, 0, next)), kind + " existing current runtime can register again")
	var newer:SessionContext = reset_fixture()
	GameDataManager.find_player_data(0)[kind] = runtime
	check(rejected(bind(manager, method, 0, newer)), kind + " stale runtime cannot be washed by fresh context")
	check(not current.runtime_source_status().ok, kind + " refused stale retains old origin")

func spell_cases() -> void:
	var source:SessionContext = reset_fixture()
	var data:Dictionary = GameDataManager.find_player_data(0)
	data.master = GameData.loaded_masters[0]
	data.servant = GameData.loaded_servants[0]
	check(rejected(bind(MasterManager, "bind_command_spell_effects", 0)), "spell missing context rejected")
	check(data.out_of_game.command_spell.is_empty(), "spell refusal retains empty holding zone")
	check(accepted(bind(MasterManager, "bind_command_spell_effects", 0, source)), "spell same-session formal template registers")
	var card:BaseCard = data.out_of_game.command_spell.back()
	check(not card._effects.is_empty(), "spell formal effects actually present")
	for effect:BaseEffect in card._effects:
		check(effect.runtime_source_status().ok and EffectManager.effect_pool.has(effect) and is_same(effect.from, card), "spell effect source pool owner current")
		for option:Dictionary in effect._options:
			for f:BaseFunc in option.get("funcs", []):
				check(f.runtime_source_status(effect).ok, "spell option function source current")
	var next:SessionContext = reset_fixture()
	data = GameDataManager.find_player_data(0)
	check(rejected(bind(MasterManager, "bind_command_spell_effects", 0, source)) and data.out_of_game.command_spell.is_empty(), "spell stale context rejected before clone append")
	check(rejected(bind(MasterManager, "bind_command_spell_effects", 999, next)) and GameDataManager.find_player_data(999).is_empty(), "spell unknown player does not create data")

func prepare_registration_failure() -> void:
	var source:SessionContext = SessionGeneration.derive_context(SessionGeneration.current_token().token, &"role-origin.failure").context
	if seen.get("spell_failure", false):
		var template:BaseCard = LoadCommandSpell.get_normal()
		seen.original = template._effects
		var conflict := SpellRegistrationConflict.new("spell-registration-conflict", [], 0, true, false)
		conflict.source = source
		conflict.report = seen
		template._effects = [conflict]
		return
	var effect:BaseEffect = BaseEffect.new("registration-owner-mismatch", [], 0, true, false)
	var bound:Dictionary = SessionGeneration.bind_origin(effect, source.token(), &"role-origin.failure-effect")
	seen.bound = effect.bind_runtime_context(bound.context)
	seen.registered = EffectManager.register_effects([effect], 1)
	seen.effect = effect
	failure_role._effects = [effect]
	effect.from = failure_role

# 负例只迁移 manager 输入；startup 仍使用原模板与原回调，单独记继承红。
func prepare_manager_conflict(kind:String, source:SessionContext) -> BaseObject:
	var template:BaseObject = failure_role
	var prepared:Dictionary = MasterManager.prepare_role_runtime(template, source)
	check(prepared.ok and prepared.object != null, kind + " conflict factory produces legal runtime clone")
	if not prepared.ok:
		return template
	failure_role = prepared.object
	seen.effect = failure_role._effects[0]
	seen.bound = seen.effect.runtime_source_status().ok
	seen.registered = EffectManager.register_effects(failure_role._effects, 1)
	check(not is_same(failure_role, template) and not is_same(seen.effect, template._effects[0]) and is_same(seen.effect.runtime_context().token(), source.token()), kind + " conflict is distinct runtime with original source")
	GameDataManager.find_player_data(0)[kind] = failure_role
	return template

func registration_cases() -> void:
	for kind in ["master", "servant"]:
		var source:SessionContext = reset_fixture()
		failure_role = fixture_role(kind)
		seen.clear()
		prepare_registration_failure()
		var manager:Node = MasterManager if kind == "master" else ServantManager
		var method:String = "bind_master_effects" if kind == "master" else "bind_servant_effects"
		var template:BaseObject = prepare_manager_conflict(kind, source)
		check(seen.bound and seen.registered and seen.effect.runtime_source_status().ok, kind + " real registration failure fixture current")
		check(not EffectManager.register_effects(failure_role._effects, 0), kind + " actual register_effects refuses conflicting owner")
		check(rejected(bind(manager, method, 0, source)), kind + " manager returns real registration false")
		failure_role = template
		reset_fixture()
		seen.clear()
		GameData.loaded_masters = [failure_role] if kind == "master" else []
		GameData.loaded_servants = [failure_role] if kind == "servant" else []
		EffectManager.messages.append(RegistrationObserver.new(self))
		preload("res://scripts/match/rule_random.gd").start_seed(709)
		var result:bool = GameStart.game_start([0, 1])
		check(seen.get("bound", false) and seen.get("registered", false), kind + " startup callback made actual current conflicting registration")
		check(not result and not GameStart._started, kind + " GameStart consumes registration refusal")
		check(not SessionGeneration.current_token().ok, kind + " startup refusal keeps domain closed")
		check(GameProgress.current_round == 0 and GameLog.query({"type":"time_point", "tags":[TimePoints.GAME_START]}, null).is_empty(), kind + " startup refusal has no first dispatch")
		GameStart.end_session()
		failure_role = null
		seen.clear()

func spell_registration_failure_cases() -> void:
	GameStart.end_session()
	var source:SessionContext = reset_fixture()
	seen.clear()
	seen.spell_failure = true
	prepare_registration_failure()
	check(rejected(bind(MasterManager, "bind_command_spell_effects", 0, source)), "spell manager propagates actual registration false")
	check(seen.get("bound", false) and seen.get("registered", false) and seen.runtime.runtime_source_status().ok, "spell conflicting owner created by real registration")
	check(GameDataManager.find_player_data(0).out_of_game.command_spell.is_empty(), "spell registration false never appends card")
	LoadCommandSpell.get_normal()._effects = seen.original
	seen.clear()
	GameStart.end_session()
	reset_fixture()
	GameData.loaded_masters = []
	GameData.loaded_servants = []
	seen.spell_failure = true
	EffectManager.messages.append(RegistrationObserver.new(self))
	preload("res://scripts/match/rule_random.gd").start_seed(709)
	var result:bool = GameStart.game_start([0, 1])
	check(seen.get("bound", false) and seen.get("registered", false), "spell startup reached real current registration conflict")
	check(not result and not GameStart._started, "GameStart consumes command-spell registration false")
	check(not SessionGeneration.current_token().ok, "spell registration refusal closes startup domain")
	check(GameProgress.current_round == 0 and GameLog.query({"type":"time_point", "tags":[TimePoints.GAME_START]}, null).is_empty(), "spell registration refusal has no first dispatch")
	check(GameDataManager.find_player_data(0).out_of_game.command_spell.is_empty(), "spell startup registration failure leaves holding zone empty")
	LoadCommandSpell.get_normal()._effects = seen.original
	seen.clear()
	GameStart.end_session()

func spell_startup_refusal_case() -> void:
	GameStart.end_session()
	var old:SessionContext = reset_fixture()
	var template:BaseCard = LoadCommandSpell.get_normal()
	var original:Array = template._effects
	var stale:BaseEffect = template_effect()
	var binding:Dictionary = SessionGeneration.bind_origin(stale, old.token(), &"role-origin.old-spell")
	check(stale.bind_runtime_context(binding.context), "spell stale-startup fixture bound originally")
	template._effects = [stale]
	GameData.loaded_masters = []
	GameData.loaded_servants = []
	preload("res://scripts/match/rule_random.gd").start_seed(709)
	var result:bool = GameStart.game_start([0, 1])
	check(not result and not GameStart._started, "GameStart consumes command-spell factory refusal")
	check(not SessionGeneration.current_token().ok and not stale.runtime_source_status().ok, "command-spell startup refusal remains closed without washing stale")
	check(GameProgress.current_round == 0 and GameLog.query({"type":"time_point", "tags":[TimePoints.GAME_START]}, null).is_empty(), "command-spell refusal has no first dispatch")
	check(GameDataManager.find_player_data(0).out_of_game.command_spell.is_empty(), "command-spell failure never appends unregistered card")
	template._effects = original
	GameStart.end_session()

func formal_case() -> void:
	GameStart.end_session()
	preload("res://scripts/match/rule_random.gd").start_seed(709)
	check(GameStart.game_start([0, 1]), "formal GameStart accepts explicit role factories")
	for id in [0, 1]:
		var data:Dictionary = GameDataManager.find_player_data(id)
		for role in [data.master, data.servant]:
			for effect:BaseEffect in role._effects:
				check(effect.runtime_source_status().ok and EffectManager.effect_pool.has(effect), "formal role effect has current provenance and real registration")
	GameStart.end_session()

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	manager_cases("master", MasterManager, "bind_master_effects")
	manager_cases("servant", ServantManager, "bind_servant_effects")
	spell_cases()
	registration_cases()
	spell_registration_failure_cases()
	spell_startup_refusal_case()
	formal_case()
	GameStart.end_session()
	GameData.release_game_objects()
	print("RESULT ", JSON.stringify({"suite":"role_factory_origin", "checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
