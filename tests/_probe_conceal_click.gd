extends Node

## 探针：未公开遮罩（闭眼图标）的判据 = "这张牌的卡面还没向其他玩家公开"。
## ① 技能区（未打出的牌，含 side.skills 回收区）：真名隐藏时＝卡面 + 遮罩；真名解放后遮罩消失；自身暗置时贴卡背 + 遮罩。
## ② 手牌区不盖遮罩（手牌默认就不向别人公开，遮罩没有信息量）。
## ③ 战区里已打出的牌不受真名影响——HideTrueName 的默认隐藏区域不含 played_cards/discard，
##    所以真名隐藏时已打出的牌仍然可见：明置的（concealed=false）无遮罩、暗置的盖遮罩。
var board: Control

func _ready() -> void:
	call_deferred("run")

func frames(count := 3) -> void:
	for i in range(count):
		await get_tree().process_frame

func overlay_of(slot: Control) -> ColorRect:
	var found := slot.find_children("ConcealOverlay", "ColorRect", true, false)
	return found[0] as ColorRect if not found.is_empty() else null

func art_path(slot: Control) -> String:
	var img: TextureRect = null
	for candidate in slot.find_children("Img", "TextureRect", true, false):
		img = candidate as TextureRect
		break
	return img.texture.resource_path.get_file() if img != null and img.texture != null else ""

func state(slot: Control) -> String:
	var card = slot.get_meta("card")
	var ov := overlay_of(slot)
	var icon: TextureRect = null
	if ov != null:
		icon = ov.get_node_or_null("OverlayIcon") as TextureRect
	return "concealed=%s art=%s overlay=%s icon=%s" % [
		str(bool(card._is_concealed)),
		art_path(slot),
		str(ov != null and ov.visible),
		str(icon != null and icon.texture != null)]

func right_click(ctrl: Control) -> void:
	await frames(2)
	var pos: Vector2 = ctrl.get_global_rect().get_center()
	get_viewport().warp_mouse(pos)
	await frames(1)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.position = pos
		ev.global_position = pos
		ev.button_index = MOUSE_BUTTON_RIGHT
		ev.pressed = pressed
		get_tree().root.push_input(ev, true)
	await frames(20)

func run() -> void:
	board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	get_tree().root.add_child(board)
	await frames(10)
	var local_id: int = board._local_player_id
	print("PROBE released_at_start=", ReleaseTrueName.is_released(local_id))
	# ① 技能区：真名隐藏时明置的牌也要有遮罩
	var zone: Array = board.get_node("Hand").get_children().filter(func(s): return s.get_meta("held_group", "") == "zone")
	var slot: Control = null
	for s in zone:
		var c = s.get_meta("card")
		if c != null and c is BaseSkill and bool(c.get("_is_awakened")):
			slot = s
			break
	if slot == null:
		print("RESULT no zone slot")
		get_tree().quit(1)
		return
	var card = slot.get_meta("card")
	print("PROBE 1_zone_revealed_nameless ", state(slot), " (expect card face + overlay=true)")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tests/runtime_reports/probe_nameless_before.png")
	# ② 右键暗置：贴卡背 + 遮罩
	await right_click(slot)
	print("PROBE 2_zone_concealed ", state(slot), " (expect card back + overlay=true)")
	await right_click(slot)
	print("PROBE 3_zone_revealed_again ", state(slot), " (expect card face + overlay=true)")
	# ③ 真名解放：技能区遮罩消失
	ReleaseTrueName.new().exec(local_id)
	board.refresh_all_ui()
	await frames(30)
	print("PROBE 4_after_true_name_release ", state(slot), " (expect card face + overlay=false)")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tests/runtime_reports/probe_nameless_after.png")
	# ④ 手牌区不盖遮罩
	var hand: Array = board.get_node("Hand").get_children().filter(func(s): return s.get_meta("held_group", "") == "hand")
	if not hand.is_empty():
		var hslot: Control = hand.front()
		SetCardConcealed.new().exec(hslot.get_meta("card"), true, local_id)
		board.refresh_all_ui()
		await frames(30)
		print("PROBE 5_hand_concealed ", state(hslot), " (expect card back + overlay=false)")
	# ⑤ 出牌区：真名隐藏也看得见已打出的牌；只有暗置打出的才盖遮罩
	var area: BaseMapArea = MapData.miyama
	var loc: BaseLocation = area._locations.filter(func(l): return l._pl_num_limit < 0)[0]
	SetLocation.new().exec(loc, local_id, false)
	var pl: Dictionary = board._pl(local_id)
	var shown_card = CloneObject.new().exec(slot.get_meta("card"))
	if shown_card != null:
		shown_card._is_concealed = false
		pl.played_cards.append(shown_card)
	board._select_scroll(MapData.areas.find(area))
	board.refresh_all_ui()
	await frames(70)
	board.refresh_all_ui()
	await frames(70)
	for grp in board._play_group_nodes():
		for child in grp.get_node("Cards/Row").get_children():
			var c = child.get_meta("card")
			if c == shown_card:
				print("PROBE 6_played_revealed ", state(child), " (expect overlay=false)")
	print("RESULT probe done")
	get_tree().quit(0)
