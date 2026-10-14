extends Node

## B31 消费者行为探针：只用公开开局、回合推进、operation 和事实查询。
## 不调用 RestoreLocationBenefits，不读写任何下划线字段，不靠 ERROR 日志判红。
const Authority = preload("res://scripts/net/authority/match_authority.gd")
const Selection = preload("res://scripts/net/authority/selection_authority.gd")
const Mode = preload("res://scripts/selection/class_pool_selection.gd")
const RandomStream = preload("res://scripts/match/rule_random.gd")
var checks: int = 0
var failures: Array = []
var authority
var source_context: SessionContext

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
	check(not EffectManager.is_waiting_for_choice(), "开局无未决规则选择")
	source_context = GameStart.startup_context()
	check(SessionGeneration.validate_context(source_context).ok, "前置：保存成功开局的原来源")
	return failures.is_empty()

# 无来源尾参原语由已批准公开 progress 工厂创建真实函数帧；不补当前票。
func progress_value(key: String, parameters: Array) -> Variant:
	var operation: Dictionary = GameProgress.start_progress_operation(key, parameters, source_context)
	var receipt: Dictionary = await GameProgress.wait_progress_operation(operation)
	check(receipt.get("ok", false) and receipt.get("completed", false)
		and is_same(receipt.get("context"), source_context), "前置：真实progress完成回执 " + key)
	return receipt.get("value")

func probe() -> void:
	# 正式地图提供输入；期望基线通过公开查询取得，不硬编码地利数字。
	var loc: BaseLocation = MapData.miyama0
	var untouched: BaseLocation = MapData.miyama1
	var untouched_value: BaseNumber = GetLocationBenefit.new().exec(untouched)
	var untouched_number: int = untouched_value.number
	check(Deploy.new().exec(loc, 0, false, source_context), "公开部署原玩家成功")
	var printed: int = GetPlayerLocationBenefit.new().exec(0)
	check(printed > 0 and (await progress_value("get_effective_location_benefit", [0])) == printed, "正式席位印刷地利与原玩家有效地利一致")
	var modified: int = printed * 2 + 1
	var edited: Variant = await progress_value("edit_location_benefit", [loc, BaseNumber.new(modified)])
	check(edited is BaseNumber and edited == GetLocationBenefit.new().exec(loc), "前置：真实修改回执返回当前原数值对象")
	var current: BaseNumber = GetLocationBenefit.new().exec(loc)
	check(current.number == modified and (await progress_value("get_effective_location_benefit", [0])) == modified, "公开修改确实改变当前及有效地利")
	check(GetPlayerLocationBenefit.new().exec(0) == printed, "修改未污染印刷基线")
	var before_round: int = GameProgress.current_round
	# 对照：同一合法修正，未调用回合尾部；真实帧经过也不能自动恢复。
	await get_tree().process_frame
	check(GameProgress.current_round == before_round and current.number == modified
		and (await progress_value("get_effective_location_benefit", [0])) == modified, "不走回合尾部对照保留修正地利")
	# 直接驱动公开回合接口；不改进度字段、不调用恢复原语。
	await GameProgress.end_round(source_context)
	check(GameProgress.current_round == before_round + 1
		and GameProgress.get_current_phase().get("name") == "prepare", "公开end_round真实完成尾部并进入下一回合")
	check(GetLocation.new().exec(0) == null and GetPlsInLocation.new().exec(loc).is_empty(), "尾部已移走原玩家且席位无归属")
	check(GetLocationBenefit.new().exec(loc) == current, "尾部保留公开地利数值对象身份")
	check(current.number == printed, "回合尾部当前地利恢复印刷基线")
	check(current.number != modified, "尾部正例与未结束回合对照结果不同")
	check(GetLocationBenefit.new().exec(untouched) == untouched_value
		and untouched_value.number == untouched_number, "未修正席位跨尾部保持原值和对象")
	check(Deploy.new().exec(loc, 1, false, source_context), "下一回合另一玩家公开部署同席位")
	check(GetLocation.new().exec(1) == loc and GetPlsInLocation.new().exec(loc) == [1], "下一玩家真实取得席位且原玩家未留占")
	check(GetPlayerLocationBenefit.new().exec(1) == printed, "下一玩家查询印刷基线仍未污染")
	check((await progress_value("get_effective_location_benefit", [1])) == printed, "下一玩家有效地利不继承上回合修正")
	var facts: Array = GameLog.query({"type": "deploy", "actor": 1, "object": loc}, 0)
	check(facts.size() == 1, "本回合部署事实确证下一玩家地利资格")

func run() -> void:
	print("DIAGNOSTIC_USER_PATH ", OS.get_user_data_dir())
	if start(): await probe()
	print("RESULT ", JSON.stringify({"suite": "round_tail_location_benefit", "checks": checks, "failures": failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
