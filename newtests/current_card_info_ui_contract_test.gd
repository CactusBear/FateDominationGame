extends Node

# B08 historical probe restored from session message 165515. All original assertions retained.
# New checks inspect current model declarations -> production builder -> formal v2 binding.
var checks := 0
var failures: Array[String] = []
var text
var legacy
var board
var builder := MatchViewBuilder.new()
var inventory: Array = []
var gaps: Array = []
var finished := false

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
	print("CHECK ", label, " ", ok)

func _ready() -> void:
	call_deferred("run")

func compare_object(obj) -> void:
	check(text.shown_name(obj) == legacy._object_shown_name(obj), "shown_name " + obj._name)
	if obj is BaseCard:
		check(text.card_desc(obj) == legacy._build_card_desc(obj), "card_desc " + obj._name)
		verify_current_card(obj)
	if obj is BaseBuff:
		check(text.token_desc(obj) == legacy._build_token_desc(obj), "token_desc " + obj._name)

func require_item(ok: bool, card: BaseCard, item: String, expected: String = "") -> void:
	var label := card._name + " / " + item
	check(ok, label)
	if not ok:
		gaps.append({"card": card._name, "shown_name": card.get_shown_name(), "script": card.get_script().resource_path, "item": item, "expected": expected, "source_name": card.get_from()._name if card.get_from() is BaseObject else ""})

func verify_current_card(card: BaseCard) -> void:
	var view: Dictionary = builder.card_view(card, true)
	var slot := Control.new()
	board.bind_zoom_for_card(slot, view)
	var desc: String = view.get("description", "")
	var row := {"card": card._name, "shown_name": card.get_shown_name(), "source_name": card.get_from()._name if card.get_from() is BaseObject else "", "visible": view.visible, "concealed": view.concealed, "back_image": view.back_image, "description": desc, "zoom_kind": view.get("zoom_kind", "")}
	inventory.append(row)
	require_item(view.back_image == card._card_back_img, card, "own back matches own declaration", card._card_back_img)
	require_item(not card._card_back_img.is_empty() and LoadHelper.texture_exists(card._card_back_img) and LoadHelper.load_texture(card._card_back_img) != null, card, "declared back exists and loads", card._card_back_img)
	if card is BaseSkill and not card._is_awakened:
		require_item(not view.visible and not view.has("description") and slot.get_meta("zoom_disabled", false), card, "unawakened own face/description forbidden")
	else:
		require_item(view.visible and view.name == card.get_shown_name() and view.image == card._card_img, card, "own name and face exact")
		require_item(desc == text.card_desc(card), card, "builder description exact formatter")
		for prop in ["_cost", "_power", "_score", "_magic", "_benefit"]:
			var value = card.get(prop)
			if value is BaseNumber:
				var expected: String = text.FIELD_LABELS[prop] + "：" + BaseNumber.display_text(value.number)
				require_item(desc.contains(expected), card, "number " + prop, expected)
		var notes = card.get("_shown_notes")
		if notes is Array:
			for note in notes:
				if not str(note).is_empty(): require_item(desc.contains(str(note)), card, "shown_note", str(note))
		var requirements = card.get("_play_requirements")
		if requirements is Array:
			for requirement in requirements:
				if requirement is Dictionary and not str(requirement.get("shown_note", "")).is_empty():
					require_item(desc.contains(str(requirement.shown_note)), card, "play_requirement", str(requirement.shown_note))
		for effect in card._effects:
			if effect is BaseEffect and effect.has_options():
				for option in effect._options:
					var option_text: String = str(option.get("shown_option_name", ""))
					if not option_text.is_empty(): require_item(desc.contains(option_text), card, "effect_option " + effect._name, option_text)
			elif effect is BaseEffect:
				require_item(desc.contains(effect.get_shown_name()), card, "effect " + effect._name, effect.get_shown_name())
		if card.get_zoom_kind() in LoadHelper.ZOOM_KINDS:
			require_item(not slot.get_meta("zoom_disabled", true) and slot.get_meta("zoom_img", "") == (card._card_back_img if card._is_concealed else card._card_img), card, "formal UI image declaration")
			require_item(slot.get_meta("zoom_desc", "") == ("" if card._is_concealed else desc) and slot.get_meta("zoom_title", "") == ("" if card._is_concealed else card.get_shown_name()), card, "formal UI title/description exact")
		else:
			require_item(slot.get_meta("zoom_disabled", false) and not slot.has_meta("zoom_img"), card, "undeclared zoom no guessing")
	var copy: BaseCard = CloneObject.new().exec(card)
	copy._is_concealed = true
	var hidden: Dictionary = builder.card_view(copy, false)
	require_item(not hidden.visible and hidden.back_image == card._card_back_img, card, "public concealed back exact")
	for field in ["name", "image", "kind", "cost", "power", "effects", "description", "zoom_kind"]:
		require_item(not hidden.has(field), card, "public concealed forbids " + field)
	slot.free()

func run() -> void:
	text = load("res://scripts/ui/text/card_desc_text.gd")
	legacy = load("res://scripts/game_scene/tactical_board_ui.gd")
	board = load("res://scripts/game_scene/battle_board_v2.gd").new()
	check(text != null and text.can_instantiate(), "new module compiled")
	if text == null or not text.can_instantiate():
		finish()
		return
	check(text.new() is RefCounted and not text.new() is Node, "RefCounted not Node")
	check(text.ATTACK_CATEGORY_LABELS == legacy.ATTACK_CATEGORY_LABELS, "attack labels identical")
	check(text.FIELD_LABELS == legacy.FIELD_LABELS, "field labels identical")
	check(text.shown_name(null) == legacy._object_shown_name(null), "null shown_name")
	check(text.card_desc(null) == legacy._build_card_desc(null), "null card_desc")
	seed(20261009)
	GameStart.reset()
	check(GameStart.game_start([0, 1, 2, 3, 4, 5, 6]), "seven-seat game starts")
	var cards := 0
	var buffs := 0
	# Clone registration changes GameData.objects; freeze enumeration, not production source.
	var objects: Array = GameData.objects.duplicate()
	for obj in objects:
		compare_object(obj)
		if obj is BaseCard:
			cards += 1
		if obj is BaseBuff:
			buffs += 1
	check(cards > 0 and buffs > 0, "card and buff coverage")
	var owner := BaseBuff.new("B08 owner", "")
	var buff := BaseBuff.new("B08 token", "")
	buff.from = owner
	buff._buff_level.number = 3
	var flat := BaseEffect.new("flat", [])
	flat._shown_name = "普通效果"
	var one := BaseEffect.new("one", [])
	one._shown_name = "选项效果一"
	one._options = [{"shown_option_name": "选项甲"}, {"shown_option_name": ""}, {"shown_option_name": "选项乙"}]
	var two := BaseEffect.new("two", [])
	two._shown_name = "选项效果二"
	two._options = [{"shown_option_name": "选项甲"}]
	var related := BaseEffect.new("related", [])
	related._shown_name = "关联效果"
	owner._effects = [flat, related]
	buff._related_effect_names = ["flat", "related", "missing", "related"]
	for effects in [[], [flat], [one], [one, flat], [one, two, flat]]:
		buff._effects = effects
		check(text.token_desc(buff) == legacy._build_token_desc(buff), "token option/related grouping " + str(effects.size()))
	for level in [0, 1, 2]:
		buff._buff_level.number = level
		check(text.token_desc(buff) == legacy._build_token_desc(buff), "token level " + str(level))
	var unnamed := BaseObject.new()
	unnamed._name = "内部名"
	for shown in ["", "显示名"]:
		unnamed._shown_name = shown
		check(text.shown_name(unnamed) == legacy._object_shown_name(unnamed), "name fallback " + shown)
	print("B08 coverage cards=", cards, " buffs=", buffs, " objects=", objects.size())
	print("CARD_INFO_INVENTORY ", JSON.stringify(inventory))
	print("CARD_INFO_GAPS ", JSON.stringify(gaps))
	board.free()
	GameStart.end_session()
	finish()

func finish() -> void:
	if finished: return
	finished = true
	print("RESULT current_card_info_ui_contract checks=", checks, " failures=", JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
