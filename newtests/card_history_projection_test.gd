extends Node

const Builder = preload("res://scripts/match/view_builder.gd")
const Mirror = preload("res://scripts/match/view_mirror.gd")
const CostOperation = preload("res://scripts/system/operations/EditCardCost.gd")
const PowerOperation = preload("res://scripts/system/operations/EditCardPower.gd")
const AttributesOperation = preload("res://scripts/system/operations/EditCardAttributes.gd")

var checks: int = 0
var failures: Array[String] = []
var builder: MatchViewBuilder
var mirror: MatchViewMirror
var card: BaseAttack
var skill: BaseSkill
var data: Dictionary
var other: Dictionary

func check(value: bool, label: String) -> void:
	checks += 1
	print("CHECK ", label, " ", value)
	if not value: failures.append(label)

func _ready() -> void:
	get_tree().create_timer(180.0).timeout.connect(func():
		failures.append("180s watchdog")
		finish())
	call_deferred("run")

func finish() -> void:
	print("RESULT ", JSON.stringify({"suite":"card_history_projection", "checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)

func player(view: Dictionary, id: int) -> Dictionary:
	for entry in view.players:
		if entry.id == id: return entry
	return {}

func transmitted(view: Dictionary) -> Dictionary:
	# 真实 Variant 编解码，不假造网络返回；跨进程传输另验。
	return bytes_to_var(var_to_bytes(view))

func accept(view: Dictionary, label: String) -> Dictionary:
	check(mirror.accept(transmitted(view)), label)
	return mirror.read()

func reject(view: Dictionary, label: String) -> void:
	var receiver = Mirror.new()
	receiver.reset(view.observer)
	check(not receiver.accept(transmitted(view)), label)
	check(receiver.read().is_empty(), label + " does not install rejected view")

func forged(base: Dictionary, records, zone: String = "hand_cards", owner: int = 0) -> Dictionary:
	var bad := base.duplicate(true)
	player(bad, owner)[zone][0]["modification_history"] = records
	return bad

func run() -> void:
	EffectManager.reset_runtime()
	GameProgress.reset_progress()
	GameLog.reset()
	GameData.player_data_library.clear()
	data = GameData.new_player_data()
	other = GameData.new_player_data()
	GameData.player_data_library[0] = data
	GameData.player_data_library[1] = other
	GameProgress.current_phase_index = 2
	GameProgress.current_player_id = 0
	GameProgress.current_round = 1
	card = BaseAttack.new("真实历史[b]", "", [], BaseNumber.new(2), BaseNumber.new(3))
	skill = BaseSkill.new("觉醒历史", "", [], BaseNumber.new(1), BaseNumber.new(1))
	skill._is_awakened = false
	data.hand_cards.append(card)
	data.master_skills.append(skill)
	builder = Builder.new()
	mirror = Mirror.new()
	mirror.reset(0)
	var empty := builder.build(0)
	accept(empty, "unchanged builder view accepted")
	check(not player(empty, 0).hand_cards[0].has("modification_history"), "unchanged card omits optional history")
	CostOperation.new().exec(BaseNumber.new(2), null, card)
	PowerOperation.new().exec(card, BaseNumber.new(3), null, 0)
	AttributesOperation.new().exec(["literal[b] 1.50"], [], [""], card)
	skill.record_modification("power", "原文[abc] 1.50")
	var records := card.get_modification_details().duplicate(true)
	check(records.size() == 3 and card._cost.number == 4 and card._power.number == 6, "real operations modify rules and record history")
	var own := builder.build(0)
	var installed := accept(own, "authorized builder history accepted by Mirror")
	check(player(own, 0).hand_cards[0].get("modification_history") == records, "builder emits exact real history in original order")
	check(player(installed, 0).hand_cards[0].get("modification_history") == records, "roundtrip preserves exact strings and order")
	check(player(own, 0).held_cards[0].card.get("modification_history") == records, "held wrapper carries authorized exact history")
	check(not player(own, 0).master_skills[0].has("modification_history"), "unawakened skill omits history")
	check(not builder.card_view(card, true).has("modification_history"), "own boolean alone grants no history")
	check(not builder.choice_cards([card], 0)[0].has("modification_history"), "mixed candidate prompt intentionally omits history")
	var detached := mirror.read()
	var detached_records = player(detached, 0).hand_cards[0].get("modification_history", [])
	if not detached_records.is_empty(): detached_records[0].detail = "tampered local copy"
	check(player(mirror.read(), 0).hand_cards[0].get("modification_history") == records and card.get_modification_details() == records, "read copies cannot change mirror or authoritative history")
	var legacy := own.duplicate(true)
	for entry in player(legacy, 0).hand_cards: entry.erase("modification_history")
	for entry in player(legacy, 0).held_cards: entry.card.erase("modification_history")
	legacy.seq = own.seq + 1
	accept(legacy, "absent field remains backward compatible")
	check(not player(mirror.read(), 0).hand_cards[0].has("modification_history"), "same ID newer seq missing field revokes cached history")
	# builder序号继续前进，保持接收端既有单调序号规则。
	builder.sequence = legacy.seq
	card.set_concealed(true)
	var hidden := builder.build(0)
	accept(hidden, "own concealed builder view accepted without history")
	check(not player(hidden, 0).hand_cards[0].has("modification_history") and not player(mirror.read(), 0).hand_cards[0].has("modification_history"), "concealing revokes history including installed copy")
	reject(forged(hidden, records), "concealed authorized container rejects injected history")
	card.set_concealed(false)
	skill._is_awakened = true
	var awakened := builder.build(0)
	accept(awakened, "awakened owner snapshot accepted")
	check(player(awakened, 0).master_skills[0].get("modification_history") == skill.get_modification_details(), "awakened actual owner receives skill history")
	check(player(awakened, 0).zone_hand_entries[0].card.get("modification_history") == skill.get_modification_details(), "zone wrapper carries awakened owner history")
	skill._is_awakened = false
	var asleep := builder.build(0)
	accept(asleep, "skill loses awakening accepted with omitted field")
	check(not player(mirror.read(), 0).master_skills[0].has("modification_history"), "loss of awakening revokes history")
	reject(forged(asleep, [], "master_skills"), "invisible skill rejects even empty history")
	# 明置本人牌放入公共可浏览区；他人及观战看到牌面仍无历史。
	data.hand_cards.erase(card)
	data.discard.append(card)
	for observer in [1, -1]:
		var public_view := builder.build(observer)
		mirror.reset(observer)
		accept(public_view, "observer switch installs clean role " + str(observer))
		check(player(public_view, 0).discard[0].visible and not player(public_view, 0).discard[0].has("modification_history"), "publicly visible card does not authorize history role " + str(observer))
		reject(forged(public_view, [], "discard"), "public container rejects empty history role " + str(observer))
	# controller等于观察者不等于当前owner；牌面旧权限不变，历史须拒绝。
	other.controller = 0
	var their_card := BaseAttack.new("受控他人牌", "", [], BaseNumber.new(1), BaseNumber.new(1))
	their_card.record_modification("power", "他人私有历史")
	other.hand_cards.append(their_card)
	var controlled := builder.build(0)
	mirror.reset(0)
	accept(controlled, "controlled entries are excluded by real player-order projection")
	check(player(controlled, 1).is_empty(), "controlled other seat is not projected as independent owner")
	other.controller = -1
	var controlled_alias := builder.build(0)
	var alias_player := player(controlled_alias, 1)
	alias_player.controller = 0
	alias_player.own = true
	alias_player.hand_cards = [builder.card_view(their_card, true)]
	accept(controlled_alias, "legacy controlled-seat card face accepted by receiver")
	reject(forged(controlled_alias, [], "hand_cards", 1), "controlled other seat rejects history")
	# 转移后保留旧source，证明取当前牌区owner而非原来源。
	var old_master := BaseMaster.new("历史归属", "历史归属", "", "", "")
	data.master = old_master
	card.from = old_master
	data.discard.erase(card)
	other.discard.append(card)
	var transferred_old := builder.build(0)
	accept(transferred_old, "old owner accepts transferred card without history")
	check(not player(transferred_old, 1).discard[0].has("modification_history"), "transfer revokes old owner despite stale source")
	var transferred_new := builder.build(1)
	mirror.reset(1)
	accept(transferred_new, "new owner accepts transferred history")
	check(player(transferred_new, 1).discard[0].get("modification_history") == records, "current new owner receives exact existing history")
	other.discard.erase(card)
	var departed := builder.build(1)
	accept(departed, "departed card snapshot accepted")
	check(player(mirror.read(), 1).discard.is_empty(), "departure removes previous card history")
	check(not builder.card_view(card, true).has("modification_history"), "source alone cannot authorize departed card")
	# 为畸形接收用同一真实授权基线，每份独立Mirror不受序号前置门掩盖。
	data.played_cards.append(card)
	var residue_effect := BaseEffect.new("", [], -1, false, true)
	card._effects.append(residue_effect)
	mirror.reset(0)
	var played := builder.build(0)
	accept(played, "real played and residue containers roundtrip")
	check(player(played, 0).played_cards[0].get("modification_history") == records, "played owner receives real history")
	check(player(played, 0).residue_cards[0].get("modification_history") == records, "residue owner receives real history")
	data.played_cards.erase(card)
	card._effects.erase(residue_effect)
	data.out_of_game.attacks.append(card)
	var removed := builder.build(0)
	accept(removed, "real out-of-game container roundtrip")
	check(player(removed, 0).out_of_game_cards[0].get("modification_history") == records, "out-of-game owner receives real history")
	data.out_of_game.attacks.erase(card)
	data.hand_cards.append(card)
	var baseline := builder.build(0)
	for invalid in [null, true, 1, "history", {}, [1], [null], [{"type":"power"}], [{"detail":"x"}], [{"type":1,"detail":"x"}], [{"type":"power","detail":false}], [{"type":"power","detail":"x","source":"leak"}], [{"type":&"power","detail":"x"}]]:
		reject(forged(baseline, invalid), "malformed history type " + str(typeof(invalid)))
	var permitted_empty := forged(baseline, [])
	var fresh = Mirror.new()
	fresh.reset(0)
	check(fresh.accept(transmitted(permitted_empty)), "authorized empty array remains legal")
	var pending := {"kind":"card_choice", "effect":1, "label":"混合候选", "cards":[baseline.players[0].hand_cards[0].id], "required":[], "min":0, "max":1, "allow_cancel":true, "card_views":[baseline.players[0].hand_cards[0].duplicate(true)], "verb":"选择", "secret":false, "confirm_text":"确认"}
	check(not fresh.accepts_pending(pending), "mixed pending private_view true must not grant history")
	pending.card_views[0].erase("modification_history")
	check(fresh.accepts_pending(pending), "legacy mixed pending face remains accepted")
	var held_bad := baseline.duplicate(true)
	player(held_bad, 0).held_cards[0].card.modification_history = [{"type":"power","detail":0}]
	reject(held_bad, "held wrapper uses strict history receiver")
	var extra := baseline.duplicate(true)
	player(extra, 0).hand_cards[0]["has_modifications"] = true
	reject(extra, "no redundant history flag allowed")
	for lane in ["situation", "event_discard", "situation_discard", "source_discard", "events", "special_command_spells"]:
		var public_bad := baseline.duplicate(true)
		var public_card: Dictionary = player(public_bad, 0).hand_cards[0].duplicate(true)
		match lane:
			"situation": public_bad.situation = public_card
			"event_discard", "situation_discard": public_bad[lane] = [public_card]
			"source_discard": public_bad.event_discard_by_source.other = [public_card]
			"events": public_bad.areas.append({"id":builder.ids.id_for(BaseObject.new()), "name":"公开区", "locations":[], "events":[public_card]})
			"special_command_spells": player(public_bad, 0).special_command_spells = [public_card]
		reject(public_bad, "public lane rejects history " + lane)
		public_card.erase("modification_history")
		var public_receiver = Mirror.new()
		public_receiver.reset(0)
		check(public_receiver.accept(transmitted(public_bad)), "public lane face-only control accepted " + lane)
	# 复用真实传输声明及分帧原语，不另设历史条数或字节魔数。
	var transport := MatchEnetTransport.new()
	var long_detail := "原文[long] " + "x".repeat(transport.max_webrtc_frame_bytes)
	card.record_modification("power", long_detail)
	var large := builder.build(0)
	var payload := var_to_bytes(large)
	var encoder := MatchPacketFragments.new()
	var decoder := MatchPacketFragments.new()
	var frames := encoder.encode(payload, transport.max_webrtc_frame_bytes, transport.max_packet_bytes)
	check(payload.size() <= transport.max_packet_bytes and frames.size() > 1, "history uses declared message and real frame budgets")
	var assembled := PackedByteArray()
	for frame in frames:
		var decoded: Dictionary = bytes_to_var(frame)
		assembled = decoder.accept(1, 0, decoded, transport.max_packet_bytes) if decoded.has(MatchPacketFragments.MARKER) else frame
	check(assembled == payload and decoder.pending_bytes() == 0, "real fragments reassemble exact history snapshot")
	var large_receiver = Mirror.new()
	large_receiver.reset(0)
	check(large_receiver.accept(bytes_to_var(assembled)), "long history Mirror roundtrip accepted without truncation")
	var long_records: Array = player(large_receiver.read(), 0).hand_cards[0].get("modification_history", [])
	check(not long_records.is_empty() and long_records.back().detail == long_detail, "long record text is exact")
	var too_large := PackedByteArray()
	too_large.resize(transport.max_packet_bytes + 1)
	check(encoder.encode(too_large, transport.max_webrtc_frame_bytes, transport.max_packet_bytes).is_empty(), "declared transport capacity rejects oversize rather than truncating history")
	# 无本机反查：删除规则库不影响已序列化的合法Mirror接收。
	GameData.player_data_library.clear()
	var independent = Mirror.new()
	independent.reset(0)
	check(independent.accept(transmitted(baseline)), "receiver works without local rule objects")
	check(player(independent.read(), 0).hand_cards[0].get("modification_history") == records, "receiver retains only transmitted authorized history")
	finish()
