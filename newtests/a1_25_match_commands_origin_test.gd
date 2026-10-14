extends Node

const COMMANDS = preload("res://scripts/match/match_commands.gd")
var checks: int = 0
var failures: Array = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
	print("CHECK ", label, " ", ok)

func _ready() -> void:
	call_deferred("run")

func bind_subject(subject: Object, token: SessionToken, origin: StringName) -> Dictionary:
	return SessionGeneration.bind_origin(subject, token, origin)

func run() -> void:
	var commands = COMMANDS.new()
	SessionGeneration.invalidate_generation(&"a1_25_test_reset")
	var generation: Dictionary = SessionGeneration.begin_generation(&"a1_25_test_start")
	check(generation.get("ok", false), "trusted test generation starts")
	if not generation.get("ok", false):
		print("RESULT checks=", checks, " failures=", failures)
		get_tree().quit(1)
		return
	var token: SessionToken = generation.get("token")
	var card: BaseCard = BaseCard.new()
	var card_origin: Dictionary = bind_subject(card, token, &"a1_25_card_creator")
	check(card_origin.get("ok", false), "trusted card creator binds original context")
	var context: SessionContext = card_origin.get("context")
	check(SessionGeneration.validate_context(context).get("ok", false), "bound context validates")

	# 无帧旧调用必须在 operation/getter 前拒绝，且不能翻面。
	var old_no_frame: Variant = commands.set_card_concealed(card, true, 0)
	check(old_no_frame == false, "old no-frame conceal command is rejected")
	check(not card._is_concealed, "no-frame conceal leaves card unchanged")

	# 同局的可信原 context 才能进入 SetCardConcealed，结果原样返回。
	var accepted: Variant = commands.set_card_concealed(card, true, 0, context)
	check(accepted == true and card._is_concealed, "explicit original context reaches conceal operation")

	# 同局另一个合法 context 不能替代卡牌创建时保存的原 context。
	var other_card: BaseCard = BaseCard.new()
	var other_origin: Dictionary = bind_subject(other_card, token, &"a1_25_other_creator")
	var wrong_context: SessionContext = other_origin.get("context")
	card.set_concealed(false)
	var wrong: Variant = commands.set_card_concealed(card, true, 0, wrong_context)
	check(wrong == false and not card._is_concealed, "different object context is rejected")

	# 伪造同形句柄不能通过服务登记；拒绝不触碰玩家库或牌。
	var forged: SessionContext = SessionContext.new(token, &"a1_25_card_creator")
	var forged_result: Variant = commands.set_card_concealed(card, true, 0, forged)
	check(forged_result == false and not card._is_concealed, "forged context is rejected without card mutation")

	# Move 在 source gate 之后才进入 operation；无来源时未知玩家不会被 getter 建库。
	var before_keys: Array = GameData.player_data_library.keys()
	var old_move: Variant = commands.move(1, 777)
	check(old_move == null, "old no-frame move is rejected")
	check(GameData.player_data_library.keys() == before_keys, "rejected move does not create a player")
	var legal_source_move: Variant = commands.move(1, 777, context)
	check(legal_source_move == null, "explicit source reaches move and preserves operation rejection")
	check(GameData.player_data_library.keys() == before_keys, "invalid move target leaves player library unchanged")

	# 选项数量在来源门之前不得预写；过期 context 也不得消费旧效果。
	var effect: BaseEffect = BaseEffect.new("a1_25_effect", [], 0, false, false)
	var effect_origin: Dictionary = bind_subject(effect, token, &"a1_25_effect_creator")
	var effect_context: SessionContext = effect_origin.get("context")
	check(effect.bind_runtime_context(effect_context), "trusted effect stores original context")
	var rejected_quantity: bool = commands.submit_option_choice(effect, {}, {0: 7}, forged)
	check(not rejected_quantity, "wrong selection context is rejected")
	check(effect._option_quantities.is_empty(), "rejected selection does not prewrite quantities")

	SessionGeneration.invalidate_generation(&"a1_25_test_rotate")
	var stale_result: Variant = commands.set_card_concealed(card, true, 0, context)
	check(stale_result == false and not card._is_concealed, "stale delivered command is rejected")
	check(GameData.player_data_library.keys() == before_keys, "stale command has no player-library side effect")

	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)