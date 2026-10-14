extends Node

const Fixture = preload("res://newtests/v2-discard-stable-id_board.gd")
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

func finish(board: Node) -> void:
	board.queue_free()
	await get_tree().process_frame
	print("RESULT ", JSON.stringify({"suite":"v2-discard-stable-id-contract", "checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)

# 身份表见证与投影 ID 两项合取；异表数字碰巧相同不代表同一规则对象。
func matches_card(meta: Variant, ids: RefCounted, id: int, original: Object) -> bool:
	return meta is Dictionary and meta.get("id", -1) == id and is_same(ids.object_for(id), original)

func run() -> void:
	var board = preload("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	board.set_script(Fixture)
	get_tree().root.add_child(board)
	board.set_process(false)
	await get_tree().process_frame
	var source: SessionContext = GameStart.startup_context()
	check(source != null and SessionGeneration.validate_context(source).ok, "original successful startup source")
	check(board.builder_factory_calls == 1 and board.identity_builder != null, "one original super factory builder handed off")
	if source == null or board.identity_builder == null:
		await finish(board)
		return
	var builder: RefCounted = board.identity_builder
	var cleared: Dictionary = EventResolver.new().clear_all(source)
	check(cleared.ok and cleared.get("completed", false), "original source cleanup receipt")
	MapData.event_discard.clear()
	var cards: Array = []
	var expected_ids: Array = []
	for area in [MapData.shinto, MapData.miyama, MapData.scout]:
		var factory := CloneContext.new()
		check(factory.configure_template(source, [LoadEvent.events[0]]), "trusted template origin " + area._area_name)
		var copied: Dictionary = factory.copy_result(LoadEvent.events[0], source)
		check(copied.ok and copied.object is BaseEvent, "runtime card receipt " + area._area_name)
		if not copied.ok or not copied.object is BaseEvent:
			await finish(board)
			return
		var card: BaseEvent = copied.object
		preload("res://scripts/system/operation_router.gd").exec_registered("add_map_area_events", [area, card], source)
		cards.append(card)
		# 在任何浏览槽读取前从原牌捕获期望；绝不读投影生成 expected。
		expected_ids.append(builder.ids.id_for(card))
		check(is_same(builder.ids.object_for(expected_ids.back()), card), "before UI same identity table resolves original " + area._area_name)
	cleared = EventResolver.new().clear_all(source)
	check(cleared.ok and cleared.get("completed", false) and MapData.event_discard.size() == 3, "real nonempty discard publication receipt")
	board.refresh_all_ui()
	var keys: Array = ["Shinto", "Miyama", "Other"]
	for i in keys.size():
		board.get_node("Piles/EventPile/Open").pressed.emit()
		board.get_node("EventDiscardMenu/Choices/" + keys[i]).pressed.emit()
		await get_tree().process_frame
		var row: Node = board.get_node("CardBrowser/Panel/CardScroll/Row")
		check(row.get_child_count() == 1, "nonempty formal browser " + keys[i])
		if row.get_child_count() != 1:
			await finish(board)
			return
		var meta: Variant = row.get_child(0).get_meta("card")
		check(matches_card(meta, builder.ids, expected_ids[i], cards[i]), "positive same session instance stable identity " + keys[i])
		check(not matches_card(meta, builder.ids, expected_ids[(i + 1) % cards.size()], cards[(i + 1) % cards.size()]), "negative wrong ID same template face " + keys[i])
		check(not matches_card(cards[i], builder.ids, expected_ids[i], cards[i]), "negative raw rule Object is not metadata " + keys[i])
		board.get_node("CardBrowser/Panel/Close").pressed.emit()
	# 第二 builder 仅用于明确负例，不作为正式浏览的期望来源。
	var foreign: RefCounted = Builder.new()
	var foreign_fillers: Array = []
	for unused in range(expected_ids[0] - 1):
		var filler := RefCounted.new()
		foreign_fillers.append(filler)
		foreign.ids.id_for(filler)
	var foreign_id: int = foreign.ids.id_for(cards[1])
	check(not is_same(foreign, builder), "negative fixture uses genuinely different builder")
	check(foreign_id == expected_ids[0] and is_same(foreign.ids.object_for(foreign_id), cards[1]), "foreign table has same numeric ID for different original")
	check(not matches_card({"id":expected_ids[0]}, foreign.ids, expected_ids[0], cards[0]), "negative colliding numeric ID cannot prove original identity")
	var snapshot: Dictionary = builder.build(GameData.player_id)
	var mirror: RefCounted = Mirror.new()
	mirror.reset(GameData.player_id)
	check(not snapshot.get("event_discard", []).is_empty() and mirror.accept(snapshot), "actual full nonempty snapshot accepted")
	var saved: Dictionary = mirror.read()
	var polluted: Dictionary = snapshot.duplicate(true)
	polluted.seq = snapshot.seq + 1
	polluted.event_discard[0]["raw"] = cards[0]
	check(not mirror.accept(polluted), "negative Object pollution rejected by real mirror")
	check(mirror.read() == saved, "pollution refusal preserves exact snapshot")
	board.refresh_all_ui()
	board.get_node("Piles/EventPile/Open").pressed.emit()
	board.get_node("EventDiscardMenu/Choices/Shinto").pressed.emit()
	await get_tree().process_frame
	var stable_row: Node = board.get_node("CardBrowser/Panel/CardScroll/Row")
	check(stable_row.get_child_count() == 1 and matches_card(stable_row.get_child(0).get_meta("card"), builder.ids, expected_ids[0], cards[0]), "same board refresh preserves captured original stable ID")
	check(is_same(source, GameStart.startup_context()) and MapData.event_discard.size() == 3, "observations retain original session and rule data")
	await finish(board)
