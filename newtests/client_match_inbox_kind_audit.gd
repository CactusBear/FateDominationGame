extends Node

const Inbox = preload("res://scripts/net/session/client_match_inbox.gd")
const Session = preload("res://scripts/net/session/lobby_session.gd")
var checks: int = 0
var failures: Array = []

class Events extends RefCounted:
	var changes: int = 0
	var previews: Array = []
	var selections: Array = []
	var resets: int = 0
	func changed_event() -> void:
		changes += 1
	func preview_event(id: int, result: Dictionary) -> void:
		previews.append([id, result])
	func selection_event(state: Dictionary) -> void:
		selections.append(state)
	func reset_event() -> void:
		resets += 1

func check(ok: bool, label: String) -> void:
	checks += 1
	print("CHECK ", ok, " #", checks, " ", label)
	if not ok:
		failures.append(label)

func view(sequence: int, observer: int = 7) -> Dictionary:
	return {"v":1,"seq":sequence,"observer":observer,"round":1,"phase":"action","current_player":7,"game_over":false,"players":[],"areas":[],"situation":{},"battle_broadcast":{"pending":false,"batch_id":0,"confirmers":[],"confirmed":[]},"state":{"phases":["action"],"total_rounds":3,"climax_rounds":[]}}

func packet(sequence: int, observer: int = 7) -> Dictionary:
	return {"kind":"match_view","state":view(sequence,observer),"pending":{},"actions":{"stamp":sequence}}

func snapshot(target) -> Array:
	return [target.read_match(), target.read_pending(), target.read_actions()]

func deliver(target, message: Dictionary, direct: bool, sender: int = 1) -> bool:
	if direct:
		return target.receive(message)
	# 公开 Transport 边界注入，走 Session 自己登记的生产入口，不调用私有方法。
	target.transport.message_received.emit(sender, message)
	return true

func observe(target, direct: bool) -> Events:
	var events = Events.new()
	target.changed.connect(events.changed_event)
	target.group_preview_received.connect(events.preview_event)
	if direct:
		target.selection_received.connect(events.selection_event)
		target.selection_reset.connect(events.reset_event)
	return events

func selection_empty(target, events: Events, direct: bool) -> bool:
	return events.resets == 1 if direct else target.selection_view.is_empty()

func valid_contract(direct: bool, denial: Dictionary) -> void:
	var target = Inbox.new() if direct else Session.new()
	var events = observe(target, direct)
	var label: String = "Inbox " if direct else "Session "
	check(deliver(target, {"kind":"match_bind","observer":7}, direct), label + "match_bind recognized")
	check(events.changes == 0 and snapshot(target) == [{},{},{}], label + "bind has no publication")
	check(deliver(target, packet(1), direct), label + "match_view recognized")
	check(events.changes == 1 and target.read_match() == view(1) and target.read_actions() == {"stamp":1}, label + "one view -> exactly one changed and complete state")
	# 重复 bind 不重新 reset 观察者，也不损坏已有视图。
	deliver(target, {"kind":"match_bind","observer":8}, direct)
	deliver(target, packet(2,8), direct)
	check(events.changes == 1 and target.read_match() == view(1), label + "duplicate bind cannot rebind")
	var selection_message: Dictionary = {"kind":"selection","state":{"revision":2,"choices":["a"]}}
	check(deliver(target, selection_message, direct), label + "selection recognized")
	check(events.changes == 2 and (events.selections.size() == 1 if direct else target.selection_view == selection_message.state), label + "one selection -> one publication")
	selection_message.state.choices.append("mutated")
	check((events.selections[0].choices == ["a"] if direct else target.selection_view.choices == ["a"]), label + "selection deep copy")
	var preview_message: Dictionary = {"kind":"group_preview","request_id":41,"result":{"ok":true,"cards":[1]}}
	check(deliver(target, preview_message, direct), label + "group_preview recognized")
	check(events.previews == [[41,{"ok":true,"cards":[1]}]] and events.changes == 2, label + "one preview -> exactly one preview signal, no changed")
	preview_message.result.cards.append(2)
	check(events.previews[0][1].cards == [1], label + "preview deep copy")
	# 使用生产 MatchAuthority 实际返回的拒绝字典，不在 Inbox 中重新解释能力政策。
	deliver(target, {"kind":"group_preview","request_id":42,"result":denial}, direct)
	check(events.previews.size() == 2 and events.previews[1] == [42,denial] and events.changes == 2, label + "production capability denial passes through unchanged once")
	var denied_view: Dictionary = packet(2)
	denied_view.actions = {"guard":{"paused":true,"can_continue":false},"management_paused":true,"end_action":false}
	deliver(target, denied_view, direct)
	check(target.read_actions() == denied_view.actions and events.changes == 3, label + "disabled action capabilities are not upgraded or filtered")
	check(deliver(target, {"kind":"match_reset"}, direct), label + "match_reset recognized")
	check(events.changes == 4 and snapshot(target) == [{},{},{}] and selection_empty(target,events,direct), label + "one reset -> one changed, reset state and selection")
	deliver(target, packet(3), direct)
	check(events.changes == 4 and snapshot(target) == [{},{},{}], label + "reset revoked bind")
	if not direct:
		target.close()

func invalid_contract(direct: bool) -> void:
	var target = Inbox.new() if direct else Session.new()
	var events = observe(target, direct)
	var label: String = "Inbox " if direct else "Session "
	for bad in [{"kind":"match_bind"},{"kind":"match_bind","observer":"7"},{"kind":"match_bind","observer":7.0},{"kind":"match_bind","observer":true}]:
		check(deliver(target,bad,direct), label + "invalid bind consumed")
		deliver(target,packet(1),direct)
		check(events.changes == 0 and snapshot(target) == [{},{},{}], label + "wrong bind type does not authorize view")
	deliver(target,{"kind":"match_bind","observer":7},direct)
	deliver(target,packet(1),direct)
	var baseline: Array = snapshot(target)
	var bad_messages: Array = [
		{"kind":"group_preview","request_id":"41","result":{}},
		{"kind":"group_preview","request_id":41.0,"result":{}},
		{"kind":"group_preview","request_id":41,"result":[]},
		{"kind":"group_preview","request_id":41},
		{"kind":"selection","state":[]},
		{"kind":"selection","state":"bad"},
		{"kind":"selection"},
		{"kind":"match_view","state":[],"pending":{},"actions":{}},
		{"kind":"match_view","state":view(2),"pending":[],"actions":{}},
		{"kind":"match_view","state":view(2),"pending":{},"actions":[]},
		{"kind":"match_view","state":view(2),"pending":{}},
		{"kind":"match_view","state":view(2),"pending":{"kind":"unknown"},"actions":{}},
		packet(2,8), packet(1)
	]
	for index in bad_messages.size():
		check(deliver(target,bad_messages[index],direct), label + "invalid recognized message consumed #" + str(index))
		check(snapshot(target) == baseline and events.changes == 1 and events.previews.is_empty() and events.selections.is_empty() and events.resets == 0 and (true if direct else target.selection_view.is_empty()), label + "invalid shape -> no publication or partial write #" + str(index))
	# reset 无必需 payload 字段；不把附带字段错类型伪称为无效 reset。
	var kinds: Array = [null,17,["match_reset"],"unknown"] if direct or OS.get_environment("CLIENT_INBOX_ENVELOPE_DEFECT") == "1" else [null,"unknown"]
	for bad_kind in kinds:
		var handled: bool = deliver(target,{"kind":bad_kind},direct)
		check((not handled if direct else true) and snapshot(target) == baseline and events.changes == 1, label + "unknown/wrong kind does not invoke reset")
	if not direct:
		target.close()

func source_gate_contract() -> void:
	var target = Session.new()
	var events = observe(target,false)
	deliver(target,{"kind":"match_bind","observer":7},false)
	deliver(target,packet(1),false)
	deliver(target,{"kind":"selection","state":{"marker":1}},false)
	var baseline: Array = snapshot(target)
	var messages: Array = [
		{"kind":"match_bind","observer":8},
		{"kind":"match_reset"},packet(2),
		{"kind":"selection","state":{"marker":2}},
		{"kind":"group_preview","request_id":41,"result":{"ok":false}}
	]
	for message in messages:
		deliver(target,message,false,2)
		check(snapshot(target) == baseline and target.selection_view == {"marker":1} and events.changes == 2 and events.previews.is_empty(), "Session foreign sender blocked " + message.kind)
	target.close()

func _ready() -> void:
	print("AUDIT_USER_DIR ", OS.get_user_data_dir())
	var authority_session = Session.new()
	var denial: Dictionary = authority_session.match_authority.preview_group(1,0,[],[])
	check(denial == {"ok":false}, "real MatchAuthority unbound capability denial")
	authority_session.close()
	valid_contract(true,denial)
	valid_contract(false,denial)
	invalid_contract(true)
	invalid_contract(false)
	source_gate_contract()
	print("RESULT ", JSON.stringify({"suite":"client_match_inbox_kind_audit","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
