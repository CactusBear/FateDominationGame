extends Node
# 本局原来源取自 reset_runtime 回执；夹具对 operation 显式传入，不从全局补票。
var ctx: SessionContext = null
func _reset_ctx() -> SessionContext:
	var reset: Dictionary = EffectManager.reset_runtime()
	return reset.get("context") if reset.get("ok", false) else null

# 规则专项：使用真实入口验证默认不透支及整组拒绝回滚。
var checks := 0
var failures: Array = []
var rows: Array = []

func check(ok: bool, label: String) -> void:
	checks += 1
	print("CHECK ", label, " ", ok)
	if not ok: failures.append(label)

func _ready() -> void:
	call_deferred("run")

func setup(spec: Dictionary) -> Dictionary:
	ctx = _reset_ctx()
	GameProgress.reset_progress()
	GameLog.reset()
	GameLog.set_context(1, "action")
	GameProgress.current_round = 1
	GameProgress.current_phase_index = 2
	GameProgress.current_player_id = 0
	GameData.player_data_library.clear()
	var d: Dictionary = GameData.new_player_data()
	GameData.player_data_library[0] = d
	d.is_out = false
	d.magic.number = spec.magic
	d.magic_limit = BaseNumber.new(spec.get("cap", 12))
	# 保持基础规则的两张整组，第二张零费；双牌案例两张均有费用。
	var cards: Array = []
	for i in range(2):
		var price: float = float(spec.cost) if i == 0 or spec.get("both", false) else 0.0
		var card := BaseAttack.new("overdraft_probe_" + str(i), "", [], BaseNumber.new(price), BaseNumber.new(1))
		cards.append(card)
		d.hand_cards.append(card)
		if spec.get("rise", 0) != 0 and (i == 0 or spec.get("both", false)):
			var effect := BaseEffect.new("explicit diagnostic cost delta", [TimePoints.SELF_CARD_COST_CALCULATED], 0, true, true)
			effect._need_activate = false
			effect._source_bound = true
			effect.from = card
			effect._funcs = LoadHelper.load_funcs([{"func_name":"edit_card_cost", "parameters":[BaseNumber.new(spec.rise)], "var_index":-1}], effect)
			card._effects = [effect]
			EffectManager.register_effect(effect, 0)
	MapData.active_situation = null
	for area in MapData.areas:
		area._events.clear()
		area._buffs.clear()
	return {"data":d, "cards":cards}

func observe(spec: Dictionary, single: bool) -> void:
	var f := setup(spec)
	var d: Dictionary = f.data
	var card: BaseAttack = f.cards[0]
	var group_pre := RegularPlay.can_submit_group(0, f.cards, [false,false])
	var quote: float = RegularPlay.cost(card, d)
	check(group_pre == bool(spec.pre), spec.label + " pre-event group gate " + str(single))
	check(d.magic.number == spec.magic and card._cost.number == spec.cost, spec.label + " quote is read-only " + str(single))
	var expected: bool = bool(spec.single if single else spec.group)
	var accepted: bool
	if single:
		# 显式特殊单卡入口：ignore_limit=true、无激活效果；不是默认普通出牌 oracle。
		accepted = PlayAttack.new().exec(card, 0, null, null, true)
	else:
		accepted = RegularPlay.submit_group(0, f.cards, [false,false], false, ctx)
	var event_ran: bool = single or bool(spec.pre)
	var final_cost: float = float(spec.cost) + (float(spec.get("rise", 0)) if event_ran else 0.0)
	var paid: float = final_cost * (2 if spec.get("both", false) and not single else 1)
	var expected_magic: float = float(spec.magic) - (paid if expected else 0.0)
	# 时点后的支付报价与拒绝回滚后保留的卡牌费用不是同一状态。
	var persisted_cost: float = final_cost if single else float(spec.get("group_persisted_cost", final_cost))
	var label: String = spec.label + (" rejected and rolled back" if not single and spec.has("group_persisted_cost") else "")
	check(accepted == expected, label + " actual return " + str(single))
	check(card._cost.number == persisted_cost, label + " actual event final cost " + str(single))
	check(d.magic.number == expected_magic, label + " actual balance " + str(single))
	check(d.played_cards.has(card) == expected and d.hand_cards.has(card) == not expected, label + " actual source/entry " + str(single))
	check(card._is_activating == expected, label + " actual activation " + str(single))
	check(GameLog.query({"type":"play", "actor":0}, 0).size() == (1 if single else 2) * int(expected), label + " actual play log " + str(single))
	check(RegularPlay.completed(0) == (expected and not single), label + " actual group completion " + str(single))
	rows.append({"case":spec.label, "path":"PlayAttack(ignore_limit=true)" if single else "RegularPlay.submit_group", "initial_magic":spec.magic, "cap":spec.get("cap",12), "initial_cost":quote, "pre_event_group_allowed":group_pre, "final_first_cost":card._cost.number, "accepted":accepted, "magic_after":d.magic.number, "entered":d.played_cards.size(), "group_completed":RegularPlay.completed(0), "injected_overcap_state":spec.get("injected",false)})

func run() -> void:
	var specs: Array = [
		{"label":"static exact", "magic":2, "cost":2, "pre":true, "group":true, "single":true},
		{"label":"static short one", "magic":1, "cost":2, "pre":false, "group":false, "single":false},
		{"label":"static cost above cap", "magic":12, "cost":13, "pre":false, "group":false, "single":false},
		{"label":"event exact", "magic":3, "cost":2, "rise":1, "pre":true, "group":true, "single":true},
		{"label":"event short one RED", "magic":2, "cost":2, "rise":1, "pre":true, "group":false, "group_persisted_cost":2, "single":false},
		{"label":"event cost above cap RED", "magic":12, "cost":12, "rise":1, "pre":true, "group":false, "group_persisted_cost":12, "single":false},
		{"label":"injected overcap state path difference", "magic":20, "cap":1, "cost":2, "pre":false, "group":false, "single":true, "injected":true},
		{"label":"two-card aggregate event overflow RED", "magic":12, "cost":6, "rise":1, "both":true, "pre":true, "group":false, "group_persisted_cost":6, "single":true}
	]
	for spec in specs:
		observe(spec, false)
		observe(spec, true)
	var f := setup({"magic":2,"cost":0})
	EditMagic.new().exec(null, BaseNumber.new(-3), 0)
	check(f.data.magic.number == 0, "EditMagic lower bound clamps negative target to zero")
	EditMagic.new().exec(BaseNumber.new(13), null, 0)
	check(f.data.magic.number == 12, "EditMagic upper bound uses declared global cap")
	f.data.magic_limit = BaseNumber.new(16)
	EditMagic.new().exec(BaseNumber.new(17), null, 0)
	check(f.data.magic.number == 16, "EditMagic upper bound respects declared player override")
	check(not f.data.is_magic_immune, "diagnostic payments did not enable explicit immunity exception")
	print("AUDIT_ROWS ", JSON.stringify(rows))
	ctx = _reset_ctx()
	print("RESULT magic_overdraft_declaration checks=", checks, " failures=", JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
