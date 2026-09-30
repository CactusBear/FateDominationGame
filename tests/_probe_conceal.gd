extends Node

## 探针：暗置牌 = 「贴卡背 + 半透明灰遮罩 + 闭眼图标」——闭眼遮罩表达的是
## "这张牌还没向其他玩家公开"；明置时遮罩消失、恢复卡面。
## 两处都要覆盖：① 技能区（zone 组）② 战区出牌区。
## 对照旧控制器 tactical_board_ui.gd 的未公开遮罩（CONCEAL_COLOR + CONCEAL_ICON）。
var board: Control

func _ready() -> void:
	call_deferred("run")

func frames(count := 3) -> void:
	for i in range(count):
		await get_tree().process_frame

func find_overlay(node: Node) -> ColorRect:
	var found := node.find_children("ConcealOverlay", "ColorRect", true, false)
	return found[0] as ColorRect if not found.is_empty() else null

func report(slot: Control, tag: String) -> void:
	var overlay := find_overlay(slot)
	var icon: TextureRect = null
	if overlay != null:
		icon = overlay.get_node_or_null("OverlayIcon") as TextureRect
	var art: Array = slot.find_children("Img", "TextureRect", true, false)
	var art_path := ""
	if not art.is_empty() and (art[0] as TextureRect).texture != null:
		art_path = (art[0] as TextureRect).texture.resource_path.get_file()
	print("PROBE ", tag, " slot_size=", slot.size,
		" art=", art_path,
		" overlay=", overlay != null and overlay.visible,
		" icon=", icon != null and icon.texture != null,
		" icon_size=", icon.size if icon != null else Vector2.ZERO,
		" icon_center=", icon.get_global_rect().get_center() if icon != null else Vector2.ZERO,
		" slot_center=", slot.get_global_rect().get_center())

func run() -> void:
	board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	get_tree().root.add_child(board)
	await frames(10)
	# ① 技能区：选一张已觉醒的技能牌（未觉醒升华技本就走卡背，不在此列），置为暗置
	var zone: Array = board.get_node("Hand").get_children().filter(func(s): return s.get_meta("held_group", "") == "zone")
	var skill_slot: Control = null
	var skill_card = null
	for s in zone:
		var c = s.get_meta("card")
		if c != null and c is BaseSkill and bool(c.get("_is_awakened")):
			skill_slot = s
			skill_card = c
			break
	print("PROBE zone_slots=", zone.size(), " picked=", str(skill_card.get("_name")) if skill_card != null else "none")
	if skill_slot != null:
		skill_card._is_concealed = true
		board.refresh_all_ui()
		# 等翻面动画播完（CARD_FLIP_SECONDS ≈ 16 帧），否则会拍到折到一半的卡
		await frames(30)
		report(skill_slot, "zone_concealed")
	# ② 出牌区：自己打出的暗置牌
	var hand: Array = board.get_node("Hand").get_children().filter(func(s): return s.get_meta("held_group", "") == "hand")
	var area: BaseMapArea = MapData.miyama
	var loc: BaseLocation = area._locations.filter(func(l): return l._pl_num_limit < 0)[0]
	SetLocation.new().exec(loc, board._local_player_id, false)
	var played = CloneObject.new().exec(hand.front().get_meta("card")) if not hand.is_empty() else null
	if played != null:
		played._is_concealed = true
		board._pl(board._local_player_id).played_cards.append(played)
		board._select_scroll(MapData.areas.find(area))
		board.refresh_all_ui()
		await frames(70)
		board.refresh_all_ui()
		await frames(70)
		var played_slot: Control = null
		for grp in board._play_group_nodes():
			for child in grp.get_node("Cards/Row").get_children():
				if child.get_meta("card") == played:
					played_slot = child
		print("PROBE played_slot=", played_slot != null)
		if played_slot != null:
			report(played_slot, "played_concealed")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tests/runtime_reports/probe_conceal.png")
	print("RESULT probe done")
	get_tree().quit(0)
