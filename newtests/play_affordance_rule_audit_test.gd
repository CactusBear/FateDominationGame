extends Node
# 本局原来源取自 reset_runtime 回执；夹具对 operation 显式传入，不从全局补票。
var ctx: SessionContext = null
func _reset_ctx() -> SessionContext:
	var reset: Dictionary = EffectManager.reset_runtime()
	return reset.get("context") if reset.get("ok", false) else null

var checks := 0
var failures: Array = []
var rows: Array = []
var board
var builder
var query
var source

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
	GameProgress.current_phase_index = int(spec.get("phase", 2))
	GameProgress.current_player_id = int(spec.get("actor", 0))
	GameData.player_data_library.clear()
	var d: Dictionary = GameData.new_player_data()
	GameData.player_data_library[0] = d
	d.is_out = bool(spec.get("out", false))
	d.magic.number = spec.get("magic", 2)
	d.play_limit.number = spec.get("limit", 2)
	d.regular_play_min.number = spec.get("minimum", 2)
	d.is_magic_immune = bool(spec.get("immune", false))
	d.ignore_skill_zone_magic_limit = bool(spec.get("ignore_zone", false))
	d.attack_cost_discount.number = spec.get("discount", 0)
	d.phase_as = spec.get("phase_as", {})
	if spec.has("magic_cap"): d.magic_limit = BaseNumber.new(spec.magic_cap)
	MapData.active_situation = null
	for area in MapData.areas:
		area._events.clear()
		area._buffs.clear()
	if spec.get("battlefield", false): d.location = MapData.miyama0
	var card: BaseHandCard
	if spec.get("skill", false):
		card = BaseSkill.new("audit", "", [], BaseNumber.new(spec.get("cost", 2)), BaseNumber.new(1))
		card._is_awakened = bool(spec.get("awakened", true))
	else:
		card = BaseAttack.new("audit", "", [], BaseNumber.new(spec.get("cost", 2)), BaseNumber.new(1))
	card._cost_discount.number = spec.get("card_discount", 0)
	card._need_extra_play = bool(spec.get("extra", false))
	card._is_activating = bool(spec.get("active", false))
	card._play_requirements = spec.get("requirements", [])
	card._attributes = spec.get("attributes", [])
	if spec.get("zone_ignore", false) and card is BaseSkill: card._ignore_limit = true
	match str(spec.get("zone", "hand")):
		"skill": d.servant_skills.append(card)
		"discard": d.discard.append(card)
		"declared_discard":
			d.discard.append(card)
			d.regular_play_zones = ["discard"]
		_: d.hand_cards.append(card)
	if spec.get("already_played", false): d.played_cards.append(card)
	var support := BaseAttack.new("support", "", [], BaseNumber.new(spec.get("support_cost", 0)), BaseNumber.new(1))
	if not spec.get("no_support", false):
		if spec.get("zone") == "declared_discard": d.discard.append(support)
		else: d.hand_cards.append(support)
	if spec.get("forbid", "") != "":
		var buff := BaseBuff.new("audit ban", "")
		buff._is_active = true
		buff._effects = [BaseEffect.new(str(spec.forbid), [], 0, false, true)]
		if spec.forbid == CannotPlayCardsEffect.EFFECT_NAME: d.buffs.append(buff)
		else:
			MapData.miyama._buffs.append(buff)
			if card.has_attribute(Attributes.SPECIAL): d.location = MapData.miyama0
	if spec.get("completed", false): GameLog.record("regular_play", 0, -1, "", null, [], {})
	for i in range(int(spec.get("committed", 0))):
		GameLog.record("play", 0, -1, "", support, [], {"extra":false, "concealed":false, "card_type":"attack"})
	return {"data": d, "card": card, "support": support}

func observe(label: String, spec: Dictionary, expected: Array, pa_expected = null) -> void:
	var f := setup(spec)
	var card = f.card
	var pending: Array = [f.support] if spec.get("pending", false) else []
	var flags: Array = [bool(spec.get("pending_hidden", false))] if not pending.is_empty() else []
	var modes := RegularPlay.pending_modes(0, pending, flags, card)
	var projected: Dictionary = query.preview(0, pending, flags)
	var projected_modes: Array = []
	for entry in projected.get("candidates", []):
		if entry.id == builder.ids.id_for(card): projected_modes = entry.modes
	var group: Dictionary = source.read_group_preview(pending, flags)
	var hint: bool = board._held_card_playable(card, {}, group)
	check(modes == expected, label + " expected modes")
	check(projected_modes == modes, label + " authority preview same modes")
	check(hint == not modes.is_empty(), label + " v2 hint same predicate")
	var before: float = f.data.magic.number
	var executed: Array = []
	# 穷举这个最多两张牌的合法完成组；不是用另一份 UI 规则作 oracle。
	for hidden in [false, true]:
		var found := false
		var groups: Array = []
		var proposed: Array = pending.duplicate(); proposed.append(card)
		var proposed_flags: Array = flags.duplicate(); proposed_flags.append(hidden)
		groups.append({"cards":proposed, "flags":proposed_flags})
		if pending.is_empty() and not spec.get("no_support", false):
			for support_hidden in [false, true]: groups.append({"cards":[card, f.support], "flags":[hidden, support_hidden]})
		var witness: Dictionary = {}
		for candidate in groups:
			if RegularPlay.can_submit_group(0, candidate.cards, candidate.flags):
				found = true
				witness = candidate
				break
		check(found == modes.has(hidden), label + (" hidden" if hidden else " faceup") + " complete-group oracle")
		if found:
			# 提交真实见证，再重建原夹具，以隔离明/暗两次执行。
			var accepted := RegularPlay.submit_group(0, witness.cards, witness.flags, false, ctx)
			check(accepted and f.data.played_cards.has(card) and card._is_concealed == hidden, label + (" hidden" if hidden else " faceup") + " actual execution")
			executed.append(hidden)
			f = setup(spec); card = f.card
			pending = [f.support] if spec.get("pending", false) else []
			flags = [bool(spec.get("pending_hidden", false))] if not pending.is_empty() else []
		else:
			var old_played: Array = f.data.played_cards.duplicate()
			var old_hand: Array = f.data.hand_cards.duplicate()
			var old_discard: Array = f.data.discard.duplicate()
			var old_magic: float = f.data.magic.number
			var old_active: bool = card._is_activating
			var old_hidden: bool = card._is_concealed
			var all_rejected := true
			for candidate in groups:
				if RegularPlay.submit_group(0, candidate.cards, candidate.flags, false, ctx): all_rejected = false
			check(all_rejected, label + (" hidden" if hidden else " faceup") + " actual illegal submissions reject")
			check(f.data.magic.number == old_magic and f.data.played_cards == old_played and f.data.hand_cards == old_hand and f.data.discard == old_discard and card._is_activating == old_active and card._is_concealed == old_hidden, label + (" hidden" if hidden else " faceup") + " rejection has no payment or entry")
	check(f.data.magic.number == before, label + " read-only/rebuilt magic unchanged")
	var pa = null
	if pa_expected != null:
		# ignore_limit=true 但无 activating_eff：保留普通阶段/行动者限制。
		pa = PlayAttack.new().exec(card, 0, null, null, true)
		check(pa == pa_expected, label + " PlayAttack observed contract")
	rows.append({"case":label, "modes":modes, "v2_hint":hint, "executed_modes":executed, "play_attack_ignore_limit":pa})

func run() -> void:
	builder = preload("res://scripts/match/view_builder.gd").new()
	query = MatchSeatQuery.new(builder)
	source = LocalBattleSource.new(0, builder, query)
	# 不进场景树，不触发 board._ready / 窗口 / 回合推进，只调用正式提示函数。
	board = load("res://scripts/game_scene/battle_board_v2.gd").new()
	board._held_action_ids = builder.ids
	observe("magic exact 2", {}, [false,true], true)
	observe("magic short 1", {"magic":1}, [true], false)
	observe("magic zero", {"magic":0}, [true], false)
	observe("discount exact", {"cost":4,"discount":1,"card_discount":1}, [false,true], true)
	observe("discount short", {"cost":5,"discount":1,"card_discount":1}, [true], false)
	observe("discount clamps zero", {"magic":0,"discount":3}, [false,true], true)
	observe("immune bypass cost", {"magic":0,"cost":20,"immune":true}, [false,true], true)
	observe("magic cap exact", {"magic":20,"magic_cap":2}, [false,true], true)
	observe("magic cap short", {"magic":20,"magic_cap":1}, [true], true)
	observe("min magic exact", {"magic":8,"requirements":[{"type":"min_magic","value":8}]}, [false,true], true)
	observe("min magic short", {"magic":7,"requirements":[{"type":"min_magic","value":8}]}, [true], false)
	observe("immune does not bypass min magic", {"magic":7,"immune":true,"requirements":[{"type":"min_magic","value":8}]}, [true], false)
	observe("unknown requirement", {"requirements":[{"type":"future_explicit_type"}]}, [false,true], true)
	observe("extra play prohibited", {"extra":true}, [], false)
	observe("activated prohibited", {"active":true}, [], false)
	observe("already played candidate excluded", {"already_played":true}, [], true)
	observe("undeclared discard excluded", {"zone":"discard"}, [], true)
	observe("declared discard allowed", {"zone":"declared_discard"}, [false,true], true)
	observe("out prohibited", {"out":true}, [], false)
	observe("wrong actor prohibited", {"actor":1}, [], false)
	for phase in [0,1,3]: observe("phase " + str(phase) + " prohibited", {"phase":phase}, [], false)
	observe("effective action in battle", {"phase":3,"phase_as":{"battle":["battle","action"]}}, [false,true], false)
	observe("actual action remapped away", {"phase_as":{"action":[]}}, [], true)
	observe("play limit short", {"limit":1}, [], true)
	observe("no completion support", {"no_support":true}, [], true)
	observe("committed at limit", {"committed":2}, [], true)
	observe("flow completed", {"completed":true}, [], true)
	observe("cannot play buff", {"forbid":CannotPlayCardsEffect.EFFECT_NAME}, [], false)
	observe("noble forbidden", {"attributes":[Attributes.NOBLE_PHANTASM],"forbid":ForbidNoblePhantasmEffect.EFFECT_NAME}, [], false)
	observe("special area forbidden", {"attributes":[Attributes.SPECIAL],"forbid":ForbidSpecialAttackEffect.EFFECT_NAME}, [], false)
	observe("battle second all hidden", {"battlefield":true,"pending":true,"pending_hidden":true}, [false], true)
	observe("battle second after faceup", {"battlefield":true,"pending":true}, [false,true], true)
	observe("nonbattle second all hidden", {"pending":true,"pending_hidden":true}, [false,true], true)
	observe("pending cost exactly", {"pending":true,"magic":3,"support_cost":1}, [false,true], true)
	observe("pending cost short", {"pending":true,"magic":2,"support_cost":1}, [true], true)
	observe("skill zone exact 8", {"skill":true,"zone":"skill","magic":8}, [false])
	observe("skill zone short 7", {"skill":true,"zone":"skill","magic":7}, [])
	observe("skill zone explicit bypass", {"skill":true,"zone":"skill","magic":2,"ignore_zone":true}, [false])
	observe("skill card zone bypass", {"skill":true,"zone":"skill","magic":2,"zone_ignore":true}, [false])
	observe("unawakened skill prohibited", {"skill":true,"awakened":false,"magic":8}, [])
	observe("hand skill no zone threshold", {"skill":true}, [false])
	var f := setup({})
	check(not PlayAttack.new().exec(f.card,0), "PlayAttack default rejects a legal normal card without effect chain")
	f = setup({"phase":3,"actor":1})
	EffectManager.activating_eff = BaseEffect.new("explicit effect driver", [], 0, false, true)
	check(PlayAttack.new().exec(f.card,0,null,null,true), "effect-driven PlayAttack bypasses phase and actor")
	EffectManager.activating_eff = null
	f = setup({"limit":0})
	EffectManager.activating_eff = BaseEffect.new("single card driver", [], 0, false, true)
	check(PlayAttack.new().exec(f.card,0), "PlayAttack default limit guard unreachable with activating effect")
	EffectManager.activating_eff = null
	dynamic_cost_probe(false)
	dynamic_cost_probe(true)
	print("AUDIT_ROWS ", JSON.stringify(rows))
	ctx = _reset_ctx()
	board.free()
	print("RESULT play_affordance_rule_audit checks=", checks, " failures=", JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

func dynamic_cost_probe(single: bool) -> void:
	var f := setup({"minimum":1,"limit":1,"no_support":true})
	var card: BaseHandCard = f.card
	var effect := BaseEffect.new("audit cost increase", [TimePoints.SELF_CARD_COST_CALCULATED], 0, true, true)
	effect._need_activate = false
	effect._source_bound = true
	effect.from = card
	effect._funcs = LoadHelper.load_funcs([{"func_name":"edit_card_cost","parameters":[BaseNumber.new(1)],"var_index":-1}], effect)
	card._effects = [effect]
	EffectManager.register_effect(effect,0)
	var hinted: bool = RegularPlay.pending_modes(0,[],[],card).has(false)
	var accepted: bool
	if single: accepted = PlayAttack.new().exec(card,0,null,null,true)
	else: accepted = RegularPlay.submit_group(0, [card], [false], false, ctx)
	check(hinted and card._cost.number == 3, "cost calculation event actually raises cost " + str(single))
	if single:
		check(not accepted and f.data.magic.number == 2 and f.data.played_cards.is_empty(), "PlayAttack rechecks raised cost and refuses")
	else:
		check(accepted and f.data.magic.number == -1 and f.data.played_cards.has(card), "regular group has no post-event affordability recheck (RED business evidence)")
	rows.append({"case":"dynamic cost single" if single else "dynamic cost group", "hinted_faceup":hinted,"accepted":accepted,"actual_cost":card._cost.number,"magic_after":f.data.magic.number})
