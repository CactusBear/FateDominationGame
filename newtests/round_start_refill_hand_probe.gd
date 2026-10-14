extends Node

## B31 补牌消费者行为探针：正式开局、公开搬牌制造缺口、真实回合尾部进入新回合。
## 不直接调用 RefillHand，不读写私有字段，不以引擎 ERROR 或路由接线判红。
const Authority = preload("res://scripts/net/authority/match_authority.gd")
const Selection = preload("res://scripts/net/authority/selection_authority.gd")
const Mode = preload("res://scripts/selection/class_pool_selection.gd")
const RandomStream = preload("res://scripts/match/rule_random.gd")
var checks: int = 0
var failures: Array = []
var authority

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
	return failures.is_empty()

func probe() -> void:
	# 即使第一回合补牌站点被跳过，也由独立公开抽牌入口建立相同合法前置，
	# 避免把开局前置失败冒充本次第二回合消费者断言的敏感性。
	for id in [0, 1]:
		var cards: Array = GetPlayerHandCards.new().exec(id)
		var pile: Array = GetPlayerDeck.new().exec(id)
		var target: int = GameData.player_hand_limit(id).number
		for unused in range(maxi(0, target - cards.size())):
			if pile.is_empty(): break
			DrawCardFromPlDeckToHand.new().exec(0, id)
	var hand: Array = GetPlayerHandCards.new().exec(0)
	var deck: Array = GetPlayerDeck.new().exec(0)
	var control_hand: Array = GetPlayerHandCards.new().exec(1)
	var control_deck: Array = GetPlayerDeck.new().exec(1)
	var limit: int = GameData.player_hand_limit(0).number
	check(limit >= 2 and hand.size() == limit
		and control_hand.size() == GameData.player_hand_limit(1).number, "公开抽牌建立两名满手牌合法前置")
	if not failures.is_empty(): return
	var moved: Array = hand.slice(0, 2)
	for card in moved:
		DrawCardByCard.new().exec(card, hand, deck, 0)
	var hand_before: Array = hand.duplicate()
	var deck_before: Array = deck.duplicate()
	var control_hand_before: Array = control_hand.duplicate()
	var control_deck_before: Array = control_deck.duplicate()
	var expected_draws: Array = deck_before.slice(0, 2)
	var before_round: int = GameProgress.current_round
	check(hand.size() == limit - 2 and deck.size() >= 2
		and deck.has(moved[0]) and deck.has(moved[1]), "公开搬牌真实制造两张手牌缺口且牌堆可补足")
	# 无回合边界对照：真实帧不会自行补牌，使用同一对象图、同一缺口。
	var old_refill_count: int = GameLog.query({"type": "refill_hand", "actor": 0}, 0).size()
	await get_tree().process_frame
	check(GameProgress.current_round == before_round and hand == hand_before and deck == deck_before,
		"不推进回合对照保留手牌缺口和牌堆")
	check(GameLog.query({"type": "refill_hand", "actor": 0}, 0).size() == old_refill_count,
		"不推进回合对照没有新补牌完成事实")
	await GameProgress.end_round()
	check(GameProgress.current_round == before_round + 1
		and GameProgress.get_current_phase().get("name") == "prepare"
		and not EffectManager.is_waiting_for_choice(), "真实回合尾部经start_round补牌后进入准备阶段")
	check(hand.size() == limit and hand.size() - hand_before.size() == 2, "新回合缺口玩家手牌真实补足两张到上限")
	check(deck.size() == deck_before.size() - 2 and deck == deck_before.slice(2), "新回合缺口玩家牌堆真实减少且仅移走顶部两张")
	check(hand == hand_before + expected_draws and not deck.has(expected_draws[0])
		and not deck.has(expected_draws[1]) and not control_hand.has(expected_draws[0])
		and not control_hand.has(expected_draws[1]), "补入卡牌按牌堆次序进入原玩家手牌且不串归属")
	check(hand != hand_before and deck != deck_before, "真实补牌与不推进回合对照业务结果不同")
	var facts: Array = GameLog.query({"type": "refill_hand", "actor": 0}, 0)
	check(facts.size() == 1 and facts[0].get("data", {}) == {
		"limit": limit, "drawn": 2, "hand_before": hand_before.size(), "deck_before": deck_before.size()},
		"缺口玩家补牌完成事实准确记录上限和前后业务差值")
	var draws: Array = GameLog.query({"type": "draw", "actor": 0}, 0)
	check(draws.size() == 2 and draws[0].get("object") == expected_draws[0]
		and draws[1].get("object") == expected_draws[1], "公开抽牌事实逐索引确证原玩家和顶部卡牌次序")
	# 同一真实回合的满手牌对照：消费者被调用，但不满足实际抽牌条件。
	check(control_hand == control_hand_before and control_deck == control_deck_before,
		"满手牌玩家对照跨新回合不抽牌且牌堆手牌均不变")
	var control_facts: Array = GameLog.query({"type": "refill_hand", "actor": 1}, 0)
	check(control_facts.size() == 1 and control_facts[0].get("data", {}) == {
		"limit": GameData.player_hand_limit(1).number, "drawn": 0,
		"hand_before": control_hand_before.size(), "deck_before": control_deck_before.size()}
		and GameLog.query({"type": "draw", "actor": 1}, 0).is_empty(),
		"满手牌玩家对照完成事实为零张且没有抽牌事实")

func run() -> void:
	print("DIAGNOSTIC_USER_PATH ", OS.get_user_data_dir())
	if start(): await probe()
	print("RESULT ", JSON.stringify({"suite": "round_start_refill_hand", "checks": checks, "failures": failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
