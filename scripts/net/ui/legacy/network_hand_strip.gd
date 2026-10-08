extends PanelContainer

var selection = preload("res://scripts/net/ui/group_selection.gd").new()
var _session

func _ready() -> void:
	selection.changed.connect(_refresh)
	$Content/Confirm.pressed.connect(selection.confirm)

func bind_session(session) -> void:
	_session = session
	selection.bind_session(session)
	_refresh()

func _refresh() -> void:
	if not is_node_ready():
		return
	var row: HBoxContainer = $Content/Cards/Row
	for child in row.get_children():
		row.remove_child(child)
		child.queue_free()
	if _session == null:
		$Content/Confirm.disabled = true
		return
	var pending: Dictionary = selection.snapshot()
	var view: Dictionary = _session.read_match()
	var shown: Array = []
	for player in view.get("players", []):
		if not player.own:
			continue
		for zone in ["hand_cards", "master_skills", "servant_skills"]:
			for card in player.get(zone, []):
				if shown.has(card.id) or not card.get("visible", false):
					continue
				shown.append(card.id)
				var item: VBoxContainer = $Templates/Card.duplicate()
				item.name = "Card" + str(card.id)
				item.get_node("Name").text = str(card.get("name", ""))
				var index: int = pending.cards.find(card.id)
				var modes: Array = selection.modes_for(card.id)
				item.get_node("Selected").text = ("已选暗置" if pending.hidden[index] else "已选明置") if index >= 0 else ""
				item.get_node("Modes/Faceup").visible = index < 0 and modes.has(false)
				item.get_node("Modes/Hidden").visible = index < 0 and modes.has(true)
				item.get_node("Modes/Remove").visible = index >= 0 and not pending.submitted
				item.get_node("Modes/Faceup").pressed.connect(selection.add.bind(card.id, false))
				item.get_node("Modes/Hidden").pressed.connect(selection.add.bind(card.id, true))
				item.get_node("Modes/Remove").pressed.connect(selection.remove.bind(card.id))
				row.add_child(item)
	$Content/Confirm.disabled = not selection.can_confirm()
	$Content/Status.text = "等待主机确认" if pending.submitted else ("正在校验组合" if pending.waiting else "已选 %d" % pending.cards.size())

func _exit_tree() -> void:
	selection.bind_session(null)
	_session = null
