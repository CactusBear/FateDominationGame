extends Node
# 本局原来源取自 reset_runtime 回执；夹具对 operation 显式传入，不从全局补票。
var ctx: SessionContext = null
func _reset_ctx() -> SessionContext:
	var reset: Dictionary = EffectManager.reset_runtime()
	return reset.get("context") if reset.get("ok", false) else null

var checks := 0
var failures: Array = []
var data: Dictionary
var support: BaseAttack
var card: BaseSkill
var third: BaseAttack
var builder
var query

func check(ok: bool, label: String) -> void:
	checks += 1
	print("CHECK ", label, " ", ok)
	if not ok: failures.append(label)

func _ready() -> void:
	call_deferred("run")

func setup() -> void:
	ctx = _reset_ctx()
	GameProgress.reset_progress()
	GameLog.reset()
	GameLog.set_context(1, "action")
	GameData.player_data_library.clear()
	data = GameData.new_player_data()
	GameData.player_data_library[0] = data
	data.is_out = false
	data.magic.number = 8
	data.regular_play_min.number = 3
	data.play_limit.number = 3
	GameProgress.current_round = 1
	GameProgress.current_phase_index = 2
	GameProgress.current_player_id = 0
	MapData.active_situation = null
	for area in MapData.areas:
		area._events.clear()
		area._buffs.clear()
	support = BaseAttack.new("support", "", [], BaseNumber.new(1), BaseNumber.new(1))
	card = BaseSkill.new("candidate", "", [], BaseNumber.new(2), BaseNumber.new(1))
	third = BaseAttack.new("completion", "", [], BaseNumber.new(0), BaseNumber.new(1))
	data.hand_cards = [support, card, third]
	builder = preload("res://scripts/match/view_builder.gd").new()
	query = MatchSeatQuery.new(builder)

func projected_modes(selected: Array, flags: Array, candidate) -> Array:
	var preview: Dictionary = query.preview(0, selected, flags)
	for entry in preview.get("candidates", []):
		if entry.id == builder.ids.id_for(candidate): return entry.modes
	return []

func complete_exists(selected: Array, flags: Array, candidate) -> bool:
	for candidate_hidden in [false, true]:
		for third_hidden in [false, true]:
			var cards: Array = selected.duplicate()
			var modes: Array = flags.duplicate()
			cards.append(candidate); modes.append(candidate_hidden)
			cards.append(third); modes.append(third_hidden)
			if RegularPlay.can_submit_group(0, cards, modes): return true
	return false

func rejected_prefix(selected: Array, flags: Array, label: String) -> void:
	var magic: float = data.magic.number
	var hand: Array = data.hand_cards.duplicate()
	var history: Array = GameLog.query({}, null, -1).duplicate(true)
	var hidden: bool = support._is_concealed
	check(not complete_exists(selected, flags, card), label + " no complete-group witness")
	check(RegularPlay.pending_modes(0, selected, flags, card).is_empty(), label + " shared modes reject")
	check(projected_modes(selected, flags, card).is_empty(), label + " shared preview rejects candidate")
	check(not RegularPlay.pending_has_legal_add(0, selected, flags), label + " no false legal-add escape")
	var preview: Dictionary = query.preview(0, selected, flags)
	check(not preview.get("can_submit", false), label + " selected prefix cannot submit")
	var proposed: Array = selected.duplicate()
	var proposed_flags: Array = flags.duplicate()
	proposed.append(card); proposed_flags.append(false)
	proposed.append(third); proposed_flags.append(true)
	check(not RegularPlay.submit_group(0, proposed, proposed_flags, false, ctx), label + " actual complete submission rejects")
	check(data.magic.number == magic and data.hand_cards == hand and data.played_cards.is_empty() and support._is_concealed == hidden and GameLog.query({}, null, -1) == history, label + " query has no rule side effects")

func run() -> void:
	# 复用 BACKEND_BOUNDARY 原反例：最低3张、只选1张，同伴资格随后失效。
	setup()
	check(RegularPlay.pending_modes(0, [support], [false], card) == [false], "valid below-minimum prefix stays extendable")
	check(projected_modes([support], [false], card) == [false], "below-minimum preview stays extendable")
	check(not RegularPlay.can_submit_group(0, [support, card], [false, false]) and complete_exists([support], [false], card), "incomplete prefix is not submit-ready but has completion")
	support._need_extra_play = true
	rejected_prefix([support], [false], "selected companion need-extra changed")
	print("BACKEND_BOUNDARY ", JSON.stringify({"minimum":3,"selected_count":1,"selected_companion_need_extra_play":true,"candidate_modes":RegularPlay.pending_modes(0,[support],[false],card),"complete_group_exists":complete_exists([support],[false],card)}))
	setup()
	data.magic.number = 0
	check(RegularPlay.pending_modes(0, [support], [true], card).is_empty(), "candidate own cost still enforced")
	card._cost.number = 0
	rejected_prefix([support], [false], "selected companion resource shortage")
	check(RegularPlay.pending_modes(0, [support], [true], card) == [false], "concealed companion remains free and extendable")
	setup()
	data.hand_cards.erase(support)
	data.servant_skills.append(support)
	rejected_prefix([support], [true], "selected concealed mode no longer in play zone")
	check(RegularPlay.pending_modes(0, [support], [false], card) == [false], "faceup companion uses existing skill-zone threshold")
	setup()
	support._is_activating = true
	rejected_prefix([support], [false], "selected companion activation changed")
	setup()
	card._is_awakened = false
	check(RegularPlay.pending_modes(0, [card], [false], support).is_empty(), "selected skill awakening changed")
	check(projected_modes([card], [false], support).is_empty(), "preview selected skill awakening changed")
	setup()
	support._play_requirements = [{"type":"min_magic", "value":9}]
	rejected_prefix([support], [false], "selected companion requirement changed")
	setup()
	check(RegularPlay.pending_modes(0, [], [], card) == [false], "empty selection retains legal initial candidates")
	var empty: Dictionary = query.preview(0, [], [])
	check(empty.get("ok", false) and not empty.can_submit and empty.mana_cost == 0, "empty preview is valid and not submittable")
	check(RegularPlay.pending_modes(0, [support, support], [false, false], card).is_empty(), "duplicate prefix rejected")
	check(not RegularPlay.can_play_group_prefix(0, [support], []), "mismatched prefix rejected")
	check(not RegularPlay.can_play_group_prefix(0, [null], [false]), "non-card prefix rejected")
	check(RegularPlay.can_play_group_prefix(0, [], []) and RegularPlay.can_play_group_prefix(0, [support], [false]), "prefix query allows empty and below minimum")
	check(not RegularPlay.can_submit_group(0, [], []), "empty group never submits")
	data.magic.number = 0
	data.is_magic_immune = true
	check(RegularPlay.can_play_group_prefix(0, [support], [false]) and RegularPlay.pending_modes(0, [support], [false], card) == [false], "existing magic immunity applies to prefix")
	data.is_magic_immune = false
	check(not RegularPlay.can_play_group_prefix(0, [support], [false]), "prefix insufficient resources reject")
	check(RegularPlay.can_play_group_prefix(0, [support], [false], true), "explicit overdraft remains supported by submit validator")
	data.magic.number = 8
	check(RegularPlay.can_submit_group(0, [support, card, third], [false, false, true]), "complete legal group accepted by predicate")
	check(query.preview(0, [support, card, third], [false, false, true]).can_submit, "complete legal preview agrees")
	check(RegularPlay.submit_group(0, [support, card, third], [false, false, true], false, ctx), "complete legal group executes")
	check(data.played_cards == [support, card, third] and data.magic.number == 5 and RegularPlay.completed(0), "complete group enters pays and finishes")
	setup()
	var ids: Array = GameData.player_data_library.keys()
	GameProgress.current_player_id = 77
	check(RegularPlay.pending_modes(77, [], [], card).is_empty(), "unknown subject modes reject")
	check(not RegularPlay.can_submit_group(77, [card], [false]), "unknown subject submit predicate rejects")
	check(query.preview(77, [], []).is_empty(), "unknown subject preview stays absent")
	check(GameData.player_data_library.keys() == ids, "queries never create unknown player")
	ctx = _reset_ctx()
	print("RESULT group_preview_prefix_validity checks=", checks, " failures=", JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
