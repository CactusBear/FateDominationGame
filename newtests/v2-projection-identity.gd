extends Node

# 只观察正式工厂与正式展示入口；不替换、补签或变造规则对象 identity。
const Builder = preload("res://scripts/match/view_builder.gd")
const Mirror = preload("res://scripts/match/view_mirror.gd")
var checks: int = 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	print("CHECK ", label, " ", ok)
	if not ok: failures.append(label)

func _ready() -> void:
	call_deferred("run")

func primitive(value: Variant) -> bool:
	if value is Array:
		for item in value:
			if not primitive(item): return false
		return true
	if value is Dictionary:
		for key in value:
			if not primitive(key) or not primitive(value[key]): return false
		return true
	return typeof(value) in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME]

func open_category(board: Control, key: String) -> void:
	if not board.get_node("EventDiscardMenu").visible:
		board.get_node("Piles/EventPile/Open").pressed.emit()
	board.get_node("EventDiscardMenu/Choices/" + key).pressed.emit()
	await get_tree().process_frame

func finish(board: Node) -> void:
	board.queue_free()
	await get_tree().process_frame
	print("RESULT ", JSON.stringify({"suite":"v2-projection-identity", "checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)

func run() -> void:
	var board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	get_tree().root.add_child(board)
	board.set_process(false)
	await get_tree().process_frame
	var source: SessionContext = GameStart.startup_context()
	check(source != null and SessionGeneration.validate_context(source).ok, "PRE formal startup retained original context")
	if source == null:
		await finish(board)
		return
	var refused_clear: Dictionary = EventResolver.new().clear_all()
	check(not refused_clear.ok, "original fixture missing clear context is rejected")
	var refused_clone = CloneObject.new().exec(LoadEvent.events[0])
	check(refused_clone == null, "original fixture bare template clone produces null not runtime card")
	check(EventResolver.new().clear_all(source).ok, "PRE cleanup via original startup source")
	MapData.event_discard.clear()
	board.refresh_all_ui()
	var cards: Array = []
	for area in [MapData.shinto, MapData.miyama, MapData.scout]:
		var factory := CloneContext.new()
		check(factory.configure_template(source, [LoadEvent.events[0]]), "PRE explicit trusted template identity")
		var copied: Dictionary = factory.copy_result(LoadEvent.events[0], source)
		check(copied.ok and copied.object is BaseEvent, "PRE actual runtime event factory")
		if not copied.ok:
			await finish(board)
			return
		var card: BaseEvent = copied.object
		check(SessionGeneration.origin_of(card).ok, "PRE runtime event has real origin")
		AddMapAreaEvents.new().exec(area, card)
		cards.append(card)
	check(EventResolver.new().clear_all(source).ok, "PRE actual event discard publication")
	check(MapData.event_discard.size() == 3, "PRE three actual nonempty discard cards")
	for card in cards:
		check(MapData.event_discard.has(card), "discard preserves true rule object identity")
	var keys := ["Shinto", "Miyama", "Other"]
	for key in keys:
		await open_category(board, key)
		var count: int = board.get_node("CardBrowser/Panel/CardScroll/Row").get_child_count()
		print("CONTRAST cached ", key, " count=", count)
		check(count == 0, "paused board stale cache masks identity predicate " + key)
		board.get_node("CardBrowser/Panel/Close").pressed.emit()
	# 单变量：只调用正式公开刷新，不改卡牌、来源、oracle、UI 或投影实现。
	board.refresh_all_ui()
	var builder = Builder.new()
	var grouped: Dictionary = builder.event_discard_by_source()
	for i in keys.size():
		await open_category(board, keys[i])
		var row: Node = board.get_node("CardBrowser/Panel/CardScroll/Row")
		check(row.get_child_count() == 1, "public refresh reaches one real source card " + keys[i])
		if row.get_child_count() != 1:
			continue
		var projected: Variant = row.get_child(0).get_meta("card")
		check(projected is Dictionary, "formal browser metadata is projection " + keys[i])
		check(not is_same(projected, cards[i]), "negative true object is not projection object " + keys[i])
		var category: String = ["shinto", "miyama", "other"][i]
		check(grouped[category].size() == 1 and builder.ids.object_for(grouped[category][0].id) == cards[i], "source filter stable ID resolves exact original identity " + keys[i])
		check(projected.name == grouped[category][0].name and projected.image == grouped[category][0].image, "formal browser matches declared source face " + keys[i])
		check(primitive(projected) and not projected.has("raw"), "projection contains no rule object " + keys[i])
		print("CONTRAST fresh ", JSON.stringify({"category":keys[i], "count":row.get_child_count(), "metadata_type":type_string(typeof(projected)), "true_type":cards[i].get_class(), "same_identity":is_same(projected,cards[i])}))
		board.get_node("CardBrowser/Panel/Close").pressed.emit()
	var snapshot: Dictionary = builder.build(GameData.player_id)
	var mirror = Mirror.new()
	mirror.reset(GameData.player_id)
	check(primitive(snapshot) and mirror.accept(snapshot), "real complete filtered snapshot accepted by mirror")
	var saved: Dictionary = mirror.read()
	var bad: Dictionary = snapshot.duplicate(true)
	bad.seq = snapshot.seq + 1
	bad.event_discard[0]["raw"] = cards[0]
	check(not mirror.accept(bad), "raw true object injection rejected not identity passthrough")
	check(mirror.read() == saved, "rejected raw identity leaves mirror snapshot unchanged")
	var id: int = builder.ids.id_for(cards[0])
	var altered: Dictionary = builder.card_view(cards[0], false)
	altered.id = builder.ids.id_for(cards[1])
	check(builder.ids.object_for(id) == cards[0] and MapData.event_discard.has(cards[0]), "changing projection ID cannot rename original rule identity")
	MapData.event_discard.erase(cards[0])
	board.refresh_all_ui()
	await open_category(board, "Shinto")
	check(board.get_node("CardBrowser/Panel/CardScroll/Row").get_child_count() == 0 and board.get_node("CardBrowser/Panel/Empty").visible, "explicit public refresh reflects real removal and empty state")
	check(MapData.event_discard.size() == 2, "browser observations never alter remaining true cards")
	await finish(board)
