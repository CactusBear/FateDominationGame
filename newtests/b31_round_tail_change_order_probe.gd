extends Node

## B31 :369 的规则消费者探针。只用公开接口，绝不直接调用 ChangePlOrder。
## 不直接写进度/玩家数据、不访问下划线字段、不按日志或 router 判通过。
const OrderObserver = preload("res://newtests/b31_order_number_observer.gd")
const Authority = preload("res://scripts/net/authority/match_authority.gd")
const Selection = preload("res://scripts/net/authority/selection_authority.gd")
const Mode = preload("res://scripts/selection/class_pool_selection.gd")
const RandomStream = preload("res://scripts/match/rule_random.gd")
var checks: int = 0
var failures: Array = []
var authority
# 成功 GameStart 创建边界保存原句柄；后续消费不签票。
var context: SessionContext
const PEERS = [101, 202, 303, 999]

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
	print("CHECK ", label, " ", ok)

func _ready() -> void:
	call_deferred("run")

func start() -> bool:
	RandomStream.start_seed(775041)
	var selection = Selection.new()
	var config: Dictionary = {"regular_classes": ["saber", "assassin", "lancer"],
		"per_class_count": 1, "special_count": 0, "randomize_initial_order": false}
	check(selection.setup(Mode.new(), {0: 101, 1: 202, 2: 303},
		GameStart.get_masters_can_use(), GameStart.get_servants_can_use(), config), "公开三玩家选人建立")
	check(selection.choose(101, 0, "emiya_shirou"), "席位0公开选择御主")
	check(selection.choose(202, 1, "kuzuki_souichirou"), "席位1公开选择御主")
	check(selection.choose(303, 2, "tohsaka_rin"), "席位2公开选择御主")
	authority = Authority.new()
	check(authority.declare_broadcast_confirmation(false), "公开声明无需播报确认")
	check(authority.start(selection), "真实三玩家权威开局: " + authority.error)
	context = GameStart.startup_context()
	check(context != null and SessionGeneration.validate_context(context).ok, "来源前置 成功开局保存原context")
	check(not EffectManager.is_waiting_for_choice(), "开局无未决规则选择")
	return failures.is_empty()

func view() -> Dictionary:
	return authority.view_for(101)

func ids(v: Dictionary) -> Array:
	var result: Array = []
	for player in v.get("players", []):
		result.append(int(player.id))
	return result

func orders(v: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for player in v.get("players", []):
		result[int(player.id)] = player.order
	return result

func out_ids(v: Dictionary) -> Array:
	var result: Array = []
	for player in v.get("players", []):
		if player.is_out:
			result.append(int(player.id))
	return result

func assert_public(expected: Array, actor: int, label: String) -> void:
	for peer in PEERS:
		var v: Dictionary = authority.view_for(peer)
		check(ids(v) == expected and v.get("current_player", -1) == actor,
			label + " 所有观察者可见顺位及行动者 peer=" + str(peer))
	check(GameProgress.get_ordered_player_ids() == expected
		and EffectManager.get_player_order_ids() == expected,
		label + " 两个公开顺位入口与视图一致")
	for i in expected.size():
		check(EffectManager.get_player_order_index(int(expected[i])) == i,
			label + " 公开顺位索引=" + str(i))

func tail(expected: Array, actors: Array, label: String) -> void:
	var before: Dictionary = view()
	var before_ids: Array = ids(before)
	var before_orders: Dictionary = orders(before)
	# 只换入数值相同且运算委托 super 的公开 BaseNumber 子类，记录真实更新次数。
	var observers: Dictionary = {}
	for pid in before_orders:
		var observer = OrderObserver.new(int(before_orders[pid]))
		# 复用正规 progress 工厂；参数保留同一数字对象，无任意 Callable。
		var install: Dictionary = GameProgress.start_progress_operation("set_player_data", ["order", observer, int(pid), context], context)
		var installed: Dictionary = await GameProgress.wait_progress_operation(install, false)
		# SetPlayerData 原ABI返回null，因此同时读回精确目标identity，不把null当成功。
		check(installed.get("ok", false) and is_same(GameDataManager.find_player_data(int(pid)).get("order"), observer),
			"来源前置 " + label + " 正规函数帧安装原观察器 player=" + str(pid))
		observers[pid] = observer
	check(orders(view()) == before_orders, label + " 公开安装被动数字观察器不改变规则值")
	# 对照：真实经过帧而不推进回合，顺位、数字和行动者都必须保持。
	for frame in range(3):
		await get_tree().process_frame
	var idle: Dictionary = view()
	for pid in observers:
		check(observers[pid].deltas.is_empty(), label + " 无尾部对照无任何顺位运算 player=" + str(pid))
	check(ids(idle) == before_ids and orders(idle) == before_orders
		and idle.round == before.round and idle.current_player == before.current_player,
		label + " 无尾部对照不轮转")
	await GameProgress.end_round(context)
	var after: Dictionary = view()
	print("ORDER_TRACE ", JSON.stringify({"case": label, "before": before_ids,
		"after": ids(after), "before_orders": before_orders, "after_orders": orders(after),
		"round_before": before.round, "round_after": after.round, "actor": after.current_player}))
	check(after.round == before.round + 1 and after.phase == "prepare"
		and not after.game_over, label + " 真实end_round只推进一个回合到准备阶段")
	check(ids(after) == expected, label + " 三独立玩家-1恰好轮转一位")
	var after_orders: Dictionary = orders(after)
	for pid in before_orders:
		var old_value: int = int(before_orders[pid])
		var expected_value: int = old_value - 1 if old_value > 0 else 2
		check(after_orders.get(pid, -99) == expected_value,
			label + " 数值-1及0到2回绕 player=" + str(pid))
		var expected_deltas: Array = [-1, 3] if old_value == 0 else [-1]
		print("COUNT_TRACE ", label, " player=", pid, " deltas=", observers[pid].deltas)
		check(observers[pid].deltas == expected_deltas,
			label + " 恰好一次真实-1运算且只做必要回绕 player=" + str(pid))
	assert_public(expected, int(actors[0]), label)
	# 不只看首位：用真实公开行动完成入口读取整个准备阶段的行动序列。
	var observed: Array = []
	for i in actors.size():
		var step: Dictionary = view()
		observed.append(step.current_player)
		check(step.phase == "prepare" and step.current_player == actors[i],
			label + " 准备阶段行动序列索引=" + str(i))
		check(GameProgress.end_current_player_action(context), label + " 公开结束准备行动索引=" + str(i))
	print("ACTOR_TRACE ", JSON.stringify({"case": label, "expected": actors, "observed": observed}))
	var advanced: Dictionary = view()
	check(observed == actors and advanced.phase == "outpost"
		and advanced.current_player == actors[0], label + " 全部行动者依序且下一阶段仍从首个在局者开始")
	check(ids(advanced) == expected and orders(advanced) == after_orders
		and advanced.round == after.round, label + " 完成整个准备阶段不发生第二次轮转")
	for frame in range(3):
		await get_tree().process_frame
	var settled: Dictionary = view()
	for pid in observers:
		var stable_deltas: Array = [-1, 3] if int(before_orders[pid]) == 0 else [-1]
		check(observers[pid].deltas == stable_deltas,
			label + " 后续行动及帧没有隐藏追加轮转 player=" + str(pid))
	check(ids(settled) == expected and orders(settled) == after_orders
		and settled.round == after.round, label + " 后续帧稳定且无追加轮转")

func probe() -> void:
	var original: Array = ids(view())
	check(original == [0, 1, 2] and orders(view()) == {0: 0.0, 1: 1.0, 2: 2.0},
		"初始三独立玩家和独立顺位数字成立")
	check(GameDataManager.get_active_player_ids() == original
		and GameDataManager.get_board_player_ids() == original,
		"初始在局及版图集合仅含三独立玩家")
	assert_public(original, 0, "初始")
	# 三个真实回合尾部，完整周期而非把规则原语当作被测入口。
	await tail([1, 2, 0], [1, 2, 0], "尾部1")
	await tail([2, 0, 1], [2, 0, 1], "尾部2")
	await tail([0, 1, 2], [0, 1, 2], "尾部3")
	check(ids(view()) == original and orders(view()) == {0: 0.0, 1: 1.0, 2: 2.0},
		"三个尾部完成一个完整周期回到原顺位")
	# 公共淘汰原语和公共条目创建原语，禁止手写 is_out/controller/order。
	check(ClimaxResolver.new().eliminate_player(1), "公开淘汰原第二位成功")
	var creation: Dictionary = GameProgress.start_progress_operation("add_player", [0, [], {"player_name": "B31分身对照", "order": 0}, context], context)
	var created: Dictionary = await GameProgress.wait_progress_operation(creation)
	check(created.get("ok", false) and created.get("value") is int and int(created.value) >= 0, "来源前置 公开分身创建真实回执")
	var clone_id: int = int(created.get("value", -1))
	check(not GameDataManager.is_independent(clone_id)
		and GameDataManager.represented_id(clone_id) == 0, "公开分身创建且代表原玩家0")
	check(ids(view()) == original and out_ids(view()) == [1]
		and GameDataManager.get_active_player_ids() == [0, 2], "出局保留独立顺位但不在行动集合")
	check(GameDataManager.get_board_player_ids() == [0, 2, clone_id]
		and not GameProgress.get_ordered_player_ids().has(clone_id), "分身加入版图集合却不占独立顺位")
	await tail([1, 2, 0], [2, 0], "出局分身尾部")
	check(out_ids(view()) == [1] and GameDataManager.get_active_player_ids() == [2, 0],
		"轮转后出局身份保持且在局顺位跳过新首位1")
	check(GameDataManager.get_board_player_ids() == [2, 0, clone_id]
		and not ids(view()).has(clone_id), "轮转后分身仍只在版图集合不占行动顺位")

func run() -> void:
	print("DIAGNOSTIC_USER_PATH ", OS.get_user_data_dir())
	if start():
		await probe()
	print("RESULT checks=", checks, " failures=", JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
