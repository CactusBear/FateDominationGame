extends Node

## 仅供 B31 两个消费者探针：公开正式开局、JSON 声明与公开阶段推进。
## 不读取下划线状态；生产规则/路由及其日志都不充当断言替身。
const Authority = preload("res://scripts/net/authority/match_authority.gd")
const Selection = preload("res://scripts/net/authority/selection_authority.gd")
const Mode = preload("res://scripts/selection/class_pool_selection.gd")
const RandomStream = preload("res://scripts/match/rule_random.gd")
var checks: int = 0
var failures: Array = []
var authority
var fixture_context: SessionContext

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
	print("CHECK ", label, " ", ok)

func _ready() -> void:
	call_deferred("run")

func start() -> bool:
	RandomStream.start_seed(775041)
	var selection = Selection.new()
	var config: Dictionary = {"regular_classes": ["saber", "assassin"], "per_class_count": 1,
		"special_count": 0, "randomize_initial_order": false}
	check(selection.setup(Mode.new(), {0: 101, 1: 202},
		GameStart.get_masters_can_use(), GameStart.get_servants_can_use(), config), "公开选人规则建立")
	check(selection.choose(101, 0, "emiya_shirou"), "席位0公开选择御主")
	check(selection.choose(202, 1, "kuzuki_souichirou"), "席位1公开选择御主")
	authority = Authority.new()
	check(authority.declare_broadcast_confirmation(false), "公开声明无播报确认等待")
	check(authority.start(selection), "真实权威开局: " + authority.error)
	fixture_context = GameStart.startup_context()
	check(fixture_context != null and SessionGeneration.validate_context(fixture_context).ok, "PRE 保存成功正式开局的原来源")
	check(not EffectManager.is_waiting_for_choice(), "开局无未决规则选择")
	return failures.is_empty()

func number(value: int) -> Dictionary:
	return {"number": value, "can_change": true, "is_pure_number": true}

func residue_effect() -> Dictionary:
	return {"effect_name": "B31显式残留", "time_points": [], "priority": 0,
		"is_pure_passive": true, "is_residue": true, "effect_numbers": [], "funcs": []}

func attack(name: String, power: int, residue: bool = false) -> BaseAttack:
	return LoadGame.load_attacks([{"attack_name": name, "attack_card_img": "", "attributes": [],
		"cost": number(0), "power": number(power),
		"effects": [residue_effect()] if residue else []}], "", null, [], fixture_context)[0] as BaseAttack

func skill(name: String, power: int) -> BaseSkill:
	return LoadGame.load_skills([{"skill_name": name, "skill_card_img": "", "attributes": [],
		"cost": number(0), "power": number(power), "ignore_limit": true, "effects": []}], "", null, "skill", fixture_context)[0] as BaseSkill

func enter_action() -> void:
	# 正式开局异步尾部必须实际到达；只等待，不改阶段/行动者或补来源。
	for unused in 60:
		if not EffectManager.is_running and not EffectManager.is_waiting_for_choice() and not GameProgress.get_current_phase().is_empty(): break
		await get_tree().process_frame
	check(GameProgress.current_round == 1 and GameProgress.get_current_phase().get("name") == "prepare", "PRE 正式开局实际到达第一准备阶段")
	# 从真实 prepare 经公开 end_phase 前进；不改阶段索引或伪造当前行动者。
	for unused in range(GameProgress.phases.size()):
		if GameProgress.get_current_phase().get("name") == "action": break
		await GameProgress.end_phase(fixture_context)
		var receipt: Dictionary = await GameProgress.wait_progress_state({"ok": true, "completed": true, "context": fixture_context}, fixture_context)
		check(receipt.get("ok", false), "PRE 正式阶段推进完成回执")
		await get_tree().process_frame
	check(GameProgress.get_current_phase().get("name") == "action"
		and GameProgress.current_player_id == 0 and not EffectManager.is_waiting_for_choice(),
		"公开阶段推进到玩家0真实行动阶段")

# 旧原语没有来源尾参时，复用生产声明式 progress 根，绝不手造执行帧。
# 消费公开结束回执；void 原语显式声明不要求非空值，业务效果仍由原断言验证。
func fixture_operation(key: String, parameters: Array, value_required: bool = true) -> Variant:
	var operation: Dictionary = GameProgress.start_progress_operation(key, parameters, fixture_context)
	var receipt: Dictionary = await GameProgress.wait_progress_operation(operation, value_required)
	check(receipt.get("ok", false) and receipt.get("completed", false), "PRE 正式原语结束回执: " + key)
	return receipt.get("value") if receipt.get("ok", false) else null

func fixture_idle() -> void:
	var receipt: Dictionary = await GameProgress.wait_progress_state({"ok": true, "completed": true, "context": fixture_context}, fixture_context)
	check(receipt.get("ok", false) and RegularPlay.completed(0), "PRE 原来源整组出牌真实完成")

func report(suite: String) -> void:
	print("RESULT ", JSON.stringify({"suite": suite, "checks": checks, "failures": failures}))
	get_tree().quit(0 if failures.is_empty() else 1)

func run() -> void:
	report("b31_fixture_only")
