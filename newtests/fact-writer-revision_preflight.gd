extends Node
const Checkpoint = preload("res://scripts/match/rule_checkpoint.gd")
const Ids = preload("res://scripts/match/net_ids.gd")
const Generation = preload("res://scripts/system/session_generation.gd")
var checks:int = 0
var failures:Array = []
# Test-local setter only: production EventJournal remains byte-identical here.
class RootProbe extends RefCounted:
	var entries:Array = []:
		set(value):
			if not is_same(entries, value):
				var revision:int = int(get_meta(&"revision", 0))
				entries = value
				set_meta(&"revision", revision + 1)
	func _init() -> void:
		set_meta(&"revision", 0)
func check(ok:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", ok)
	if not ok: failures.append(label)
func _ready() -> void:
	await get_tree().process_frame
	var generation:Dictionary = Generation.begin_generation(&"fact_writer_preflight")
	var context = Generation.derive_context(generation.token, &"fact_writer_preflight").context
	var journal = EventJournal.new()
	journal.set_meta(&"fact_writer_probe", [0])
	var backing:Array = journal.get_meta(&"fact_writer_probe")
	var checkpoint = Checkpoint.new()
	check(checkpoint.capture([journal], {}, context), "actual EventJournal generic capture accepts owner metadata")
	check(not Ids.script_fields(journal).has("metadata/fact_writer_probe"), "native metadata is not a script rule field")
	var captured:bool = false
	for row in checkpoint._collections:
		if is_same(row.target, backing): captured = true
	check(not captured, "generic capture never visits metadata backing")
	journal.record({"round":1, "type":"child"})
	backing[0] = 7
	check(checkpoint.restore() and journal.entries.is_empty(), "actual EventJournal generic restore restores rule contents")
	check(is_same(backing, journal.get_meta(&"fact_writer_probe")) and backing[0] == 7, "metadata identity and revision survive actual restore")
	var probe = RootProbe.new()
	check(probe.entries.is_empty() and probe.get_meta(&"revision") == 0, "setter initialization retains empty mutable Array")
	var root:Array = probe.entries
	probe.set("entries", [])
	probe.entries = root
	check(probe.get_meta(&"revision") == 2 and is_same(probe.entries, root), "direct and reflective root change-back reach setter")
	var fields:Dictionary = Ids.script_fields(probe)
	check(fields.has("entries") and is_same(fields.entries, root), "reflection preserves public root identity")
	var clone = RootProbe.new()
	for key in fields: clone.set(key, fields[key])
	check(is_same(clone.entries, root) and clone.get_meta(&"revision") == 1 and probe.get_meta(&"revision") == 2, "old field-copy clone does not copy owner metadata")
	var shadow = GameLog.new_shadow_sink()
	shadow.record("shadow")
	check(shadow.journal.entries.size() == 1 and journal.entries.is_empty(), "old real shadow sink remains independent")
	print("RESULT ", JSON.stringify({"suite":"fact-writer-revision-preflight", "checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
