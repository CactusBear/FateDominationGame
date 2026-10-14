extends PanelContainer

var _session
var _board: Control
var _prompt: Dictionary = {}
var _sequence: int = 0
var _submitted: bool = false
var _submit_sequence: int = 0
var _submitted_player_prompt: Dictionary = {}
var _player_choice_generation: int = 0
var _notification_inbox = preload("res://scripts/net/ui/notification_inbox.gd").new()
var _observer: int = -2
var _lock_active: bool = false
var _notice_queue: Array = []
var _notice_busy: bool = false
var _notice_epoch: int = 0

func _ready() -> void:
	hide()

func _process(_delta: float) -> void:
	_flush_notices()

func bind_session(session) -> void:
	_player_choice_generation += 1
	_unbind()
	_board = get_parent().get_parent() as Control
	_session = session
	_submitted = false
	_submit_sequence = 0
	_submitted_player_prompt = {}
	_notice_queue.clear()
	_notice_busy = false
	_notice_epoch += 1
	_prompt = {}
	_notification_inbox.reset()
	_observer = -2
	for entry in [[_board._effect_modal,"Box/ButtonsRow/BtnConfirm",_confirm_active],[_board._effect_modal,"Box/ButtonsRow/BtnCancel",_cancel],[_board._card_select_panel,"Box/ButtonsRow/BtnConfirmSelect",_confirm_cards],[_board._card_select_panel,"Box/ButtonsRow/BtnCancelSelect",_cancel]]:
		var button: Button = entry[0].get_node(entry[1])
		if not button.pressed.is_connected(entry[2]): button.pressed.connect(entry[2])
	if _session != null:
		_session.changed.connect(_refresh)
		_session.request_rejected.connect(_rejected)
		_session.request_completed.connect(_completed)
		_session.request_associations_invalidated.connect(_player_request_invalidated)
	_refresh()

func _refresh() -> void:
	hide()
	if _session == null: return
	var view: Dictionary = _board._source.read_view() if _board._source != null else {}
	var observer: int = view.get("observer", -1)
	if observer != _observer:
		_notification_inbox.reset()
		_notice_queue.clear()
		_notice_busy = false
		_notice_epoch += 1
		_board._toast.hide()
		_observer = observer
	var next: Dictionary = _board._source.read_pending() if _board._source != null else {}
	_sequence = int(view.get("seq",0))
	if not _card_prompt_same(_prompt, next):
		_player_choice_generation += 1
		_prompt = next.duplicate(true)
		# 选人声明重绘不是业务回执；保持提交时登记的精确 seq。
		if _submitted_player_prompt.is_empty():
			_submitted = false
			_submit_sequence = 0
		_hide_native()
		_lock_active = false
		_render()
	refresh_submission_availability()
	var texts: Array = []
	for notice in _notification_inbox.ingest(view.get("notifications", [])):
		texts.append(notice.text)
	_notice_queue.append_array(texts)
	_flush_notices()

func _flush_notices() -> void:
	if _board == null or _session == null or _notice_busy or _notice_queue.is_empty() or _board._is_paused(): return
	if _board._effect_modal.visible or _board._tactical_confirm.visible: return
	_notice_busy = true
	_board._say_effect_batches([_notice_queue.pop_front()])
	var epoch: int = _notice_epoch
	var owner: WeakRef = weakref(self)
	var timer: SceneTreeTimer = get_tree().create_timer(_board._EFFECT_MSG_TOAST_INTERVAL,false)
	timer.timeout.connect(func() -> void:
		var current = owner.get_ref()
		if current != null and current._notice_epoch == epoch: current._notice_busy = false
	)

func _hide_native() -> void:
	for panel in [_board._effect_modal,_board._card_select_panel,_board._player_select_panel]:
		for button in panel.find_children("*","Button",true,false):
			if button.has_meta("choice_disabled"):
				button.disabled = bool(button.get_meta("choice_disabled"))
				button.remove_meta("choice_disabled")
	_board.get_node("Hint/LocationCancel").hide()
	for panel in [_board._effect_modal,_board._card_select_panel,_board._player_select_panel]: panel.hide()
	_board._card_select_request = {}
	_board._card_select_picked = []

func _render() -> void:
	match _prompt.get("kind", ""):
		"active_choice":
			var declaration: Dictionary = _prompt.duplicate(true)
			preload("res://scripts/game_scene/native_choice_renderer.gd").active(_board,_prompt,_pick.bind(declaration,_player_choice_generation),_pick_quantity.bind(declaration,_player_choice_generation))
			var confirm: Button = _board._effect_modal.get_node("Box/ButtonsRow/BtnConfirm")
			var cancel: Button = _board._effect_modal.get_node("Box/ButtonsRow/BtnCancel")
			for connection in confirm.pressed.get_connections(): confirm.pressed.disconnect(connection.callable)
			for connection in cancel.pressed.get_connections(): cancel.pressed.disconnect(connection.callable)
			confirm.pressed.connect(_confirm_active.bind(declaration,_player_choice_generation))
			cancel.pressed.connect(_cancel_active.bind(declaration,_player_choice_generation))
		"card_choice":
			# Card dictionaries are already filtered by the authority. No local templates.
			_board._show_card_select_panel({"cards":_prompt.get("card_views",[]),"required_cards":_required_cards(),"shown_name":_prompt.label,"min":_prompt.min,"max":_prompt.max,"allow_cancel":_prompt.allow_cancel,"verb":_prompt.get("verb","选择"),"secret":_prompt.get("secret",false),"confirm_text":_prompt.get("confirm_text","确认选择")})
			var declaration: Dictionary = _prompt.duplicate(true)
			var confirm: Button = _board._card_select_panel.get_node("Box/ButtonsRow/BtnConfirmSelect")
			var cancel: Button = _board._card_select_panel.get_node("Box/ButtonsRow/BtnCancelSelect")
			for connection in confirm.pressed.get_connections(): confirm.pressed.disconnect(connection.callable)
			for connection in cancel.pressed.get_connections(): cancel.pressed.disconnect(connection.callable)
			confirm.pressed.connect(_confirm_cards.bind(declaration,_player_choice_generation))
			cancel.pressed.connect(_cancel_player.bind(declaration,_player_choice_generation))
		"player_choice":
			var names: Dictionary = {}
			for pid in _prompt.players: names[pid] = _player_name(pid)
			var declaration: Dictionary = _prompt.duplicate(true)
			preload("res://scripts/game_scene/native_choice_renderer.gd").players(_board,_prompt,names,_pick_players.bind(declaration,_player_choice_generation),_cancel_player.bind(declaration,_player_choice_generation))
		"location_choice":
			var cancel: Button = _board.get_node("Hint/LocationCancel")
			for connection in cancel.pressed.get_connections(): cancel.pressed.disconnect(connection.callable)
			preload("res://scripts/game_scene/native_choice_renderer.gd").location(_board,_prompt.label,_prompt.allow_cancel,_cancel_player.bind(_prompt.duplicate(true),_player_choice_generation))

func _required_cards() -> Array:
	return _prompt.get("card_views",[]).filter(func(card): return _prompt.get("required",[]).has(int(card.get("id", -1))))

func _card_ids(cards: Array) -> Array:
	var ids: Array = []
	for card in cards:
		var id := int(card) if card is int else (int(card.get("id", -1)) if card is Dictionary else -1)
		if id >= 0 and not ids.has(id): ids.append(id)
	return ids

func _card_prompt_same(a: Dictionary, b: Dictionary) -> bool:
	if a.get("kind", "") != "card_choice" or b.get("kind", "") != "card_choice": return a == b
	return int(a.get("effect", -1)) == int(b.get("effect", -1)) and _card_ids(a.get("cards", [])) == _card_ids(b.get("cards", [])) and _card_ids(a.get("required", [])) == _card_ids(b.get("required", [])) and int(a.get("min", 1)) == int(b.get("min", 1)) and int(a.get("max", -1)) == int(b.get("max", -1)) and bool(a.get("allow_cancel", false)) == bool(b.get("allow_cancel", false)) and bool(a.get("secret", false)) == bool(b.get("secret", false)) and str(a.get("verb", "")) == str(b.get("verb", "")) and str(a.get("confirm_text", "")) == str(b.get("confirm_text", ""))

func _player_name(pid: int) -> String:
	var view: Dictionary = _board._source.read_view() if _board._source != null else {}
	for player in view.get("players",[]):
		if player.id == pid: return str(player.player_name)
	return "玩家"

func refresh_submission_availability() -> void:
	if _session == null or _board == null: return
	if _prompt.get("kind") == "card_choice" and not _submitted and _session.match_commands_available():
		_board._refresh_card_select_confirm(_board._card_select_request)
	var locked: bool = _submitted or not _session.match_commands_available()
	for panel in [_board._effect_modal,_board._card_select_panel,_board._player_select_panel]:
		if not panel.visible: continue
		for button in panel.find_children("*","Button",true,false):
			if locked and not _lock_active: button.set_meta("choice_disabled",button.disabled)
			if locked: button.disabled = true
			elif _lock_active and button.has_meta("choice_disabled"):
				button.disabled = bool(button.get_meta("choice_disabled"))
	_board.get_node("Hint/LocationCancel").disabled = locked
	_lock_active = locked

func _allowed() -> bool:
	return _session != null and not _prompt.is_empty() and not _submitted and _session.match_commands_available() and not _board._is_paused()

func _send(command: String, params: Dictionary) -> void:
	if not _allowed(): return
	_submitted = true
	_submitted_player_prompt = _prompt.duplicate(true)
	refresh_submission_availability()
	var result: Error = _session.request("match_command",{"view_seq":_sequence,"command":command,"params":params},_register_submit)
	if result != OK and _submitted:
		_submitted = false
		_submitted_player_prompt = {}
		refresh_submission_availability()
		_board._say(error_string(result))

func _register_submit(sequence: int) -> void:
	_submit_sequence = sequence

func _rejected(sequence: int, reason: String) -> void:
	if sequence <= 0 or not _submitted or sequence != _submit_sequence: return
	_submitted = false
	_submit_sequence = 0
	_submitted_player_prompt = {}
	_refresh()
	_board._say(reason)

func _completed(sequence: int, ok: bool, reason: String) -> void:
	if _submitted_player_prompt.is_empty() or sequence <= 0 or not _submitted or sequence != _submit_sequence: return
	if not ok:
		_rejected(sequence, reason)
		return
	var completed: Dictionary = _submitted_player_prompt
	_submitted = false
	_submit_sequence = 0
	_submitted_player_prompt = {}
	refresh_submission_availability()
	if _card_prompt_same(_prompt, completed):
		if completed.get("kind") == "active_choice": _board._effect_modal.hide()
		elif completed.get("kind") == "player_choice": _board._player_select_panel.hide()
		elif completed.get("kind") == "card_choice": _board._card_select_panel.hide()

func _player_request_invalidated(_generation: int, _reason: String) -> void:
	_player_choice_generation += 1
	if _submitted_player_prompt.is_empty(): return
	_submitted = false
	_submit_sequence = 0
	_submitted_player_prompt = {}
	_prompt = {}
	_hide_native()
	_lock_active = false
	# 通知栈中不重读旧视图、不重建输入；未知不是成功或规则拒绝。
	_board._say("会话请求关联已失效，执行结果未知；不自动重发")

func _pick(index: int, declaration: Dictionary = {}, generation: int = -1) -> void:
	if not _player_declaration_current(_prompt if declaration.is_empty() else declaration, generation): return
	if _prompt.get("kind") != "active_choice" or index < 0 or index >= _prompt.options.size(): return
	var option: Dictionary = _prompt.options[index]
	if not option.available or option.has("quantity_range"): return
	_send("option_choice",{"effect":_prompt.effect,"choices":[{"index":option.index,"count":1}]})

func _pick_quantity(index: int, spin: SpinBox, declaration: Dictionary = {}, generation: int = -1) -> void:
	if not _player_declaration_current(_prompt if declaration.is_empty() else declaration, generation): return
	if _prompt.get("kind") != "active_choice" or index < 0 or index >= _prompt.options.size() or spin == null: return
	var option: Dictionary = _prompt.options[index]
	if not option.available or not option.has("quantity_range"): return
	spin.apply()
	var quantity: int = int(spin.value)
	if quantity < option.quantity_range[0] or quantity > option.quantity_range[1]: return
	_send("option_choice",{"effect":_prompt.effect,"choices":[{"index":option.index,"count":1,"quantity":quantity}]})

func _confirm_active(declaration: Dictionary = {}, generation: int = -1) -> void:
	if not _player_declaration_current(_prompt if declaration.is_empty() else declaration, generation): return
	if _prompt.get("kind") != "active_choice": return
	if _prompt.options.is_empty():
		_send("active_choice",{"effect":_prompt.effect,"activate":true})
		return
	if not _prompt.multi: return
	var choices: Array = preload("res://scripts/game_scene/native_choice_renderer.gd").active_choices(_board, _prompt)
	if not choices.is_empty(): _send("option_choice",{"effect":_prompt.effect,"choices":choices})

func _cancel_active(declaration: Dictionary, generation: int = -1) -> void:
	if not _player_declaration_current(declaration, generation): return
	_cancel()

func _confirm_cards(declaration: Dictionary = {}, generation: int = -1) -> void:
	if not _player_declaration_current(_prompt if declaration.is_empty() else declaration, generation): return
	if _prompt.get("kind") != "card_choice": return
	var cards: Array = _card_ids(_board._card_select_picked)
	if cards.size() < _prompt.min or (_prompt.max != -1 and cards.size() > _prompt.max): return
	for required in _prompt.required:
		if not cards.has(required): return
	_send("card_choice",{"effect":_prompt.effect,"cards":cards})

func _player_declaration_current(declaration: Dictionary, generation: int = -1) -> bool:
	if generation >= 0 and generation != _player_choice_generation: return false
	if declaration != _prompt or _board._source == null or declaration != _board._source.read_pending():
		_refresh()
		return false
	return true

func _pick_players(picks: Array, declaration: Dictionary = {}, generation: int = -1) -> void:
	if not _player_declaration_current(_prompt if declaration.is_empty() else declaration, generation): return
	if _prompt.get("kind") != "player_choice" or picks.size() < _prompt.min or (_prompt.max != -1 and picks.size() > _prompt.max): return
	for pid in picks:
		if not _prompt.players.has(pid): return
	_send("player_choice",{"effect":_prompt.effect,"players":picks})

func _cancel_player(declaration: Dictionary, generation: int = -1) -> void:
	if not _player_declaration_current(declaration, generation): return
	_cancel()

func choose_area(area: int) -> bool:
	if _prompt.get("kind") != "location_choice": return false
	if not _player_declaration_current(_prompt): return true
	if _prompt.areas.has(area): _send("location_choice",{"effect":_prompt.effect,"area":area})
	return true

func _cancel() -> void:
	if not _prompt.get("allow_cancel",false): return
	_send("cancel_choice",{"effect":_prompt.effect})

func _unbind() -> void:
	if _session != null:
		if _session.changed.is_connected(_refresh): _session.changed.disconnect(_refresh)
		if _session.request_rejected.is_connected(_rejected): _session.request_rejected.disconnect(_rejected)
		if _session.request_completed.is_connected(_completed): _session.request_completed.disconnect(_completed)
		if _session.request_associations_invalidated.is_connected(_player_request_invalidated): _session.request_associations_invalidated.disconnect(_player_request_invalidated)
	_session = null

func _exit_tree() -> void:
	_unbind()
